// B24-LAB — production Sunwoven Weaver proof page (issue #24).
//
// Loads sunwoven_lab.glb + the Sunwoven event-marker manifest, then plays the
// authored sequence
//   Idle → Walk → Gather → Carry → Deposit → Walk → Construct → Idle
// at repository RTS scale. The sequence steps, waypoints, walk speed, arc
// keyframes and piece-settle keys are all authored in the DCC and shipped
// through the manifest / clip channels — nothing here is a runtime physics
// sim. Markers drive the event-authoritative state machine
// (sunwoven-sequence.js) and the prop presentation: chunk arcs, cargo in the
// basket, the atomic deposit transfer, and piece lock/settle.
//
// Exposes window.sunwovenProof for the CDP capture pass.

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MarkerScheduler } from "./lab-marker-scheduler.js";
import { createSunwovenCycle } from "./sunwoven-sequence.js";
import { createRtsCamera, applyRtsCamera } from "./rts-camera.js";

const RTS_TARGET = new THREE.Vector3(0, 0, 0);
const CLIP_CROSSFADE_S = 0.14;
const W = 1280;
const H = 720;

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(1);
renderer.setSize(W, H);
document.getElementById("sunwoven-root").appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050711);
const camera = createRtsCamera(W / H);
applyRtsCamera(camera, RTS_TARGET);

const key = new THREE.DirectionalLight(0xffd28c, 3.0);
key.position.set(-4, 10, 5);
scene.add(key);
const fill = new THREE.DirectionalLight(0x14172b, 0.45);
fill.position.set(2, 3, -4);
scene.add(fill);

const el = (id) => document.getElementById(id);

let gltf = null;
let manifest = { clips: [], markers: [], sequence: { steps: [] }, piece_settle: { keys: [] } };
let mixer = null;
let armature = null;
let cycle = null;
let scheduler = null;
let clock = new THREE.Clock();
let playing = false;
let proof = null;

// ---- prop registry -------------------------------------------------------
const props = {
  arc: null,
  cargo: [],
  sourcePiles: [],
  pieces: [],
  pieceBaseY: [],
  depositChunks: [],
  visibleCargo: 0,
  gathered: 0,
  installed: 0,
  depositDone: false,
};

function findNamed(root, name) {
  let found = null;
  root.traverse((o) => {
    if (o.name === name) found = o;
  });
  return found;
}

function collectProps() {
  props.arc = findNamed(gltf.scene, "sunwoven_arc_prop");
  for (let i = 0; i < 3; i += 1) {
    props.cargo.push(findNamed(gltf.scene, `sunwoven_cargo_${i}`));
    props.sourcePiles.push(findNamed(gltf.scene, `sunwoven_source_pile_${i}`));
    const piece = findNamed(gltf.scene, `sunwoven_construction_frame_${i}`);
    props.pieces.push(piece);
    props.pieceBaseY.push(piece ? piece.position.y : 0);
  }
  // Runtime presentation starts clean: cargo hidden, arc hidden, deposit fill absent.
  for (const obj of [props.arc, ...props.cargo]) {
    if (obj) obj.visible = false;
  }
  for (const chunk of props.depositChunks) scene.remove(chunk);
}

function revealCargoAt(i) {
  if (props.cargo[i]) props.cargo[i].visible = true;
  props.visibleCargo += 1;
}

function clearCargo() {
  for (const obj of props.cargo) {
    if (obj) obj.visible = false;
  }
  props.visibleCargo = 0;
}

function spawnDepositFill() {
  const mat = new THREE.MeshStandardMaterial({ color: 0x6e5640, roughness: 0.85, metalness: 0.0 });
  const target = new THREE.Vector3(-0.2, 0.14, 2.7);
  const placements = [
    [0, 0, 0, 0.07],
    [0.09, 0.02, 0.05, 0.06],
    [-0.07, 0.05, 0.09, 0.065],
  ];
  for (const [dx, dy, dz, r] of placements) {
    const geo = new THREE.BoxGeometry(r, r * 0.8, r * 0.9);
    geo.translate(dx, dy + r * 0.4, dz);
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(target);
    mesh.rotation.set(0.3, 0.7, 0.1);
    scene.add(mesh);
    props.depositChunks.push(mesh);
  }
}

// ---- authored settle driver ----------------------------------------------
const settle = { active: false, piece: null, baseY: 0, startTime: 0, keys: [] };

function applySettleTo(pieceIndex) {
  const piece = props.pieces[pieceIndex];
  if (!piece) return;
  const keys = (manifest.piece_settle?.keys ?? []).map(([frame, offset]) => [frame / manifest.fps, offset]);
  settle.active = true;
  settle.piece = piece;
  settle.baseY = props.pieceBaseY[pieceIndex];
  settle.startTime = clock.elapsedTime;
  settle.keys = keys;
  props.installed += 1;
}

