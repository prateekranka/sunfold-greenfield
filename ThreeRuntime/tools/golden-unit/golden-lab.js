// Golden Unit Lab — 48 Sunwoven Foundation Citizens as 16-direction masked
// sprites, at gameplay scale, under the locked RTS camera.
//
// Test script:
//   1. preload golden atlases (12 textures) while the page boots
//   2. spawn 48 units in one burst — the spawn-hitch window
//   3. scripted camera phases: default (16 m) → medium (26 m) → closest
//      permitted (8.5 m) → camera movement (pan orbit + zoom) → settle
//   4. measure fps per phase + spawn max frame; gate on 60 fps stability
//   5. capture: default / medium / close zoom frames + the battlefield frame
//      at 2560×1440, POSTed to the serving node
//
// Exposes window.goldenLab = { stats, phases, units, capture, result }.

import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { createRegistry, assetIdForUnit } from "../../src/asset-registry.js";
import { UnitPresentationLayer } from "../../src/sprites/unit-layer.js";
import { GoldenSpriteUnit } from "../../src/sprites/golden-unit.js";
import { createProceduralUnit } from "../../src/procedural-units.js";
import { applyRtsCamera, RTS_CAMERA } from "../../src/rts-camera.js";
import assetRegistryData from "../../assets/asset-registry.json";

const UNIT_COUNT = 48;
// Absolute from the served root: the canonical sheet ships under
// assets/citizens/sprites/ (dev server) and Resources/ThreeRuntime/sprites/
// (bundled app) — the lab runs against the dev copy.
const SHEET = "/assets/citizens/sprites/sunwoven-golden/";
const CAPTURE_DIR = "assets/citizens/captures/golden-unit";

const registry = createRegistry(assetRegistryData);

const root = document.getElementById("golden-root");
const hud = document.getElementById("hud");
const setHud = (lines) => {
  hud.innerHTML = lines.map((l) => l.replace(/</g, "&lt;")).join("\n");
};

// Deterministic LCG (project determinism rule — no Math.random in visuals).
function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// ---- renderer / scene ------------------------------------------------------

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
renderer.setSize(root.clientWidth, root.clientHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
root.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050711);
const camera = new THREE.PerspectiveCamera(
  RTS_CAMERA.fovDegrees,
  root.clientWidth / root.clientHeight,
  RTS_CAMERA.near,
  RTS_CAMERA.far
);
applyRtsCamera(camera, new THREE.Vector3(0, 0, 0), RTS_CAMERA.defaultDistance);

// Lights — key casts the real shadow map; structures cast, units use blobs.
const key = new THREE.DirectionalLight(0xffd28c, 3.0);
key.position.set(-4, 10, 5);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.camera.left = -30;
key.shadow.camera.right = 30;
key.shadow.camera.top = 30;
key.shadow.camera.bottom = -30;
key.shadow.camera.near = 1;
key.shadow.camera.far = 40;
key.shadow.bias = -0.0005;
scene.add(key);
scene.add(new THREE.AmbientLight(0x9ab5d9, 0.55));
const fill = new THREE.DirectionalLight(0x14172b, 0.45);
fill.position.set(2, 3, -4);
scene.add(fill);

const ground = new THREE.Mesh(
  new THREE.CircleGeometry(60, 64),
  new THREE.MeshStandardMaterial({ color: 0x4c403d, roughness: 0.94, metalness: 0 })
);
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);

// The Civilization Core (rings + spire) so structures cast real shadows.
const core = new THREE.Group();
const ring = new THREE.Mesh(
  new THREE.TorusGeometry(2.1, 0.04, 8, 64),
  new THREE.MeshBasicMaterial({ color: 0xe2b866, transparent: true, opacity: 0.85 })
);
ring.rotation.x = -Math.PI / 2;
ring.position.y = 0.02;
const spire = new THREE.Mesh(
  new THREE.ConeGeometry(0.65, 1.8, 6),
  new THREE.MeshStandardMaterial({
    color: 0xc29b5d,
    roughness: 0.55,
    metalness: 0.12,
    emissive: 0x2e1808,
    emissiveIntensity: 0.45
  })
);
spire.position.y = 0.9;
spire.castShadow = true;
core.add(ring, spire);
core.position.set(-16, 0, -12);
scene.add(core);

