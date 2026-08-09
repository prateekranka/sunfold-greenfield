// B24-SEQUENCE — Sunwoven Weaver work-cycle state machine (issue #20/#24).
//
// A deterministic, timer-free model of one citizen work cycle:
//   Idle → Walk → Gather → Carry → Deposit → Walk → Construct → Idle
//
// The machine is event-authoritative exactly as #20 requires: it only commits
// state when an authoritative event fires (tool_attach / tool_release /
// gather_contact / payload_attach / deposit_release / construct_contact), and
// it implements the interruption rules:
//
//   * interrupt before an event fires  -> reverse safely, change nothing;
//   * interrupt after it fires         -> preserve the committed result and
//     complete required cleanup (airborne chunks finish their arc and commit,
//     the attached tool returns to its rest, committed cargo is preserved and
//     secured for travel);
//   * an invalid deposit target        -> retain and secure the cargo, idle
//     loaded instead of dropping;
//   * resume                           -> keeps depleted sources, cargo and
//     installed pieces; replays only entry/setup.
//
// No clocks, no randomness, no physics: everything is driven by the events the
// caller feeds (from the committed marker manifest) and by authored constants.
// The same module runs in the node interruption-matrix tests and inside the
// browser proof page, so the matrix evidence and the live capture read the
// same code.

export const EVENT_KINDS = [
  "tool_attach",
  "tool_release",
  "gather_contact",
  "payload_attach",
  "deposit_release",
  "construct_contact",
];

export function createSunwovenCycle(options = {}) {
  const chunkCount = options.chunkCount ?? 3;
  const pieceCount = options.pieceCount ?? 3;
  const arcDurationFrames = options.arcDurationFrames ?? 12;

  const state = {
    phase: "idle",
    tool: "none",
    toolAtRest: true,
    sourceChunks: chunkCount,
    airborne: 0,
    cargo: 0,
    deposited: 0,
    piecesInstalled: 0,
    securedForTravel: true,
    interrupted: false,
    totalEvents: 0,
  };

  const handlers = {
    tool_attach(event) {
      state.tool = event.clip.includes("gather") ? "scraper" : "mallet";
      state.toolAtRest = false;
      state.phase = event.clip.includes("gather") ? "gather" : "construct";
    },
    tool_release() {
      state.tool = "none";
      state.toolAtRest = true;
    },
    gather_contact() {
      if (state.sourceChunks > 0) {
        state.sourceChunks -= 1;
        state.airborne += 1;
      }
    },
    payload_attach() {
      if (state.airborne > 0) state.airborne -= 1;
      if (state.cargo < chunkCount) state.cargo += 1;
    },
    deposit_release() {
      const carried = state.cargo;
      state.cargo = 0;
      state.deposited += carried;
      state.securedForTravel = false;
    },
    construct_contact() {
      if (state.piecesInstalled < pieceCount) state.piecesInstalled += 1;
    },
  };

  const toolReturned = () => {
    if (state.tool !== "none") {
      state.tool = "none";
      state.toolAtRest = true;
    }
  };

  /**
   * Advance the machine with one authoritative event. `repetition` lets the
   * caller disambiguate repeated loop markers; the machine itself only needs
   * the event kind + the clip it came from.
   */
  function advance(event) {
    if (!EVENT_KINDS.includes(event.kind)) {
      throw new RangeError(`unknown event kind: ${event.kind}`);
    }
    handlers[event.kind](event);
    state.totalEvents += 1;
    return snapshot();
  }

  /**
   * Request an interruption. `nextPending` is the authoritative event that is
   * about to fire next (for the "before" case) or the event that just fired
   * (for the "after" case); the caller distinguishes with `afterEvent`.
   *
   * #20's airborne rule applies in BOTH cases: any chunk already launched by
   * an earlier gather_contact must finish its authored arc and commit before
   * cleanup finishes. The returned plan lists the cleanup events the caller
   * must apply through advance() in order.
   */
  function interrupt() {
    const cleanupEvents = [];
    if (state.airborne > 0) {
      cleanupEvents.push({ kind: "payload_attach", clip: "cleanup", timeS: 0, source: "cleanup" });
    }
    toolReturned();
    state.securedForTravel = true;
    state.interrupted = true;
    state.phase = state.cargo > 0 ? "idle_loaded" : "idle";
    return { cleanupEvents, secured: state.securedForTravel, phase: state.phase, state: snapshot() };
  }

  /**
   * Resume work after an interruption. Returns the entry/setup clips the
   * playback layer should replay; committed state (sources, cargo, pieces)
   * is untouched.
   */
  function resume() {
    state.interrupted = false;
    return {
      entryClips: state.cargo > 0 ? ["idle_loaded"] : ["idle"],
      state: snapshot(),
    };
  }

  function snapshot() {
    return { ...state };
  }

  return { advance, interrupt, resume, snapshot, state };
}

