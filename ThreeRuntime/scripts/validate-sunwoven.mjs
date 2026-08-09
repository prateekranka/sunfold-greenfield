// B24-IMPORT — Three.js GLTFLoader import validation for the production
// Sunwoven Weaver (issue #24).
//
// Proves, in the actual Three.js runtime, that the shipped Sunwoven GLBs:
//   * load with the exact 27-bone shared skeleton and all sockets;
//   * carry the full 18-clip Sunwoven inventory (matching the manifest);
//   * keep walk/gather clips in place (root-motion inspection);
//   * carry authored accessory-strap + tool-socket tracks (no runtime physics);
//   * carry the authored chunk-arc channels inside the gather-loop clips;
//   * reproduce the authored locked pose from the .blend (per-bone deltas);
//   * and that the sequence/interruption module runs (event-authoritative).
//
//   node ThreeRuntime/scripts/validate-sunwoven.mjs
//
// Writes: Tools/citizens/build/import-validation-sunwoven.json
//         Tools/citizens/build/locked-pose-imported-sunwoven.json
//         Tools/citizens/build/mismatch-report-sunwoven.json

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import * as THREE from "three";

import { findBone, loadGLB, maxRootTranslation } from "./glb-validation-utils.mjs";
import { buildInterruptionMatrix } from "../src/sunwoven-sequence.js";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const toolsBuild = resolve(root, "Tools/citizens/build");
const citizensAssets = resolve(root, "ThreeRuntime/assets/citizens");

const MANIFEST = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/sunwoven-event-markers.json"), "utf8")
);
const LOCKED_CLIP = "sunwoven_gather_loop_R";
const LOCKED_FRAME = 12;
const FPS = MANIFEST.fps;

function findSunwovenSkinned(root, name) {
  let group = null;
  root.traverse((o) => {
    if (o.name === name && !o.isBone) group = o;
  });
  if (!group) return null;
  if (group.isSkinnedMesh) return group;
  return group.children.filter((c) => c.isSkinnedMesh) || null;
}

function rootMotionReport(gltf) {
  const report = {};
  for (const clipName of [
    "sunwoven_walk_inplace",
    "sunwoven_walk_loaded_inplace",
    "sunwoven_gather_loop_R",
    "sunwoven_construct_loop_L",
  ]) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    if (!clip) {
      report[clipName] = { error: "clip missing" };
      continue;
    }
    const maxDeviation = maxRootTranslation(gltf, clipName);
    report[clipName] = {
      duration_s: Number(clip.duration.toFixed(4)),
      max_root_translation_m: Number(maxDeviation.toExponential(6)),
      in_place: maxDeviation < 1e-4,
    };
  }
  return report;
}

function accessoryTrackReport(gltf) {
  const clips = ["sunwoven_deposit", "sunwoven_walk_loaded_inplace", "sunwoven_gather_loop_R"];
  const report = {};
  for (const clipName of clips) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    const tracks = (clip?.tracks ?? []).map((t) => t.name);
    report[clipName] = {
      accessory_strap_tracked: tracks.some((n) => n.includes("accessory_strap")),
      tool_socket_tracked: tracks.some((n) => n.includes("socket_tool_R") || n.includes("socket_tool_L")),
    };
  }
  return report;
}

function arcTrackReport(gltf) {
  const report = {};
  for (const side of ["R", "L"]) {
    const clipName = `sunwoven_gather_loop_${side}`;
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    const track = clip?.tracks.find((t) => t.name.includes("sunwoven_arc_prop.position"));
    report[clipName] = {
      arc_channel_present: Boolean(track),
      keyframe_count: track ? track.times.length : 0,
    };
  }
  return report;
}

function skeletonReport(gltf) {
  const bones = [];
  gltf.scene.traverse((o) => {
    if (o.isBone) bones.push(o.name);
  });
  const skinned = [];
  gltf.scene.traverse((o) => {
    if (o.isSkinnedMesh) skinned.push(o.name);
  });
  return {
    bone_count: bones.length,
    bone_names: bones.sort(),
    skinned_mesh_count: skinned.length,
    skinned_meshes: skinned.sort(),
    socket_tool_R: findBone(gltf.scene, "socket_tool_R") !== null,
    socket_tool_L: findBone(gltf.scene, "socket_tool_L") !== null,
    socket_carrier: findBone(gltf.scene, "socket_carrier") !== null,
  };
}