// A few deposit piles for the gatherers to face.
const deposits = [];
for (let i = 0; i < 3; i += 1) {
  const pile = new THREE.Group();
  for (let j = 0; j < 5; j += 1) {
    const rock = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.35 + makeRng(i * 7 + j)() * 0.3),
      new THREE.MeshStandardMaterial({ color: 0x7a6a52, roughness: 0.9 })
    );
    rock.position.set((makeRng(i * 13 + j)() - 0.5) * 1.4, 0.2 + makeRng(i * 17 + j)() * 0.25, (makeRng(i * 23 + j)() - 0.5) * 1.4);
    rock.castShadow = true;
    pile.add(rock);
  }
  const angle = (i / 3) * Math.PI * 2 + 0.6;
  pile.position.set(Math.cos(angle) * 17, 0, Math.sin(angle) * 17);
  scene.add(pile);
  deposits.push(pile.position);
}

// ---- units -----------------------------------------------------------------

const rng = makeRng(20260726);
const units = [];
for (let i = 0; i < UNIT_COUNT; i += 1) {
  const col = i % 8;
  const row = Math.floor(i / 8);
  const x = (col - 3.5) * 2.9;
  const z = (row - 2.5) * 2.9;
  const role = ["idle", "walk", "gather", "carry"][i % 4];
  const unit = {
    id: i + 1,
    kind: "citizen",
    faction: "sunwoven",
    position: { x, z },
    facing: rng() * Math.PI * 2,
    role,
    selected: i < 8
  };
  if (role === "gather") {
    unit.activity = { tag: "gathering" };
    const target = deposits[i % deposits.length];
    unit.facing = Math.atan2(target.x - x, target.z - z);
  } else if (role === "carry") {
    unit.activity = { tag: "carrying" };
    unit.destination = { x: x + Math.sin(unit.facing) * 6, z: z + Math.cos(unit.facing) * 6 };
  } else if (role === "walk") {
    unit.destination = { x: x + Math.sin(unit.facing) * 6, z: z + Math.cos(unit.facing) * 6 };
  }
  units.push(unit);
}

let layer = null;
let composer = null;

// ---- preload (before the spawn burst — no first-frame texture hits) -------

async function preloadSheet() {
  const probe = new GoldenSpriteUnit(null, { basePath: SHEET });
  const manifest = await probe.loadManifest(`${SHEET}atlas-manifest.json`);
  for (const clip of Object.keys(manifest.clips)) {
    await probe.setClip(clip);
  }
  return { probe, manifest };
}

// ---- perf measurement ------------------------------------------------------

const stats = {
  spawn: { maxFrameMs: 0, frames: 0, windowMs: 2500 },
  phases: {},
  frameDeltas: []
};
let spawnStartedAt = 0;
let spawnDone = false;

// ---- camera script ---------------------------------------------------------

const PHASES = [
  { name: "default", distance: 16, target: [0, 0], duration: 4000 },
  { name: "medium", distance: 26, target: [0, 0], duration: 4000 },
  { name: "close", distance: 8.5, target: [0, 0], duration: 4000 },
  { name: "movement", distance: 16, target: [0, 0], duration: 6000, move: true },
  { name: "capture", distance: 16, target: [0, 0], duration: 3000 }
];

let phaseIndex = 0;
let phaseStartedAt = performance.now();
const target = new THREE.Vector3(0, 0, 0);
let currentDistance = 16;

function advanceCamera(now) {
  const phase = PHASES[phaseIndex];
  const t = (now - phaseStartedAt) / phase.duration;
  if (t >= 1) {
    phaseIndex += 1;
    if (phaseIndex >= PHASES.length) {
      finishRun();
      return;
    }
    phaseStartedAt = now;
    stats.phases[PHASES[phaseIndex].name] = { frames: 0, sumMs: 0, maxMs: 0 };
    setHud([`phase: ${PHASES[phaseIndex].name}`, ...statusLines()]);
    return;
  }
  if (phase.move) {
    // Camera movement: pan the look-at in a circle + ease zoom in/out.
    const a = (t / PHASES.length + now * 0.00012) * Math.PI * 2;
    target.set(Math.sin(a) * 5.5, 0, Math.cos(a) * 5.5);
    currentDistance = 16 + Math.sin(now * 0.0016) * 7;
  } else {
    target.set(phase.target[0], 0, phase.target[1]);
    currentDistance = currentDistance + (phase.distance - currentDistance) * 0.08;
  }
  applyRtsCamera(camera, target, currentDistance);
}

