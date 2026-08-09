// Training queues: enqueue, tick, spawn, cancel, refund.
//
// Ported from `Sources/Simulation/ProductionSystem.swift`.
//
// Cost is charged on **enqueue**, not on completion. That single decision is
// what makes a queued unit count against population — the resources are already
// spent, so the seat is already taken — and it is why every exit path from a
// queue has to hand something back.
//
// Tick-driven and fully deterministic: no wall clock, and no draw from
// `state.random`. The Swift spawn search is a fixed ring of bearings rather
// than a scatter, so the registered `production.spawn` stream is deliberately
// left untouched; drawing from it would invent randomness the original never
// had and shift every other stream's meaning of "the same match".

import { RESOURCE_KINDS, activity, covers, distance, pool } from "./types.js";
import { buildingKind, unitKind } from "./kinds.js";
import { TUNING, unitBuildTicks, unitCost } from "./tuning.js";

/**
 * Hard ceiling on the population cap, above whatever Dwellings grant.
 *
 * Ported from the literal in `ProductionSystem.swift`; it lives with the rule
 * rather than in the tuning table in the Swift original too.
 */
const POPULATION_HARD_CEILING = 200;

/** Ring search geometry for the spawn point. Fixed, so spawns are replayable. */
const SPAWN_RINGS = 4;
const SPAWN_SLOTS_PER_RING = 6;
const SPAWN_RING_SPACING = 1.8;
const SPAWN_CLEARANCE = 0.6;
const SPAWN_FALLBACK_MARGIN = 1.2;

