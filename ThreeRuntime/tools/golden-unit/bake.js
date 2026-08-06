// Golden Sunwoven Foundation Citizen — 16-direction sprite bake.
//
// Renders the shipped villager GLB (assets/units/citizen_villager.glb) from
// the locked RTS camera (pitch 57°, yaw 45°, orthographic framing) at 16 unit
// yaws × AoE2-timed clip frames, producing three channel atlases per clip:
//
//   albedo   — flat base colours (unlit; lighting happens at runtime)
//   normal   — WORLD-space normals (packNormalToRGB), for runtime key light
//   emissive — emissiveFactor × KHR emissiveStrength, clamped, for glow/bloom
//
// Clips: idle (4 @ 3 fps), walk (4 @ 10 fps), gather (6 @ 5 fps), carry
// (walk with an authored resource pack on hand_R, 4 @ 10 fps). Gather gets an
// authored sickle on hand_R. All frames sampled from the 30 fps GLB actions.
//
// Outputs (POSTed to the serving node):
//   sprites/sunwoven-golden/<clip>-<channel>.png   (16 cols × frames rows, 160 px cells)
//   sprites/sunwoven-golden/atlas-manifest.json

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { clone as cloneSkeleton } from "three/addons/utils/SkeletonUtils.js";

const CELL = 160;
const DIRECTIONS = 16;
const GLB_FPS = 30;
const GLB_URL = "/assets/units/citizen_villager.glb";
const OUT = "/assets/citizens/sprites/sunwoven-golden";
const PITCH_DEG = 57;
const YAW_DEG = 45;
const FACINGS_16 = [
  "S", "SSE", "SE", "ESE", "E", "ENE", "NE", "NNE",
  "N", "NNW", "NW", "WNW", "W", "WSW", "SW", "SSW"
];

// AoE2-timed sampling from the villager GLB actions (30 fps).
const CLIPS = [
  { name: "idle",   action: "idle", frames: [0, 30, 60, 90], fps: 3, loop: true },
  { name: "walk",   action: "walk", frames: [0, 9, 18, 27], fps: 10, loop: true },
  { name: "gather", action: "gather_loop", frames: [0, 10, 20, 30, 40, 50], fps: 5, loop: true, prop: "sickle" },
  { name: "carry",  action: "walk", frames: [0, 9, 18, 27], fps: 10, loop: true, prop: "pack" }
];

const statusEl = () => document.getElementById("status");
const log = (line) => {
  statusEl().textContent += `${line}\n`;
  console.log(line);
};

function el(id) {
  return document.getElementById(id);
}

// ---- authored props --------------------------------------------------------

function buildSickle() {
  const group = new THREE.Group();
  const grip = new THREE.Mesh(
    new THREE.CylinderGeometry(0.018, 0.02, 0.16, 8),
    new THREE.MeshStandardMaterial({ color: 0x6e4a2f, roughness: 0.7 })
  );
  grip.rotation.z = Math.PI / 2;
  const blade = new THREE.Mesh(
    new THREE.TorusGeometry(0.085, 0.014, 6, 22, Math.PI * 1.15),
    new THREE.MeshStandardMaterial({ color: 0xdfc89a, metalness: 0.55, roughness: 0.35 })
  );
  blade.position.set(0.1, 0, 0);
  const tip = new THREE.Mesh(
    new THREE.ConeGeometry(0.018, 0.07, 8),
    new THREE.MeshStandardMaterial({ color: 0xdfc89a, metalness: 0.55, roughness: 0.35 })
  );
  tip.position.set(0.185, 0.015, 0);
  tip.rotation.z = -Math.PI / 2;
  group.add(grip, blade, tip);
  return group;
}

