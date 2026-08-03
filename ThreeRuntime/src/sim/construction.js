// Foundations: placement, builder assignment, and the progress rule.
//
// Ported from `Sources/Simulation/ConstructionSystem.swift` and the
// `placeBuilding` / `cancelConstruction` / `assignBuilders` /
// `sendToConstruction` / `buildBlocker` methods of
// `Sources/Simulation/SkirmishSimulation.swift`.
//
// The rule that must survive every rewrite: **progress is linear in builder
// count**. Two citizens finish in half the time of one, four in a quarter. Any
// diminishing-returns curve is a balance decision nobody made, so the shape is
// pinned here rather than left to emerge from an accumulator.

import {
  RESOURCE_KINDS,
  activity,
  addPoints,
  distance,
  distanceSquared,
  length,
  pool,
  subtractPoints
} from "./types.js";
import { buildingKind, unitKind } from "./kinds.js";
import { TUNING, buildingCost, buildTime } from "./tuning.js";
import { ProductionSystem } from "./production.js";

/**
 * How close a builder must stand, measured from the building centre.
 *
 * Must reach past the approach kerb (`footprintRadius + 1.4`), or builders
 * arrive, clear their destination, and then never advance progress — the
 * stalled-foundation bug this margin exists to prevent.
 */
const WORK_RADIUS_MARGIN = 2.0;

/** The kerb a builder walks to, so they do not pile into the foundation disc. */
const APPROACH_MARGIN = 1.4;
const APPROACH_SAFETY = 0.85;

/**
 * Completion tolerance for the accumulated progress sum.
 *
 * Deliberate deviation from a literal transcription of the Swift accumulator,
 * and the only one in this file. `progress += (builders * dt) / duration`
 * repeated 240 times sums to 0.999999999999999889, not 1, so a Farm that the
 * tuning table prices at 12 s would finish at 12.05 s — and two builders would
 * take 121 ticks, which is not half of 241. The IEEE-754 residue would be
 * leaking into gameplay timing and breaking the linear-in-builders rule by one
 * tick. Worst-case drift over the longest build (Dawn Loom, 520 ticks) is about
 * 1e-13; one tick of progress is at least 1.9e-3. An epsilon of 1e-9 sits far
 * above the drift and far below a tick, so it can close the rounding gap
 * without ever finishing a building a tick early.
 */
const COMPLETION_EPSILON = 1e-9;

