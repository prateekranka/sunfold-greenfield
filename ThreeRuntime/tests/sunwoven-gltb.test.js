// Issue #24 — Sunwoven production GLB import gates.
//
// These are the automated acceptance gates for the production citizen and lab:
// exact shared rig contract, full 18-clip inventory, authored arc channels in
// the gather-loop clips (multi-slot export), in-place root motion, authored
// accessory tracks, tool sockets, and the locked-pose skin round trip.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import * as THREE from "three";

import {
  boneNames,
  deformedSkinVertices,
  findBone,
  findSkinned,
  loadGLB,
  maxRootTranslation,
  pointCloudVertexError,
} from "../scripts/glb-validation-utils.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const assets = resolve(root, "ThreeRuntime/assets/citizens");
const toolsBuild = resolve(root, "Tools/citizens/build");

const manifest = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/sunwoven-event-markers.json"), "utf8")
);
const manifestClips = new Map(manifest.clips.map((c) => [c.name, c]));
const sourcePose = JSON.parse(
  readFileSync(resolve(toolsBuild, "locked-pose-sunwoven-source.json"), "utf8")
);
const LOCKED_CLIP = "sunwoven_gather_loop_R";
const LOCKED_FRAME = 12;
const FPS = manifest.fps;

// Multi-material production meshes import as a Group (one SkinnedMesh child
// per material); the loader names those children after the glTF mesh data.
// This resolves either the direct SkinnedMesh or its per-material children.
function findSunwovenSkinned(root, name) {
  let group = null;
  root.traverse((o) => {
    if (o.name === name && !o.isBone) group = o;
  });
  if (!group) return null;
  if (group.isSkinnedMesh) return group;
  for (const child of group.children) {
    if (child.isSkinnedMesh) return child;
  }
  return null;
}

test("citizen GLB: exact 27-bone shared rig contract, all sockets present", async () => {
  const gltf = await loadGLB(resolve(assets, "citizen_sunwoven.glb"));
  const names = boneNames(gltf.scene);
  assert.equal(names.length, 27);
  const expected = manifest.clips.map((c) => c.name).filter((n) => n.startsWith("sunwoven_")).sort();
  const actual = gltf.animations.map((a) => a.name).sort();
  assert.deepEqual(actual, expected);
  assert.equal(actual.length, 18);
  for (const socket of ["socket_tool_R", "socket_tool_L", "socket_carrier"]) {
    assert.ok(names.includes(socket), `socket ${socket} missing`);
  }
  assert.ok(findSunwovenSkinned(gltf.scene, "sunwoven_body"), "body must be a SkinnedMesh");
  assert.ok(findSunwovenSkinned(gltf.scene, "sunwoven_basket"), "basket must be a SkinnedMesh");
});

test("lab GLB: 18 clips, arc prop present with gather-loop channels (multi-slot)", async () => {
  const gltf = await loadGLB(resolve(assets, "sunwoven_lab.glb"));
  const names = gltf.animations.map((a) => a.name).sort();
  const expected = manifest.clips.map((c) => c.name).sort();
  assert.deepEqual(names, expected);
  assert.equal(names.length, 18);
  for (const side of ["R", "L"]) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, `sunwoven_gather_loop_${side}`);
    assert.ok(clip, `gather_loop_${side} missing`);
    const arcTrack = clip.tracks.find((t) => t.name.includes("sunwoven_arc_prop.position"));
    assert.ok(arcTrack, `gather_loop_${side} must carry the authored arc prop channel`);
    assert.ok(arcTrack.times.length >= 5, "arc must have authored keyframes");
  }
  const arcProp = gltf.scene.getObjectByName("sunwoven_arc_prop");
  assert.ok(arcProp, "arc prop node must exist in the lab scene");
});

test("walk/gather clips keep the root in place (root-motion inspection)", async () => {
  const gltf = await loadGLB(resolve(assets, "citizen_sunwoven.glb"));
  for (const clipName of [
    "sunwoven_walk_inplace",
    "sunwoven_walk_loaded_inplace",
    "sunwoven_gather_loop_R",
    "sunwoven_construct_loop_L",
  ]) {
    const maxDev = maxRootTranslation(gltf, clipName);
    assert.ok(maxDev < 1e-4, `${clipName} root drifted ${maxDev} m`);
  }
});