function buildPack() {
  const group = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.26, 0.18, 0.18),
    new THREE.MeshStandardMaterial({ color: 0x8a6a44, roughness: 0.85 })
  );
  const strapA = new THREE.Mesh(
    new THREE.BoxGeometry(0.27, 0.03, 0.03),
    new THREE.MeshStandardMaterial({ color: 0xdea84f, metalness: 0.4, roughness: 0.4 })
  );
  strapA.position.y = 0.05;
  const strapB = strapA.clone();
  strapB.position.y = -0.05;
  strapB.rotation.z = Math.PI / 2;
  strapB.scale.set(1, 1, 1);
  const knot = new THREE.Mesh(
    new THREE.SphereGeometry(0.035, 8, 6),
    new THREE.MeshStandardMaterial({ color: 0xdea84f, metalness: 0.4, roughness: 0.4 })
  );
  knot.position.set(0, 0, -0.1);
  group.add(body, strapA, strapB, knot);
  return group;
}

// ---- bake state ------------------------------------------------------------

const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: true });
renderer.setPixelRatio(1);
renderer.setSize(CELL, CELL);
renderer.setClearColor(0x000000, 0);
const rt = new THREE.WebGLRenderTarget(CELL, CELL, {
  format: THREE.RGBAFormat,
  type: THREE.UnsignedByteType,
  colorSpace: THREE.LinearSRGBColorSpace
});
const pixels = new Uint8Array(CELL * CELL * 4);

const scene = new THREE.Scene();
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);

let gltf = null;
let frameWorldHeight = 3.0;
let figureHeight = 1.7;
let centerY = 0.85;
let anchorY = 0.2;

const atlasCanvases = new Map(); // `${clip}-${channel}` → canvas

function setCamera(targetY) {
  const half = frameWorldHeight / 2;
  camera.left = -half;
  camera.right = half;
  camera.top = half;
  camera.bottom = -half;
  camera.updateProjectionMatrix();
  const pitch = THREE.MathUtils.degToRad(PITCH_DEG);
  const yaw = THREE.MathUtils.degToRad(YAW_DEG);
  const dist = 30;
  const offset = new THREE.Vector3(
    dist * Math.cos(pitch) * Math.sin(yaw),
    dist * Math.sin(pitch),
    dist * Math.cos(pitch) * Math.cos(yaw)
  );
  const target = new THREE.Vector3(0, targetY, 0);
  camera.position.copy(target).add(offset);
  camera.lookAt(target);
}

function renderPass(instance, channel) {
  if (channel === "albedo") renderer.outputColorSpace = THREE.SRGBColorSpace;
  else renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
  renderer.setRenderTarget(rt);
  renderer.clear(true, true, true);
  renderer.render(scene, camera);
  renderer.readRenderTargetPixels(rt, 0, 0, CELL, CELL, pixels);
  renderer.setRenderTarget(null);
  return pixels;
}

function drawCell(channelKey, d, frameIndex) {
  let canvas = atlasCanvases.get(channelKey);
  if (!canvas) {
    const def = CLIPS.find((c) => channelKey.startsWith(c.name));
    canvas = document.createElement("canvas");
    canvas.width = DIRECTIONS * CELL;
    canvas.height = def.frames.length * CELL;
    atlasCanvases.set(channelKey, canvas);
  }
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(CELL, CELL);
  img.data.set(pixels);
  ctx.putImageData(img, d * CELL, frameIndex * CELL);
}

// ---- pass materials --------------------------------------------------------

const normalPassMaterial = new THREE.MeshNormalMaterial();
normalPassMaterial.side = THREE.DoubleSide;
normalPassMaterial.onBeforeCompile = (shader) => {
  // Declare the varying at global scope, alongside the built-in vNormal.
  shader.vertexShader = shader.vertexShader
    .replace(
      "#include <normal_pars_vertex>",
      "#include <normal_pars_vertex>\nvarying vec3 vWorldNormal;"
    )
    .replace(
      "#include <skinnormal_vertex>",
      `#include <skinnormal_vertex>
\tvWorldNormal = normalize( mat3( modelMatrix ) * objectNormal );`
    );
  shader.fragmentShader = shader.fragmentShader
    .replace(
      "#include <normal_pars_fragment>",
      "#include <normal_pars_fragment>\nvarying vec3 vWorldNormal;"
    )
    .replace("#include <normal_fragment_begin>", "vec3 normal = normalize( vWorldNormal );")
    .replace("#include <normal_fragment_maps>", "");
};

