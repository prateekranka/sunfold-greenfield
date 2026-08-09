// Golden Unit — 16-direction masked sprite pipeline contract tests.
//
// Covers: facing-16 math, the sunfold.sprite-manifest/2 shape, the baked
// atlas channel contract (albedo/normal/emissive), and GoldenSpriteUnit
// construction math. Atlas pixels are decoded with the zero-dependency PNG
// decoder (tests/helpers/png.js).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as THREE from "three";
import { decodePng } from "./helpers/png.js";
import {
  FACINGS_16,
  yawToFacing16,
  facingName16
} from "../src/sprites/facing.js";
import { GoldenSpriteUnit, isGoldenManifest } from "../src/sprites/golden-unit.js";

const SHEET_DIR = "assets/citizens/sprites/sunwoven-golden";
const CELL = 160;

function loadManifest() {
  return JSON.parse(readFileSync(`${SHEET_DIR}/atlas-manifest.json`, "utf8"));
}

function decode(name) {
  return decodePng(readFileSync(`${SHEET_DIR}/${name}`));
}

/** Mean per-channel difference over the union of non-transparent pixels. */
function diffCells(a, b) {
  let d = 0;
  let n = 0;
  for (let i = 0; i < a.length; i += 4) {
    if (a[i + 3] > 8 || b[i + 3] > 8) {
      d += Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]);
      n += 1;
    }
  }
  return n ? d / (3 * n) : 0;
}

function coverage(rgba, width, col, row) {
  const x0 = col * CELL;
  const y0 = row * CELL;
  let covered = 0;
  for (let y = y0; y < y0 + CELL; y += 2) {
    for (let x = x0; x < x0 + CELL; x += 2) {
      if (rgba[(y * width + x) * 4 + 3] > 8) covered += 1;
    }
  }
  return covered / ((CELL / 2) * (CELL / 2));
}

test("facing-16: yaw maps to 16 direction cells", () => {
  assert.equal(FACINGS_16.length, 16);
  assert.equal(FACINGS_16[0], "S");
  assert.equal(FACINGS_16[8], "N");
  assert.equal(FACINGS_16[4], "E");
  assert.equal(yawToFacing16(0), 0);
  assert.equal(yawToFacing16(Math.PI / 8), 1);
  assert.equal(yawToFacing16(Math.PI), 8);
  assert.equal(yawToFacing16(-Math.PI / 16), 0); // -22.5° is the S/SSW boundary → rounds up to S
  assert.equal(yawToFacing16(Math.PI * 2), 0);
  assert.equal(yawToFacing16(Math.PI * 2 + Math.PI / 4), 2);
  assert.equal(facingName16(8), "N");
  assert.equal(facingName16(-1), "SSW");
});

test("golden manifest: sunfold.sprite-manifest/2 with atlas16 playback", () => {
  const m = loadManifest();
  assert.equal(m.schema, "sunfold.sprite-manifest/2");
  assert.equal(m.unit, "sunwoven-golden");
  assert.equal(m.playback, "atlas16");
  assert.equal(m.directionColumns, 16);
  assert.equal(m.frameWidth, CELL);
  assert.equal(m.frameHeight, CELL);
  assert.equal(m.facings.length, 16);
  assert.deepEqual(
    Object.keys(m.clips),
    ["idle", "walk", "gather", "carry"]
  );
  // Per-clip timing is AoE2-authentic: 3 fps idle, 10 fps walk/carry, 5 fps gather.
  assert.equal(m.clips.idle.fps, 3);
  assert.equal(m.clips.walk.fps, 10);
  assert.equal(m.clips.gather.fps, 5);
  assert.equal(m.clips.carry.fps, 10);
  // Clip rows are contiguous within the manifest's logical sheet order.
  assert.equal(m.clips.idle.originRow, 0);
  assert.equal(m.clips.walk.originRow, 4);
  assert.equal(m.clips.gather.originRow, 8);
  assert.equal(m.clips.carry.originRow, 14);
  for (const clip of Object.values(m.clips)) {
    for (const channel of ["albedo", "normal", "emissive"]) {
      assert.ok(clip.channels[channel], `${clip} missing ${channel} channel`);
    }
  }
  // Bake provenance: measured figure, gameplay-scale frame, locked camera.
  assert.equal(m.unitHeightMeters, 1.7);
  assert.ok(m.worldHeight >= 2.5 && m.worldHeight <= 2.7);
  assert.ok(m.anchor.y > 0.8 && m.anchor.y < 0.85);
  assert.equal(m.camera.pitchDegrees, 57);
  assert.equal(m.camera.yawDegrees, 45);
  assert.equal(m.camera.fovDegrees, 38);
  assert.equal(m.mirrorAtRuntime, false);
  assert.equal(m.provenance.glb, "assets/units/citizen_villager.glb");
  assert.equal(m.provenance.normalSpace, "world");
  assert.equal(m.provenance.directions, 16);
});

test("golden atlases: dimensions match the manifest", () => {
  const m = loadManifest();
  for (const [clip, def] of Object.entries(m.clips)) {
    for (const channel of ["albedo", "normal", "emissive"]) {
      const { width, height } = decode(`${clip}-${channel}.png`);
      assert.equal(width, 16 * m.frameWidth, `${clip}-${channel} width`);
      assert.equal(height, def.frames * m.frameHeight, `${clip}-${channel} height`);
    }
  }
});

