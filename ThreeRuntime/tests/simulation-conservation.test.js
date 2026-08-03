// Resource and cargo conservation for the authoritative simulation (issue #22).
//
// Matter is the countable resource: deposits hold a finite pile, citizens
// accrue it against the pile, commit it to their backs and deliver it to a
// drop-off, and the Core trickle adds a fixed amount every tick. The ledger
// below says matter can only ever move between deposits, carriers and the two
// stockpiles — a gather creates none of it, an interrupt loses none of it, and
// construction spends and refunds it by exactly the authored rule.

import assert from "node:assert/strict";
import test from "node:test";

import { Simulation, INPUT_LATENCY_TICKS } from "../src/sim/simulation.js";
import { STEP_DURATION } from "../src/sim/clock.js";
import { TUNING } from "../src/sim/tuning.js";
import { ProductionSystem } from "../src/sim/production.js";

const SEED = 20260803;

/** Core trickle of matter into BOTH stockpiles per fixed tick (0.2/s each × step). */
const MATTER_TRICKLE_PER_TICK = TUNING.coreTrickle.matter * STEP_DURATION * 2;

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

function sunwovenFarm(simulation) {
  return simulation.state.buildings.ordered().find((building) => building.kind === "farm");
}

function sunwovenCore(simulation) {
  return simulation.state.buildings
    .ordered()
    .find((building) => building.faction === "sunwoven" && building.kind === "civilizationCore");
}

/**
 * Matter that has left a deposit for good: committed cargo on carriers, chunks
 * mid-flight, and both stockpiles.
 *
 * `unit.pending` is deliberately excluded. It is speculative accrual against a
 * deposit's *future* yield — the deposit still holds that matter until a
 * `gather_contact` debits the pile, so counting pending would double-count the
 * same matter for as long as a citizen stands and accrues. Excluding it makes
 * the identity hold on every tick, not just between contacts.
 */
function committedMatter(simulation) {
  let matter = 0;
  for (const deposit of simulation.state.deposits.ordered()) {
    if (deposit.kind === "matter") matter += deposit.remaining;
  }
  for (const unit of simulation.state.units.ordered()) {
    if (unit.cargo && unit.cargo.kind === "matter") matter += unit.cargo.amount;
    for (const chunk of unit.animation.airborneChunks) {
      if (chunk.kind === "matter") matter += chunk.amount;
    }
  }
  matter += simulation.stock("sunwoven").matter;
  matter += simulation.stock("gravemark").matter;
  return matter;
}

test("matter is conserved across a full gather, delivery and deposit cycle", () => {
  const simulation = new Simulation({ seed: SEED });
  const deposit = homeMatterDeposit(simulation);
  const initialRemaining = deposit.remaining;
  const initialStock = simulation.stock("sunwoven").matter;
  const start = committedMatter(simulation);

  const citizens = sunwovenCitizens(simulation);
  simulation.submit("gather", { unitIDs: citizens.map((unit) => unit.id), depositID: deposit.id });

  for (const tick of [100, 400, 800, 1200]) {
    simulation.runToTick(tick);
    const expected = start + MATTER_TRICKLE_PER_TICK * tick;
    assert.ok(
      Math.abs(committedMatter(simulation) - expected) < 1e-6,
      `the matter ledger drifted by tick ${tick}`
    );
  }

  // The identity only proves anything if a real cycle ran: matter left the
  // pile and at least one load reached the stockpile.
  assert.ok(deposit.remaining < initialRemaining, "the deposit must have been drawn down");
  assert.ok(
    simulation.stock("sunwoven").matter > initialStock,
    "a delivered load must have reached stock"
  );
});