export const ConstructionSystem = {
  /** Maximum citizens that may work one foundation at once. */
  maxBuildersPerSite: 4,

  workRadius(kind) {
    return buildingKind(kind).footprintRadius + WORK_RADIUS_MARGIN;
  },

  /**
   * Advances every incomplete building that has builders standing on it.
   *
   * Builders that have not arrived are given a destination on the kerb; the
   * movement system owns the walk itself and replans when the destination
   * stops matching the planned path target.
   */
  step(state, deltaTime) {
    const incomplete = state.buildings
      .orderedIDs()
      .filter((id) => !isComplete(state.buildings.get(id)));
    if (incomplete.length === 0) return;

    for (const buildingID of incomplete) {
      const building = state.buildings.get(buildingID);
      if (!building || isComplete(building)) continue;

      const onSiteRadius = this.workRadius(building.kind);
      let buildersOnSite = 0;

      for (const unitID of state.units.orderedIDs()) {
        const unit = state.units.get(unitID);
        if (!unit) continue;
        if (unit.activity.tag !== "constructing" || unit.activity.subject !== buildingID) continue;
        if (unit.faction !== building.faction) continue;
        if (!unitKind(unit.kind).canGather) continue;

        if (distance(unit.position, building.position) <= onSiteRadius) {
          unit.destination = null;
          buildersOnSite += 1;
        } else if (unit.destination === null || unit.destination === undefined) {
          const offset = approachOffset(unit.position, building);
          const destination = resolveDestination(state, unit, addPoints(building.position, offset));
          if (destination) unit.destination = destination;
        }
      }

      if (buildersOnSite === 0) continue;

      // `max(..., 0.01)` guards the two build-time-zero kinds against a divide
      // by zero rather than special-casing them; neither is placeable.
      const duration = Math.max(buildTime(building.kind), 0.01);
      const advanced = building.constructionProgress + (buildersOnSite * deltaTime) / duration;
      building.constructionProgress = advanced >= 1 - COMPLETION_EPSILON ? 1 : advanced;

      if (isComplete(building)) {
        // The three neutral frame pieces are advanced by the animation
        // controller's `construct_contact` events while the foundation is
        // under way; a completed building has all three regardless of how many
        // contacts the controller managed to land.
        building.installedComponents = 3;
        releaseBuilders(state, buildingID);
      }
    }
  },

  /**
   * The simulation-owned reason a building cannot be started, before a site is
   * chosen. Footprint legality is a placement concern and stays out of here.
   */
  buildBlocker(state, kind, faction) {
    if (kind === "lumenSpire") {
      let hasCompletedYard = false;
      for (const building of state.buildings.ordered()) {
        if (
          building.faction === faction &&
          building.kind === "formationYard" &&
          isComplete(building)
        ) {
          hasCompletedYard = true;
          break;
        }
      }
      if (!hasCompletedYard) {
        return { reason: "missingPrerequisite", prerequisite: "formationYard" };
      }
    }

    const cost = buildingCost(kind);
    const have = state.stock[faction] ?? pool();
    let affordable = true;
    const missing = pool();
    for (const resource of RESOURCE_KINDS) {
      missing[resource] = Math.max(0, cost[resource] - have[resource]);
      if (missing[resource] > 0) affordable = false;
    }
    if (affordable) return null;
    return { reason: "unaffordable", missing };
  },

  /**
   * Commits a foundation at `point`. Charges the cost, spawns the incomplete
   * building, and sends preferred (else nearest idle or gathering) citizens.
   *
   * Returns the new building id, or null when stock, prerequisite or region
   * refuse. The caller owns footprint legality — the adversary and the player
   * reach this through different site checks and neither may be assumed here.
   */
  placeBuilding(state, kind, point, faction, preferredIDs = []) {
    const region = state.map.region(point);
    if (!region) return null;
    if (this.buildBlocker(state, kind, faction) !== null) return null;

    const cost = buildingCost(kind);
    const stock = state.stock[faction];
    for (const resource of RESOURCE_KINDS) stock[resource] -= cost[resource];

    const id = state.allocator.allocate();
    state.buildings.set(id, {
      id,
      faction,
      kind,
      position: { x: point.x, z: point.z },
      region,
      life: buildingKind(kind).maxLife,
      constructionProgress: 0,
      installedComponents: 0
    });

    this.assignBuilders(state, id, faction, preferredIDs);
    return id;
  },

  /**
   * Tears down an incomplete foundation and refunds exactly
   * `cost * cancelRefundFraction`. Completed buildings cannot be cancelled
   * this way — a finished Farm is demolished, not un-ordered.
   */
  cancelConstruction(state, buildingID) {
    const building = state.buildings.get(buildingID);
    if (!building) return false;
    const owner = building.faction;
    if (owner === null || owner === undefined) return false;
    if (isComplete(building)) return false;

    const cost = buildingCost(building.kind);
    const stock = state.stock[owner];
    for (const resource of RESOURCE_KINDS) {
      stock[resource] += cost[resource] * TUNING.cancelRefundFraction;
    }

    releaseBuilders(state, buildingID);
    // Runs while the building still exists, because the queue's refund needs to
    // read its owner. A foundation cannot have a queue today, but a cancel that
    // silently dropped one would be exactly the kind of quiet loss the
    // conservation rule exists to catch.
    ProductionSystem.onBuildingDestroyed(state, buildingID);
    state.buildings.delete(buildingID);
    return true;
  },

  /**
   * Sends citizens to an incomplete building. Prefers the caller's selection,
   * then the nearest idle or gathering citizens of the same faction. Builders
   * already on the job stay assigned until the foundation completes or is
   * cancelled, so adding help never scatters the crew already working.
   *
   * Returns how many citizens were newly assigned.
   */
  assignBuilders(state, buildingID, faction, preferredIDs = []) {
    const building = state.buildings.get(buildingID);
    if (!building || isComplete(building)) return 0;

    const alreadyAssigned = new Set();
    for (const unit of state.units.ordered()) {
      if (unit.activity.tag === "constructing" && unit.activity.subject === buildingID) {
        alreadyAssigned.add(unit.id);
      }
    }

    let slots = Math.max(0, this.maxBuildersPerSite - alreadyAssigned.size);
    if (slots <= 0) return 0;

    const toAssign = [];
    const chosen = new Set();
    for (const id of [...preferredIDs].sort((left, right) => left - right)) {
      if (slots <= 0) break;
      if (chosen.has(id) || alreadyAssigned.has(id)) continue;
      const unit = state.units.get(id);
      if (!unit) continue;
      if (unit.faction !== faction) continue;
      if (!canBeAssignedToConstruction(unit)) continue;
      toAssign.push(id);
      chosen.add(id);
      slots -= 1;
    }

    // Only when the caller named nobody usable *and* named nobody at all. A
    // selection of one busy transport must not quietly conscript the citizens
    // the player did not select.
    if (toAssign.length === 0 && preferredIDs.length === 0 && slots > 0) {
      const candidates = [];
      for (const unit of state.units.ordered()) {
        if (unit.faction !== faction) continue;
        if (!canBeAssignedToConstruction(unit)) continue;
        if (alreadyAssigned.has(unit.id)) continue;
        if (unit.activity.tag !== "idle" && unit.activity.tag !== "gathering") continue;
        candidates.push(unit);
      }
      // Nearest first, ties broken on ascending id — two citizens equidistant
      // from a foundation must not depend on collection order.
      candidates.sort((left, right) => {
        const leftDistance = distanceSquared(left.position, building.position);
        const rightDistance = distanceSquared(right.position, building.position);
        if (leftDistance !== rightDistance) return leftDistance - rightDistance;
        return left.id - right.id;
      });
      for (const unit of candidates.slice(0, Math.min(slots, 2))) toAssign.push(unit.id);
    }

    for (const id of toAssign) sendToConstruction(state, id, buildingID, building);
    return toAssign.length;
  }
};

