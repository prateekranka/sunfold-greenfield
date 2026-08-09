// Sunwoven Villager cutout sprite set — manifest contract + frame coverage.
//
// The sheet is baked offline from a 2D cutout puppet (Tools/villager-sprites).
// The runtime reads nothing but the manifest, so these tests pin the fields the
// player depends on and prove every frame the manifest promises is on disk. A
// missing frame is otherwise invisible until a unit turns to that facing.

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { FACINGS } from "../src/sprites/facing.js";

const here = dirname(fileURLToPath(import.meta.url));
const spriteDir = resolve(here, "../assets/citizens/sprites/sunwoven-villager");
const manifest = JSON.parse(readFileSync(resolve(spriteDir, "manifest.json"), "utf8"));

test("manifest schema and frame geometry", () => {
  assert.equal(manifest.schema, "sunfold.sprite-manifest/1");
  assert.equal(manifest.unit, "sunwoven-villager");
  assert.equal(manifest.frameWidth, manifest.frameHeight, "frames are square");
  assert.ok(manifest.frameWidth >= 128, "frames are large enough to read at RTS zoom");
});

test("facings match the shared 8-direction order", () => {
  assert.deepEqual(manifest.facings, [...FACINGS]);
});

test("all eight facings are baked, so the player must not mirror again", () => {
  assert.equal(manifest.mirrorAtRuntime, false);
  assert.equal(Object.keys(manifest.facingSource).length, 8);
  // Facings 5, 6 and 7 are mirrors of painted views. That is on disk, not a
  // runtime flip, which is exactly what mirrorAtRuntime: false declares.
  for (const index of [5, 6, 7]) {
    assert.equal(manifest.facingSource[index].mirror, true);
  }
});

test("world placement is declared, not guessed by the player", () => {
  assert.equal(manifest.anchor.x, 0.5);
  assert.ok(manifest.anchor.y > 0.5 && manifest.anchor.y < 1,
    "the ground line sits low in the frame, with footroom under it");
  assert.ok(manifest.unitHeightMeters > 1.4 && manifest.unitHeightMeters < 2.1);
  assert.ok(manifest.worldHeight > manifest.unitHeightMeters,
    "the frame is taller than the villager, to hold a raised tool");
});

test("camera matches the locked RTS rig", () => {
  assert.equal(manifest.camera.pitchDegrees, 57);
  assert.equal(manifest.camera.yawDegrees, 45);
  assert.equal(manifest.camera.fovDegrees, 38);
});

test("the core four clips are present with AoE2 timing", () => {
  const expected = {
    idle: { fps: 3 },
    walk: { frames: 4, fps: 10 },
    gather: { frames: 6, fps: 5 },
    build: { frames: 6, fps: 5 },
  };
  for (const [name, want] of Object.entries(expected)) {
    const clip = manifest.clips[name];
    assert.ok(clip, `clip ${name} is missing`);
    assert.equal(clip.loop, true);
    assert.equal(clip.fps, want.fps, `${name} fps`);
    if (want.frames) assert.equal(clip.frames, want.frames, `${name} frame count`);
  }
});

test("gather and build carry the contact frame the sim schedules against", () => {
  assert.deepEqual(manifest.clips.gather.events.gatherContact, [3]);
  assert.deepEqual(manifest.clips.build.events.constructContact, [3]);
});

test("every frame the manifest promises exists on disk", () => {
  const missing = [];
  for (const [name, clip] of Object.entries(manifest.clips)) {
    for (let facing = 0; facing < manifest.facings.length; facing += 1) {
      for (let frame = 0; frame < clip.frames; frame += 1) {
        const path = resolve(spriteDir, name, String(facing), `${frame}.png`);
        if (!existsSync(path)) missing.push(`${name}/${facing}/${frame}.png`);
      }
    }
  }
  assert.deepEqual(missing, [], `missing frames: ${missing.slice(0, 8).join(", ")}`);
});

test("provenance records that no facing is a placeholder", () => {
  assert.deepEqual(manifest.provenance.substitutedViews, {});
  assert.deepEqual(manifest.provenance.paintedViews, ["E", "N", "S"]);
  assert.match(manifest.provenance.honesty, /mirrored/);
});