test("speculative accrual is not debited until a gather_contact commits it", () => {
  const simulation = new Simulation({ seed: SEED });
  const deposit = homeMatterDeposit(simulation);
  const citizen = sunwovenCitizens(simulation)[0];
  const initial = deposit.remaining;
  const accrualPerTick = TUNING.gatherRates.matter * STEP_DURATION;

  simulation.submit("gather", { unitIDs: [citizen.id], depositID: deposit.id });

  let stoodAt = null;
  let debitTick = null;
  let debit = 0;
  for (let tick = 1; tick <= 400; tick += 1) {
    simulation.runToTick(tick);
    if (debitTick !== null) break;
    const unit = simulation.state.units.get(citizen.id);
    const standing = unit.pending && unit.pending.amount > 0;
    if (standing) {
      stoodAt ??= tick;
      assert.equal(deposit.remaining, initial, `the pile moved before a contact (tick ${tick})`);
    } else if (deposit.remaining < initial) {
      debitTick = tick;
      debit = initial - deposit.remaining;
    }
  }

  assert.ok(stoodAt !== null, "the citizen must accrue pending while the pile stands still");
  assert.ok(debitTick !== null, "a gather_contact must eventually debit the pile");
  assert.ok(debit > 0, "the contact must move matter");

  // The debit is a whole number of per-tick accrual steps — the full standing
  // pending, nothing more and nothing less. No fractional skimming, no double
  // debit of the same accrued amount.
  const steps = debit / accrualPerTick;
  assert.ok(
    Math.abs(steps - Math.round(steps)) < 1e-6,
    `a contact must debit whole accrued steps only (${debit} / ${accrualPerTick})`
  );
});

test("an interrupt abandons speculative accrual without touching the deposit", () => {
  const simulation = new Simulation({ seed: SEED });
  const deposit = homeMatterDeposit(simulation);
  const citizen = sunwovenCitizens(simulation)[0];
  const initial = deposit.remaining;

  simulation.submit("gather", { unitIDs: [citizen.id], depositID: deposit.id });

  // A stand with the tool attached, accruing, and several ticks clear of the
  // next contact phase — the window where an interrupt can only abandon what
  // has not been committed yet.
  let interruptAt = null;
  for (let tick = 1; tick <= 300; tick += 1) {
    simulation.runToTick(tick);
    const unit = simulation.state.units.get(citizen.id);
    const standing = unit.pending && unit.pending.amount > 0;
    if (
      standing &&
      unit.animation.state === "workLoop" &&
      unit.animation.phaseTicks <= 6 &&
      deposit.remaining === initial
    ) {
      interruptAt = tick;
      break;
    }
  }
  assert.ok(interruptAt !== null, "the citizen must reach an accruing, pre-contact stand");

  const ledgerBefore = committedMatter(simulation);
  simulation.submit("interrupt", { unitIDs: [citizen.id] });

  // The order applies INPUT_LATENCY_TICKS ahead, and its first effect is to
  // cut the work cycle short: the tool is on its way back to its rest.
  simulation.runToTick(interruptAt + INPUT_LATENCY_TICKS);
  assert.equal(
    simulation.state.units.get(citizen.id).animation.state,
    "cleanup",
    "the interrupt must engage the cleanup path"
  );

  // Well before the citizen could accrue back to another contact, nothing has
  // left the pile and the ledger is exactly where it was plus the trickle.
  simulation.runToTick(interruptAt + 15);
  assert.equal(deposit.remaining, initial, "no contact fired across the interrupt");
  assert.ok(
    Math.abs(committedMatter(simulation) - (ledgerBefore + MATTER_TRICKLE_PER_TICK * 15)) < 1e-6,
    "the ledger is conserved across the interrupt"
  );
});

test("a committed chunk survives an interrupt and still lands", () => {
  const simulation = new Simulation({ seed: SEED });
  const deposit = homeMatterDeposit(simulation);
  const citizen = sunwovenCitizens(simulation)[0];

  simulation.submit("gather", { unitIDs: [citizen.id], depositID: deposit.id });

  // First chunk committed at a gather_contact and now mid-arc.
  let airborneAt = null;
  let chunkAmount = null;
  for (let tick = 1; tick <= 300; tick += 1) {
    simulation.runToTick(tick);
    const unit = simulation.state.units.get(citizen.id);
    if (unit.animation.airborneChunks.length > 0) {
      airborneAt = tick;
      chunkAmount = unit.animation.airborneChunks[0].amount;
      break;
    }
  }
  assert.ok(airborneAt !== null, "a chunk must enter flight");
  assert.ok(chunkAmount > 0, "the committed chunk must carry matter");

  const ledgerBefore = committedMatter(simulation);
  simulation.submit("interrupt", { unitIDs: [citizen.id] });
  simulation.runToTick(airborneAt + 4);

  const unit = simulation.state.units.get(citizen.id);
  assert.equal(unit.animation.airborneChunks.length, 0, "the committed chunk lands despite the interrupt");
  assert.ok(
    unit.cargo && unit.cargo.kind === "matter" && unit.cargo.amount >= chunkAmount - 1e-9,
    "the chunk arrives on the carrier's back"
  );

  simulation.runToTick(airborneAt + 40);
  assert.ok(
    Math.abs(committedMatter(simulation) - (ledgerBefore + MATTER_TRICKLE_PER_TICK * 40)) < 1e-6,
    "the ledger is conserved across the interrupt"
  );
});

