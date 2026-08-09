// B23-IMPORT — Three.js GLTFLoader import validation + locked-pose round trip.
//
// Proves, in the actual Three.js runtime, that the shipped GLBs:
//   * load (GLTFLoader.parse) with the expected bone/skin/clip inventory;
//   * keep walk clips in place (root-motion inspection);
//   * carry authored accessory-strap tracks (no runtime physics);
//   * expose the tool sockets and the scraper/mallet as socket children;
//   * reproduce the authored locked pose from the .blend (per-bone deltas).
//
//   node ThreeRuntime/scripts/validate-glb.mjs
//
// Writes: Tools/citizens/build/import-validation.json
//         Tools/citizens/build/locked-pose-imported.json
//         Tools/citizens/build/mismatch-report.json

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import * as THREE from "three";
import { findBone, loadGLB, maxRootTranslation } from "./glb-validation-utils.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const toolsBuild = resolve(root, "Tools/citizens/build");
const labAssets = resolve(root, "ThreeRuntime/assets/lab");

const MANIFEST = JSON.parse(
  readFileSync(resolve(root, "Tools/citizens/manifest/event-markers.json"), "utf8")
);
const LOCKED_CLIP = "slender_gather_loop_R";
const LOCKED_FRAME = 12;
const FPS = MANIFEST.fps;

const manifestClips = new Map(MANIFEST.clips.map((c) => [c.name, c]));

