// The citizen work-cycle controller: tool in hand, contact loops, chunk arcs.
//
// This module owns the animation-facing substate #20's citizen contract
// defines and nothing else. It adds no gameplay activity — `ACTIVITY_TAGS`
// stays closed — and it decides no rule. What it owns is *when the authored
// moments fall*: the tick a tool is taken up, the tick a chunk leaves the
// pile, the tick it lands on the carrier, the tick a load is released at the
// drop-off, and the tick a frame piece seats on a foundation.
//
// Those moments are the commit points of the work cycle, so this controller
// is the one caller of `GatheringSystem.commitContact` / `commitPayload` /
// `commitDeposit`. The ledger those commits close is described in
// `gathering.js`; this file only guarantees the events fire in a fixed order
// on fixed ticks, so two runs of one seed commit the same amounts on the same
// tick.
//
// Everything here is tick arithmetic on state the simulation already owns.
// No wall clock, no frame timing, no unseeded randomness — the substate is
// hashed and saved, so every transition is a pure function of state.

import { unitKind, CHUNKS_PER_LOAD } from "./kinds.js";
import { GatheringSystem } from "./gathering.js";

/**
 * The controller substates a citizen's animation block can be in.
 *
 * These are presentation-facing detail, **not** gameplay activities. The
 * simulation's activity tags stay the seven the Swift original owns; this list
 * is how `unit.animation.state` refines "gathering" into "mid second contact
 * loop, scraper in left hand".
 */
export const CITIZEN_ANIMATION_STATES = Object.freeze([
  "idle",
  "attachTool",
  "workLoop",
  "releaseTool",
  "deliver",
  "cleanup"
]);

// MARK: - Cadence, in fixed 20 Hz ticks
//
// Throughput does not depend on these numbers: accrual into `unit.pending`
// runs at the tuning rate from the moment a citizen stands at its station,
// including the settle and tool-attach ticks (see gathering.js). The constants
// below only choose *which tick* an already-accrued amount commits on, so they
// are picked for readable motion, not for balance.

/** Reaching for the tool and raising it. */
const ATTACH_TICKS = 6;
/** One full contact loop (swing, contact, recover) while gathering. */
const GATHER_LOOP_TICKS = 14;
/** Phase inside the gather loop at which `gather_contact` fires. */
const GATHER_CONTACT_PHASE = 9;
/** One mallet loop on a foundation. */
const CONSTRUCT_LOOP_TICKS = 16;
/** Phase inside the construct loop at which `construct_contact` fires. */
const CONSTRUCT_CONTACT_PHASE = 11;
/** Arc time for a chunk from the pile to the carrier's back. */
const CHUNK_FLIGHT_TICKS = 4;
/** Returning the tool to its rest. */
const RELEASE_TICKS = 5;
/** The full tip/dump at the drop-off. */
const DELIVER_TICKS = 10;
/** Deepest point of the tip — `deposit_release` fires here. */
const DELIVER_COMMIT_PHASE = 7;
/** Tool return during an interrupt cleanup, brisk but still ordered. */
const CLEANUP_TICKS = 4;

/** The tool each work context takes up. */
function toolFor(unit) {
  return unit.activity && unit.activity.tag === "constructing" ? "mallet" : "scraper";
}

/** A fresh animation block — the same shape `populate.js` and `production.js` seed. */
function createBlock() {
  return {
    state: "idle",
    loopIndex: 0,
    phaseTicks: 0,
    leadHand: "none",
    toolHeld: null,
    carriedChunks: 0,
    airborneChunks: []
  };
}

/**
 * Older states and hand-built units may lack the block. Healing here keeps
 * every later branch free of guards, and a restored snapshot that predates a
 * field gets the pinned shape on its first step rather than throwing.
 */
function ensureBlock(unit) {
  if (!unit.animation) unit.animation = createBlock();
  const animation = unit.animation;
  if (animation.loopIndex === undefined) animation.loopIndex = 0;
  if (animation.phaseTicks === undefined) animation.phaseTicks = 0;
  if (animation.leadHand === undefined) animation.leadHand = "none";
  if (animation.toolHeld === undefined) animation.toolHeld = null;
  if (animation.carriedChunks === undefined) animation.carriedChunks = 0;
  if (!animation.airborneChunks) animation.airborneChunks = [];
  return animation;
}

function enter(animation, state) {
  animation.state = state;
  animation.phaseTicks = 0;
}

// MARK: - Chunk flight

/**
 * Advances every chunk mid-arc and lands the ones whose flight ends.
 *
 * Unconditional across substates — including `cleanup`. #20's rule is that a
 * chunk committed at `gather_contact` must land whatever happens next, so an
 * interrupt never cancels a flight; it only stops new ones from starting.
 */