test("golden atlases: figure, directions, frames, and emissive accents", () => {
  const m = loadManifest();
  for (const clip of ["idle", "walk", "gather", "carry"]) {
    const albedo = decode(`${clip}-albedo.png`);
    const normal = decode(`${clip}-normal.png`);
    const emissive = decode(`${clip}-emissive.png`);
    // The figure occupies a healthy fraction of every cell.
    const cov = coverage(albedo.rgba, albedo.width, 0, 0);
    assert.ok(cov >= 0.03 && cov <= 0.3, `${clip} cell coverage ${cov}`);
    // Normal and emissive masks follow the albedo silhouette.
    assert.ok(coverage(normal.rgba, normal.width, 0, 0) >= cov * 0.8, `${clip} normal coverage`);
    assert.ok(coverage(emissive.rgba, emissive.width, 0, 0) >= cov * 0.8, `${clip} emissive coverage`);
    // 16 directions are real: a 90° turn (col 0 → col 4) must change the
    // silhouette strongly, and front vs back (col 0 vs col 8) must at least
    // differ (face/satchel vs robe back).
    const rowBytes = CELL * albedo.width * 4;
    const s0 = albedo.rgba.subarray(0, rowBytes);
    const s4 = albedo.rgba.subarray(4 * CELL * 4, 4 * CELL * 4 + rowBytes);
    const s8 = albedo.rgba.subarray(8 * CELL * 4, 8 * CELL * 4 + rowBytes);
    assert.ok(
      diffCells(s0, s4) > 30,
      `${clip} S-vs-E(90°) meanDelta ${diffCells(s0, s4).toFixed(1)}`
    );
    assert.ok(
      diffCells(s0, s8) > 15,
      `${clip} S-vs-N meanDelta ${diffCells(s0, s8).toFixed(1)}`
    );
  }
  // Walk frames animate (row 0 vs row 2 of the walk atlas).
  const walk = decode("walk-albedo.png");
  const rowBytes = CELL * walk.width * 4;
  const frameDelta = diffCells(
    walk.rgba.subarray(0, rowBytes),
    walk.rgba.subarray(2 * CELL * walk.width * 4, 2 * CELL * walk.width * 4 + rowBytes)
  );
  assert.ok(frameDelta > 8, `walk frame0-vs-frame2 meanDelta ${frameDelta}`);
  // Emissive mask carries real accents (bright gold/gem pixels).
  const em = decode("idle-emissive.png");
  let maxLuma = 0;
  for (let i = 0; i < em.rgba.length; i += 4) {
    const l = 0.299 * em.rgba[i] + 0.587 * em.rgba[i + 1] + 0.114 * em.rgba[i + 2];
    if (l > maxLuma) maxLuma = l;
  }
  assert.ok(maxLuma > 200, `emissive maxLuma ${maxLuma}`);
});

test("golden unit: construction math matches the manifest", () => {
  const m = loadManifest();
  const unit = new GoldenSpriteUnit(m, { basePath: `${SHEET_DIR}/` });
  // The billboard faces the locked camera at yaw 45°.
  assert.equal(unit.group.rotation.y, Math.PI / 4);
  // Plane: worldHeight tall, frame aspect wide, ground line at anchor.y.
  const geo = unit.mesh.geometry;
  const box = new THREE.Box3().setFromBufferAttribute(geo.attributes.position);
  const height = box.max.y - box.min.y;
  const width = box.max.x - box.min.x;
  assert.ok(Math.abs(height - m.worldHeight) < 1e-6, `plane height ${height}`);
  assert.ok(Math.abs(width - m.worldHeight) < 1e-6, `plane width ${width}`);
  const footroom = 1 - m.anchor.y;
  assert.ok(Math.abs(box.min.y + height * footroom) < 1e-6, `ground line y=${box.min.y}`);
  // Facing: setYaw snaps to the nearest 22.5° cell; setFacing stores the cell.
  unit.setFacing(8);
  assert.equal(unit.facing, 8);
  unit.setYaw(Math.PI / 8);
  assert.equal(unit.facing, 1);
  unit.setYaw(-Math.PI / 16); // -22.5° boundary → rounds to S (cell 0)
  assert.equal(unit.facing, 0);
  // Shader uniforms carry the shared lighting/emissive tuning.
  const u = unit.material.uniforms;
  assert.ok(u.uAlbedo && u.uNormal && u.uEmissive);
  assert.ok(u.uEmissiveBoost.value >= 1 && u.uEmissiveBoost.value <= 2);
  assert.ok(u.uAmbient.value < 0.4, "ambient stays under the bloom threshold");
});

test("isGoldenManifest: schema/playback detection", () => {
  assert.equal(isGoldenManifest({ playback: "atlas16" }), true);
  assert.equal(isGoldenManifest({ schema: "sunfold.sprite-manifest/2" }), true);
  assert.equal(isGoldenManifest({ playback: "grid", schema: "sunfold.sprite-manifest/1" }), false);
  assert.equal(isGoldenManifest(null), false);
  assert.equal(isGoldenManifest({}), false);
});