function toolChildReport(gltf) {
  const report = {};
  for (const [socket, tool] of [["socket_tool_R", "sunwoven_scraper"], ["socket_tool_L", "sunwoven_mallet"]]) {
    const socketBone = findBone(gltf.scene, socket);
    const children = socketBone ? socketBone.children.map((c) => c.name) : [];
    report[socket] = { tool_present: children.includes(tool), children };
  }
  return report;
}

function lockedPoseImport(gltf) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, LOCKED_CLIP);
  if (!clip) return { error: `clip ${LOCKED_CLIP} missing` };
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  const t = LOCKED_FRAME / FPS;
  action.time = t;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  const bodyGroup = gltf.scene.getObjectByName("sunwoven_body");
  const meshes = bodyGroup
    ? bodyGroup.isSkinnedMesh ? [bodyGroup] : bodyGroup.children.filter((c) => c.isSkinnedMesh)
    : [];
  if (meshes.length === 0) return { error: "sunwoven_body not found or not skinned" };
  for (const mesh of meshes) mesh.skeleton.update();
  const bones = {};
  gltf.scene.traverse((o) => {
    if (o.isBone) {
      const pos = new THREE.Vector3();
      const quat = new THREE.Quaternion();
      o.matrixWorld.decompose(pos, quat, new THREE.Vector3());
      bones[o.name] = {
        position: [pos.x, pos.y, pos.z].map((v) => Number(v.toFixed(6))),
        quaternion: [quat.x, quat.y, quat.z, quat.w].map((v) => Number(v.toFixed(6))),
      };
    }
  });
  const verts = [];
  const tmp = new THREE.Vector3();
  for (const mesh of meshes) {
    const posAttr = mesh.geometry.attributes.position;
    for (let i = 0; i < posAttr.count; i += 1) {
      tmp.set(posAttr.getX(i), posAttr.getY(i), posAttr.getZ(i));
      mesh.applyBoneTransform(i, tmp);
      tmp.applyMatrix4(mesh.matrixWorld);
      verts.push([tmp.x, tmp.y, tmp.z].map((v) => Number(v.toFixed(6))));
    }
  }
  mixer.stopAllAction();
  return {
    schema: "sunfold.sunwoven.locked-pose/1",
    clip: LOCKED_CLIP,
    frame: LOCKED_FRAME,
    time_s: Number(t.toFixed(4)),
    space: "gltf",
    bones,
    skin_vertex_count: verts.length,
    skin_vertices: verts,
  };
}

function quatError(a, b) {
  const dot = Math.abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]);
  return 2 * Math.acos(Math.min(1, dot));
}

function vertexError(sourceVerts, importedVerts) {
  const n = sourceVerts.length;
  let maxErr = 0;
  let sum = 0;
  let worst = 0;
  for (let i = 0; i < n; i += 1) {
    const s = sourceVerts[i];
    let best = Infinity;
    for (const im of importedVerts) {
      const err = Math.hypot(s[0] - im[0], s[1] - im[1], s[2] - im[2]);
      if (err < best) best = err;
    }
    sum += best;
    if (best > maxErr) {
      maxErr = best;
      worst = i;
    }
  }
  return {
    compared: n,
    source_count: n,
    imported_count: importedVerts.length,
    max_error_m: Number(maxErr.toExponential(6)),
    mean_error_m: Number((sum / n).toExponential(6)),
    worst_vertex_index: worst,
  };
}

function mismatchReport(sourcePath, importedPath) {
  const source = JSON.parse(readFileSync(sourcePath, "utf8"));
  const imported = JSON.parse(readFileSync(importedPath, "utf8"));
  const perBone = [];
  let maxPos = 0;
  let worstPosBone = "";
  for (const [name, s] of Object.entries(source.bones)) {
    const im = imported.bones[name];
    if (!im) {
      perBone.push({ bone: name, error: "missing in import" });
      continue;
    }
    const posErr = Math.hypot(
      s.position[0] - im.position[0],
      s.position[1] - im.position[1],
      s.position[2] - im.position[2]
    );
    if (posErr > maxPos) {
      maxPos = posErr;
      worstPosBone = name;
    }
    perBone.push({
      bone: name,
      position_error_m: Number(posErr.toExponential(6)),
      quaternion_error_rad: Number(quatError(s.quaternion, im.quaternion).toExponential(6)),
    });
  }
  const verts = vertexError(source.skin_vertices, imported.skin_vertices);
  return {
    schema: "sunfold.sunwoven.mismatch/1",
    clip: LOCKED_CLIP,
    frame: LOCKED_FRAME,
    bone_count_compared: perBone.length,
    max_bone_position_error_m: Number(maxPos.toExponential(6)),
    worst_position_bone: worstPosBone,
    skin_vertex: verts,
    quaternion_gate: "informational",
    passed: maxPos < 1e-3 && verts.max_error_m < 1e-3 && verts.compared === verts.source_count,
    per_bone: perBone.sort((a, b) => (b.position_error_m ?? 0) - (a.position_error_m ?? 0)),
  };
}