function updateSettle(now) {
  if (!settle.active) return;
  const t = now - settle.startTime;
  const keys = settle.keys;
  let offset = 0;
  if (t >= keys[keys.length - 1][0]) {
    offset = keys[keys.length - 1][1];
    settle.active = false;
  } else if (t >= keys[0][0]) {
    for (let i = 0; i < keys.length - 1; i += 1) {
      const [t0, v0] = keys[i];
      const [t1, v1] = keys[i + 1];
      if (t >= t0 && t <= t1) {
        const k = (t - t0) / (t1 - t0);
        offset = v0 + (v1 - v0) * k;
        break;
      }
    }
  }
  settle.piece.position.y = settle.baseY - offset;
}

// ---- player --------------------------------------------------------------
const player = {
  stepIndex: 0,
  stepTime: 0,
  stepDuration: 0,
  action: null,
  clipName: "",
  repeat: 1,
  repeatCount: 0,
  captures: {},
  eventTrace: [],
  clipsPlayed: [],
};

function blenderToGltf(bx, bz) {
  // Blender ground (x, y) -> glTF (x, 0, -y); Blender yaw about +Z -> glTF -yaw about +Y.
  return new THREE.Vector3(bx, 0, -bz);
}

function positionStep(step, t) {
  const start = blenderToGltf(...player.startPos);
  const end = blenderToGltf(...step.position);
  const p = start.clone().lerp(end, t);
  armature.position.copy(p);
  const yaw = (step.yaw_deg ?? 0) * (Math.PI / 180);
  armature.rotation.set(0, -yaw, 0);
}

function followCamera() {
  // Locked RTS rig — no orbit or chase cam; GLB proof plays under fixed AoE2 angles.
  applyRtsCamera(camera, RTS_TARGET);
}

function startStep(step) {
  player.clipName = step.clip;
  player.stepTime = 0;
  player.repeatCount = 0;
  const clip = THREE.AnimationClip.findByName(gltf.animations, step.clip);
  if (!clip) {
    throw new Error(`clip ${step.clip} missing from GLB`);
  }
  const manifestClip = manifest.clips.find((c) => c.name === step.clip);
  const isWalk = step.clip.includes("walk");
  player.loopable = (step.repeat ?? 1) > 1 || Boolean(manifestClip?.loop);
  if (isWalk && player.startPos) {
    const dist = blenderToGltf(...step.position).distanceTo(blenderToGltf(...player.startPos));
    player.stepDuration = Math.max(0.6, dist / manifest.sequence.walk_speed_m_s);
  } else if (step.repeat) {
    player.stepDuration = clip.duration * step.repeat;
  } else {
    player.stepDuration = clip.duration;
  }
  const next = mixer.clipAction(clip);
  next.loop = THREE.LoopOnce;
  next.clampWhenFinished = true;
  next.reset();
  if (player.action) {
    player.action.fadeOut(CLIP_CROSSFADE_S);
    next.fadeIn(CLIP_CROSSFADE_S);
  }
  next.play();
  player.action = next;
  scheduler.reset();
  player.clipsPlayed.push(step.clip);
  if (el("current-clip")) el("current-clip").textContent = step.clip;
}

function handleMarker(marker, timeS) {
  player.eventTrace.push({ ...marker, played_at_s: Number(timeS.toFixed(3)) });
  cycle.advance({ kind: marker.name, clip: marker.clip, timeS, repetition: scheduler.cycle });
  switch (marker.name) {
    case "gather_contact": {
      if (props.sourcePiles[props.gathered]) props.sourcePiles[props.gathered].visible = false;
      if (props.arc) props.arc.visible = true;
      captureFrame(`10-gather-contact-${props.gathered + 1}`);
      break;
    }
    case "payload_attach": {
      if (props.arc) props.arc.visible = false;
      revealCargoAt(props.visibleCargo);
      captureFrame(`15-cargo-${props.visibleCargo}`);
      break;
    }
    case "deposit_release": {
      clearCargo();
      spawnDepositFill();
      props.depositDone = true;
      captureFrame("30-deposit-release");
      break;
    }
    case "construct_contact": {
      applySettleTo(props.installed);
      captureFrame(`40-construct-contact-${props.installed}`);
      break;
    }
    default:
      break;
  }
}