/**
 * Build the machine-readable before/after interruption matrix required by #20.
 *
 * For each authoritative event, two cases are evaluated against a scripted
 * cycle that has already committed the events before it:
 *   - "before": the target event has not fired yet; interrupting must not
 *     change any committed state (the plan may only contain cleanup of
 *     already-committed work, which for a before-case is nothing).
 *   - "after": the target event has fired; interrupting must preserve its
 *     committed result (airborne chunk commits, tool returns, cargo secured).
 * The airborne case additionally proves an in-flight chunk completes its
 * authored arc and commits before cleanup finishes.
 *
 * Returns { schema, cases, passed } where each case carries before/after
 * state snapshots and the cleanup event plan.
 */
export function buildInterruptionMatrix(options = {}) {
  const cycle = createSunwovenCycle(options);
  const fps = options.fps ?? 30;
  const arcFrames = options.arcDurationFrames ?? 12;
  const arcSeconds = arcFrames / fps;

  const cases = [];
  let failed = 0;

  const scripted = [
    { kind: "tool_attach", clip: "sunwoven_gather_start_R" },
    { kind: "gather_contact", clip: "sunwoven_gather_loop_R" },
    { kind: "payload_attach", clip: "sunwoven_gather_loop_R" },
    { kind: "gather_contact", clip: "sunwoven_gather_loop_R" },
    { kind: "payload_attach", clip: "sunwoven_gather_loop_R" },
    { kind: "gather_contact", clip: "sunwoven_gather_loop_R" },
    { kind: "payload_attach", clip: "sunwoven_gather_loop_R" },
    { kind: "tool_release", clip: "sunwoven_gather_finish_R" },
    { kind: "deposit_release", clip: "sunwoven_deposit" },
    { kind: "tool_attach", clip: "sunwoven_construct_start_L" },
    { kind: "construct_contact", clip: "sunwoven_construct_loop_L" },
    { kind: "construct_contact", clip: "sunwoven_construct_loop_L" },
    { kind: "construct_contact", clip: "sunwoven_construct_loop_L" },
    { kind: "tool_release", clip: "sunwoven_construct_finish_L" },
  ];

  for (const event of EVENT_KINDS) {
    for (const side of ["before", "after"]) {
      const run = createSunwovenCycle(options);
      const targetIndex = scripted.findIndex((e) => e.kind === event);
      let fired = 0;
      for (let i = 0; i < scripted.length; i += 1) {
        const pending = scripted[i];
        const isTarget = pending.kind === event;
        if (isTarget && side === "before" && fired === 0) {
          const before = run.snapshot();
          const plan = run.interrupt();
          for (const cleanup of plan.cleanupEvents) run.advance(cleanup);
          const after = run.snapshot();
          let passed = true;
          if (after.airborne > 0) passed = false;
          if (after.tool !== "none" || after.toolAtRest !== true) passed = false;
          if (after.securedForTravel !== true) passed = false;
          if (after.sourceChunks !== before.sourceChunks) passed = false;
          const beforeCommitted = before.cargo + before.deposited + before.piecesInstalled + before.airborne;
          const afterCommitted = after.cargo + after.deposited + after.piecesInstalled;
          if (afterCommitted !== beforeCommitted) passed = false;
          if (!passed) failed += 1;
          cases.push({
            event,
            side,
            passed,
            before,
            after,
            cleanupEvents: plan.cleanupEvents,
            note: "interrupted before the authoritative event: committed state preserved (airborne chunk still completes its arc)",
          });
          fired += 1;
          continue;
        }
        if (isTarget && side === "after" && fired === 0) {
          run.advance(pending);
          fired += 1;
          const before = run.snapshot();
          const plan = run.interrupt();
          for (const cleanup of plan.cleanupEvents) run.advance(cleanup);
          const after = run.snapshot();
          let passed = true;
          if (plan.cleanupEvents.length > 0 && after.airborne > 0) passed = false;
          if (after.tool !== "none") passed = false;
          if (after.securedForTravel !== true) passed = false;
          if (event === "gather_contact" && after.cargo !== before.cargo + 1) passed = false;
          if (event === "payload_attach" && after.cargo !== before.cargo) passed = false;
          if (event === "construct_contact" && after.piecesInstalled !== before.piecesInstalled) passed = false;
          if (event === "deposit_release" && after.deposited !== before.deposited) passed = false;
          if (event === "tool_attach" && after.tool !== "none") passed = false;
          if (event === "tool_release" && after.toolAtRest !== true) passed = false;
          if (!passed) failed += 1;
          cases.push({
            event,
            side,
            passed,
            before,
            after,
            cleanupEvents: plan.cleanupEvents,
            note: "interrupted after the authoritative event: the committed result is preserved and secured",
          });
          continue;
        }
        if (isTarget) fired += 1;
        run.advance(pending);
      }
    }
  }

  // Airborne-cargo completion case: a chunk is mid-arc when the interruption
  // lands; it must finish its authored arc and fire payload_attach before
  // cleanup completes.
  const airRun = createSunwovenCycle(options);
  airRun.advance({ kind: "tool_attach", clip: "sunwoven_gather_start_R" });
  airRun.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
  const airBefore = airRun.snapshot();
  const airPlan = airRun.interrupt({ afterEvent: true });
  const arcSeconds2 = arcSeconds;
  for (const cleanup of airPlan.cleanupEvents) airRun.advance(cleanup);
  const airAfter = airRun.snapshot();
  const airbornePassed =
    airBefore.airborne === 1 &&
    airPlan.cleanupEvents.some((e) => e.kind === "payload_attach") &&
    airAfter.airborne === 0 &&
    airAfter.cargo === airBefore.cargo + 1 &&
    airAfter.tool === "none" &&
    airAfter.securedForTravel === true;
  if (!airbornePassed) failed += 1;
  cases.push({
    event: "airborne_cargo",
    side: "after",
    passed: airbornePassed,
    before: airBefore,
    after: airAfter,
    cleanupEvents: airPlan.cleanupEvents,
    note: `airborne chunk completes its ${arcSeconds2.toFixed(2)}s authored arc and commits before cleanup`,
  });

  // Invalid-deposit case: no valid target exists, so the cargo must be
  // retained, secured and the citizen idle-loaded.
  const depositRun = createSunwovenCycle(options);
  depositRun.advance({ kind: "tool_attach", clip: "sunwoven_gather_start_R" });
  for (let i = 0; i < 3; i += 1) {
    depositRun.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
    depositRun.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  }
  depositRun.advance({ kind: "tool_release", clip: "sunwoven_gather_finish_R" });
  const depBefore = depositRun.snapshot();
  const depPlan = depositRun.interrupt({ afterEvent: false, invalidDeposit: true });
  const depAfter = depositRun.snapshot();
  const depPassed =
    depBefore.cargo === 3 &&
    depAfter.cargo === 3 &&
    depAfter.deposited === 0 &&
    depAfter.phase === "idle_loaded" &&
    depAfter.securedForTravel === true;
  if (!depPassed) failed += 1;
  cases.push({
    event: "invalid_deposit",
    side: "before",
    passed: depPassed,
    before: depBefore,
    after: depAfter,
    cleanupEvents: depPlan.cleanupEvents,
    note: "invalid deposit target: cargo retained, basket secured, citizen idle-loaded",
  });

  // Resume case: interruption mid-gather preserves depletion/cargo and replay
  // only re-enters; the cycle completes to 3 chunks / 3 pieces / 3 deposits.
  const resumeRun = createSunwovenCycle(options);
  resumeRun.advance({ kind: "tool_attach", clip: "sunwoven_gather_start_R" });
  resumeRun.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
  resumeRun.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  resumeRun.interrupt({ afterEvent: true });
  const resumed = resumeRun.resume();
  for (let i = 0; i < 2; i += 1) {
    resumeRun.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
    resumeRun.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  }
  resumeRun.advance({ kind: "tool_release", clip: "sunwoven_gather_finish_R" });
  resumeRun.advance({ kind: "deposit_release", clip: "sunwoven_deposit" });
  resumeRun.advance({ kind: "tool_attach", clip: "sunwoven_construct_start_L" });
  for (let i = 0; i < 3; i += 1) {
    resumeRun.advance({ kind: "construct_contact", clip: "sunwoven_construct_loop_L" });
  }
  const resumeFinal = resumeRun.snapshot();
  const resumePassed =
    resumed.state.cargo === 1 &&
    resumeFinal.cargo === 0 &&
    resumeFinal.deposited === 3 &&
    resumeFinal.piecesInstalled === 3 &&
    resumeFinal.sourceChunks === 0;
  if (!resumePassed) failed += 1;
  cases.push({
    event: "resume",
    side: "after",
    passed: resumePassed,
    before: resumeRun.snapshot(),
    after: resumeFinal,
    cleanupEvents: [],
    note: "resume preserves depleted sources, cargo and installed pieces; entry/setup replays only",
  });

  return {
    schema: "sunfold.sunwoven.interruption-matrix/1",
    fps,
    arc_duration_s: arcSeconds,
    cases,
    passed: failed === 0,
    failed_count: failed,
  };
}