test("accessory (basket/strap) and tool-socket motion is authored in the clips", async () => {
  const gltf = await loadGLB(resolve(assets, "citizen_sunwoven.glb"));
  for (const clipName of ["sunwoven_deposit", "sunwoven_walk_loaded_inplace", "sunwoven_gather_loop_R"]) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    const trackNames = clip.tracks.map((t) => t.name);
    assert.ok(
      trackNames.some((n) => n.includes("accessory_strap")),
      `${clipName} lacks accessory_strap track`
    );
    assert.ok(
      trackNames.some((n) => n.includes("socket_tool_R") || n.includes("socket_tool_L")),
      `${clipName} lacks tool socket tracks`
    );
  }
});

test("tools are bone-parented to their sockets; cargo chunks ride the basket strap", async () => {
  const gltf = await loadGLB(resolve(assets, "citizen_sunwoven.glb"));
  assert.ok(findBone(gltf.scene, "socket_tool_R").children.some((c) => c.name === "sunwoven_scraper"));
  assert.ok(findBone(gltf.scene, "socket_tool_L").children.some((c) => c.name === "sunwoven_mallet"));
  const lab = await loadGLB(resolve(assets, "sunwoven_lab.glb"));
  const strap = findBone(lab.scene, "accessory_strap");
  const cargoChildren = strap.children.filter((c) => c.name.startsWith("sunwoven_cargo_"));
  assert.equal(cargoChildren.length, 3, "cargo chunks must ride the basket strap (deposit swing included)");
});

test("every manifest marker resolves inside its clip's frame range", () => {
  for (const marker of manifest.markers) {
    const clip = manifestClips.get(marker.clip);
    assert.ok(clip, `marker references unknown clip ${marker.clip}`);
    assert.ok(
      marker.frame >= clip.frame_start && marker.frame <= clip.frame_end,
      `${marker.name} @ ${marker.frame} outside ${marker.clip}`
    );
  }
  const eventTypes = new Set(manifest.markers.map((m) => m.name));
  for (const event of ["tool_attach", "tool_release", "gather_contact", "payload_attach", "deposit_release", "construct_contact"]) {
    assert.ok(eventTypes.has(event), `marker event ${event} missing`);
  }
});

test("payload_attach is deterministically derived from gather_contact + arc duration", () => {
  const derived = manifest.markers.filter((m) => m.source === "derived");
  assert.ok(derived.length >= 2, "expected derived payload_attach markers");
  for (const m of derived) {
    assert.equal(m.name, "payload_attach");
    const contact = manifest.markers.find((x) => x.clip === m.clip && x.name === "gather_contact");
    assert.ok(contact, "payload_attach must anchor to an authored gather_contact");
    assert.equal(m.frame, contact.frame + m.offset_frames);
  }
});

test("locked-pose round trip: skinned vertices match the authored pose within 1 mm", async () => {
  const gltf = await loadGLB(resolve(assets, "citizen_sunwoven.glb"));
  const clip = THREE.AnimationClip.findByName(gltf.animations, LOCKED_CLIP);
  assert.ok(clip, `${LOCKED_CLIP} missing`);
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  action.time = LOCKED_FRAME / FPS;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  const bodyGroup = gltf.scene.getObjectByName("sunwoven_body");
  assert.ok(bodyGroup, "sunwoven_body node missing");
  const meshes = bodyGroup.isSkinnedMesh ? [bodyGroup] : bodyGroup.children.filter((c) => c.isSkinnedMesh);
  assert.ok(meshes.length >= 1, "expected skinned body mesh/bones");
  for (const mesh of meshes) mesh.skeleton.update();
  const imported = [];
  for (const mesh of meshes) imported.push(...deformedSkinVertices(mesh));
  const err = pointCloudVertexError(sourcePose.skin_vertices, imported);
  assert.ok(
    err.max_error_m < 1e-3,
    `locked-pose skin mismatch: max ${err.max_error_m} m (authored ${sourcePose.skin_vertices.length} verts, imported ${imported.length})`
  );
  mixer.stopAllAction();
});

test("sequence manifest: authored waypoints cover the full cycle and both handed variants", () => {
  const sequence = manifest.sequence;
  assert.equal(sequence.fps, FPS);
  const clipNames = sequence.steps.map((s) => s.clip);
  assert.ok(clipNames.includes("sunwoven_gather_start_R"));
  assert.ok(clipNames.includes("sunwoven_gather_loop_R"));
  assert.ok(clipNames.includes("sunwoven_construct_start_L"));
  assert.ok(clipNames.includes("sunwoven_construct_loop_L"));
  const loops = sequence.steps.filter((s) => s.repeat);
  assert.ok(loops.every((s) => s.repeat === 3));
  assert.ok(manifest.piece_settle.keys.length >= 3, "piece settle must be authored keyframe data");
});
