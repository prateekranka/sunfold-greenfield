// The one authoritative simulation. It owns all game truth.
//
// Issue #19 moved simulation ownership inside the Three.js runtime; issue #22
// makes that ownership real. Nothing in Swift decides a rule any more, and
// nothing crosses the bridge per frame. The renderer projects this state; it
// never writes to it.

import { SimulationClock, MAX_STEPS_PER_FRAME, SIMULATION_HZ, STEP_DURATION } from "./clock.js";
import { EntityIDAllocator, EntityStore } from "./ids.js";
import { RandomStreams, seedFrom } from "./rng.js";
import { EventLog } from "./events.js";
import { worldHash, WORLD_HASH_LAYOUT_VERSION } from "./hash.js";
import { TUNING } from "./tuning.js";
import { addPools, clonePool, scalePool } from "./types.js";
import { WorldMap } from "./world.js";
import { populate } from "./populate.js";
import { MovementSystem } from "./movement.js";
import { GatheringSystem } from "./gathering.js";
import { ConstructionSystem } from "./construction.js";
import { ProductionSystem } from "./production.js";
import { AnimationController } from "./animation.js";
import { captureSnapshot, restoreSnapshot, SNAPSHOT_SCHEMA_VERSION } from "./snapshot.js";

/**
 * How far ahead of the current tick an order from outside the runtime is
 * scheduled.
 *
 * This is the whole answer to "no gameplay outcome depends on bridge-message
 * latency". An order is never applied on the tick it arrives; it is stamped for
 * `tick + INPUT_LATENCY_TICKS` and applied at that tick boundary. Any delivery
 * jitter smaller than that window therefore lands on the same tick and produces
 * the same match. Two ticks at 20 Hz is 100 ms — far above any plausible
 * `evaluateJavaScript` round trip, and small enough to stay imperceptible.
 */
export const INPUT_LATENCY_TICKS = 2;

/** The order kinds the runtime accepts. Closed set — an unknown kind is an error. */
export const ORDER_KINDS = Object.freeze([
  "move",
  "gather",
  "construct",
  "place",
  "cancelConstruction",
  "enqueue",
  "cancelProduction",
  "interrupt"
]);

export class Simulation {
  constructor({ seed = 20260803, mapID = "riverlands", playerFaction = "sunwoven" } = {}) {
    const resolvedSeed = seedFrom(seed);
    this.state = {
      seed: resolvedSeed,
      mapID,
      playerFaction,
      clock: new SimulationClock(),
      random: new RandomStreams(resolvedSeed),
      allocator: new EntityIDAllocator(),
      map: WorldMap.create(mapID, resolvedSeed),
      stock: {
        sunwoven: clonePool(TUNING.startingResources),
        gravemark: clonePool(TUNING.startingResources)
      },
      age: { sunwoven: "foundation", gravemark: "foundation" },
      units: new EntityStore(),
      buildings: new EntityStore(),
      deposits: new EntityStore(),
      productionQueues: new Map(),
      events: new EventLog(),
      /**
       * Order scheduling state. `pending` holds orders waiting for their
       * scheduled tick, in arrival order; `sequence` is the monotonic counter
       * that keeps two orders scheduled for one tick in a fixed order;
       * `script` is every order ever accepted — the replayable input script.
       *
       * This is simulation truth like any other: a match saved with an order
       * still in flight must apply that order on the same tick after a
       * restore, or the restored match is a different match. It is therefore
       * part of the state, saved and hashed with everything else.
       */
      orders: { sequence: 0, pending: [], script: [] },
      paused: false
    };
    populate(this.state);
  }

  // MARK: - Readouts

  get tick() {
    return this.state.clock.tick;
  }

  get elapsed() {
    return this.state.clock.elapsed;
  }

  get paused() {
    return this.state.paused;
  }

  /** Canonical fingerprint of the whole world. Two runs that agree here played the same match. */
  hash() {
    return worldHash(this.state);
  }

  stock(faction) {
    return this.state.stock[faction];
  }

  population(faction) {
    return ProductionSystem.populationCommitment(this.state, faction);
  }

