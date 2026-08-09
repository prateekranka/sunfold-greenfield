// Event-marker + clip-semantic manifest contract (issue #23).
//
// The manifest is the committed carrier for everything glTF cannot express
// (event markers, loop semantics, handedness, derived payload timing). These
// tests pin its schema so a future exporter change cannot silently break the
// runtime's marker scheduling.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const manifest = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/event-markers.json"), "utf8")
);

test("manifest schema and fps", () => {
  assert.equal(manifest.schema, "sunfold.lab.event-markers/1");
  assert.equal(manifest.fps, 30);
  assert.ok(manifest.arc_duration_frames > 0);
});

test("every required semantic clip group exists for both citizens", () => {
  const required = [
    "idle",
    "walk_inplace",
    "walk_loaded_inplace",
    "idle_loaded",
    "reverse",
    "deposit",
    "gather_start",
    "gather_loop",
    "gather_finish",
    "construct_start",
    "construct_loop",
    "construct_finish",
  ];
  for (const citizen of ["slender", "broad"]) {
    const semantics = new Set(
      manifest.clips.filter((c) => c.name.startsWith(citizen)).map((c) => c.semantic)
    );
    for (const group of required) {
      assert.ok(semantics.has(group), `${citizen} missing ${group}`);
    }
  }
});

test("left- and right-leading variants are distinct clips", () => {
  for (const citizen of ["slender", "broad"]) {
    const prefixes = manifest.clips
      .filter((c) => c.name.startsWith(`${citizen}_gather_loop_`))
      .map((c) => c.name.slice(-1))
      .sort();
    assert.deepEqual(prefixes, ["L", "R"]);
  }
});

test("both leading-hand variants bind the matching tool socket", () => {
  for (const citizen of ["slender", "broad"]) {
    for (const semantic of ["gather", "construct"]) {
      for (const hand of ["L", "R"]) {
        for (const phase of ["start", "loop", "finish"]) {
          const clip = manifest.clips.find((candidate) => candidate.name === `${citizen}_${semantic}_${phase}_${hand}`);
          assert.equal(clip?.grip_socket, `socket_tool_${hand}`, `${clip?.name ?? "missing clip"} grip`);
        }
      }
    }
  }
});

test("walk clips are in-place by contract and loops are flagged", () => {
  for (const c of manifest.clips) {
    if (c.semantic.includes("walk")) {
      assert.ok(c.loop, `${c.name} must loop`);
    }
  }
  const loops = manifest.clips.filter((c) => c.loop).map((c) => c.semantic);
  for (const s of ["gather_loop", "construct_loop", "idle", "walk_inplace", "walk_loaded_inplace"]) {
    assert.ok(loops.includes(s), `${s} must be flagged loop`);
  }
});

test("marker timing equals frame / fps and all six events are covered", () => {
  for (const m of manifest.markers) {
    assert.ok(Math.abs(m.time_s - m.frame / manifest.fps) < 1e-4, `${m.clip} ${m.name} time`);
    assert.ok(["authored", "derived"].includes(m.source), `${m.name} source`);
  }
  const events = new Set(manifest.markers.map((m) => m.name));
  assert.deepEqual(
    [...events].sort(),
    ["construct_contact", "deposit_release", "gather_contact", "payload_attach", "tool_attach", "tool_release"]
  );
});

test("tool clips anchor attach before release with correct rest semantics", () => {
  const gatherStart = manifest.clips.find((c) => c.name === "slender_gather_start_R");
  const gatherFinish = manifest.clips.find((c) => c.name === "slender_gather_finish_R");
  const constructStart = manifest.clips.find((c) => c.name === "slender_construct_start_L");
  const attach = manifest.markers.filter((m) => m.name === "tool_attach").map((m) => m.clip);
  const release = manifest.markers.filter((m) => m.name === "tool_release").map((m) => m.clip);
  assert.ok(attach.includes(gatherStart.name) && attach.includes(constructStart.name));
  assert.ok(release.includes(gatherFinish.name));
  assert.equal(gatherStart.grip_socket, "socket_tool_R");
  assert.equal(constructStart.grip_socket, "socket_tool_L");
});