test("placing a foundation charges its exact cost and cancelling refunds the exact fraction", () => {
  const simulation = new Simulation({ seed: SEED });
  const anchor = simulation.state.map.regionAnchor("sunwovenHome");
  const site = simulation.state.map.clampToLand({ x: anchor.x + 16, z: anchor.z - 6 }, 3.6);
  assert.ok(site, "the test site must clamp onto land");

  const cost = TUNING.farmCost.matter;
  const tricklePerTick = TUNING.coreTrickle.matter * STEP_DURATION;
  const initial = simulation.stock("sunwoven").matter;

  simulation.submit("place", { kind: "farm", point: site, faction: "sunwoven", unitIDs: [] });
  simulation.runToTick(10);

  const farm = sunwovenFarm(simulation);
  assert.ok(farm, "the foundation must exist after placement");
  assert.ok(farm.constructionProgress < 1, "the foundation starts incomplete");
  assert.ok(
    Math.abs(simulation.stock("sunwoven").matter - (initial - cost + tricklePerTick * 10)) < 1e-9,
    "placement charges exactly the cost"
  );

  const beforeCancel = simulation.stock("sunwoven").matter;
  simulation.submit("cancelConstruction", { buildingID: farm.id });
  simulation.runToTick(20);

  assert.equal(sunwovenFarm(simulation), undefined, "the foundation is gone");
  assert.ok(
    Math.abs(
      simulation.stock("sunwoven").matter -
        (beforeCancel + cost * TUNING.cancelRefundFraction + tricklePerTick * 10)
    ) < 1e-9,
    "cancellation refunds exactly cost × cancelRefundFraction"
  );
});

test("construction progress is linear in builder count", () => {
  const buildRun = (unitIDs) => {
    const simulation = new Simulation({ seed: SEED });
    const anchor = simulation.state.map.regionAnchor("sunwovenHome");
    const site = simulation.state.map.clampToLand({ x: anchor.x + 16, z: anchor.z - 6 }, 3.6);
    simulation.submit("place", { kind: "farm", point: site, faction: "sunwoven", unitIDs });
    let started = null;
    let done = null;
    for (let tick = 1; tick <= 500; tick += 1) {
      simulation.runToTick(tick);
      const farm = sunwovenFarm(simulation);
      if (farm && started === null && farm.constructionProgress > 0) started = tick;
      if (farm && farm.constructionProgress >= 1) {
        done = tick;
        break;
      }
    }
    assert.ok(started !== null && done !== null, "the foundation must build");
    return { started, done, workTicks: done - started };
  };

  // One builder: the steady-state slope is exactly builders × dt / buildTime,
  // so the whole build is the authored build time.
  const solo = new Simulation({ seed: SEED });
  const anchor = solo.state.map.regionAnchor("sunwovenHome");
  const site = solo.state.map.clampToLand({ x: anchor.x + 16, z: anchor.z - 6 }, 3.6);
  solo.submit("place", { kind: "farm", point: site, faction: "sunwoven", unitIDs: [2] });
  solo.runToTick(120);
  const p120 = sunwovenFarm(solo).constructionProgress;
  solo.runToTick(300);
  const p300 = sunwovenFarm(solo).constructionProgress;
  const slope = (p300 - p120) / 180;
  const expectedSlope = STEP_DURATION / TUNING.farmBuildTime;
  assert.ok(p120 > 0 && p300 < 1, "the slope window must sit inside the build");
  assert.ok(Math.abs(slope - expectedSlope) < 1e-9, "one builder advances exactly dt / buildTime");

  // Four builders finish strictly sooner than one — the rule that progress is
  // linear in builder count, not a fixed-rate progress bar.
  const soloRun = buildRun([2]);
  const fullRun = buildRun([2, 3, 4, 5]);
  assert.ok(
    fullRun.workTicks < soloRun.workTicks,
    `more builders must finish sooner (${fullRun.workTicks} vs ${soloRun.workTicks})`
  );
});