  /**
   * A stable description of the rules this build runs, for evidence headers.
   * Every number here is one a determinism report has to state anyway.
   */
  static describe() {
    return {
      simulationHz: SIMULATION_HZ,
      stepDuration: STEP_DURATION,
      maxStepsPerFrame: MAX_STEPS_PER_FRAME,
      inputLatencyTicks: INPUT_LATENCY_TICKS,
      worldHashLayoutVersion: WORLD_HASH_LAYOUT_VERSION,
      snapshotSchemaVersion: SNAPSHOT_SCHEMA_VERSION
    };
  }

  // MARK: - Orders

  /**
   * Accepts an order from outside the simulation.
   *
   * Nothing is applied here. The order is stamped for a future tick and applied
   * at that boundary, which is what makes the outcome independent of when the
   * message actually arrived.
   */
  submit(kind, payload = {}) {
    if (!ORDER_KINDS.includes(kind)) throw new RangeError(`unknown order kind: ${kind}`);
    const orders = this.state.orders;
    const order = {
      kind,
      payload,
      scheduledTick: this.state.clock.tick + INPUT_LATENCY_TICKS,
      sequence: orders.sequence
    };
    orders.sequence += 1;
    orders.pending.push(order);
    orders.script.push({ kind, payload, scheduledTick: order.scheduledTick, sequence: order.sequence });
    return order.scheduledTick;
  }

  /**
   * Replays a recorded input script exactly, ignoring arrival time entirely.
   * The benchmark in #27 and every determinism test drive the runtime this way.
   */
  loadInputScript(script) {
    this.state.orders.pending = script.map((entry) => ({ ...entry }));
    this.state.orders.script = script.map((entry) => ({ ...entry }));
    this.state.orders.sequence = script.reduce((max, entry) => Math.max(max, entry.sequence + 1), 0);
  }

  /** Applies every order scheduled for the tick about to run, in a fixed order. */
  applyScheduledOrders() {
    const tick = this.state.clock.tick;
    const orders = this.state.orders;
    const due = orders.pending.filter((order) => order.scheduledTick <= tick);
    if (due.length === 0) return;
    orders.pending = orders.pending.filter((order) => order.scheduledTick > tick);

    // Scheduled tick first, then arrival sequence. Never wall-clock.
    due.sort((left, right) =>
      left.scheduledTick === right.scheduledTick
        ? left.sequence - right.sequence
        : left.scheduledTick - right.scheduledTick
    );
    for (const order of due) this.applyOrder(order);
  }

  applyOrder(order) {
    const state = this.state;
    const payload = order.payload;
    switch (order.kind) {
      case "move":
        this.orderMove(payload.unitIDs, payload.point);
        break;
      case "gather":
        GatheringSystem.orderGather(state, payload.unitIDs, payload.depositID);
        break;
      case "construct":
        ConstructionSystem.assignBuilders(state, payload.buildingID, payload.faction, payload.unitIDs);
        break;
      case "place":
        ConstructionSystem.placeBuilding(
          state,
          payload.kind,
          payload.point,
          payload.faction,
          payload.unitIDs || []
        );
        break;
      case "cancelConstruction":
        ConstructionSystem.cancelConstruction(state, payload.buildingID);
        break;
      case "enqueue":
        ProductionSystem.enqueue(state, payload.kind, payload.buildingID);
        break;
      case "cancelProduction":
        ProductionSystem.cancelFront(state, payload.buildingID);
        break;
      case "interrupt":
        for (const id of [...(payload.unitIDs || [])].sort((left, right) => left - right)) {
          const unit = state.units.get(id);
          if (unit) AnimationController.requestInterrupt(state, unit);
        }
        break;
      default:
        throw new RangeError(`unhandled order kind: ${order.kind}`);
    }
  }