function materialForPass(original, channel) {
  if (channel === "normal") return normalPassMaterial;
  if (channel === "albedo") {
    const m = new THREE.MeshBasicMaterial({
      color: original.color ? original.color.clone() : 0xffffff,
      vertexColors: Boolean(original.vertexColors),
      side: THREE.DoubleSide
    });
    m.name = `albedo-${original.name}`;
    return m;
  }
  // emissive mask: factor × strength, clamped to 1
  const strength =
    original.extensions?.KHR_materials_emissive_strength?.emissiveStrength ?? 1;
  const e = original.emissive ? original.emissive.clone() : new THREE.Color(0, 0, 0);
  e.multiplyScalar(Math.max(0.001, strength));
  const clamped = new THREE.Color(
    Math.min(1, Math.max(0, e.r)),
    Math.min(1, Math.max(0, e.g)),
    Math.min(1, Math.max(0, e.b))
  );
  const m = new THREE.MeshBasicMaterial({ color: clamped, side: THREE.DoubleSide });
  m.name = `emissive-${original.name}`;
  return m;
}

/** Snapshot the GLB's own materials so every pass bakes from the same source. */
function snapshotMaterials(root) {
  const snapshot = new Map();
  root.traverse((o) => {
    if (!o.isMesh) {
      snapshot.set(o, null);
      return;
    }
    const mats = Array.isArray(o.material) ? o.material : [o.material];
    snapshot.set(o, mats.map((m) => ({ original: m, source: o })));
  });
  return snapshot;
}

function applyPassMaterials(snapshot, channel) {
  for (const [object, entry] of snapshot) {
    if (!entry) continue;
    const assigned = entry.map(({ original }) => materialForPass(original, channel));
    // Single-element arrays draw nothing when geometry has no groups — keep
    // a bare material for the common one-material-per-mesh case.
    object.material = assigned.length === 1 ? assigned[0] : assigned;
  }
}

// ---- pose + measure --------------------------------------------------------

function makeMixer(instance, def) {
  const clip = THREE.AnimationClip.findByName(gltf.animations, def.action);
  const mixer = new THREE.AnimationMixer(instance);
  const action = mixer.clipAction(clip);
  // The action must be playing for mixer.update() to apply the clip — a
  // paused action ignores _update even when .time is set.
  action.play();
  action.time = 0;
  mixer.update(0);
  return { mixer, action };
}

function poseInstance(instance, def, frame, pose) {
  pose.action.time = frame / GLB_FPS;
  pose.mixer.update(0);
  instance.updateMatrixWorld(true);
}

function attachProp(instance, def) {
  if (!def.prop) return;
  let hand = null;
  instance.traverse((o) => {
    if (o.isBone && o.name === "hand_R") hand = o;
  });
  if (!hand) return;
  const prop = def.prop === "pack" ? buildPack() : buildSickle();
  prop.name = `prop-${def.prop}`;
  if (def.prop === "pack") prop.position.set(0.02, -0.04, 0.06);
  else prop.position.set(0.03, -0.05, 0.02);
  hand.add(prop);
}

function measure() {
  const instance = cloneSkeleton(gltf.scene);
  scene.add(instance);
  let minY = Infinity;
  let maxY = -Infinity;
  let maxXZ = 0;
  for (const def of CLIPS) {
    const pose = makeMixer(instance, def);
    for (const frame of def.frames) {
      poseInstance(instance, def, frame, pose);
      const box = new THREE.Box3().setFromObject(instance);
      minY = Math.min(minY, box.min.y);
      maxY = Math.max(maxY, box.max.y);
      maxXZ = Math.max(maxXZ, Math.max(box.max.x - box.min.x, box.max.z - box.min.z));
    }
  }
  scene.remove(instance);
  figureHeight = maxY - minY;
  // Frame must clear the tallest pose with padding, and fit the stride width.
  frameWorldHeight = Math.max(maxY * 1.4 + 0.2, maxXZ * 1.55, 2.6);
  centerY = (minY + maxY) / 2;
  anchorY = (centerY + frameWorldHeight / 2) / frameWorldHeight;
  log(`measure: figure ${figureHeight.toFixed(3)} m, stride ${maxXZ.toFixed(3)} m → frame ${frameWorldHeight.toFixed(3)} m, anchor.y ${anchorY.toFixed(4)}`);
}

