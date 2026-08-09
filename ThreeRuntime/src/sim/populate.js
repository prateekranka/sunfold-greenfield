// Seeds the authored starting state: Cores, citizens, the Dominion Spire and the
// resource deposits every region opens with.
//
// Ported from `Sources/Simulation/WorldPopulator.swift`. Placement is
// deterministic: whatever the Sunwoven receive on their home fragment, the
// Gravemark receive the equivalent on theirs, and nothing here grants either side
// an advantage. The map itself is free to be asymmetric — CP-14's fairness rule is
// that the two Cores are equidistant from the Dominion, and that is the whole of
// it.
//
// Three deliberate departures from the Swift original, all forced by the pinned
// contract rather than chosen:
//
//   1. **Streams.** Swift opens a fresh stream per faction (`start.sunwoven`) and
//      per region (`deposits.dominion`). `rng.js` closes the tag list, so both
//      factions share `world.populate` and every region shares `world.deposits`.
//      Draw order is therefore load-bearing: factions in `FACTIONS` order, regions
//      in `REGION_IDS` order, and every attempt draws whether or not it succeeds,
//      exactly as the Swift loop does.
//   2. **No Light Transports.** Swift berths one hull per faction at
//      `dockPoint`. Boarding and void travel are deferred in this migration
//      (CONTRACT.md), `world.js` exposes no `dockPoint`, and a unit sitting in the
//      void would fail the rule that every unit stands on land. Spawning a hull
//      nothing can drive would be inventing a rule, so it waits for the system
//      that owns it.
//   3. **Clamping.** Swift clamps a citizen back along the segment from the Core.
//      The contract's `clampToLand(point, margin)` carries no origin, so it
//      resolves to the nearest legal ground instead. On a home plateau the wanted
//      point is already land, so this only bites on a map whose Core sits within
//      ~12 m of water.

import { EntityIDAllocator } from "./ids.js";
import { CHUNKS_PER_LOAD, DEPOSIT_WORK_RADIUS, buildingKind, unitKind } from "./kinds.js";
import { TUNING, depositYield } from "./tuning.js";
import { FACTIONS, REGION_IDS, activity, expansionRegion, homeRegion } from "./types.js";

/**
 * What each region carries at match start.
 *
 * Swift also plans the two neutral outcrops. `REGION_IDS` has no slot for them —
 * see the header of `world.js` — so their ground is part of whichever territory
 * reaches it and carries no deposits of its own.
 */
const DEPOSIT_PLANS = Object.freeze({
  sunwovenHome: Object.freeze(["provisions", "provisions", "matter", "matter", "lumen"]),
  gravemarkHome: Object.freeze(["provisions", "provisions", "matter", "matter", "lumen"]),
  sunwovenExpansion: Object.freeze(["matter", "lumen", "provisions", "aether"]),
  gravemarkExpansion: Object.freeze(["matter", "lumen", "provisions", "aether"]),
  dominion: Object.freeze(["aether", "lumen"])
});

/** How many of the three neutral frame pieces a finished building carries. */
const COMPLETE_COMPONENTS = 3;

/** Attempts allowed per deposit before it falls back to the region anchor. */
const DEPOSIT_ATTEMPTS = 48;

/** Metres two deposits must be apart before the search stops early. */
const DEPOSIT_SPACING = 5.0;

/**
 * Seeds `state.units`, `state.buildings`, `state.deposits` and `state.allocator`.
 *
 * Ids come only from the allocator, in one fixed declaration order — both Cores
 * and their citizens, then the Spire, then deposits — so two runs from one seed
 * name the same entity with the same number and a replay lines up.
 */
export function populate(state) {
  requireEmpty(state);
  const map = state.map;
  const random = state.random.stream("world.populate");

  for (const faction of FACTIONS) {
    placeHome(state, map, random, faction);
  }
  placeDominionSpire(state, map);

  const deposits = state.random.stream("world.deposits");
  for (const region of REGION_IDS) {
    placeDeposits(state, map, deposits, region);
  }
}

// MARK: - Home region

function placeHome(state, map, random, faction) {
  const region = homeRegion(faction);
  const anchor = map.regionAnchor(region);

  // The Core anchors the region centre — the visual anchor in concept 01 — and is
  // the point CP-14's fairness rule measures from.
  addBuilding(state, {
    faction,
    kind: "civilizationCore",
    position: anchor,
    region
  });

  // Citizens stand in a loose arc in front of the Core, not a rigid ring. The arc
  // faces the expansion, which since CP-14 is the direction the water is in.
  const expansion = map.regionAnchor(expansionRegion(faction));
  const outward = normalise({ x: expansion.x - anchor.x, z: expansion.z - anchor.z });
  // Compass convention, carried over from Swift: bearings here are `atan2(x, z)`
  // and are spent as `(sin, cos)`, not the `atan2(z, x)` the coast profiles use.
  const baseAngle = Math.atan2(outward.x, outward.z);
  const coreRadius = buildingKind("civilizationCore").footprintRadius;
  const footprint = unitKind("citizen").footprintRadius;

  const count = TUNING.startingCitizens;
  for (let index = 0; index < count; index += 1) {
    const spread = (index - (count - 1) / 2) * 0.34;
    const angle = baseAngle + spread + random.float(-0.06, 0.06);
    const distance = coreRadius + random.float(3.0, 6.5);
    const wanted = {
      x: anchor.x + Math.sin(angle) * distance,
      z: anchor.z + Math.cos(angle) * distance
    };
    const position = map.clampToLand(wanted, footprint) ?? { x: anchor.x, z: anchor.z };

    addUnit(state, {
      faction,
      kind: "citizen",
      position,
      facing: angle,
      region: map.region(position)
    });
  }
}

