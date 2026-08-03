// Neutral citizen animation lab — Three.js harness (issue #23).
//
// Loads the shipped neutral_lab.glb with GLTFLoader, plays the named clips
// through AnimationMixer, schedules the committed event markers from the
// event-marker manifest, inspects root motion, and renders the locked-pose
// round-trip comparison (side-by-side / overlay / difference vs the Blender
// source render). Everything is exposed on window.sunfoldLab for the CDP
// proof pass and for humans poking at the page.
//
// The lab uses the repository-derived RTS camera and lighting (main.js).

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MarkerScheduler } from "./lab-marker-scheduler.js";

const RTS_POS = new THREE.Vector3(0, 7.5, 12.5);
// Blender front camera (0, -4.5, 3.0) maps to glTF (0, 3.0, 4.5).
const LOCK_POS = new THREE.Vector3(0, 3.0, 4.5);
const LOCK_TARGET = new THREE.Vector3(0, 0, 0.9);
const LOCKED_CLIP = "slender_gather_loop_R";
const LOCKED_FRAME = 12;
const DIFF_W = 800;
const DIFF_H = 450;

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(1);
renderer.setSize(DIFF_W, DIFF_H);
document.getElementById("lab-root").appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050711);
const camera = new THREE.PerspectiveCamera(38, DIFF_W / DIFF_H, 0.1, 120);
const params0 = new URLSearchParams(location.search);
const keyIntensity = Number(params0.get("key") || 3.0);
const fillIntensity = Number(params0.get("fill") || 0.45);
const key = new THREE.DirectionalLight(0xffd28c, keyIntensity);
key.position.set(-4, 10, 5);
scene.add(key);
const fill = new THREE.DirectionalLight(0x14172b, fillIntensity);
fill.position.set(2, 3, -4);
scene.add(fill);

let gltf = null;
let manifest = { clips: [], markers: [] };
let mixer = null;
let action = null;
let clock = new THREE.Clock();
let playing = false;
let markerScheduler = null;
let unlitSwap = null;

// Swap every material to unlit MeshBasicMaterial to match the Blender
// Workbench FLAT studio render for the pixel comparison; originals are kept
// in `unlitSwap` and restored when setUnlit(false) is called.
function setUnlit(on) {
  if (on && !unlitSwap && gltf) {
    const originals = [];
    gltf.scene.traverse((o) => {
      if (o.material) {
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
          originals.push([o, m]);
          o.material = new THREE.MeshBasicMaterial({ color: m.color ? m.color.clone() : 0xffffff });
        }
      }
    });
    unlitSwap = originals;
  } else if (!on && unlitSwap) {
    for (const [o, m] of unlitSwap) o.material = m;
    unlitSwap = null;
  }
}

const el = (id) => document.getElementById(id);
const statusEl = el("status");
const logEl = el("event-log");
const markerCounts = {};

function setStatus(text) {
  statusEl.textContent = text;
}

function logEvent(name, clip, timeS) {
  const li = document.createElement("li");
  li.textContent = `[${timeS.toFixed(2)}s] ${name}  (${clip})`;
  logEl.prepend(li);
  while (logEl.children.length > 40) logEl.lastChild.remove();
  markerCounts[name] = (markerCounts[name] || 0) + 1;
  el("marker-tally").textContent = Object.entries(markerCounts)
    .map(([k, v]) => `${k}:${v}`)
    .join("  ");
}

function loadLab() {
  return new Promise((resolve, reject) => {
    new GLTFLoader().load("neutral_lab.glb", (g) => {
      gltf = g;
      scene.add(g.scene);
      mixer = new THREE.AnimationMixer(g.scene);
      resolve(g);
    }, undefined, reject);
  });
}

async function loadManifest() {
  manifest = await (await fetch("event-markers.json")).json();
  markerScheduler = new MarkerScheduler(manifest.markers);
}

function clipOptions() {
  const citizen = el("citizen").value;
  const names = gltf.animations
    .map((a) => a.name)
    .filter((n) => n.startsWith(`${citizen}_`))
    .sort();
  const select = el("clip");
  select.innerHTML = "";
  for (const name of names) {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    select.appendChild(opt);
  }
  fillClipMeta(select.value);
}

function fillClipMeta(name) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, name);
  const manifestClip = manifest.clips.find((c) => c.name === name);
  const markers = manifest.markers.filter((m) => m.clip === name);
  el("clip-meta").textContent =
    `${name}: ${clip.duration.toFixed(2)}s, ${clip.tracks.length} tracks` +
    `${manifestClip?.loop ? ", loop" : ""}` +
    (markers.length ? `, markers @ ${markers.map((m) => `${m.name}:${m.time_s.toFixed(2)}s`).join(", ")}` : "");
}