// ---- bake ------------------------------------------------------------------

async function bakeClip(def) {
  log(`baking ${def.name} (${def.frames.length} frames × ${DIRECTIONS} dirs)`);
  const instance = cloneSkeleton(gltf.scene);
  scene.add(instance);
  attachProp(instance, def);
  const snapshot = snapshotMaterials(instance);
  const pose = makeMixer(instance, def);
  setCamera(centerY);
  for (let f = 0; f < def.frames.length; f += 1) {
    poseInstance(instance, def, def.frames[f], pose);
    for (let d = 0; d < DIRECTIONS; d += 1) {
      instance.rotation.y = (d * Math.PI * 2) / DIRECTIONS;
      instance.updateMatrixWorld(true);
      for (const channel of ["albedo", "normal", "emissive"]) {
        applyPassMaterials(snapshot, channel);
        renderPass(instance, channel);
        drawCell(`${def.name}-${channel}`, d, f);
      }
    }
    log(`  frame ${f + 1}/${def.frames.length} done`);
  }
  scene.remove(instance);
}

async function postPng(channelKey, def) {
  const canvas = atlasCanvases.get(channelKey);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
  const filename = `${def.name}-${channelKey.split("-").pop()}.png`;
  const res = await fetch(`/save?path=${OUT}/${filename}`, { method: "POST", body: blob });
  if (!res.ok) throw new Error(`save ${filename} → HTTP ${res.status}`);
  return filename;
}

async function postManifest() {
  const clips = {};
  let originRow = 0;
  for (const def of CLIPS) {
    clips[def.name] = {
      frames: def.frames.length,
      fps: def.fps,
      loop: def.loop,
      originRow,
      channels: {
        albedo: `${def.name}-albedo.png`,
        normal: `${def.name}-normal.png`,
        emissive: `${def.name}-emissive.png`
      }
    };
    originRow += def.frames.length;
  }
  const manifest = {
    schema: "sunfold.sprite-manifest/2",
    unit: "sunwoven-golden",
    playback: "atlas16",
    frameWidth: CELL,
    frameHeight: CELL,
    fps: 10,
    mirrorAtRuntime: false,
    directionColumns: DIRECTIONS,
    anchor: { x: 0.5, y: Number(anchorY.toFixed(4)) },
    unitHeightMeters: Number(figureHeight.toFixed(3)),
    worldHeight: Number(frameWorldHeight.toFixed(3)),
    facings: FACINGS_16,
    camera: { pitchDegrees: PITCH_DEG, yawDegrees: YAW_DEG, fovDegrees: 38 },
    clips,
    provenance: {
      method: "GLB bake — Three.js WebGLRenderer, orthographic at locked RTS angles",
      glb: "assets/units/citizen_villager.glb",
      glbFps: GLB_FPS,
      sampledFrames: Object.fromEntries(CLIPS.map((c) => [c.name, c.frames])),
      directions: DIRECTIONS,
      normalSpace: "world",
      emissiveMask: "emissiveFactor × KHR_materials_emissive_strength, clamped to 1",
      carryProp: "authored resource pack on hand_R (walk frames)",
      gatherProp: "authored sickle on hand_R",
      honest: "Directional cells render the unit rotated to each of 16 yaws under the locked camera; runtime picks cell = round(worldYaw / 22.5°)."
    }
  };
  const res = await fetch(`/save?path=${OUT}/atlas-manifest.json`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(manifest, null, 2)
  });
  if (!res.ok) throw new Error(`save manifest → HTTP ${res.status}`);
  return manifest;
}

