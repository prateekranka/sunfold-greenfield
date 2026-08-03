// Determinism and lifecycle tests for the authoritative simulation (issue #22).
//
// Every test here is headless and fixed-clock: no render loop, no wall time,
// no unseeded randomness. The property under test is the one the whole
// migration exists for — the same seed and the same logical input produce the
// same world, however the display's frames happened to fall.

import assert from "node:assert/strict";
import test from "node:test";

import { Simulation, INPUT_LATENCY_TICKS } from "../src/sim/simulation.js";
import { RandomStreams, seedFrom } from "../src/sim/rng.js";
import { SNAPSHOT_SCHEMA_VERSION } from "../src/sim/snapshot.js";
import { MAX_STEPS_PER_FRAME, STEP_DURATION } from "../src/sim/clock.js";
import { ProductionSystem } from "../src/sim/production.js";

const SEED = 20260803;

/** The sunwoven citizens and one matter node, found by rule rather than by id. */
function sunwovenCitizens(simulation) {
  return simulation.state.units
    .ordered()
    .filter((unit) => unit.faction === "sunwoven" && unit.kind === "citizen");
}

function sunwovenMatterDeposit(simulation) {
  return simulation.state.deposits
    .ordered()
    .find((deposit) => deposit.kind === "matter" && deposit.region === "sunwovenHome");
}

function sunwovenCore(simulation) {
  return simulation.state.buildings
    .ordered()
    .find((building) => building.faction === "sunwoven" && building.kind === "civilizationCore");
}

/**
 * One fixed logical script: gather, then a group move, then a foundation and
 * a training order. Shared by the determinism tests so a divergence can never
 * be blamed on the inputs differing.
 */
function applyScript(simulation) {
  const citizens = sunwovenCitizens(simulation);
  const deposit = sunwovenMatterDeposit(simulation);
  const core = sunwovenCore(simulation);
  const anchor = simulation.state.map.regionAnchor("sunwovenHome");

  simulation.submit("gather", { unitIDs: citizens.map((unit) => unit.id), depositID: deposit.id });
  simulation.submit("move", {
    unitIDs: [citizens[citizens.length - 1].id],
    point: { x: anchor.x + 10, z: anchor.z + 4 }
  });
  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });

  const site = simulation.state.map.clampToLand({ x: anchor.x + 16, z: anchor.z - 6 }, 3.6);
  assert.ok(site, "test site must clamp onto land");
  simulation.submit("place", { kind: "farm", point: site, faction: "sunwoven", unitIDs: [] });
}

test("same seed plus same input schedule produces identical state hashes", () => {
  const first = new Simulation({ seed: SEED });
  const second = new Simulation({ seed: SEED });

  applyScript(first);
  applyScript(second);

  const checkpoints = [50, 120, 240, 400, 600];
  for (const tick of checkpoints) {
    first.runToTick(tick);
    second.runToTick(tick);
    assert.equal(first.hash(), second.hash(), `divergence by tick ${tick}`);
  }
});

test("different render frame schedules produce identical final hashes", () => {
  // Three deliveries of the same 20 simulated seconds: exact 20 Hz frames,
  // exact 60 Hz frames, and an irregular cadence. Deltas are multiples of the
  // step so every schedule lands exactly on tick 400.
  const steady = new Simulation({ seed: SEED });
  const fine = new Simulation({ seed: SEED });
  const ragged = new Simulation({ seed: SEED });
  applyScript(steady);
  applyScript(fine);
  applyScript(ragged);

  for (let frame = 0; frame < 400; frame += 1) steady.update(STEP_DURATION);
  // STEP_DURATION / 2 sums to exactly one step every two frames in IEEE 754;
  // a non-dyadic fraction would accumulate sub-ULP residue and land a tick
  // short — that is a property of float addition, not of the clock.
  for (let frame = 0; frame < 800; frame += 1) fine.update(STEP_DURATION / 2);
  const raggedDeltas = [
    STEP_DURATION * 2,
    STEP_DURATION,
    STEP_DURATION * 3,
    STEP_DURATION * 0.5,
    STEP_DURATION * 1.5
  ];
  // Sum per cycle is 8 steps; 50 cycles is exactly 400 steps.
  for (let cycle = 0; cycle < 50; cycle += 1) {
    for (const delta of raggedDeltas) ragged.update(delta);
  }

  assert.equal(steady.tick, 400);
  assert.equal(fine.tick, 400);
  assert.equal(ragged.tick, 400);
  assert.equal(steady.hash(), fine.hash());
  assert.equal(steady.hash(), ragged.hash());
});

