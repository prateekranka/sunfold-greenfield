// Shared GLB import-validation helpers for the neutral citizen lab.
// Used by scripts/validate-glb.mjs and tests/glb-import.test.js so the
// runtime proof and the automated gate read the same numbers.

import { readFileSync } from "node:fs";

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

export function loadGLB(path) {
  return new Promise((resolve, reject) => {
    const buffer = readFileSync(path);
    const ab = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    new GLTFLoader().parse(ab, "", resolve, reject);
  });
}

export function findBone(root, name) {
  let found = null;
  root.traverse((obj) => {
    if (obj.isBone && obj.name === name) found = obj;
  });
  return found;
}

export function findSkinned(root, name) {
  let found = null;
  root.traverse((obj) => {
    if (obj.isSkinnedMesh && obj.name === name) found = obj;
  });
  return found;
}

export function boneNames(root) {
  const names = [];
  root.traverse((o) => {
    if (o.isBone) names.push(o.name);
  });
  return names.sort();
}

export function maxRootTranslation(gltf, clipName, steps = 24) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
  if (!clip) return { error: `clip ${clipName} missing` };
  const root = findBone(gltf.scene, "root");
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  let maxDeviation = 0;
  for (let i = 0; i <= steps; i += 1) {
    action.time = (clip.duration * i) / steps;
    mixer.update(0);
    gltf.scene.updateMatrixWorld(true);
    maxDeviation = Math.max(maxDeviation, root.position.length());
  }
  mixer.stopAllAction();
  return maxDeviation;
}

export function deformedSkinVertices(mesh) {
  const pos = mesh.geometry.attributes.position;
  const out = [];
  const tmp = new THREE.Vector3();
  for (let i = 0; i < pos.count; i += 1) {
    tmp.set(pos.getX(i), pos.getY(i), pos.getZ(i));
    mesh.applyBoneTransform(i, tmp);
    tmp.applyMatrix4(mesh.matrixWorld);
    out.push([tmp.x, tmp.y, tmp.z]);
  }
  return out;
}

export function pointCloudVertexError(sourceVerts, importedVerts) {
  let maxErr = 0;
  let sum = 0;
  for (const s of sourceVerts) {
    let best = Infinity;
    for (const im of importedVerts) {
      best = Math.min(best, Math.hypot(s[0] - im[0], s[1] - im[1], s[2] - im[2]));
    }
    maxErr = Math.max(maxErr, best);
    sum += best;
  }
  return { max_error_m: maxErr, mean_error_m: sum / sourceVerts.length };
}

export function boneWorldPose(gltf, clipName, timeS) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, clipName);
  if (!clip) return { error: `clip ${clipName} missing` };
  const mixer = new THREE.AnimationMixer(gltf.scene);
  const action = mixer.clipAction(clip);
  action.play();
  action.time = timeS;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  const bones = {};
  gltf.scene.traverse((o) => {
    if (o.isBone) {
      const pos = new THREE.Vector3();
      const quat = new THREE.Quaternion();
      o.matrixWorld.decompose(pos, quat, new THREE.Vector3());
      bones[o.name] = { position: [pos.x, pos.y, pos.z], quaternion: [quat.x, quat.y, quat.z, quat.w] };
    }
  });
  mixer.stopAllAction();
  return bones;
}
