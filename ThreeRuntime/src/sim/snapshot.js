// Save and restore for the authoritative simulation.
//
// The contract issue #22 sets is exact: restoring a snapshot must not change the
// future. A match saved at tick N and resumed must produce the same world hashes
// from tick N+1 onward as the same match played straight through. That rules out
// anything derived, anything reconstructed by re-simulating, and anything left
// out because "it will settle again in a few ticks".
//
// Two things are deliberately NOT saved:
//   - the clock's sub-step accumulator, which is presentation residue and would
//     make a reload depend on where inside a frame the save happened;
//   - the event log, which is an observation of the run rather than state the run
//     depends on.

import { SimulationClock } from "./clock.js";
import { EntityIDAllocator, EntityStore } from "./ids.js";
import { RandomStreams, seedFrom } from "./rng.js";
import { EventLog } from "./events.js";
import { RESOURCE_KINDS } from "./types.js";
import { WorldMap } from "./world.js";

/**
 * The version of the saved state document.
 *
 * Bumped whenever a field is added, removed or reinterpreted. A snapshot from a
 * different version is refused rather than best-effort migrated: a save that
 * loads into a subtly different world is worse than a save that will not load.
 */
export const SNAPSHOT_SCHEMA_VERSION = 2;

/** JSON has no infinity, and a renewable deposit's yield is genuinely infinite. */
function encodeNumber(value) {
  if (value === Infinity) return "+inf";
  if (value === -Infinity) return "-inf";
  if (Number.isNaN(value)) throw new TypeError("cannot serialise NaN out of simulation state");
  return value;
}

function decodeNumber(value) {
  if (value === "+inf") return Infinity;
  if (value === "-inf") return -Infinity;
  if (typeof value !== "number") throw new TypeError(`not a serialised number: ${String(value)}`);
  return value;
}

function encodePool(pool) {
  const out = {};
  for (const kind of RESOURCE_KINDS) out[kind] = encodeNumber(pool[kind]);
  return out;
}

function decodePool(raw) {
  const out = {};
  for (const kind of RESOURCE_KINDS) out[kind] = decodeNumber(raw[kind]);
  return out;
}

function encodePoint(point) {
  return point ? [point.x, point.z] : null;
}

function decodePoint(raw) {
  return raw ? { x: raw[0], z: raw[1] } : null;
}

export function captureSnapshot(state) {
  return {
    schemaVersion: SNAPSHOT_SCHEMA_VERSION,
    seed: `${state.seed.hi.toString(16).padStart(8, "0")}${state.seed.lo.toString(16).padStart(8, "0")}`,
    mapID: state.mapID,
    playerFaction: state.playerFaction,
    tick: state.clock.tick,
    paused: state.paused,
    random: state.random.snapshot(),
    allocator: state.allocator.snapshot(),
    stock: {
      sunwoven: encodePool(state.stock.sunwoven),
      gravemark: encodePool(state.stock.gravemark)
    },
    age: { ...state.age },
    units: state.units.ordered().map(encodeUnit),
    buildings: state.buildings.ordered().map(encodeBuilding),
    deposits: state.deposits.ordered().map(encodeDeposit),
    productionQueues: [...state.productionQueues.keys()]
      .sort((left, right) => left - right)
      .map((buildingID) => {
        const queue = state.productionQueues.get(buildingID);
        return {
          buildingID,
          heldReason: queue.heldReason,
          items: queue.items.map((item) => ({
            kind: item.kind,
            progressTicks: item.progressTicks,
            hasStarted: item.hasStarted
          }))
        };
      }),
    orders: encodeOrders(state.orders)
  };
}

/**
 * The scheduled-order state. An order in flight at save time is part of the
 * match's future, so it is serialised with the world — dropping it would make
 * the restored match diverge from the saved one on the tick it was due.
 *
 * Payloads are plain data by construction (ids, points, kind strings); the
 * JSON round trip both deep-copies them and proves nothing unserialisable
 * slipped in.
 */
function encodeOrders(orders) {
  return {
    sequence: orders.sequence,
    pending: orders.pending.map((order) => ({
      kind: order.kind,
      scheduledTick: order.scheduledTick,
      sequence: order.sequence,
      payload: JSON.parse(JSON.stringify(order.payload ?? {}))
    })),
    script: orders.script.map((entry) => ({
      kind: entry.kind,
      scheduledTick: entry.scheduledTick,
      sequence: entry.sequence,
      payload: JSON.parse(JSON.stringify(entry.payload ?? {}))
    }))
  };
}

function decodeOrders(raw) {
  if (!raw || !Array.isArray(raw.pending) || !Array.isArray(raw.script) || !Number.isSafeInteger(raw.sequence)) {
    throw new TypeError("save snapshot carries malformed order state");
  }
  const decode = (entry) => ({
    kind: entry.kind,
    scheduledTick: entry.scheduledTick,
    sequence: entry.sequence,
    payload: JSON.parse(JSON.stringify(entry.payload ?? {}))
  });
  return {
    sequence: raw.sequence,
    pending: raw.pending.map(decode),
    script: raw.script.map(decode)
  };
}