function advancePlayer(dt) {
  if (!player.action) return;
  player.stepTime += dt;
  const step = manifest.sequence.steps[player.stepIndex];
  if (step.position && player.startPos) {
    const t = Math.min(1, player.stepTime / player.stepDuration);
    positionStep(step, t);
  }
  mixer.update(dt);
  updateSettle(clock.elapsedTime);
  const clip = player.action.getClip();
  if (clip) {
    const t = player.action.time;
    for (const marker of scheduler.advance(clip.name, t)) {
      handleMarker(marker, t);
    }
    if (player.stepTime >= player.stepDuration) {
      nextStep();
      return;
    }
    if (t >= clip.duration - 1e-4) {
      if (player.loopable) {
        player.action.reset();
        player.action.play();
        scheduler.reset();
      }
    }
  }
}

function nextStep() {
  player.stepIndex += 1;
  if (player.stepIndex >= manifest.sequence.steps.length) {
    playing = false;
    captureFrame("50-final-idle");
    finishProof();
    return;
  }
  const step = manifest.sequence.steps[player.stepIndex];
  const prev = manifest.sequence.steps[player.stepIndex - 1];
  player.startPos = prev ? prev.position : step.position;
  startStep(step);
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.1);
  if (playing) advancePlayer(dt);
  followCamera();
  renderer.render(scene, camera);
}

function captureFrame(label) {
  if (player.captures[label]) return;
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  canvas.getContext("2d").drawImage(renderer.domElement, 0, 0, W, H);
  player.captures[label] = canvas.toDataURL("image/png");
  if (el("capture-log")) el("capture-log").textContent = Object.keys(player.captures).join(", ");
}

async function loadAssets() {
  await new Promise((resolve, reject) => {
    new GLTFLoader().load("sunwoven_lab.glb", (g) => {
      gltf = g;
      scene.add(g.scene);
      mixer = new THREE.AnimationMixer(g.scene);
      armature = findNamed(g.scene, "sunwoven_armature");
      resolve();
    }, undefined, reject);
  });
  manifest = await (await fetch("sunwoven-event-markers.json")).json();
  scheduler = new MarkerScheduler(manifest.markers);
  cycle = createSunwovenCycle({
    fps: manifest.fps,
    arcDurationFrames: manifest.arc_duration_frames,
  });
  collectProps();
}

function finishProof() {
  const finalState = cycle.snapshot();
  const facts = {
    chunks_gathered: finalState.sourceChunks === 0,
    cargo_committed: finalState.cargo === 0 && finalState.deposited === 3,
    deposit_atomic: props.depositDone,
    pieces_installed: props.installed === 3,
    tool_secured: finalState.tool === "none" && finalState.toolAtRest === true,
    sequence_clips: player.clipsPlayed.length,
  };
  proof = {
    three_revision: THREE.REVISION,
    glb: {
      clip_count: gltf.animations.length,
      clips: gltf.animations.map((a) => a.name).sort(),
      skeleton_bones: (() => {
        const bones = [];
        gltf.scene.traverse((o) => {
          if (o.isBone) bones.push(o.name);
        });
        return bones.length;
      })(),
    },
    manifest: {
      clip_count: manifest.clips.length,
      marker_count: manifest.markers.length,
      fps: manifest.fps,
    },
    clip_inventory_matches_manifest:
      gltf.animations.map((a) => a.name).sort().join() === manifest.clips.map((c) => c.name).sort().join(),
    sequence: {
      steps_played: player.clipsPlayed,
      event_trace: player.eventTrace,
      cycle_final: finalState,
    },
    facts,
    captures: player.captures,
  };
  proof.ok =
    facts.chunks_gathered &&
    facts.cargo_committed &&
    facts.deposit_atomic &&
    facts.pieces_installed &&
    facts.tool_secured &&
    proof.clip_inventory_matches_manifest &&
    player.eventTrace.length >= 12;
  if (el("proof-summary")) {
    el("proof-summary").textContent = JSON.stringify(
      { ok: proof.ok, clips: proof.clip_inventory_matches_manifest, facts, events: player.eventTrace.length },
      null,
      1
    );
  }
  window.sunwovenProof = proof;
}

function start() {
  player.startPos = [0, 0];
  player.stepIndex = 0;
  startStep(manifest.sequence.steps[0]);
  playing = true;
  captureFrame("00-idle-start");
}

const params = new URLSearchParams(location.search);

async function init() {
  if (el("status")) el("status").textContent = "LOADING sunwoven_lab.glb";
  try {
    await loadAssets();
  } catch (err) {
    if (el("status")) el("status").textContent = `LOAD FAILED: ${err.message}`;
    return;
  }
  if (el("status")) el("status").textContent = "READY — playing authored Sunwoven sequence";
  if (params.get("proof") === "1") {
    start();
  }
}

window.sunwovenProof = proof;
requestAnimationFrame(frame);
init();