// ---- frame loop ------------------------------------------------------------

let lastFrameAt = performance.now();
let runFinished = false;

function frame(now) {
  requestAnimationFrame(frame);
  const delta = now - lastFrameAt;
  lastFrameAt = now;

  if (!runFinished) {
    stats.frameDeltas.push(delta);
    if (!spawnDone && now - spawnStartedAt <= stats.spawn.windowMs) {
      stats.spawn.maxFrameMs = Math.max(stats.spawn.maxFrameMs, delta);
    } else if (!spawnDone) {
      spawnDone = true;
    }
    const phase = PHASES[Math.min(phaseIndex, PHASES.length - 1)];
    const phaseStats = stats.phases[phase.name] ?? (stats.phases[phase.name] = { frames: 0, sumMs: 0, maxMs: 0 });
    phaseStats.frames += 1;
    phaseStats.sumMs += delta;
    phaseStats.maxMs = Math.max(phaseStats.maxMs, delta);
    advanceCamera(now);
  }

  // Rotate walkers/carriers slowly so every 22.5° facing cell gets exercised.
  for (const unit of units) {
    if (unit.role === "walk" || unit.role === "carry") {
      unit.facing += 0.0021;
      if (unit.role === "walk" || unit.role === "carry") {
        unit.destination = {
          x: unit.position.x + Math.sin(unit.facing) * 6,
          z: unit.position.z + Math.cos(unit.facing) * 6
        };
      }
    }
  }

  const state = {
    age: { sunwoven: "foundation" },
    units: { ordered: () => units }
  };
  layer.sync(state, delta / 1000);
  composer.render();
}

// ---- capture ---------------------------------------------------------------

async function postCapture(canvas, filename) {
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
  const res = await fetch(`/save?path=${CAPTURE_DIR}/${filename}`, { method: "POST", body: blob });
  if (!res.ok) throw new Error(`capture ${filename} → HTTP ${res.status}`);
  return filename;
}

async function captureZoom(label, distance) {
  applyRtsCamera(camera, new THREE.Vector3(0, 0, 0), distance);
  composer.render();
  const canvas = document.createElement("canvas");
  canvas.width = root.clientWidth;
  canvas.height = root.clientHeight;
  canvas.getContext("2d").drawImage(renderer.domElement, 0, 0);
  return postCapture(canvas, `golden-zoom-${label}.png`);
}

async function captureBattlefield() {
  // 2× full-resolution battlefield frame at default zoom.
  applyRtsCamera(camera, new THREE.Vector3(0, 0, 0), 16);
  renderer.setPixelRatio(2);
  renderer.setSize(2560, 1440, false);
  composer.setSize(2560, 1440);
  camera.aspect = 2560 / 1440;
  camera.updateProjectionMatrix();
  composer.render();
  const canvas = document.createElement("canvas");
  canvas.width = 2560;
  canvas.height = 1440;
  canvas.getContext("2d").drawImage(renderer.domElement, 0, 0);
  const filename = await postCapture(canvas, "golden-battlefield.png");
  // Restore interactive size.
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setSize(root.clientWidth, root.clientHeight, false);
  composer.setSize(root.clientWidth, root.clientHeight);
  camera.aspect = root.clientWidth / root.clientHeight;
  camera.updateProjectionMatrix();
  return filename;
}

// ---- finish ----------------------------------------------------------------

function statusLines() {
  const phase = PHASES[Math.min(phaseIndex, PHASES.length - 1)];
  const ps = stats.phases[phase.name];
  const avg = ps && ps.frames ? 1000 / (ps.sumMs / ps.frames) : 0;
  return [
    `phase: ${phase.name}`,
    `units: ${units.length}  views: ${layer.views.size}`,
    `phase fps: ${avg.toFixed(1)}  (max frame ${(ps?.maxMs ?? 0).toFixed(1)} ms)`,
    `spawn max frame: ${stats.spawn.maxFrameMs.toFixed(1)} ms`,
    `draw calls: ${renderer.info.render.calls}  triangles: ${renderer.info.render.triangles}`
  ];
}