// MARK: - The objective

/**
 * The Dominion Spire stands at the exact centre of the contested region, which is
 * the one point both Cores are equidistant from — the map's only fairness
 * contract. Placed before deposits so nothing spawns under it.
 *
 * It belongs to nobody, so it is never trained from, never counted as anyone's
 * building, and cannot be destroyed.
 */
function placeDominionSpire(state, map) {
  addBuilding(state, {
    faction: null,
    kind: "dominionSpire",
    position: map.regionAnchor("dominion"),
    region: "dominion"
  });
}

// MARK: - Deposits

function placeDeposits(state, map, random, region) {
  const plan = DEPOSIT_PLANS[region];
  if (!plan) throw new RangeError(`no deposit plan for region: ${region}`);

  const anchor = map.regionAnchor(region);
  const placed = [];

  for (let index = 0; index < plan.length; index += 1) {
    const kind = plan[index];
    let position = { x: anchor.x, z: anchor.z };

    // A bounded search: spread deposits around the region by index, then jitter,
    // retrying if the pick lands on water, off the plate, or on top of an earlier
    // one. Both draws happen on every attempt, successful or not — moving them
    // inside a guard would change the stream and so change every later map.
    for (let attempt = 0; attempt < DEPOSIT_ATTEMPTS; attempt += 1) {
      const sector = (index / plan.length) * 2 * Math.PI;
      const angle = sector + random.float(-0.5, 0.5) + attempt * 0.31;
      const heading = { x: Math.sin(angle), z: Math.cos(angle) };
      // Measured per bearing off the authored outline; a fixed radius would put
      // deposits in the void wherever the coast cuts in.
      const outerLimit =
        map.regionReachToward(region, { x: anchor.x + heading.x, z: anchor.z + heading.z }) - 4.5;
      const inner = innerLimit(region);
      const distance = random.float(inner, Math.max(inner + 1, outerLimit));
      const candidate = { x: anchor.x + heading.x * distance, z: anchor.z + heading.z * distance };

      // `workRadius` clearance, so a citizen can stand anywhere in the gathering
      // ring without standing in a river.
      if (!map.isStandableIn(candidate, region, DEPOSIT_WORK_RADIUS)) continue;
      position = candidate;
      if (placed.every((other) => distanceBetween(other, candidate) > DEPOSIT_SPACING)) break;
    }
    placed.push(position);

    addDeposit(state, { kind, position, region });
  }
}

/**
 * How far out from the region anchor a deposit may start.
 *
 * Home regions clear the Core footprint plus room to build against it. The
 * Dominion's centre is not empty ground — the Spire stands on it — so its
 * deposits start outside the Spire's footprint plus a citizen's working ring.
 * Without that a Matter node can sit *inside* the objective, and the one piece of
 * ground the whole match is fought over becomes a mine.
 */
function innerLimit(region) {
  if (region === "sunwovenHome" || region === "gravemarkHome") {
    return buildingKind("civilizationCore").footprintRadius + 6;
  }
  if (region === "dominion") {
    return buildingKind("dominionSpire").footprintRadius + DEPOSIT_WORK_RADIUS + 1;
  }
  return 3.0;
}

// MARK: - Entity construction

function addUnit(state, { faction, kind, position, facing, region }) {
  const id = state.allocator.allocate();
  const unit = {
    id,
    faction,
    kind,
    position: { x: position.x, z: position.z },
    destination: null,
    movementPath: [],
    movementPathTarget: null,
    facing,
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
  state.units.set(id, unit);
  return unit;
}

function addBuilding(state, { faction, kind, position, region }) {
  const id = state.allocator.allocate();
  const building = {
    id,
    faction,
    kind,
    position: { x: position.x, z: position.z },
    region,
    life: buildingKind(kind).maxLife,
    // Both authored buildings stand finished: nobody built them, so there is no
    // foundation to raise and all three frame pieces are already in.
    constructionProgress: 1,
    installedComponents: COMPLETE_COMPONENTS
  };
  state.buildings.set(id, building);
  return building;
}

function addDeposit(state, { kind, position, region }) {
  const id = state.allocator.allocate();
  const deposit = {
    id,
    kind,
    position: { x: position.x, z: position.z },
    region,
    remaining: depositYield(kind, region),
    // The visible loose pile. Full at match start; gathering takes one chunk per
    // contact loop and refills it while yield remains.
    chunksRemaining: CHUNKS_PER_LOAD
  };
  state.deposits.set(id, deposit);
  return deposit;
}

// MARK: - Helpers

function normalise(vector) {
  const magnitude = Math.sqrt(vector.x * vector.x + vector.z * vector.z);
  if (magnitude < 1e-6) return { x: 0, z: 0 };
  return { x: vector.x / magnitude, z: vector.z / magnitude };
}

function distanceBetween(a, b) {
  const dx = a.x - b.x;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dz * dz);
}

/**
 * Populating a state that already holds entities would hand out a second set of
 * ids for the same world. Cheaper to refuse than to debug a doubled opening.
 */
function requireEmpty(state) {
  if (!(state.allocator instanceof EntityIDAllocator)) {
    throw new TypeError("populate needs a state carrying an EntityIDAllocator");
  }
  if (state.units.size > 0 || state.buildings.size > 0 || state.deposits.size > 0) {
    throw new Error("populate was given a state that is already seeded");
  }
}
