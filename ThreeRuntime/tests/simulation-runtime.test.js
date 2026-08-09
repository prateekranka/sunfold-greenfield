// Runtime session lifecycle for the authoritative simulation (issue #22).
//
// `SimulationSession` is the headless part of the runtime's ownership: exactly
// one simulation per started or restored match, time enters only as render
// deltas, serialisation happens only on `save()`, and `dispose()` ends
// ownership so a return to the menu leaves nothing advancing behind a scene
// that no longer exists. `main.js` forwards bridge commands straight into
// these methods, so proving them here proves the lifecycle.

import assert from "node:assert/strict";
import test from "node:test";

import { SimulationSession } from "../src/sim/session.js";
import { Simulation } from "../src/sim/simulation.js";
import { STEP_DURATION } from "../src/sim/clock.js";

const SEED = 20260803;

function homeMatterDeposit(simulation) {
  return simulation.state.deposits
    .ordered()
    .find((deposit) => deposit.kind === "matter" && deposit.region === "sunwovenHome");
}

function sunwovenCitizens(simulation) {
  return simulation.state.units
    .ordered()
    .filter((unit) => unit.faction === "sunwoven" && unit.kind === "citizen");
}

test("a fresh session owns no simulation and manufactures no time", () => {
  const session = new SimulationSession();
  assert.equal(session.active, false);
  assert.equal(session.paused, false);
  assert.equal(session.hash(), null);
  assert.equal(session.save(), null);
  assert.equal(session.update(1), 0);
  assert.equal(session.update(STEP_DURATION * 10), 0);
});

test("start owns one active simulation and update advances it through render deltas", () => {
  const session = new SimulationSession();
  const simulation = session.start({ seed: SEED });
  assert.equal(session.active, true);
  assert.ok(simulation instanceof Simulation);
  assert.equal(simulation.tick, 0);

  for (let frame = 0; frame < 20; frame += 1) session.update(STEP_DURATION);
  assert.equal(simulation.tick, 20);
  assert.ok(session.hash());
});

test("start replaces the previous simulation outright", () => {
  const session = new SimulationSession();
  const first = session.start({ seed: SEED });
  first.runToTick(50);
  const second = session.start({ seed: SEED });
  assert.equal(session.active, true);
  assert.equal(second.tick, 0);
  assert.notEqual(session.hash(), first.hash());
});

test("pause and resume flow through the session without advancing ticks", () => {
  const session = new SimulationSession();
  session.start({ seed: SEED });
  for (let frame = 0; frame < 40; frame += 1) session.update(STEP_DURATION);
  const frozen = session.hash();

  session.setPaused(true);
  assert.equal(session.paused, true);
  assert.equal(session.update(STEP_DURATION * 5), 0);
  assert.equal(session.hash(), frozen, "paused time must not advance the world");

  session.setPaused(false);
  assert.equal(session.paused, false);
  assert.equal(session.update(STEP_DURATION), 1);
  assert.notEqual(session.hash(), frozen, "resumed time must advance the world");
});

test("save and restore through the session continue the same match", () => {
  const live = new SimulationSession();
  const simulation = live.start({ seed: SEED });

  for (let frame = 0; frame < 100; frame += 1) live.update(STEP_DURATION);
  const citizen = sunwovenCitizens(simulation)[0];
  const deposit = homeMatterDeposit(simulation);
  simulation.submit("gather", { unitIDs: [citizen.id], depositID: deposit.id });
  for (let frame = 100; frame < 200; frame += 1) live.update(STEP_DURATION);

  const document = live.save();
  assert.ok(document, "an active match must save a document");
  assert.equal(document.tick, 200);

  const restored = new SimulationSession();
  restored.restore(document);
  assert.equal(restored.active, true);
  assert.equal(restored.save().tick, 200);
  assert.equal(restored.hash(), live.hash(), "restore reproduces the exact world");

  // Both sessions keep producing the same match from the same render deltas.
  for (let frame = 0; frame < 100; frame += 1) {
    live.update(STEP_DURATION);
    restored.update(STEP_DURATION);
  }
  assert.equal(restored.hash(), live.hash(), "both sessions advance the same match");
});

test("a paused save restores paused and advances no time", () => {
  const session = new SimulationSession();
  session.start({ seed: SEED });
  session.update(STEP_DURATION * 40);
  session.setPaused(true);
  const document = session.save();
  assert.equal(document.paused, true);

  const restored = new SimulationSession();
  restored.restore(document);
  assert.equal(restored.paused, true);
  const frozen = restored.hash();
  assert.equal(restored.update(STEP_DURATION * 10), 0);
  assert.equal(restored.hash(), frozen, "a restored pause must still gate time");
});

test("restore refuses a malformed document and keeps the current match", () => {
  const session = new SimulationSession();
  session.start({ seed: SEED });
  session.update(STEP_DURATION * 30);
  const before = session.hash();

  assert.throws(() => session.restore({}), /schema version/);
  assert.equal(session.active, true);
  assert.equal(session.hash(), before, "a failed restore must not disturb the live match");
});

test("dispose ends ownership and update becomes a no-op", () => {
  const session = new SimulationSession();
  session.start({ seed: SEED });
  session.update(STEP_DURATION * 10);
  assert.equal(session.active, true);

  session.dispose();
  assert.equal(session.active, false);
  assert.equal(session.paused, false);
  assert.equal(session.update(STEP_DURATION * 10), 0);
  assert.equal(session.save(), null);
  assert.equal(session.hash(), null);
});