function tickAirborne(state, unit, animation) {
  if (animation.airborneChunks.length === 0) return;
  const remaining = [];
  for (const chunk of animation.airborneChunks) {
    chunk.remainingTicks -= 1;
    if (chunk.remainingTicks > 0) {
      remaining.push(chunk);
      continue;
    }
    const landed = GatheringSystem.commitPayload(state, unit, chunk);
    if (landed > 0) {
      animation.carriedChunks = Math.min(CHUNKS_PER_LOAD, animation.carriedChunks + 1);
    }
    state.events.emit("payload_attach", state.clock.tick, unit.id, {
      kind: chunk.kind,
      amount: chunk.amount
    });
  }
  animation.airborneChunks = remaining;
}

// MARK: - Work predicates
//
// Both mirror the condition the owning system acted on earlier in the same
// tick, so the controller never starts a cycle the rule system would refuse.

/**
 * On-site with a foundation: construction's own step pins a builder's
 * destination while it is short of the kerb and clears it once inside the
 * work radius, so a cleared destination is the arrival signal — derived one
 * system earlier this tick, never recomputed here under a second rule.
 */
function isBuildingOnSite(state, unit) {
  if (!unit.activity || unit.activity.tag !== "constructing") return false;
  if (unit.destination !== null && unit.destination !== undefined) return false;
  const building = state.buildings.get(unit.activity.subject);
  return Boolean(building) && building.constructionProgress < 1;
}

/** Standing at the assigned node with extraction still legal (or pending to drain). */
function isExtractingAtStation(state, unit) {
  const leg = GatheringSystem.legOf(state, unit);
  if (leg.leg !== "extract" || !leg.atStation) return false;
  if (leg.canExtract) return true;
  // Full and winding down: the residual accrual still owes one last contact.
  return Boolean(unit.pending && unit.pending.amount > 0);
}

// MARK: - State machine

function stepIdle(state, unit, animation) {
  if (animation.toolHeld !== null) {
    // Holding a tool with no work context is only ever a exit-path residue.
    enter(animation, "releaseTool");
    return;
  }

  if (!unitKind(unit.kind).canGather) return;

  if (isBuildingOnSite(state, unit)) {
    enter(animation, "attachTool");
    return;
  }

  const leg = GatheringSystem.legOf(state, unit);
  if (leg.leg === "deliver" && leg.atTarget && unit.cargo && unit.cargo.amount > 0) {
    if (animation.airborneChunks.length === 0) enter(animation, "deliver");
    return;
  }
  if (leg.leg === "extract" && leg.atStation && (leg.canExtract || (unit.pending && unit.pending.amount > 0))) {
    enter(animation, "attachTool");
  }
}

function stepAttachTool(state, unit, animation) {
  animation.phaseTicks += 1;
  if (animation.phaseTicks < ATTACH_TICKS) return;
  const tool = toolFor(unit);
  animation.toolHeld = tool;
  animation.leadHand = animation.loopIndex % 2 === 0 ? "left" : "right";
  state.events.emit("tool_attach", state.clock.tick, unit.id, { tool });
  enter(animation, "workLoop");
}

/**
 * The contact instant inside a loop — the only place resources move here.
 *
 * A gather contact that finds nothing to take fires no event and launches no
 * chunk: the pile is untouched, so nothing is spent for no resource.
 */
function fireContact(state, unit, animation) {
  if (animation.toolHeld === "scraper") {
    const chunk = GatheringSystem.commitContact(state, unit);
    if (!chunk) return;
    state.events.emit("gather_contact", state.clock.tick, unit.id, {
      kind: chunk.kind,
      amount: chunk.amount,
      depositID: chunk.depositID
    });
    animation.airborneChunks.push({
      kind: chunk.kind,
      amount: chunk.amount,
      remainingTicks: CHUNK_FLIGHT_TICKS,
      depositID: chunk.depositID
    });
    return;
  }

  if (animation.toolHeld === "mallet") {
    const building = state.buildings.get(unit.activity ? unit.activity.subject : null);
    if (!building || building.constructionProgress >= 1) return;
    if (building.installedComponents >= CHUNKS_PER_LOAD) return;
    building.installedComponents += 1;
    state.events.emit("construct_contact", state.clock.tick, unit.id, {
      buildingID: building.id,
      components: building.installedComponents
    });
  }
}

function stepWorkLoop(state, unit, animation) {
  animation.phaseTicks += 1;
  const contactPhase = animation.toolHeld === "mallet" ? CONSTRUCT_CONTACT_PHASE : GATHER_CONTACT_PHASE;
  const loopTicks = animation.toolHeld === "mallet" ? CONSTRUCT_LOOP_TICKS : GATHER_LOOP_TICKS;

  if (animation.phaseTicks === contactPhase) fireContact(state, unit, animation);
  if (animation.phaseTicks < loopTicks) return;

  // Loop complete. The next loop is the next of the three authored contacts,
  // and the lead hand alternates with it — both derived from the durable
  // loopIndex, never from a coin flip.
  animation.loopIndex = (animation.loopIndex + 1) % CHUNKS_PER_LOAD;
  animation.leadHand = animation.loopIndex % 2 === 0 ? "left" : "right";

  const continues =
    animation.toolHeld === "mallet" ? isBuildingOnSite(state, unit) : isExtractingAtStation(state, unit);
  if (continues) {
    animation.phaseTicks = 0;
  } else {
    enter(animation, "releaseTool");
  }
}

