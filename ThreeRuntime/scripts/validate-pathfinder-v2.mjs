// Pathfinder (Scout) v2 — GLB structural QA gates (additive).
//
// Verifies the exported pathfinder_scout_v2.glb against the shared rig
// contract and the v2 sheet requirements:
//   * exact 27-bone rig, all three sockets present
//   * every authored part imports as a SkinnedMesh (or per-material Group)
//   * material roster matches the authored pathfinder_v2_* keys
//   * character world AABB height in [1.70, 1.80] m (skinned parts only;
//     the ground-anchored standard pole is excluded by design)
//   * the two scout clips exist, keep the root in place, and carry the
//     pennant sway channel
//   * pole is static (no skin weights); vertex budget < 50k

import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as THREE from "three";

import {
  boneNames,
  deformedSkinVertices,
  loadGLB,
  maxRootTranslation,
} from "./glb-validation-utils.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const glbPath = resolve(root, "ThreeRuntime/assets/citizens/pathfinder_scout_v2.glb");
const manifest = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/pathfinder-v2-clips.json"), "utf8")
);
const PREFIX = "pathfinder_v2";

function findSkinnedGroup(node, name) {
  let found = null;
  node.traverse((o) => {
    if (o.name === name && !o.isBone) found = o;
  });
  if (!found) return null;
  if (found.isSkinnedMesh) return found;
  for (const child of found.children) {
    if (child.isSkinnedMesh) return child;
  }
  return null;
}

const skinnedPartNames = [
  "pathfinder_v2_body",
  "pathfinder_v2_hood",
  "pathfinder_v2_hood_drape",
  "pathfinder_v2_gem",
  "pathfinder_v2_robe",
  "pathfinder_v2_shoulder_cap_L",
  "pathfinder_v2_shoulder_cap_R",
  "pathfinder_v2_shoulder_rim_L",
  "pathfinder_v2_shoulder_rim_R",
  "pathfinder_v2_sleeve_L",
  "pathfinder_v2_sleeve_R",
  "pathfinder_v2_cuff_L",
  "pathfinder_v2_cuff_R",
  "pathfinder_v2_sash",
  "pathfinder_v2_sash_tail",
  "pathfinder_v2_hip_bag",
  "pathfinder_v2_hip_bag_flap",
  "pathfinder_v2_strap",
  "pathfinder_v2_foot_wrap_L",
  "pathfinder_v2_foot_wrap_R",
];

test("GLB parses under GLTFLoader and the file is > 100 KB", async () => {
  const st = statSync(glbPath);
  assert.ok(st.size > 100_000, `GLB too small: ${st.size} bytes`);
  const gltf = await loadGLB(glbPath);
  assert.ok(gltf.scene, "scene must parse");
});

test("exact 27-bone shared rig contract; all sockets present", async () => {
  const gltf = await loadGLB(glbPath);
  const names = boneNames(gltf.scene);
  assert.equal(names.length, 27);
  for (const socket of ["socket_tool_R", "socket_tool_L", "socket_carrier"]) {
    assert.ok(names.includes(socket), `socket ${socket} missing`);
  }
});

test("every authored part imports as a SkinnedMesh", async () => {
  const gltf = await loadGLB(glbPath);
  for (const name of skinnedPartNames) {
    assert.ok(findSkinnedGroup(gltf.scene, name), `skinned part ${name} missing`);
  }
  // The standard pole and pennant are rigid, not skinned.
  assert.ok(gltf.scene.getObjectByName("pathfinder_v2_pole"), "pole node missing");
  assert.ok(gltf.scene.getObjectByName("pathfinder_v2_pennant"), "pennant node missing");
});

test("material roster matches the authored pathfinder_v2_* keys", async () => {
  const gltf = await loadGLB(glbPath);
  const expected = new Set(
    Object.keys(manifest.materials).map((k) => `${PREFIX}_${k}`)
  );
  const actual = new Set((gltf.materials || []).map((m) => m.name));
  assert.deepEqual([...actual].sort(), [...expected].sort());
});

test("character world AABB height in [1.70, 1.80] m (skinned parts, rest pose)", async () => {
  const gltf = await loadGLB(glbPath);
  gltf.scene.updateMatrixWorld(true);
  let minY = Infinity;
  let maxY = -Infinity;
  let verts = 0;
  gltf.scene.traverse((o) => {
    if (!o.isSkinnedMesh) return;
    for (const [_x, y, _z] of deformedSkinVertices(o)) {
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);
      verts += 1;
    }
  });
  const height = maxY - minY;
  assert.ok(height >= 1.70 && height <= 1.80, `character AABB height ${height.toFixed(4)} m out of [1.70, 1.80]`);
  assert.ok(minY > -0.02, `feet below ground plane: ${minY}`);
  assert.ok(verts < 50_000, `skinned vertex budget blown: ${verts}`);
});

test("the two scout clips: sane names, durations, in-place root, pennant sway", async () => {
  const gltf = await loadGLB(glbPath);
  const expected = manifest.clips.map((c) => c.name).sort();
  const actual = gltf.animations.map((a) => a.name).sort();
  assert.deepEqual(actual, expected);
  assert.equal(actual.length, 2);
  for (const clipMeta of manifest.clips) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipMeta.name);
    assert.ok(clip, `clip ${clipMeta.name} missing`);
    const dur = clip.duration;
    assert.ok(Math.abs(dur - clipMeta.duration_s) < 0.02, `${clipMeta.name} duration ${dur} != ${clipMeta.duration_s}`);
    const trackNames = clip.tracks.map((t) => t.name);
    assert.ok(
      trackNames.some((n) => n.includes("pathfinder_v2_pennant.rotation")),
      `${clipMeta.name} lacks the pennant sway channel`
    );
    const maxDev = maxRootTranslation(gltf, clipMeta.name);
    assert.ok(maxDev < 1e-4, `${clipMeta.name} root drifted ${maxDev} m`);
  }
});

test("pole and pennant stay planted: no bone influence, position constant at clip time", async () => {
  const gltf = await loadGLB(glbPath);
  const pennant = gltf.scene.getObjectByName("pathfinder_v2_pennant");
  const pole = pennant.parent;
  assert.ok(pole && pole.name === "pathfinder_v2_pole", "pennant must be a child of the pole");
  const clip = THREE.AnimationClip.findByName(gltf.animations, "pathfinder_v2_idle");
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  const base = pole.position.clone();
  for (const t of [0.25, 0.5, 0.75, 1.0]) {
    action.time = clip.duration * t;
    mixer.update(0);
    gltf.scene.updateMatrixWorld(true);
    assert.ok(pole.position.distanceTo(base) < 1e-5, `pole moved at t=${t}`);
  }
  mixer.stopAllAction();
});

test("manifest self-consistency: clips resolve and durations match frame spans", () => {
  for (const c of manifest.clips) {
    assert.equal(c.name, `${PREFIX}_${c.semantic === "walk_inplace" ? "walk_inplace" : "idle"}`);
    const span = (c.frame_end - c.frame_start) / manifest.fps;
    assert.ok(Math.abs(span - c.duration_s) < 1e-6, `${c.name} duration mismatch`);
  }
  assert.equal(manifest.clips.length, 2);
});