/** `constructionProgress >= 1`, in one place so no caller invents its own test. */
function isComplete(building) {
  return building ? building.constructionProgress >= 1 : true;
}

function canBeAssignedToConstruction(unit) {
  if (!unitKind(unit.kind).canGather) return false;
  // Citizens boarding or aboard a transport cannot be pulled into construction.
  return unit.activity.tag !== "aboard" && unit.activity.tag !== "boarding";
}

/**
 * G2a carry disposition.
 *
 * A citizen holding cargo credits it to faction stock exactly once, then the
 * cargo is cleared. Construction is not a second drop-off: crediting here and
 * leaving the load on the citizen would let the same 10 Matter be banked twice
 * by walking to a foundation and then to the Core.
 */
function sendToConstruction(state, id, buildingID, building) {
  const unit = state.units.get(id);
  if (!unit || !canBeAssignedToConstruction(unit)) return;

  if (unit.cargo) {
    const stock = state.stock[unit.faction];
    if (stock) stock[unit.cargo.kind] += unit.cargo.amount;
    unit.cargo = null;
  }

  unit.assignment = null;
  unit.activity = activity("constructing", buildingID);

  const offset = approachOffset(unit.position, building);
  unit.destination = resolveDestination(state, unit, addPoints(building.position, offset)) ?? null;
}

/** Where on the kerb a builder approaching from `from` should stand. */
function approachOffset(from, building) {
  const delta = subtractPoints(from, building.position);
  const span = length(delta);
  // Stay inside workRadius so arrival actually counts as on-site.
  const radius = Math.min(
    buildingKind(building.kind).footprintRadius + APPROACH_MARGIN,
    ConstructionSystem.workRadius(building.kind) * APPROACH_SAFETY
  );
  if (span < 0.01) return { x: radius, z: 0 };
  return { x: (delta.x / span) * radius, z: (delta.z / span) * radius };
}

/**
 * The land clamp a walk order goes through.
 *
 * `MovementSystem.resolveDestination` is the Swift entry point, and for a land
 * unit it is exactly this call. Reaching for it from here would make
 * construction depend on a module owned by another builder for a one-line
 * clamp, so the clamp is called directly. Void travellers never build.
 */
function resolveDestination(state, unit, point) {
  return state.map.clampToLand(point, unitKind(unit.kind).footprintRadius);
}

/** Returns every builder on this site to idle. */
function releaseBuilders(state, buildingID) {
  for (const id of state.units.orderedIDs()) {
    const unit = state.units.get(id);
    if (!unit) continue;
    if (unit.activity.tag !== "constructing" || unit.activity.subject !== buildingID) continue;
    unit.activity = activity("idle");
    unit.destination = null;
  }
}