// Diagnostic: render the raw clone with its ORIGINAL materials + a light.
window.probe = () => {
  const instance = cloneSkeleton(gltf.scene);
  scene.add(instance);
  const light = new THREE.DirectionalLight(0xffffff, 2);
  light.position.set(5, 10, 5);
  scene.add(light);
  setCamera(0.85);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setRenderTarget(rt);
  renderer.clear(true, true, true);
  renderer.render(scene, camera);
  renderer.readRenderTargetPixels(rt, 0, 0, CELL, CELL, pixels);
  renderer.setRenderTarget(null);
  scene.remove(instance);
  scene.remove(light);
  let covered = 0;
  for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 3] > 8) covered += 1;
  let skinned = 0;
  let visibleMeshes = 0;
  let totalMeshes = 0;
  instance.traverse((o) => {
    if (o.isSkinnedMesh) skinned += 1;
    if (o.isMesh) {
      totalMeshes += 1;
      if (o.visible) visibleMeshes += 1;
    }
  });
  const result = {
    covered,
    fraction: Number((covered / (CELL * CELL)).toFixed(4)),
    skinned,
    totalMeshes,
    visibleMeshes,
    triangles: renderer.info.render.triangles,
    calls: renderer.info.render.calls,
    geometryBounds: (() => {
      const box = new THREE.Box3().setFromObject(instance);
      return box.min.toArray().map((v) => v.toFixed(2)).join(",") + " → " + box.max.toArray().map((v) => v.toFixed(2)).join(",");
    })()
  };
  console.log("probe:", JSON.stringify(result));
  window.__probeResult = result;
  return result;
};

// Diagnostic: render each pass material set and report what actually drew.
window.probeChannel = (channel) => {
  const instance = cloneSkeleton(gltf.scene);
  scene.add(instance);
  const snapshot = snapshotMaterials(instance);
  applyPassMaterials(snapshot, channel);
  setCamera(0.85);
  renderer.outputColorSpace =
    channel === "albedo" ? THREE.SRGBColorSpace : THREE.LinearSRGBColorSpace;
  renderer.setRenderTarget(rt);
  renderer.clear(true, true, true);
  renderer.render(scene, camera);
  renderer.readRenderTargetPixels(rt, 0, 0, CELL, CELL, pixels);
  renderer.setRenderTarget(null);
  scene.remove(instance);
  let covered = 0;
  for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 3] > 8) covered += 1;
  const result = {
    channel,
    covered,
    fraction: Number((covered / (CELL * CELL)).toFixed(4)),
    triangles: renderer.info.render.triangles,
    calls: renderer.info.render.calls,
    firstMaterial: (() => {
      let out = null;
      instance.traverse((o) => {
        if (!out && o.isMesh) {
          const m = Array.isArray(o.material) ? o.material[0] : o.material;
          out = { type: m?.type, name: m?.name, side: m?.side };
        }
      });
      return out;
    })()
  };
  console.log("probeChannel:", JSON.stringify(result));
  return result;
};

async function run() {
  log("loading GLB…");
  gltf = await new Promise((resolve, reject) => {
    new GLTFLoader().load(GLB_URL, resolve, undefined, reject);
  });
  log(`GLB loaded: ${gltf.animations.length} animations`);
  measure();
  for (const def of CLIPS) {
    await bakeClip(def);
  }
  for (const def of CLIPS) {
    for (const channel of ["albedo", "normal", "emissive"]) {
      const filename = await postPng(`${def.name}-${channel}`, def);
      log(`saved ${filename}`);
    }
  }
  const manifest = await postManifest();
  log(`saved atlas-manifest.json (${Object.keys(manifest.clips).length} clips)`);

  // Preview strip
  const strip = el("atlas");
  for (const def of CLIPS) {
    const img = document.createElement("img");
    img.src = atlasCanvases.get(`${def.name}-albedo`).toDataURL();
    img.title = `${def.name} albedo`;
    strip.appendChild(img);
  }
  window.bakeResult = { ok: true, clips: CLIPS.map((c) => c.name), manifest };
  log("BAKE COMPLETE — ok");
}

run().catch((error) => {
  console.error(error);
  log(`BAKE FAILED: ${error?.message ?? error}`);
  window.bakeResult = { ok: false, error: String(error?.message ?? error) };
});
