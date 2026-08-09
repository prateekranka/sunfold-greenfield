// Atlas UV math for packed sprite sheets (Gemini-style single-texture playback).

import assert from "node:assert/strict";
import test from "node:test";

import { atlasCellUV, atlasFrameCell, applyAtlasUV } from "../src/sprites/atlas.js";
import { clipForUnit } from "../src/sprites/unit-layer.js";

test("atlasCellUV maps top-left cell with flipY convention", () => {
  const atlas = { width: 1024, height: 512, columns: 4, rows: 2 };
  const uv = atlasCellUV(atlas, 256, 256, 0, 0);
  assert.equal(uv.repeatX, 0.25);
  assert.equal(uv.repeatY, 0.5);
  assert.equal(uv.offsetX, 0);
  assert.equal(uv.offsetY, 0.5);
});

test("atlasCellUV advances columns and rows", () => {
  const atlas = { width: 1024, height: 512, columns: 4, rows: 2 };
  const uv = atlasCellUV(atlas, 256, 256, 1, 2);
  assert.equal(uv.offsetX, 0.5);
  assert.equal(uv.offsetY, 0);
});

test("facing-grid places frames under clip.originRow + facing", () => {
  const atlas = { width: 1024, height: 2048, columns: 4, rows: 8 };
  const clip = { frames: 4, originRow: 8 };
  assert.deepEqual(atlasFrameCell(atlas, clip, 2, 3), { row: 10, column: 3 });
});

test("clip-rows layout ignores facing (single-facing Gemini row sheets)", () => {
  const atlas = { width: 1600, height: 840, columns: 8, rows: 3, layout: "clip-rows", singleFacing: true };
  const clip = { frames: 8, originRow: 1 };
  assert.deepEqual(atlasFrameCell(atlas, clip, 5, 7), { row: 1, column: 7 });
});

test("applyAtlasUV writes repeat/offset and supports mirror", () => {
  const tex = {
    repeat: { x: 0, y: 0, set(x, y) { this.x = x; this.y = y; } },
    offset: { x: 0, y: 0, set(x, y) { this.x = x; this.y = y; } },
    needsUpdate: false
  };
  applyAtlasUV(tex, { repeatX: 0.25, repeatY: 0.5, offsetX: 0.25, offsetY: 0.5 }, false);
  assert.equal(tex.repeat.x, 0.25);
  assert.equal(tex.offset.x, 0.25);
  assert.equal(tex.needsUpdate, false, "UV swaps must not re-upload atlas pixels");
  applyAtlasUV(tex, { repeatX: 0.25, repeatY: 0.5, offsetX: 0.25, offsetY: 0.5 }, true);
  assert.equal(tex.repeat.x, -0.25);
  assert.equal(tex.offset.x, 0.5);
  assert.equal(tex.needsUpdate, false);
});

test("applyAtlasUVGeometry bakes cell window into plane UVs", async () => {
  const { applyAtlasUVGeometry } = await import("../src/sprites/atlas.js");
  const attr = {
    count: 4,
    xs: [0, 0, 0, 0],
    ys: [0, 0, 0, 0],
    needsUpdate: false,
    setXY(i, x, y) {
      this.xs[i] = x;
      this.ys[i] = y;
    }
  };
  const geometry = { getAttribute: () => attr };
  applyAtlasUVGeometry(geometry, { repeatX: 0.25, repeatY: 0.5, offsetX: 0.25, offsetY: 0.5 }, false);
  assert.deepEqual(attr.xs, [0.25, 0.5, 0.25, 0.5]);
  assert.deepEqual(attr.ys, [1.0, 1.0, 0.5, 0.5]);
  assert.equal(attr.needsUpdate, true);
});

test("clipForUnit maps activity and movement to sprite clips", () => {
  assert.equal(clipForUnit({ activity: { tag: "idle" }, position: { x: 0, z: 0 }, movementPath: [] }), "idle");
  assert.equal(
    clipForUnit({
      activity: { tag: "idle" },
      position: { x: 0, z: 0 },
      destination: { x: 4, z: 0 },
      movementPath: []
    }),
    "walk"
  );
  assert.equal(
    clipForUnit({
      activity: { tag: "gathering" },
      position: { x: 0, z: 0 },
      movementPath: []
    }),
    "gather"
  );
  assert.equal(
    clipForUnit({
      activity: { tag: "constructing" },
      position: { x: 0, z: 0 },
      movementPath: []
    }),
    "build"
  );
});
