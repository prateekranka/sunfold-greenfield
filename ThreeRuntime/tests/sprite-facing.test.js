import test from "node:test";
import assert from "node:assert/strict";
import {
  yawToFacing,
  yawToFacing16,
  yawToFacingStable,
  yawToFacing16Stable,
  facingName,
  facingName16,
  facingMirror,
  FACINGS,
  FACINGS_16
} from "../src/sprites/facing.js";

test("FACINGS has 8 AoE2 directions from S", () => {
  assert.equal(FACINGS.length, 8);
  assert.equal(FACINGS[0], "S");
  assert.equal(FACINGS[4], "N");
});

test("FACINGS_16 has 16 directions from S", () => {
  assert.equal(FACINGS_16.length, 16);
  assert.equal(FACINGS_16[0], "S");
  assert.equal(FACINGS_16[4], "E");
  assert.equal(FACINGS_16[8], "N");
});

test("yawToFacing maps +Z to south", () => {
  assert.equal(yawToFacing(0), 0);
  assert.equal(facingName(0), "S");
});

test("yawToFacing maps east-ish yaw", () => {
  assert.equal(yawToFacing(Math.PI / 2), 2);
  assert.equal(facingName(2), "E");
});

test("yawToFacing16 maps 22.5° steps", () => {
  assert.equal(yawToFacing16(0), 0);
  assert.equal(facingName16(0), "S");
  assert.equal(yawToFacing16(Math.PI / 2), 4);
  assert.equal(facingName16(4), "E");
  assert.equal(yawToFacing16(Math.PI), 8);
  assert.equal(facingName16(8), "N");
});

test("facingMirror marks W NW SW", () => {
  assert.deepEqual(facingMirror(6), { mirror: true, sourceFacing: 2 });
  assert.deepEqual(facingMirror(0), { mirror: false });
});

test("yawToFacing16Stable holds near cell edge chatter", () => {
  const slice = (Math.PI * 2) / 16;
  // Sitting on S (0); nudge just past the classic half-cell toward SSE but under hold.
  const yaw = slice * 0.55;
  assert.equal(yawToFacing16(yaw), 1);
  assert.equal(yawToFacing16Stable(yaw, 0), 0);
  // Far enough should switch.
  assert.equal(yawToFacing16Stable(slice * 0.9, 0), 1);
});

test("yawToFacingStable holds near 8-dir edge chatter", () => {
  const slice = (Math.PI * 2) / 8;
  const yaw = slice * 0.55;
  assert.equal(yawToFacing(yaw), 1);
  assert.equal(yawToFacingStable(yaw, 0), 0);
  assert.equal(yawToFacingStable(slice * 0.9, 0), 1);
});