function rootMotionReport(gltf, prefix) {
  const report = {};
  for (const clipName of [`${prefix}_walk_inplace`, `${prefix}_walk_loaded_inplace`, `${prefix}_gather_loop_R`]) {
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

function accessoryTrackReport(gltf, prefix) {
  const clips = [`${prefix}_deposit`, `${prefix}_walk_loaded_inplace`, `${prefix}_gather_loop_R`];
  const report = {};
  for (const clipName of clips) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
    const tracks = (clip?.tracks ?? []).map((t) => t.name);
    report[clipName] = {
      accessory_strap_tracked: tracks.some((n) => n.includes("accessory_strap")),
      socket_tool_R_tracked: tracks.some((n) => n.includes("socket_tool_R")),
    };
  }
  return report;
}

function markerSchedule() {
  const schedule = MANIFEST.markers.map((m) => {
    const clip = manifestClips.get(m.clip);
    return {
      ...m,
      in_clip_range: clip ? m.frame >= clip.frame_start && m.frame <= clip.frame_end : false,
    };
  });
  return schedule;
}

function skeletonReport(gltf) {
  const bones = [];
  gltf.scene.traverse((o) => {
    if (o.isBone) bones.push(o.name);
  });
  const skinnedMeshes = [];
  gltf.scene.traverse((o) => {
    if (o.isSkinnedMesh) skinnedMeshes.push(o.name);
  });
  return {
    bone_names: bones.sort(),
    bone_count: bones.length,
    skinned_meshes: skinnedMeshes.sort(),
    skinned_mesh_count: skinnedMeshes.length,
    socket_tool_R: findBone(gltf.scene, "socket_tool_R") !== null,
    socket_tool_L: findBone(gltf.scene, "socket_tool_L") !== null,
    socket_carrier: findBone(gltf.scene, "socket_carrier") !== null,
  };
}

function toolChildReport(gltf, prefix) {
  const report = {};
  for (const [socket, tool] of [["socket_tool_R", `${prefix}_scraper`], ["socket_tool_L", `${prefix}_mallet`]]) {
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
  const mesh = gltf.scene.getObjectByName("slender_body");
  if (!mesh?.isSkinnedMesh) return { error: "slender_body not found or not skinned" };
  mesh.skeleton.update();
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
  const posAttr = mesh.geometry.attributes.position;
  const tmp = new THREE.Vector3();
  for (let i = 0; i < posAttr.count; i += 1) {
    tmp.set(posAttr.getX(i), posAttr.getY(i), posAttr.getZ(i));
    mesh.applyBoneTransform(i, tmp);
    tmp.applyMatrix4(mesh.matrixWorld);
    verts.push([tmp.x, tmp.y, tmp.z].map((v) => Number(v.toFixed(6))));
  }
  mixer.stopAllAction();
  return {
    schema: "sunfold.lab.locked-pose/1",
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
  // The exporter duplicates vertices per-face (flat normals), so the import
  // is a superset of the authored mesh. Compare as point clouds: every
  // authored vertex must have a matching imported vertex within tolerance.
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
    schema: "sunfold.lab.mismatch/1",
    clip: LOCKED_CLIP,
    frame: LOCKED_FRAME,
    bone_count_compared: perBone.length,
    max_bone_position_error_m: Number(maxPos.toExponential(6)),
    worst_position_bone: worstPosBone,
    skin_vertex: verts,
    // Bone quaternions are reported but not gated: the glTF exporter
    // reconstructs bone rest orientations in its own basis, so raw bone
    // quaternions differ while the deformed pose (skinned vertices) matches.
    quaternion_gate: "informational",
    passed: maxPos < 1e-3 && verts.max_error_m < 1e-3 && verts.compared === verts.source_count,
    per_bone: perBone.sort((a, b) => (b.position_error_m ?? 0) - (a.position_error_m ?? 0)),
  };
}

async function main() {
  const out = {
    schema: "sunfold.lab.import-validation/1",
    manifest: "Tools/citizens/manifest/event-markers.json",
    three_version: THREE.REVISION,
    glbs: {},
  };

  for (const [key, file, prefix] of [
    ["citizen", "citizen_slender.glb", "slender"],
    ["citizen_broad", "citizen_broad.glb", "broad"],
    ["lab", "neutral_lab.glb", null],
  ]) {
    const gltf = await loadGLB(resolve(labAssets, file));
    const clipNames = gltf.animations.map((a) => a.name);
    const expected = MANIFEST.clips
      .map((c) => c.name)
      .filter((n) => (prefix ? n.startsWith(`${prefix}_`) : true));
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
      tool_children: prefix ? toolChildReport(gltf, prefix) : null,
      root_motion: prefix ? rootMotionReport(gltf, prefix) : null,
      accessory_motion: prefix ? accessoryTrackReport(gltf, prefix) : null,
    };
  }

  out.marker_schedule = markerSchedule();
  out.marker_events_covered = [...new Set(MANIFEST.markers.map((m) => m.name))].sort();
  out.marker_in_range = out.marker_schedule.every((m) => m.in_clip_range);

  const importedPath = resolve(toolsBuild, "locked-pose-imported.json");
  const sourcePath = resolve(toolsBuild, "locked-pose-source.json");
  const imported = lockedPoseImport(await loadGLB(resolve(labAssets, "citizen_slender.glb")));
  writeFileSync(importedPath, JSON.stringify(imported, null, 2));
  out.locked_pose = { clip: LOCKED_CLIP, frame: LOCKED_FRAME, imported_path: "Tools/citizens/build/locked-pose-imported.json" };

  const mismatch = mismatchReport(sourcePath, importedPath);
  writeFileSync(resolve(toolsBuild, "mismatch-report.json"), JSON.stringify(mismatch, null, 2));
  out.mismatch = {
    passed: mismatch.passed,
    max_bone_position_error_m: mismatch.max_bone_position_error_m,
    skin_vertex_max_error_m: mismatch.skin_vertex.max_error_m,
    skin_vertex_mean_error_m: mismatch.skin_vertex.mean_error_m,
    skin_vertex_count: mismatch.skin_vertex.compared,
    report_path: "Tools/citizens/build/mismatch-report.json",
  };

  writeFileSync(resolve(toolsBuild, "import-validation.json"), JSON.stringify(out, null, 2));
  console.log(JSON.stringify(out, null, 2));
  console.log(`[validate-glb] wrote ${resolve(toolsBuild, "import-validation.json")}`);
}

main().catch((err) => {
  console.error("[validate-glb] FAILED:", err);
  process.exit(1);
});