export const ProductionSystem = {
  /**
   * Advances the front item of every queue by one tick and spawns what
   * finished.
   *
   * Walks buildings in ascending id, so two runs of one seed train in the same
   * order even though the queue map is keyed by building.
   */
  step(state) {
    const buildingIDs = state.buildings
      .orderedIDs()
      .filter((id) => state.productionQueues.has(id));

    for (const buildingID of buildingIDs) {
      const queue = state.productionQueues.get(buildingID);
      if (!queue || queue.items.length === 0) continue;

      const building = state.buildings.get(buildingID);
      if (!building) continue;
      const owner = building.faction;
      if (owner === null || owner === undefined) continue;
      if (building.constructionProgress < 1) continue;
      if (buildingKind(building.kind).trains.length === 0) continue;

      const front = queue.items[0];
      const totalTicks = unitBuildTicks(front.kind);
      if (totalTicks <= 0) continue;

      // The first tick marks the front started. Refunds are cheaper after this
      // point, so the flag is a rule of its own, not a progress side effect.
      front.hasStarted = true;
      front.progressTicks = Math.min(front.progressTicks + 1, totalTicks);

      if (front.progressTicks >= totalTicks) {
        // The front item's population is already reserved by
        // `populationCommitment` — it was charged on enqueue. A commitment
        // *above* the cap means the room it reserved has since been taken, so
        // the finished unit waits rather than pushing the faction over.
        const population = this.populationCommitment(state, owner);
        if (population.used > population.cap) {
          queue.heldReason = "populationCap";
        } else {
          const spawn = spawnPosition(state, front.kind, building);
          if (spawn) {
            const id = state.allocator.allocate();
            state.units.set(id, createUnit(id, owner, front.kind, spawn, building.region));
            queue.items.shift();
            queue.heldReason = null;
          } else {
            queue.heldReason = "noSpawnPosition";
          }
        }
      } else {
        queue.heldReason = null;
      }

      if (queue.items.length === 0) state.productionQueues.delete(buildingID);
    }
  },

  /**
   * Adds one unit to a building's queue, charging its cost now.
   *
   * Returns `{ ok: true }` or `{ ok: false, reason }`. The reasons are the
   * Swift failure cases verbatim, because the HUD tells the player which one it
   * was and "could not train" is not an answer.
   */
  enqueue(state, kind, buildingID) {
    const building = state.buildings.get(buildingID);
    if (!building) return { ok: false, reason: "notTrainable" };

    // A neutral objective has no treasury and trains nothing.
    const owner = building.faction;
    if (owner === null || owner === undefined) return { ok: false, reason: "notTrainable" };
    if (building.constructionProgress < 1) return { ok: false, reason: "buildingIncomplete" };
    if (!buildingKind(building.kind).trains.includes(kind)) {
      return { ok: false, reason: "notTrainable" };
    }

    const queue = state.productionQueues.get(buildingID) ?? { items: [], heldReason: null };
    if (queue.items.length >= TUNING.maxQueueLength) return { ok: false, reason: "queueFull" };

    const cost = unitCost(kind);
    const stock = state.stock[owner];
    if (!stock || !covers(stock, cost)) {
      return { ok: false, reason: "cannotAfford", missing: shortfall(cost, stock ?? pool()) };
    }

    const population = this.populationCommitment(state, owner);
    const additional = unitKind(kind).populationCost;
    if (population.used + additional > population.cap) {
      return {
        ok: false,
        reason: "populationCap",
        used: population.used + additional,
        cap: population.cap
      };
    }

    for (const resource of RESOURCE_KINDS) stock[resource] -= cost[resource];
    queue.items.push({ kind, progressTicks: 0, hasStarted: false });
    state.productionQueues.set(buildingID, queue);
    return { ok: true };
  },

  /**
   * Removes the front item and refunds its cost.
   *
   * Matches `ProductionSystem.cancelFront` exactly: an item that has not yet
   * received a tick is returned in full, and one that has started is returned
   * at `cost * cancelRefundFraction`. The `hasStarted` flag decides, not the
   * progress bar.
   */
  cancelFront(state, buildingID) {
    const queue = state.productionQueues.get(buildingID);
    if (!queue || queue.items.length === 0) return false;

    const building = state.buildings.get(buildingID);
    if (!building) return false;
    const owner = building.faction;
    if (owner === null || owner === undefined) return false;

    const item = queue.items.shift();
    const fraction = item.hasStarted ? TUNING.cancelRefundFraction : 1.0;
    refund(state.stock[owner], unitCost(item.kind), fraction);
    queue.heldReason = null;

    if (queue.items.length === 0) state.productionQueues.delete(buildingID);
    return true;
  },

  /**
   * Refunds the in-progress front item and discards the rest when a building
   * is lost. Call before removing the building — the refund needs its owner.
   *
   * Matches `ProductionSystem.onBuildingDestroyed` exactly: only the front
   * item is returned, under the same started rule as a manual cancel, and the
   * remaining queue goes with the building. This is the authored Swift
   * contract, not a conservation reinterpretation of it.
   */
  onBuildingDestroyed(state, buildingID) {
    const queue = state.productionQueues.get(buildingID);
    if (!queue || queue.items.length === 0) {
      state.productionQueues.delete(buildingID);
      return;
    }

    const building = state.buildings.get(buildingID);
    const owner = building ? building.faction : null;
    // No owner means nothing was ever charged: `enqueue` refuses a neutral or
    // absent building, so such a queue cannot hold a paid-for item.
    if (owner === null || owner === undefined) {
      state.productionQueues.delete(buildingID);
      return;
    }

    const stock = state.stock[owner];
    const front = queue.items[0];
    const fraction = front.hasStarted ? TUNING.cancelRefundFraction : 1.0;
    refund(stock, unitCost(front.kind), fraction);
    state.productionQueues.delete(buildingID);
  },

  /**
   * Population in use versus the cap granted by Dwellings and Outposts.
   *
   * Queued units count toward used population because cost is charged on
   * enqueue. Anything else lets a player queue ten Citizens against a cap of
   * ten they already fill, and discover the lie only when the first one refuses
   * to appear.
   */
  populationCommitment(state, faction) {
    let live = 0;
    for (const unit of state.units.ordered()) {
      if (unit.faction !== faction) continue;
      live += unitKind(unit.kind).populationCost;
    }

    let queued = 0;
    const queueIDs = [...state.productionQueues.keys()].sort((left, right) => left - right);
    for (const buildingID of queueIDs) {
      const building = state.buildings.get(buildingID);
      if (!building || building.faction !== faction) continue;
      const queue = state.productionQueues.get(buildingID);
      for (const item of queue.items) queued += unitKind(item.kind).populationCost;
    }

    let granted = 0;
    for (const building of state.buildings.ordered()) {
      if (building.faction !== faction) continue;
      if (building.constructionProgress < 1) continue;
      granted += buildingKind(building.kind).populationGrant;
    }

    return {
      used: live + queued,
      cap: Math.min(TUNING.startingPopulationCap + granted, POPULATION_HARD_CEILING)
    };
  },

  /** Front-item progress as 0…1, for the HUD readout. */
  progress(state, buildingID) {
    const queue = state.productionQueues.get(buildingID);
    if (!queue || queue.items.length === 0) return 0;
    const front = queue.items[0];
    const total = unitBuildTicks(front.kind);
    if (total <= 0) return 0;
    return front.progressTicks / total;
  }
};