test("a stalled frame drops its backlog rather than fast-forwarding", () => {
  const simulation = new Simulation({ seed: SEED });
  const steps = simulation.update(10);
  assert.equal(steps, MAX_STEPS_PER_FRAME);
  assert.equal(simulation.tick, MAX_STEPS_PER_FRAME);
});

test("pause and resume do not advance simulation ticks", () => {
  const simulation = new Simulation({ seed: SEED });
  simulation.runToTick(40);
  const before = simulation.hash();

  simulation.setPaused(true);
  assert.equal(simulation.update(1), 0);
  assert.equal(simulation.update(STEP_DURATION), 0);
  assert.equal(simulation.tick, 40);
  assert.equal(simulation.hash(), before);

  simulation.setPaused(false);
  simulation.update(STEP_DURATION);
  assert.equal(simulation.tick, 41);
});

test("delivery jitter inside the input-latency window cannot change an outcome", () => {
  // The same logical move order, delivered at three different accumulator
  // offsets that all fall inside tick 20. Each is stamped for tick 22, so all
  // three matches are the same match.
  const runs = [0, STEP_DURATION * 0.4, STEP_DURATION * 0.9].map((offset) => {
    const simulation = new Simulation({ seed: SEED });
    simulation.runToTick(20);
    simulation.update(offset); // sub-step residue; the tick does not move
    assert.equal(simulation.tick, 20);
    const citizen = sunwovenCitizens(simulation)[0];
    const scheduled = simulation.submit("move", {
      unitIDs: [citizen.id],
      point: { x: citizen.position.x + 6, z: citizen.position.z }
    });
    assert.equal(scheduled, 20 + INPUT_LATENCY_TICKS);
    simulation.runToTick(200);
    return simulation;
  });

  assert.equal(runs[0].hash(), runs[1].hash());
  assert.equal(runs[0].hash(), runs[2].hash());
});

test("a recorded input script replays identically", () => {
  const live = new Simulation({ seed: SEED });
  applyScript(live);
  live.runToTick(500);

  const replayed = new Simulation({ seed: SEED });
  replayed.loadInputScript(live.state.orders.script);
  replayed.runToTick(500);

  assert.equal(replayed.hash(), live.hash());
});

test("save/restore continuation matches uninterrupted play, orders in flight included", () => {
  const uninterrupted = new Simulation({ seed: SEED });
  applyScript(uninterrupted);
  uninterrupted.runToTick(100);

  // An order still in flight at save time: scheduled for tick 102, saved at
  // tick 101. If the queue did not ride the snapshot, the restored match would
  // never apply it and the two runs would diverge at tick 102.
  const citizen = sunwovenCitizens(uninterrupted)[0];
  uninterrupted.submit("move", {
    unitIDs: [citizen.id],
    point: { x: citizen.position.x - 5, z: citizen.position.z + 3 }
  });
  uninterrupted.runToTick(101);
  assert.equal(uninterrupted.state.orders.pending.length, 1);

  const document = JSON.parse(JSON.stringify(uninterrupted.save()));
  const restored = Simulation.restore(document);

  // The snapshot round trip is exact: re-saving the restore reproduces the
  // document, order state included.
  assert.deepEqual(restored.save(), uninterrupted.save());

  for (const tick of [102, 150, 300, 500]) {
    uninterrupted.runToTick(tick);
    restored.runToTick(tick);
    assert.equal(restored.hash(), uninterrupted.hash(), `restored run diverged by tick ${tick}`);
  }
  assert.equal(restored.state.orders.pending.length, 0, "the in-flight order has landed by now");
});

test("tagged RNG streams stay independent when another subsystem draws", () => {
  const seed = seedFrom(SEED);
  const untouched = new RandomStreams(seed);
  const drawn = new RandomStreams(seed);

  // Several subsystems consume their streams at different rates.
  drawn.stream("world.populate").float(0, 1);
  drawn.stream("world.populate").float(0, 1);
  drawn.stream("movement.jitter").int(6);
  drawn.stream("adversary.plan").unitFloat();

  // A stream no one touched is completely unaffected.
  const expected = untouched.stream("gathering.station");
  const actual = drawn.stream("gathering.station");
  for (let index = 0; index < 8; index += 1) {
    assert.equal(actual.unitFloat(), expected.unitFloat());
  }
});