test("a new queue item starts unstarted and the first production step starts it", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);
  assert.ok(core, "the sunwoven Core must exist");

  const result = ProductionSystem.enqueue(simulation.state, "citizen", core.id);
  assert.equal(result.ok, true);
  const front = simulation.state.productionQueues.get(core.id).items[0];
  assert.equal(front.progressTicks, 0);
  assert.equal(front.hasStarted, false, "a new item has not received a tick yet");

  simulation.runToTick(1);
  const started = simulation.state.productionQueues.get(core.id).items[0];
  assert.equal(started.hasStarted, true, "the first production step marks the front started");
  assert.equal(started.progressTicks, 1, "the first step also advances progress");
});

test("cancelling an unstarted front item refunds the full cost", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);

  // Both orders land on the same tick — the enqueue, then the cancel — so the
  // item is removed before any production step can start it.
  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.submit("cancelProduction", { buildingID: core.id });
  simulation.runToTick(2);

  const provisions = simulation.stock("sunwoven").provisions;
  const trickle = TUNING.coreTrickle.provisions * STEP_DURATION * 2;
  const expected = TUNING.startingResources.provisions + trickle;
  assert.ok(
    Math.abs(provisions - expected) < 1e-9,
    `an unstarted cancel must refund the full 50 (got ${provisions}, expected ${expected})`
  );
  assert.equal(
    simulation.state.productionQueues.has(core.id),
    false,
    "an emptied queue is dropped"
  );
});

test("cancelling a started front item refunds cost × cancelRefundFraction", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);

  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.runToTick(3); // enqueued at tick 2, started and advanced by ticks 2 and 3

  simulation.submit("cancelProduction", { buildingID: core.id });
  simulation.runToTick(5); // the cancel lands at tick 5, after the item started

  const provisions = simulation.stock("sunwoven").provisions;
  const trickle = TUNING.coreTrickle.provisions * STEP_DURATION * 5;
  const expected =
    TUNING.startingResources.provisions +
    trickle -
    TUNING.citizenCost.provisions +
    TUNING.citizenCost.provisions * TUNING.cancelRefundFraction;
  assert.ok(
    Math.abs(provisions - expected) < 1e-9,
    `a started cancel must refund cost × fraction (got ${provisions}, expected ${expected})`
  );
  assert.equal(simulation.state.productionQueues.has(core.id), false);
});

test("destroying a building refunds only the front item and discards the rest", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);

  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.submit("enqueue", { kind: "citizen", buildingID: core.id });
  simulation.runToTick(3); // front started; second item queued behind it

  const queue = simulation.state.productionQueues.get(core.id);
  assert.equal(queue.items.length, 2);
  assert.equal(queue.items[0].hasStarted, true);
  assert.equal(queue.items[1].hasStarted, false);

  const before = simulation.stock("sunwoven").provisions;
  ProductionSystem.onBuildingDestroyed(simulation.state, core.id);
  const after = simulation.stock("sunwoven").provisions;

  const refunded = TUNING.citizenCost.provisions * TUNING.cancelRefundFraction;
  assert.ok(
    Math.abs(after - before - refunded) < 1e-9,
    `destruction must refund only the started front at the fraction (got ${after - before})`
  );
  assert.equal(
    simulation.state.productionQueues.has(core.id),
    false,
    "the rest of the queue is discarded with the building"
  );
});

test("destroying a building refunds an unstarted front in full and discards the rest", () => {
  const simulation = new Simulation({ seed: SEED });
  const core = sunwovenCore(simulation);

  // Both items land in the queue with no production step between them and the
  // destruction, so the front is still unstarted when the building is lost.
  ProductionSystem.enqueue(simulation.state, "citizen", core.id);
  ProductionSystem.enqueue(simulation.state, "citizen", core.id);
  assert.equal(
    simulation.state.productionQueues.get(core.id).items[0].hasStarted,
    false
  );

  const before = simulation.stock("sunwoven").provisions;
  ProductionSystem.onBuildingDestroyed(simulation.state, core.id);
  const after = simulation.stock("sunwoven").provisions;

  const refunded = TUNING.citizenCost.provisions;
  assert.ok(
    Math.abs(after - before - refunded) < 1e-9,
    `an unstarted front must refund in full on destruction (got ${after - before})`
  );
  assert.equal(simulation.state.productionQueues.has(core.id), false);
});