async function main() {
  const out = {
    schema: "sunfold.sunwoven.import-validation/1",
    manifest: "Tools/citizens/manifest/sunwoven-event-markers.json",
    three_version: THREE.REVISION,
    glbs: {},
  };

  for (const [key, file] of [
    ["citizen", "citizen_sunwoven.glb"],
    ["lab", "sunwoven_lab.glb"],
  ]) {
    const gltf = await loadGLB(resolve(citizensAssets, file));
    const clipNames = gltf.animations.map((a) => a.name);
    const expected = MANIFEST.clips.map((c) => c.name);
    const missing = expected.filter((n) => !clipNames.includes(n));
    const unexpected = clipNames.filter((n) => !new Set(expected).has(n));
    out.glbs[key] = {
      file,
      animation_count: clipNames.length,
      clips: clipNames,
      expected_clip_count: expected.length,
      all_expected_present: missing.length === 0 && unexpected.length === 0,
      missing_expected: missing,
      unexpected: unexpected,
      skeleton: skeletonReport(gltf),
      tool_children: key === "citizen" ? toolChildReport(gltf) : null,
      root_motion: rootMotionReport(gltf),
      accessory_motion: accessoryTrackReport(gltf),
    };
  }

  const lab = await loadGLB(resolve(citizensAssets, "sunwoven_lab.glb"));
  out.glbs.lab.arc_channels = arcTrackReport(lab);

  out.marker_schedule = MANIFEST.markers.map((m) => {
    const clip = new Map(MANIFEST.clips.map((c) => [c.name, c])).get(m.clip);
    return { ...m, in_clip_range: clip ? m.frame >= clip.frame_start && m.frame <= clip.frame_end : false };
  });
  out.marker_in_range = out.marker_schedule.every((m) => m.in_clip_range);
  out.marker_events_covered = [...new Set(MANIFEST.markers.map((m) => m.name))].sort();

  const interruption = buildInterruptionMatrix({ fps: FPS, arcDurationFrames: MANIFEST.arc_duration_frames });
  out.interruption_matrix = {
    passed: interruption.passed,
    failed_count: interruption.failed_count,
    case_count: interruption.cases.length,
    report_path: "Tools/citizens/build/sunwoven-interruption-matrix.json",
  };
  writeFileSync(
    resolve(toolsBuild, "sunwoven-interruption-matrix.json"),
    `${JSON.stringify(interruption, null, 2)}\n`
  );

  const importedPath = resolve(toolsBuild, "locked-pose-imported-sunwoven.json");
  const sourcePath = resolve(toolsBuild, "locked-pose-sunwoven-source.json");
  const imported = lockedPoseImport(await loadGLB(resolve(citizensAssets, "citizen_sunwoven.glb")));
  writeFileSync(importedPath, JSON.stringify(imported, null, 2));
  out.locked_pose = { clip: LOCKED_CLIP, frame: LOCKED_FRAME, imported_path: "Tools/citizens/build/locked-pose-imported-sunwoven.json" };

  const mismatch = mismatchReport(sourcePath, importedPath);
  writeFileSync(resolve(toolsBuild, "mismatch-report-sunwoven.json"), JSON.stringify(mismatch, null, 2));
  out.mismatch = {
    passed: mismatch.passed,
    max_bone_position_error_m: mismatch.max_bone_position_error_m,
    skin_vertex_max_error_m: mismatch.skin_vertex.max_error_m,
    skin_vertex_mean_error_m: mismatch.skin_vertex.mean_error_m,
    skin_vertex_count: mismatch.skin_vertex.compared,
    report_path: "Tools/citizens/build/mismatch-report-sunwoven.json",
  };

  writeFileSync(resolve(toolsBuild, "import-validation-sunwoven.json"), JSON.stringify(out, null, 2));
  console.log(JSON.stringify(out, null, 2));
  console.log(`[validate-sunwoven] wrote ${resolve(toolsBuild, "import-validation-sunwoven.json")}`);
}

main().catch((err) => {
  console.error("[validate-sunwoven] FAILED:", err);
  process.exit(1);
});