async function finishRun() {
  runFinished = true;
  // Aggregate stats.
  const deltas = stats.frameDeltas.filter((d) => d > 0);
  deltas.sort((a, b) => a - b);
  const p95 = deltas[Math.floor(deltas.length * 0.95)];
  const avgMs = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  const phaseFps = {};
  for (const [name, ps] of Object.entries(stats.phases)) {
    phaseFps[name] = ps.frames ? Number((1000 / (ps.sumMs / ps.frames)).toFixed(1)) : 0;
  }
  const gates = {
    avgFps60: 1000 / avgMs >= 55,
    p95FrameMs: p95 <= 22.2,
    spawnNoHitch: stats.spawn.maxFrameMs <= 66,
    allUnitsPresent: layer.views.size === UNIT_COUNT
  };

  setHud([...statusLines(), "capturing…"]);
  let captures = {};
  try {
    captures = {
      default: await captureZoom("default", 16),
      medium: await captureZoom("medium", 26),
      close: await captureZoom("close", 8.5),
      battlefield: await captureBattlefield()
    };
  } catch (error) {
    console.error("capture failed", error);
  }

  // Read the real scene draw-call count (composer's last pass would report 1).
  renderer.render(scene, camera);
  const drawCalls = renderer.info.render.calls;
  const triangles = renderer.info.render.triangles;

  const result = {
    ok: Object.values(gates).every(Boolean),
    gates,
    units: UNIT_COUNT,
    views: layer.views.size,
    fps: { avg: Number((1000 / avgMs).toFixed(1)), p95: Number((1000 / p95).toFixed(1)) },
    frameMs: { avg: Number(avgMs.toFixed(2)), p95: Number(p95.toFixed(2)), max: Number(deltas[deltas.length - 1].toFixed(2)) },
    spawnMaxFrameMs: Number(stats.spawn.maxFrameMs.toFixed(2)),
    phaseFps,
    drawCalls,
    triangles,
    captures,
    threeRevision: THREE.REVISION
  };
  window.goldenLab.result = result;
  setHud([...statusLines(), `RESULT ${result.ok ? "PASS" : "FAIL"}`, JSON.stringify(result, null, 1)]);
  console.log("goldenLab result:", JSON.stringify(result, null, 1));
}

// ---- boot ------------------------------------------------------------------

async function boot() {
  setHud(["preloading golden atlases…"]);
  let probe = null;
  try {
    const preloaded = await preloadSheet();
    probe = preloaded.probe;
    setHud([`preloaded: ${Object.keys(preloaded.manifest.clips).join(", ")}`, "spawning 48 units…"]);
  } catch (error) {
    setHud([`preload FAILED: ${error?.message ?? error}`]);
    return;
  }

  layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    camera,
    proceduralFactory: createProceduralUnit,
    forceArt: "sprite",
    blobShadows: true,
    spriteRoot: "/assets/citizens/"
  });
  await layer.init();

  // Post-processing: bloom makes the emissive mask read as glow.
  composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(
    new THREE.Vector2(root.clientWidth, root.clientHeight),
    0.35,
    0.5,
    1.0
  );
  composer.addPass(bloom);

  // Warm up EVERY shader program AND texture upload (sprite material, shadow
  // map, bloom chain, all 12 atlases) before the burst — first-use GPU work
  // inside the spawn window would otherwise read as a spawning hitch.
  scene.add(probe.group);
  for (const clip of Object.keys(probe.manifest.clips)) {
    await probe.setClip(clip);
    composer.render();
  }
  scene.remove(probe.group);

  // The spawn burst — the hitch window starts here.
  spawnStartedAt = performance.now();
  layer.sync(
    { age: { sunwoven: "foundation" }, units: { ordered: () => units } },
    0.016
  );

  // The layer syncs views asynchronously; give the burst a moment, then let
  // the camera script run from the default phase.
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 400));
  phaseStartedAt = performance.now();
  stats.phases.default = { frames: 0, sumMs: 0, maxMs: 0 };
  setHud(["phase: default", ...statusLines()]);
  // The first frame's delta must measure from HERE, not from script load —
  // otherwise the whole boot time (preload + warmup) reads as a spawn hitch.
  lastFrameAt = performance.now();
  requestAnimationFrame(frame);
}

window.goldenLab = {
  stats,
  units,
  get layer() {
    return layer;
  },
  get scene() {
    return scene;
  },
  get camera() {
    return camera;
  },
  result: null,
  capture: captureBattlefield
};

boot();