function refund(stock, cost, fraction) {
  if (!stock) return;
  for (const resource of RESOURCE_KINDS) {
    stock[resource] += cost[resource] * fraction;
  }
}

function shortfall(needed, have) {
  const missing = pool();
  for (const resource of RESOURCE_KINDS) {
    missing[resource] = Math.max(0, needed[resource] - have[resource]);
  }
  return missing;
}

/** A freshly trained unit, complete down to the animation block. */
function createUnit(id, faction, kind, spawn, region) {
  return {
    id,
    faction,
    kind,
    position: { x: spawn.position.x, z: spawn.position.z },
    destination: null,
    movementPath: [],
    movementPathTarget: null,
    facing: spawn.facing,
    activity: activity("idle"),
    life: unitKind(kind).maxLife,
    region,
    carrying: [],
    cargo: null,
    assignment: null,
    boardingProgress: 0,
    animation: {
      state: "idle",
      loopIndex: 0,
      phaseTicks: 0,
      leadHand: "none",
      toolHeld: null,
      carriedChunks: 0,
      airborneChunks: []
    }
  };
}

/**
 * Deterministic ring search beside the building — ring 1 at six bearings, then
 * ring 2 at twelve, and so on. The same building always releases units to the
 * same offsets, with no draw and no dependence on who spawned first.
 */
function spawnPosition(state, kind, building) {
  const margin = unitKind(kind).footprintRadius;
  const footprint = buildingKind(building.kind).footprintRadius;

  for (let ring = 1; ring <= SPAWN_RINGS; ring += 1) {
    const slots = ring * SPAWN_SLOTS_PER_RING;
    for (let slot = 0; slot < slots; slot += 1) {
      const angle = (slot / slots) * 2 * Math.PI;
      const span = footprint + margin + ring * SPAWN_RING_SPACING;
      const candidate = {
        x: building.position.x + Math.sin(angle) * span,
        z: building.position.z + Math.cos(angle) * span
      };

      if (!isStandable(state.map, candidate, building.region, margin)) continue;
      if (overlapsStructure(state, candidate, margin + SPAWN_CLEARANCE, building.id)) continue;
      if (overlapsUnit(state, candidate, margin + SPAWN_CLEARANCE)) continue;

      return { position: candidate, facing: angle };
    }
  }

  // Last resort: straight out from the centre along +X, clamped back onto land.
  // The Swift clamp retreats along the segment towards the building and so can
  // always answer; this runtime's `clampToLand` may refuse, and the building
  // centre is the same degenerate answer the retreat would have reached.
  const fallback = {
    x: building.position.x + footprint + margin + SPAWN_FALLBACK_MARGIN,
    z: building.position.z
  };
  const clamped = state.map.clampToLand(fallback, margin);
  return {
    position: clamped
      ? { x: clamped.x, z: clamped.z }
      : { x: building.position.x, z: building.position.z },
    facing: 0
  };
}

/**
 * Whether a unit of `margin` footprint fits at `point` inside `region`.
 *
 * The Swift map exposes `isStandable(_:in:margin:)` directly. This runtime's
 * map contract does not, so the same question is asked of the two calls it does
 * expose: the region must match, and the margin-aware land clamp must return
 * the point unchanged rather than retreat from it.
 */
function isStandable(map, point, region, margin) {
  if (map.region(point) !== region) return false;
  const clamped = map.clampToLand(point, margin);
  if (!clamped) return false;
  return Math.abs(clamped.x - point.x) < 1e-6 && Math.abs(clamped.z - point.z) < 1e-6;
}

function overlapsStructure(state, point, radius, excludingID) {
  for (const building of state.buildings.ordered()) {
    if (building.id === excludingID) continue;
    const need = buildingKind(building.kind).footprintRadius + radius;
    if (distance(building.position, point) < need) return true;
  }
  return false;
}

function overlapsUnit(state, point, radius) {
  for (const unit of state.units.ordered()) {
    const need = unitKind(unit.kind).footprintRadius + radius;
    if (distance(unit.position, point) < need) return true;
  }
  return false;
}