test("unit movement resolves deterministically for a group order", () => {
  const first = new Simulation({ seed: SEED });
  const second = new Simulation({ seed: SEED });
  const anchor = first.state.map.regionAnchor("sunwovenHome");
  const ids = sunwovenCitizens(first).map((unit) => unit.id);

  first.submit("move", { unitIDs: ids, point: { x: anchor.x + 18, z: anchor.z + 9 } });
  second.submit("move", { unitIDs: ids, point: { x: anchor.x + 18, z: anchor.z + 9 } });
  first.runToTick(260);
  second.runToTick(260);

  const firstPositions = sunwovenCitizens(first).map((unit) => [unit.position.x, unit.position.z]);
  const secondPositions = sunwovenCitizens(second).map((unit) => [unit.position.x, unit.position.z]);
  assert.deepEqual(firstPositions, secondPositions);
  // A formation actually formed: the four citizens did not pile onto one point.
  const distinct = new Set(firstPositions.map(([x, z]) => `${x.toFixed(3)},${z.toFixed(3)}`));
  assert.ok(distinct.size > 1, "group order must spread into formation slots");
});

test("iteration over entities is in ascending id order", () => {
  const simulation = new Simulation({ seed: SEED });
  const unitIDs = simulation.state.units.orderedIDs();
  const sorted = [...unitIDs].sort((left, right) => left - right);
  assert.deepEqual(unitIDs, sorted);
  const buildingIDs = simulation.state.buildings.orderedIDs();
  assert.deepEqual(buildingIDs, [...buildingIDs].sort((left, right) => left - right));
});

test("unknown order kinds are rejected", () => {
  const simulation = new Simulation({ seed: SEED });
  assert.throws(() => simulation.submit("terraform", {}), /unknown order kind/);
});

test("snapshot schema versions fail closed when stale, future, or malformed", () => {
  const simulation = new Simulation({ seed: SEED });
  simulation.runToTick(30);
  const document = simulation.save();
  assert.equal(document.schemaVersion, SNAPSHOT_SCHEMA_VERSION);

  assert.throws(
    () => Simulation.restore({ ...document, schemaVersion: SNAPSHOT_SCHEMA_VERSION - 1 }),
    /schema version/
  );
  assert.throws(
    () => Simulation.restore({ ...document, schemaVersion: SNAPSHOT_SCHEMA_VERSION + 1 }),
    /schema version/
  );
  assert.throws(() => Simulation.restore(null), /not an object/);
  assert.throws(() => Simulation.restore("a save"), /not an object/);
  assert.throws(() => Simulation.restore({}), /schema version/);

  const withoutOrders = { ...document };
  delete withoutOrders.orders;
  assert.throws(() => Simulation.restore(withoutOrders), /order state/);
});

test("save/restore preserves production queue start and hold state exactly", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);

  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.runToTick(3); // front started; second item queued, still unstarted

  // A hold is exactly the state ProductionSystem.step writes when the front
  // cannot spawn; set it directly to prove the snapshot carries the field.
  const queue = simulation.state.productionQueues.get(core.id);
  queue.heldReason = "noSpawnPosition";
  assert.equal(queue.items[0].hasStarted, true);
  assert.equal(queue.items[1].hasStarted, false);

  const document = simulation.save();
  const savedQueue = document.productionQueues.find((entry) => entry.buildingID === core.id);
  assert.equal(savedQueue.items[0].hasStarted, true);
  assert.equal(savedQueue.items[1].hasStarted, false);
  assert.equal(savedQueue.heldReason, "noSpawnPosition");

  const restored = Simulation.restore(document);
  // The snapshot round trip is exact: re-saving the restore reproduces the
  // document, queue fields included.
  assert.deepEqual(restored.save(), simulation.save());
  const restoredQueue = restored.state.productionQueues.get(core.id);
  assert.equal(restoredQueue.items[0].hasStarted, true);
  assert.equal(restoredQueue.items[1].hasStarted, false);
  assert.equal(restoredQueue.heldReason, "noSpawnPosition");

  // And the restored match continues identically: the started front keeps
  // progressing, the queued item behind it is untouched, and the hold gates
  // the same way.
  for (const tick of [10, 30, 60]) {
    simulation.runToTick(tick);
    restored.runToTick(tick);
    assert.equal(restored.hash(), simulation.hash(), `queue continuation diverged by tick ${tick}`);
  }
});

test("world hash fingerprints queue start and hold state", () => {
  const first = new Simulation({ seed: SEED });
  const second = new Simulation({ seed: SEED });

  ProductionSystem.enqueue(first.state, "citizen", sunwovenCore(first).id);
  ProductionSystem.enqueue(second.state, "citizen", sunwovenCore(second).id);

  first.runToTick(1); // started the front on the first run only
  assert.notEqual(first.hash(), second.hash(), "an unstarted and a started front must differ");

  second.runToTick(1);
  assert.equal(first.hash(), second.hash(), "both fronts started, the hashes agree");

  first.state.productionQueues.get(sunwovenCore(first).id).heldReason = "populationCap";
  assert.notEqual(first.hash(), second.hash(), "a held front must hash differently");
});