  /**
   * Ordering several units to one point spreads them so they do not pile onto a
   * single coordinate. Slots derive from durable ids, never from collection
   * order, so the same unit keeps the same slot every time.
   */
  orderMove(unitIDs, point) {
    const ordered = [...unitIDs].sort((left, right) => left - right);
    ordered.forEach((id, index) => {
      const unit = this.state.units.get(id);
      if (!unit) return;
      const offset = formationOffset(index, ordered.length);
      const route = MovementSystem.resolveOrder(
        { x: point.x + offset.x, z: point.z + offset.z },
        unit,
        this.state
      );
      if (!route) return;
      unit.assignment = null;
      unit.destination = route.destination;
      unit.movementPath = route.waypoints;
      unit.movementPathTarget = route.destination;
      unit.activity = { tag: "moving", subject: null };
      AnimationController.requestInterrupt(this.state, unit);
    });
  }

  // MARK: - Lifecycle

  setPaused(paused) {
    this.state.paused = Boolean(paused);
  }

  /**
   * Advances simulated time by a frame's worth of real time.
   *
   * A paused game does not step. Surplus time beyond `maxStepsPerFrame` is
   * dropped by the clock rather than replayed as a burst.
   */
  update(deltaTime) {
    if (this.state.paused) return 0;
    const steps = this.state.clock.advance(deltaTime);
    const clock = this.state.clock;
    // `advance` has already summed the batch into `tick`, but every step must
    // run at its own tick boundary. If a frame covering several ticks ran all
    // `step()` calls under the batch's final tick, orders scheduled for the
    // intermediate ticks would apply back to back with no simulation tick
    // between them and the match would change with the render cadence. Rewind
    // to the step before the batch and walk up one tick at a time, exactly as
    // `runToTick` does.
    const base = clock.tick - steps;
    for (let index = 0; index < steps; index += 1) {
      clock.tick = base + index + 1;
      clock.elapsed = clock.tick * clock.stepDuration;
      this.step();
    }
    return steps;
  }

  /** Runs whole ticks directly. Tests and the benchmark drive time this way. */
  runToTick(targetTick) {
    while (this.state.clock.tick < targetTick) {
      this.state.clock.tick += 1;
      this.state.clock.elapsed = this.state.clock.tick * this.state.clock.stepDuration;
      this.step();
    }
    return this.state.clock.tick;
  }

  /**
   * One fixed simulation step. Everything rule-bearing happens here, in this
   * order, matching the Swift original.
   */
  step() {
    const state = this.state;
    const seconds = state.clock.stepDuration;

    this.applyScheduledOrders();

    // Both sides receive the identical Core trickle. The AI is never granted
    // hidden income; difficulty changes planning, not accounting.
    const trickle = scalePool(TUNING.coreTrickle, seconds);
    state.stock.sunwoven = addPools(state.stock.sunwoven, trickle);
    state.stock.gravemark = addPools(state.stock.gravemark, trickle);

    // Gathering decides where citizens want to be; movement then carries them
    // there. Running it first means a citizen that finishes a load this step
    // starts walking home in the same step rather than idling for one tick.
    GatheringSystem.step(state, seconds);
    ConstructionSystem.step(state, seconds);
    MovementSystem.step(state, seconds);
    ProductionSystem.step(state);

    // Last, so it reacts to the state every other system just produced.
    AnimationController.step(state, seconds);
  }

  // MARK: - Save and restore

  save() {
    return captureSnapshot(this.state);
  }

  /**
   * Restores a snapshot into a live simulation.
   *
   * The scheduled-order state rides the snapshot like everything else, so an
   * order in flight when the save was taken lands on its scheduled tick after
   * the reload — a restored match continues as the same match, which is the
   * whole contract of saving.
   */
  static restore(document) {
    const simulation = Object.create(Simulation.prototype);
    simulation.state = restoreSnapshot(document);
    return simulation;
  }
}

/** A stable, outward-growing ring so groups arrive as a readable cluster. */
function formationOffset(index, count) {
  if (count <= 1 || index === 0) return { x: 0, z: 0 };
  const ring = Math.floor(index / 6) + 1;
  const slotsInRing = ring * 6;
  const slot = (index - 1) % slotsInRing;
  const angle = (slot / slotsInRing) * 2 * Math.PI;
  const radius = ring * 2.2;
  return { x: Math.sin(angle) * radius, z: Math.cos(angle) * radius };
}