function playSelected() {
  const name = el("clip").value;
  if (!name) return;
  mixer.stopAllAction();
  action = mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, name));
  action.clampWhenFinished = !el("loop").checked;
  action.play();
  el("clip").closest(".row").querySelector(".control").textContent = "Pause";
  markerScheduler.reset();
  playing = true;
  setStatus(`PLAYING ${name}`);
}

function stopAll() {
  mixer?.stopAllAction();
  playing = false;
  setStatus("STOPPED");
}

function frame() {
  requestAnimationFrame(frame);
  const delta = Math.min(clock.getDelta(), 0.1);
  if (playing && action) {
    mixer.update(delta);
    if (action.getClip()) {
      const t = action.time;
      for (const marker of markerScheduler.advance(action.getClip().name, t)) {
        logEvent(marker.name, marker.clip, t);
      }
    }
    el("time").textContent = `${action.time.toFixed(2)}s / ${action.getClip().duration.toFixed(2)}s`;
  }
  renderer.render(scene, camera);
}

function setCamera(pos, target) {
  camera.position.copy(pos);
  camera.lookAt(target);
  camera.updateProjectionMatrix();
}

function rootMotion(name, steps = 24) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, name);
  const citizen = name.slice(0, name.indexOf("_"));
  const root = gltf.scene.getObjectByName(`${citizen}_body`)?.skeleton?.bones.find(
    (bone) => bone.name === "root" || bone.name.startsWith("root_")
  );
  if (!root) return { clip: name, error: "root bone missing", in_place: false };
  mixer.stopAllAction();
  const a = mixer.clipAction(clip);
  a.play();
  let maxDev = 0;
  for (let i = 0; i <= steps; i += 1) {
    a.time = (clip.duration * i) / steps;
    mixer.update(0);
    gltf.scene.updateMatrixWorld(true);
    maxDev = Math.max(maxDev, root.position.length());
  }
  mixer.stopAllAction();
  return { clip: name, max_root_translation_m: maxDev, in_place: maxDev < 1e-4 };
}

function findBone(root, name) {
  let found = null;
  root.traverse((o) => {
    if (o.isBone && o.name === name) found = o;
  });
  return found;
}

function drawToCanvas(canvas) {
  const ctx = canvas.getContext("2d");
  ctx.drawImage(renderer.domElement, 0, 0, DIFF_W, DIFF_H);
  return canvas;
}

function compositeImages(source, mode) {
  const out = document.createElement("canvas");
  out.width = DIFF_W * (mode === "sideBySide" ? 2 : 1);
  out.height = DIFF_H;
  const ctx = out.getContext("2d");
  if (mode === "sideBySide") {
    ctx.drawImage(source, 0, 0, DIFF_W, DIFF_H);
    ctx.drawImage(renderer.domElement, DIFF_W, 0, DIFF_W, DIFF_H);
  } else if (mode === "overlay") {
    ctx.drawImage(source, 0, 0);
    ctx.globalAlpha = 0.5;
    ctx.drawImage(renderer.domElement, 0, 0);
  }
  return out;
}

function differenceImage(source) {
  const out = document.createElement("canvas");
  out.width = DIFF_W;
  out.height = DIFF_H;
  const ctx = out.getContext("2d");
  const a = ctx.createImageData(DIFF_W, DIFF_H);
  const b = ctx.createImageData(DIFF_W, DIFF_H);
  ctx.drawImage(source, 0, 0);
  const srcData = ctx.getImageData(0, 0, DIFF_W, DIFF_H).data;
  const rt = document.createElement("canvas");
  rt.width = DIFF_W;
  rt.height = DIFF_H;
  rt.getContext("2d").drawImage(renderer.domElement, 0, 0);
  const rtData = rt.getContext("2d").getImageData(0, 0, DIFF_W, DIFF_H).data;
  let sum = 0;
  let overThreshold = 0;
  const THRESHOLD = 32; // per-channel byte delta
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.abs(srcData[i] - rtData[i]) + Math.abs(srcData[i + 1] - rtData[i + 1]) + Math.abs(srcData[i + 2] - rtData[i + 2]);
    sum += d;
    if (d > THRESHOLD) overThreshold += 1;
    const v = Math.min(255, d * 4);
    a.data[i] = v;
    a.data[i + 1] = v;
    a.data[i + 2] = v;
    a.data[i + 3] = 255;
  }
  ctx.putImageData(a, 0, 0);
  const total = DIFF_W * DIFF_H;
  return {
    canvas: out,
    mean_abs_channel_delta: Number((sum / (total * 3)).toFixed(3)),
    pixels_over_threshold: overThreshold,
    pixels_over_threshold_frac: Number((overThreshold / total).toFixed(4)),
  };
}

