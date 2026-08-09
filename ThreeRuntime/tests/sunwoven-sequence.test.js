// Issue #24 — Sunwoven interruption matrix and cycle invariants.
//
// The machine-readable before/after interruption matrix required by #20 is
// produced by buildInterruptionMatrix() and written to
// Tools/citizens/build/sunwoven-interruption-matrix.json by this suite.

import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import {
  EVENT_KINDS,
  buildInterruptionMatrix,
  createSunwovenCycle,
} from "../src/sunwoven-sequence.js";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const toolsBuild = resolve(root, "Tools/citizens/build");
mkdirSync(toolsBuild, { recursive: true });

const FPS = 30;
const ARC_FRAMES = 12;

test("interruption matrix: all before/after cases pass, airborne included", () => {
  const matrix = buildInterruptionMatrix({ fps: FPS, arcDurationFrames: ARC_FRAMES });
  assert.equal(matrix.passed, true);
  assert.equal(matrix.failed_count, 0);
  assert.ok(matrix.cases.length >= 12, `expected >=12 cases, got ${matrix.cases.length}`);
  for (const event of EVENT_KINDS) {
    const kinds = matrix.cases.filter((c) => c.event === event);
    assert.ok(kinds.some((c) => c.side === "before"), `${event} missing before case`);
    assert.ok(kinds.some((c) => c.side === "after"), `${event} missing after case`);
  }
  const airborne = matrix.cases.find((c) => c.event === "airborne_cargo");
  assert.ok(airborne, "airborne_cargo case missing");
  assert.ok(airborne.cleanupEvents.some((e) => e.kind === "payload_attach"));
  writeFileSync(
    resolve(toolsBuild, "sunwoven-interruption-matrix.json"),
    `${JSON.stringify(matrix, null, 2)}\n`
  );
});

test("cycle invariants: deposit empties atomically into the target", () => {
  const cycle = createSunwovenCycle({ chunkCount: 3, arcDurationFrames: ARC_FRAMES });
  cycle.advance({ kind: "tool_attach", clip: "sunwoven_gather_start_R" });
  for (let i = 0; i < 3; i += 1) {
    cycle.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
    cycle.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  }
  const loaded = cycle.snapshot();
  assert.equal(loaded.cargo, 3);
  assert.equal(loaded.sourceChunks, 0);
  cycle.advance({ kind: "tool_release", clip: "sunwoven_gather_finish_R" });
  cycle.advance({ kind: "deposit_release", clip: "sunwoven_deposit" });
  const dumped = cycle.snapshot();
  assert.equal(dumped.cargo, 0, "basket must empty atomically");
  assert.equal(dumped.deposited, 3, "target receives exactly the committed cargo");
  assert.equal(dumped.sourceChunks, 0);
});

test("cycle invariants: construction installs one piece per contact", () => {
  const cycle = createSunwovenCycle({ pieceCount: 3 });
  cycle.advance({ kind: "tool_attach", clip: "sunwoven_construct_start_L" });
  for (let i = 0; i < 3; i += 1) {
    cycle.advance({ kind: "construct_contact", clip: "sunwoven_construct_loop_L" });
  }
  const done = cycle.snapshot();
  assert.equal(done.piecesInstalled, 3);
  cycle.advance({ kind: "tool_release", clip: "sunwoven_construct_finish_L" });
  assert.equal(cycle.snapshot().tool, "none");
});

test("cycle invariants: gather never removes more chunks than the pile holds", () => {
  const cycle = createSunwovenCycle({ chunkCount: 3 });
  for (let i = 0; i < 6; i += 1) {
    cycle.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
  }
  const state = cycle.snapshot();
  assert.equal(state.sourceChunks, 0, "the pile can never go below zero");
  assert.equal(state.airborne, 3, "all three chunks are airborne, none committed");
  assert.equal(state.cargo, 0);
  for (let i = 0; i < 3; i += 1) {
    cycle.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  }
  const committed = cycle.snapshot();
  assert.equal(committed.airborne, 0);
  assert.equal(committed.cargo, 3);
});

test("interruption before an event never reverses committed cargo", () => {
  const cycle = createSunwovenCycle({ chunkCount: 3 });
  cycle.advance({ kind: "tool_attach", clip: "sunwoven_gather_start_R" });
  cycle.advance({ kind: "gather_contact", clip: "sunwoven_gather_loop_R" });
  cycle.advance({ kind: "payload_attach", clip: "sunwoven_gather_loop_R" });
  const before = cycle.snapshot();
  const plan = cycle.interrupt();
  for (const cleanup of plan.cleanupEvents) cycle.advance(cleanup);
  const after = cycle.snapshot();
  assert.equal(after.cargo, before.cargo, "committed cargo must survive");
  assert.equal(after.phase, "idle_loaded", "loaded cargo means idle-loaded");
  assert.equal(after.securedForTravel, true);
});