function encodeUnit(unit) {
  return {
    id: unit.id,
    faction: unit.faction,
    kind: unit.kind,
    position: encodePoint(unit.position),
    destination: encodePoint(unit.destination),
    movementPath: unit.movementPath.map(encodePoint),
    movementPathTarget: encodePoint(unit.movementPathTarget),
    facing: unit.facing,
    activity: [unit.activity.tag, unit.activity.subject],
    life: unit.life,
    region: unit.region,
    carrying: [...unit.carrying],
    cargo: unit.cargo ? [unit.cargo.kind, unit.cargo.amount] : null,
    assignment: unit.assignment,
    boardingProgress: unit.boardingProgress,
    pending: unit.pending === undefined ? null : unit.pending,
    animation: {
      state: unit.animation.state,
      loopIndex: unit.animation.loopIndex,
      phaseTicks: unit.animation.phaseTicks,
      leadHand: unit.animation.leadHand,
      toolHeld: unit.animation.toolHeld,
      carriedChunks: unit.animation.carriedChunks,
      airborneChunks: unit.animation.airborneChunks.map((chunk) => ({
        kind: chunk.kind,
        amount: chunk.amount,
        remainingTicks: chunk.remainingTicks
      })),
      // Optional controller fields are carried opaquely so the animation owner
      // can add substate detail without every save needing a schema bump here.
      extra: unit.animation.extra ? JSON.parse(JSON.stringify(unit.animation.extra)) : null
    }
  };
}

function decodeUnit(raw) {
  return {
    id: raw.id,
    faction: raw.faction,
    kind: raw.kind,
    position: decodePoint(raw.position),
    destination: decodePoint(raw.destination),
    movementPath: raw.movementPath.map(decodePoint),
    movementPathTarget: decodePoint(raw.movementPathTarget),
    facing: raw.facing,
    activity: { tag: raw.activity[0], subject: raw.activity[1] },
    life: raw.life,
    region: raw.region,
    carrying: [...raw.carrying],
    cargo: raw.cargo ? { kind: raw.cargo[0], amount: raw.cargo[1] } : null,
    assignment: raw.assignment,
    boardingProgress: raw.boardingProgress,
    pending: raw.pending ?? null,
    animation: {
      state: raw.animation.state,
      loopIndex: raw.animation.loopIndex,
      phaseTicks: raw.animation.phaseTicks,
      leadHand: raw.animation.leadHand,
      toolHeld: raw.animation.toolHeld,
      carriedChunks: raw.animation.carriedChunks,
      airborneChunks: raw.animation.airborneChunks.map((chunk) => ({ ...chunk })),
      extra: raw.animation.extra ? JSON.parse(JSON.stringify(raw.animation.extra)) : null
    }
  };
}

function encodeBuilding(building) {
  return {
    id: building.id,
    faction: building.faction,
    kind: building.kind,
    position: encodePoint(building.position),
    region: building.region,
    life: building.life,
    constructionProgress: building.constructionProgress,
    installedComponents: building.installedComponents
  };
}

function decodeBuilding(raw) {
  return {
    id: raw.id,
    faction: raw.faction,
    kind: raw.kind,
    position: decodePoint(raw.position),
    region: raw.region,
    life: raw.life,
    constructionProgress: raw.constructionProgress,
    installedComponents: raw.installedComponents
  };
}

function encodeDeposit(deposit) {
  return {
    id: deposit.id,
    kind: deposit.kind,
    position: encodePoint(deposit.position),
    region: deposit.region,
    remaining: encodeNumber(deposit.remaining),
    chunksRemaining: deposit.chunksRemaining
  };
}

function decodeDeposit(raw) {
  return {
    id: raw.id,
    kind: raw.kind,
    position: decodePoint(raw.position),
    region: raw.region,
    remaining: decodeNumber(raw.remaining),
    chunksRemaining: raw.chunksRemaining
  };
}

/**
 * Rebuilds a complete simulation state from a snapshot.
 *
 * The map is not stored — it is a pure function of `(mapID, seed)`, so
 * regenerating it is both smaller and strictly safer than trusting a serialised
 * copy to match the generator that would be used on the next run.
 */
export function restoreSnapshot(document) {
  if (!document || typeof document !== "object") {
    throw new TypeError("save snapshot is not an object");
  }
  if (document.schemaVersion !== SNAPSHOT_SCHEMA_VERSION) {
    throw new TypeError(
      `save schema version ${document.schemaVersion} cannot be read by version ${SNAPSHOT_SCHEMA_VERSION}`
    );
  }

  const seed = seedFrom(document.seed);
  const state = {
    seed,
    mapID: document.mapID,
    playerFaction: document.playerFaction,
    clock: SimulationClock.restore({ tick: document.tick }),
    random: RandomStreams.restore(seed, document.random),
    allocator: EntityIDAllocator.restore(document.allocator),
    map: WorldMap.create(document.mapID, seed),
    stock: {
      sunwoven: decodePool(document.stock.sunwoven),
      gravemark: decodePool(document.stock.gravemark)
    },
    age: { ...document.age },
    units: new EntityStore(),
    buildings: new EntityStore(),
    deposits: new EntityStore(),
    productionQueues: new Map(),
    events: new EventLog(),
    orders: decodeOrders(document.orders),
    paused: Boolean(document.paused)
  };

  for (const raw of document.units) {
    const unit = decodeUnit(raw);
    state.units.set(unit.id, unit);
  }
  for (const raw of document.buildings) {
    const building = decodeBuilding(raw);
    state.buildings.set(building.id, building);
  }
  for (const raw of document.deposits) {
    const deposit = decodeDeposit(raw);
    state.deposits.set(deposit.id, deposit);
  }
  for (const entry of document.productionQueues) {
    state.productionQueues.set(entry.buildingID, {
      items: entry.items.map((item) => ({
        kind: item.kind,
        progressTicks: item.progressTicks,
        hasStarted: item.hasStarted
      })),
      heldReason: entry.heldReason
    });
  }

  return state;
}

/** The canonical text form written across the bridge and to disk. */
export function serialiseSnapshot(state) {
  return JSON.stringify(captureSnapshot(state));
}

export function deserialiseSnapshot(text) {
  return restoreSnapshot(JSON.parse(text));
}
