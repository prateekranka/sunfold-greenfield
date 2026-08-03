// GLB import contract for the neutral citizen lab (issue #23).
//
// These are the automated acceptance gates that must hold against the
// shipped GLBs and the committed marker manifest: clip inventory, skeleton
// and socket presence, in-place root motion, authored accessory tracks,
// marker timing, and the locked-pose round trip (deformed skin vertices).

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
const labAssets = resolve(root, "ThreeRuntime/assets/lab");
const toolsBuild = resolve(root, "Tools/citizens/build");

const manifest = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/event-markers.json"), "utf8")
);
const manifestClips = new Map(manifest.clips.map((c) => [c.name, c]));
const sourcePose = JSON.parse(
  readFileSync(resolve(toolsBuild, "locked-pose-source.json"), "utf8")
);

const LOCKED_CLIP = "slender_gather_loop_R";
const LOCKED_FRAME = 12;
const FPS = manifest.fps;

test("citizen GLB loads and matches the manifest clip inventory (18 slender clips)", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  const names = gltf.animations.map((a) => a.name).sort();
  const expected = manifest.clips.map((c) => c.name).filter((n) => n.startsWith("slender_")).sort();
  assert.deepEqual(names, expected);
  assert.equal(names.length, 18);
  assert.ok(gltf.animations.every((a) => a.tracks.length > 0));
});

test("broad citizen GLB preserves the shared bone names and its 18 clips", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_broad.glb"));
  const names = gltf.animations.map((a) => a.name).sort();
  const expected = manifest.clips.map((c) => c.name).filter((n) => n.startsWith("broad_")).sort();
  const slender = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  assert.deepEqual(names, expected);
  assert.equal(names.length, 18);
  assert.deepEqual(boneNames(gltf.scene), boneNames(slender.scene));
  for (const clipName of ["broad_walk_inplace", "broad_walk_loaded_inplace"]) {
    assert.ok(maxRootTranslation(gltf, clipName) < 1e-4, `${clipName} must remain in place`);
  }
});

test("lab GLB loads and matches the full manifest clip inventory (36 clips)", async () => {
  const gltf = await loadGLB(resolve(labAssets, "neutral_lab.glb"));
  const names = gltf.animations.map((a) => a.name).sort();
  const expected = manifest.clips.map((c) => c.name).sort();
  assert.deepEqual(names, expected);
  assert.equal(names.length, 36);
});

test("skeleton contract: 27 bones, sockets present, body + carrier skinned", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  const names = boneNames(gltf.scene);
  assert.equal(names.length, 27);
  for (const required of ["root", "hips", "spine_02", "chest", "head", "thigh_L", "foot_R", "toe_L"]) {
    assert.ok(names.includes(required), `bone ${required} missing`);
  }
  for (const socket of ["socket_tool_R", "socket_tool_L", "socket_carrier"]) {
    assert.ok(names.includes(socket), `socket ${socket} missing`);
  }
  assert.ok(findSkinned(gltf.scene, "slender_body"), "slender_body must be a SkinnedMesh");
  assert.ok(findSkinned(gltf.scene, "slender_carrier"), "slender_carrier must be a SkinnedMesh");
});

test("tools are bone-parented to their sockets (authored, no runtime physics)", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  const rSocket = findBone(gltf.scene, "socket_tool_R");
  const lSocket = findBone(gltf.scene, "socket_tool_L");
  assert.ok(rSocket.children.some((c) => c.name === "slender_scraper"), "scraper not on right socket");
  assert.ok(lSocket.children.some((c) => c.name === "slender_mallet"), "mallet not on left socket");
});

test("walk and gather clips keep the root in place (root-motion inspection)", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  for (const clipName of ["slender_walk_inplace", "slender_walk_loaded_inplace", "slender_gather_loop_R"]) {
    const maxDev = maxRootTranslation(gltf, clipName);
    assert.ok(maxDev < 1e-4, `${clipName} root drifted ${maxDev} m`);
  }
});

test("accessory (basket/strap) motion is authored in the clips", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  for (const clipName of ["slender_deposit", "slender_walk_loaded_inplace", "slender_gather_loop_R"]) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    const trackNames = clip.tracks.map((t) => t.name);
    assert.ok(
      trackNames.some((n) => n.includes("accessory_strap")),
      `${clipName} lacks accessory_strap track`
    );
  }
});

test("every manifest marker resolves inside its clip's frame range", () => {
  for (const marker of manifest.markers) {
    const clip = manifestClips.get(marker.clip);
    assert.ok(clip, `marker references unknown clip ${marker.clip}`);
    assert.ok(
      marker.frame >= clip.frame_start && marker.frame <= clip.frame_end,
      `${marker.name} @ ${marker.frame} outside ${marker.clip} [${clip.frame_start}, ${clip.frame_end}]`
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
    const contact = manifest.markers.find(
      (x) => x.clip === m.clip && x.name === "gather_contact"
    );
    assert.ok(contact, "payload_attach must anchor to an authored gather_contact");
    assert.equal(m.frame, contact.frame + m.offset_frames);
  }
});

test("locked-pose round trip: skinned vertices match the authored pose within 1 mm", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  const clip = THREE.AnimationClip.findByName(gltf.animations, LOCKED_CLIP);
  assert.ok(clip, `${LOCKED_CLIP} missing`);
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  action.time = LOCKED_FRAME / FPS;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  const mesh = findSkinned(gltf.scene, "slender_body");
  mesh.skeleton.update();
  const imported = deformedSkinVertices(mesh);
  const err = pointCloudVertexError(sourcePose.skin_vertices, imported);
  assert.ok(
    err.max_error_m < 1e-3,
    `locked-pose skin mismatch: max ${err.max_error_m} m (authored ${sourcePose.skin_vertices.length} verts, imported ${imported.length})`
  );
  mixer.stopAllAction();
});

test("locked-pose bone positions match within 1 mm", async () => {
  const gltf = await loadGLB(resolve(labAssets, "citizen_slender.glb"));
  const clip = THREE.AnimationClip.findByName(gltf.animations, LOCKED_CLIP);
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  action.time = LOCKED_FRAME / FPS;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  gltf.scene.traverse((o) => {
    if (o.isBone && sourcePose.bones[o.name]) {
      const expected = sourcePose.bones[o.name].position;
      const world = new THREE.Vector3().setFromMatrixPosition(o.matrixWorld);
      assert.ok(
        Math.hypot(world.x - expected[0], world.y - expected[1], world.z - expected[2]) < 1e-3,
        `${o.name} drifted`
      );
    }
  });
  mixer.stopAllAction();
});