function loadSourceImage() {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = "locked-pose-source.png";
  });
}

async function lockedPoseProof() {
  const source = await loadSourceImage();
  setCamera(LOCK_POS, LOCK_TARGET);
  mixer.stopAllAction();
  const clip = THREE.AnimationClip.findByName(gltf.animations, LOCKED_CLIP);
  const a = mixer.clipAction(clip);
  a.play();
  a.time = LOCKED_FRAME / manifest.fps;
  mixer.update(0);
  gltf.scene.updateMatrixWorld(true);
  const result = { clip: LOCKED_CLIP, frame: LOCKED_FRAME, time_s: LOCKED_FRAME / manifest.fps, source_loaded: source !== null };
  renderer.render(scene, camera);
  result.raw_render = renderer.domElement.toDataURL("image/png");
  const diff = differenceImage(source);
  result.diff_stats = {
    mean_abs_channel_delta: diff.mean_abs_channel_delta,
    pixels_over_threshold: diff.pixels_over_threshold,
    pixels_over_threshold_frac: diff.pixels_over_threshold_frac,
    image_width: DIFF_W,
    image_height: DIFF_H,
  };
  result.images = {
    side_by_side: compositeImages(source, "sideBySide").toDataURL("image/jpeg", 0.9),
    overlay: compositeImages(source, "overlay").toDataURL("image/jpeg", 0.9),
    difference: diff.canvas.toDataURL("image/jpeg", 0.9),
  };
  setCamera(RTS_POS, new THREE.Vector3(0, 0, 0));
  return result;
}

async function runProof() {
  const proof = {
    three_revision: THREE.REVISION,
    glb: { clip_count: gltf.animations.length, clips: gltf.animations.map((a) => a.name).sort() },
    manifest: { clip_count: manifest.clips.length, marker_count: manifest.markers.length },
    clip_inventory_matches_manifest:
      gltf.animations.map((a) => a.name).sort().join() === manifest.clips.map((c) => c.name).sort().join(),
    root_motion: [
      rootMotion("slender_walk_inplace"),
      rootMotion("slender_walk_loaded_inplace"),
      rootMotion("slender_gather_loop_R"),
      rootMotion("broad_walk_inplace"),
      rootMotion("broad_walk_loaded_inplace"),
    ],
    marker_events_covered: [...new Set(manifest.markers.map((m) => m.name))].sort(),
    locked_pose: await lockedPoseProof(),
  };
  proof.ok =
    proof.clip_inventory_matches_manifest &&
    proof.root_motion.every((r) => r.in_place) &&
    proof.locked_pose.source_loaded;
  document.getElementById("proof-summary").textContent = JSON.stringify(
    {
      ok: proof.ok,
      clips: proof.clip_inventory_matches_manifest ? `${proof.glb.clip_count}/${proof.manifest.clip_count}` : "MISMATCH",
      root_motion: proof.root_motion.map((r) => r.max_root_translation_m),
      diff: proof.locked_pose.diff_stats,
    },
    null,
    1
  );
  window.sunfoldLab.proof = proof;
  return proof;
}

// Public API for the CDP proof pass.
window.sunfoldLab = {
  THREE,
  scene,
  camera,
  get gltf() {
    return gltf;
  },
  get manifest() {
    return manifest;
  },
  clipOptions,
  playSelected,
  stopAll,
  rootMotion,
  lockedPoseProof,
  runProof,
  setCamera,
  setUnlit,
  proof: null,
};

// Auto-drive the proof when ?proof=1, else show the lab playing idle.
const params = new URLSearchParams(location.search);

async function init() {
  setStatus("LOADING neutral_lab.glb");
  try {
    await Promise.all([loadLab(), loadManifest()]);
  } catch (err) {
    setStatus(`LOAD FAILED: ${err.message}`);
    return;
  }
  el("clip-select").hidden = false;
  clipOptions();
  setCamera(RTS_POS, new THREE.Vector3(0, 0, 0));
  setStatus("READY — select a clip to play");
  if (params.get("proof") === "1") {
    setStatus("RUNNING PROOF");
    try {
      const proof = await runProof();
      setStatus(`PROOF ${proof.ok ? "PASS" : "FAIL"} — see window.sunfoldLab.proof`);
    } catch (err) {
      setStatus(`PROOF ERROR: ${err.message}`);
    }
  } else {
    el("clip").value = "slender_idle";
    fillClipMeta("slender_idle");
    playSelected();
  }
}

el("citizen").addEventListener("change", clipOptions);
el("clip").addEventListener("change", () => fillClipMeta(el("clip").value));
el("play").addEventListener("click", playSelected);
el("stop").addEventListener("click", stopAll);

requestAnimationFrame(frame);
init();