function stepReleaseTool(state, unit, animation) {
  animation.phaseTicks += 1;
  if (animation.phaseTicks < RELEASE_TICKS) return;
  const tool = animation.toolHeld;
  animation.toolHeld = null;
  animation.leadHand = "none";
  if (tool !== null) state.events.emit("tool_release", state.clock.tick, unit.id, { tool });
  enter(animation, "idle");
}

function stepDeliver(state, unit, animation) {
  animation.phaseTicks += 1;
  if (animation.phaseTicks === DELIVER_COMMIT_PHASE) {
    const released = GatheringSystem.commitDeposit(state, unit);
    if (released) {
      state.events.emit("deposit_release", state.clock.tick, unit.id, {
        kind: released.kind,
        amount: released.amount
      });
    }
    animation.carriedChunks = 0;
  }
  if (animation.phaseTicks >= DELIVER_TICKS) enter(animation, "idle");
}

/**
 * The interrupt path. No new work starts here; the tool goes back on its rest
 * and anything airborne lands on its own schedule via `tickAirborne`. Only
 * when both are settled is the citizen idle again.
 */
function stepCleanup(state, unit, animation) {
  if (animation.toolHeld !== null) {
    animation.phaseTicks += 1;
    if (animation.phaseTicks >= CLEANUP_TICKS) {
      const tool = animation.toolHeld;
      animation.toolHeld = null;
      if (tool !== null) state.events.emit("tool_release", state.clock.tick, unit.id, { tool });
    }
    return;
  }
  if (animation.airborneChunks.length > 0) return;
  animation.leadHand = "none";
  enter(animation, "idle");
}

// MARK: - The controller

export const AnimationController = {
  /** The initial animation block, matching what `populate.js` seeds by hand. */
  create: createBlock,

  /**
   * Advances every unit's substate by one fixed tick, in ascending id order,
   * and fires the authoritative events whose phase has arrived.
   *
   * Runs last in the simulation step, reacting to the state the rule systems
   * just produced — a citizen whose load completed this tick begins the walk
   * home with the controller already winding its cycle down, not one tick
   * later.
   */
  step(state, _deltaTime) {
    for (const id of state.units.orderedIDs()) {
      const unit = state.units.get(id);
      if (!unit) continue;
      const animation = ensureBlock(unit);

      // Chunks in flight land regardless of the substate beneath them.
      tickAirborne(state, unit, animation);

      // The carrier's back mirrors committed cargo. A load credited by a
      // construction reassignment (the G2a hand-off) never passes through a
      // controller event, so the count is reconciled here rather than left to
      // describe chunks the citizen is no longer holding.
      if (animation.carriedChunks > 0 && !unit.cargo && animation.airborneChunks.length === 0) {
        animation.carriedChunks = 0;
      }

      switch (animation.state) {
        case "idle": stepIdle(state, unit, animation); break;
        case "attachTool": stepAttachTool(state, unit, animation); break;
        case "workLoop": stepWorkLoop(state, unit, animation); break;
        case "releaseTool": stepReleaseTool(state, unit, animation); break;
        case "deliver": stepDeliver(state, unit, animation); break;
        case "cleanup": stepCleanup(state, unit, animation); break;
        default: enter(animation, "idle"); break;
      }
    }
  },

  /**
   * Interrupts a unit's work cycle, preserving everything already committed.
   *
   * Speculative accrual is abandoned (`abortPending` — nothing had left the
   * deposit, so nothing is lost). The tool is returned and airborne chunks
   * still land. Returns true when cleanup is now running — that answer is how
   * an order learns whether it cut authored work short.
   */
  requestInterrupt(state, unit) {
    const animation = ensureBlock(unit);
    GatheringSystem.abortPending(unit);

    const midCycle =
      animation.state === "attachTool" ||
      animation.state === "workLoop" ||
      animation.state === "releaseTool" ||
      animation.state === "deliver";
    const owes = animation.toolHeld !== null || animation.airborneChunks.length > 0;

    if (!midCycle && !owes) {
      if (animation.state !== "idle") enter(animation, "idle");
      return false;
    }
    enter(animation, "cleanup");
    return true;
  },

  /** True while the controller still owes this unit a tool return or a landing. */
  isBusy(unit) {
    const animation = unit.animation;
    if (!animation) return false;
    return (
      animation.state !== "idle" ||
      animation.toolHeld !== null ||
      (animation.airborneChunks !== undefined && animation.airborneChunks.length > 0)
    );
  }
};
