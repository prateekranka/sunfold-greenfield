// Milestone 1 — AoE-style RTS proof: sprite Citizens on a Sunwoven biome.
// Mix: 16 walk · 8 carry · 4 gather · 4 build (32 total) — opt-in via Start activities.
// Default: all 32 stay idle standing (gather-f0 hold, playbackSpeed 0).
// Serve assets/citizens and open citizen-rts-proof.html

import * as THREE from "three";
import { SpriteUnit } from "./sprites/sprite-unit.js";
import { createRtsCamera, RtsCameraController, RTS_CAMERA } from "./rts-camera.js";
import { FACINGS_16 } from "./sprites/facing.js";
import manifest from "../assets/citizens/sprites/village-manbun-wanderer/atlas-manifest.json";
// Atlas PNG is served beside this page (not dataurl-embedded) so the 16k sheet
// stays a single GPU upload instead of a 22MB JS string.

const root = document.getElementById("proof-root");
const status = document.getElementById("status");
const fpsEl = document.getElementById("fps");

const CLIP_PLAN = [
  ...Array(16).fill("walk"),
  ...Array(8).fill("carry"),
  ...Array(4).fill("gather"),
  ...Array(4).fill("build")
];

// Proof page: pixelRatio 1 + no MSAA — fill-rate win on Retina laptops.
// preserveDrawingBuffer off — measurable FPS win; Argent CDP screenshot still works.
const renderer = new THREE.WebGLRenderer({
  antialias: false,
  alpha: false,
  powerPreference: "high-performance"
});
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(1);
root.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x87a878);
scene.fog = new THREE.Fog(0x9bb88a, 42, 95);

const camera = createRtsCamera(1);
const camCtrl = new RtsCameraController(camera, renderer.domElement, {
  panRadius: 38,
  zoomSmooth: 18,
  panSmooth: 20
});

/** Minimap world half-extent (metres). Matches gameplay ring + a little margin. */
const MINIMAP_HALF = 18;
const CLIP_BLIP = {
  walk: "#7ec8ff",
  carry: "#e2b866",
  gather: "#6fd67a",
  build: "#d48a5a",
  idle: "#c8d4a8"
};
/** Throttle minimap canvas redraws (full 2D path is costly every frame). */
const MINIMAP_INTERVAL = 1 / 12;

function resize() {
  const w = Math.max(1, root.clientWidth);
  const h = Math.max(1, root.clientHeight);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
resize();
window.addEventListener("resize", resize);

scene.add(new THREE.HemisphereLight(0xfff0d0, 0x3a5a32, 1.15));
const key = new THREE.DirectionalLight(0xffe2a8, 1.85);
key.position.set(-8, 18, 6);
scene.add(key);
const fill = new THREE.DirectionalLight(0xa8c8ff, 0.35);
fill.position.set(6, 8, -4);
scene.add(fill);

/** Soft blob shadow material (shared). */
function makeBlobShadowMat() {
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 64;
  const ctx = canvas.getContext("2d");
  const g = ctx.createRadialGradient(32, 32, 4, 32, 32, 30);
  g.addColorStop(0, "rgba(0,0,0,0.5)");
  g.addColorStop(0.7, "rgba(0,0,0,0.22)");
  g.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  const tex = new THREE.CanvasTexture(canvas);
  return new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false });
}
const blobMat = makeBlobShadowMat();
const selectionMat = new THREE.MeshBasicMaterial({
  color: 0x7dff7d,
  transparent: true,
  opacity: 0.55,
  depthWrite: false
});

function addBlobShadow(parent, radius = 0.85) {
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(radius * 2, radius * 2), blobMat);
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.012;
  mesh.name = "blob-shadow";
  parent.add(mesh);
  return mesh;
}

function addSelectionRing(parent, radius = 1.05) {
  const ring = new THREE.Mesh(new THREE.RingGeometry(radius * 0.72, radius, 40), selectionMat);
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.02;
  ring.name = "selection-ring";
  ring.visible = false;
  parent.add(ring);
  return ring;
}

function addHealthBar(parent, hpRatio = 1) {
  const group = new THREE.Group();
  group.name = "health-bar";
  group.position.y = 2.55;
  const width = 1.05;
  const bg = new THREE.Mesh(
    new THREE.PlaneGeometry(width, 0.11),
    new THREE.MeshBasicMaterial({ color: 0x1a1a1a, transparent: true, opacity: 0.72, depthWrite: false })
  );
  const fillMesh = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 0.96, 0.07),
    new THREE.MeshBasicMaterial({ color: 0x5ad46a, depthWrite: false })
  );
  fillMesh.name = "fill";
  fillMesh.position.z = 0.01;
  group.add(bg);
  group.add(fillMesh);
  parent.add(group);
  const r = Math.max(0.05, Math.min(1, hpRatio));
  fillMesh.scale.x = r;
  fillMesh.position.x = -((1 - r) * width * 0.96) / 2;
  return group;
}

// Unlit biome meshes — MeshStandard + many trees was a measurable fill tax.
const matBark = new THREE.MeshBasicMaterial({ color: 0x5a3a1e });
const matFoliage = new THREE.MeshBasicMaterial({ color: 0x2f6b2c });
const matWall = new THREE.MeshBasicMaterial({ color: 0xd8c4a0 });
const matRoof = new THREE.MeshBasicMaterial({ color: 0x8b4a2e });
const matDoor = new THREE.MeshBasicMaterial({ color: 0x5a3a22 });
const matPlaza = new THREE.MeshBasicMaterial({ color: 0xc4b48a });
const matSpire = new THREE.MeshBasicMaterial({ color: 0xc29b5d });
const matBase = new THREE.MeshBasicMaterial({ color: 0xa89068 });
const matGround = new THREE.MeshBasicMaterial({ color: 0x5a8f4a });
const patchMat = new THREE.MeshBasicMaterial({ color: 0x6aa055 });

function makeTree(x, z, scale = 1) {
  const g = new THREE.Group();
  const trunk = new THREE.Mesh(
    new THREE.CylinderGeometry(0.22 * scale, 0.32 * scale, 1.8 * scale, 6),
    matBark
  );
  trunk.position.y = 0.9 * scale;
  const canopy = new THREE.Mesh(new THREE.IcosahedronGeometry(1.35 * scale, 0), matFoliage);
  canopy.position.y = 2.35 * scale;
  canopy.scale.set(1, 0.95, 1);
  const canopy2 = new THREE.Mesh(new THREE.IcosahedronGeometry(0.95 * scale, 0), matFoliage);
  canopy2.position.set(0.35 * scale, 2.85 * scale, -0.2 * scale);
  g.add(trunk, canopy, canopy2);
  g.position.set(x, 0, z);
  return g;
}

function makeHouse(x, z, yaw = 0) {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new THREE.BoxGeometry(3.2, 1.8, 2.6), matWall);
  body.position.y = 0.9;
  const roof = new THREE.Mesh(new THREE.ConeGeometry(2.4, 1.2, 4), matRoof);
  roof.position.y = 2.35;
  roof.rotation.y = Math.PI / 4;
  const door = new THREE.Mesh(new THREE.BoxGeometry(0.55, 1.1, 0.08), matDoor);
  door.position.set(0, 0.55, 1.32);
  g.add(body, roof, door);
  g.position.set(x, 0, z);
  g.rotation.y = yaw;
  return g;
}

function makeTownCenter() {
  const g = new THREE.Group();
  const plaza = new THREE.Mesh(new THREE.CircleGeometry(4.2, 48), matPlaza);
  plaza.rotation.x = -Math.PI / 2;
  plaza.position.y = 0.02;
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(3.4, 0.06, 8, 48),
    new THREE.MeshBasicMaterial({ color: 0xe2b866, transparent: true, opacity: 0.8 })
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.04;
  const spire = new THREE.Mesh(new THREE.ConeGeometry(0.85, 2.4, 6), matSpire);
  spire.position.y = 1.2;
  const base = new THREE.Mesh(new THREE.CylinderGeometry(1.35, 1.55, 0.45, 8), matBase);
  base.position.y = 0.22;
  g.add(plaza, ring, base, spire);
  return g;
}

// Grassy ground
const ground = new THREE.Mesh(new THREE.CircleGeometry(55, 72), matGround);
ground.rotation.x = -Math.PI / 2;
scene.add(ground);

// Subtle grass patches (shared material + fewer segments)
for (let i = 0; i < 28; i += 1) {
  const a = (i / 28) * Math.PI * 2 + i * 0.37;
  const r = 8 + (i % 7) * 3.2;
  const patch = new THREE.Mesh(new THREE.CircleGeometry(1.6 + (i % 3) * 0.4, 10), patchMat);
  patch.rotation.x = -Math.PI / 2;
  patch.position.set(Math.cos(a) * r, 0.015, Math.sin(a) * r);
  scene.add(patch);
}

scene.add(makeTownCenter());

const housePositions = [
  [7.5, 5.5, -0.35],
  [-8.2, 4.0, 0.85],
  [5.5, -8.0, 0.25]
];
for (const [x, z, yaw] of housePositions) scene.add(makeHouse(x, z, yaw));

const trees = [];
// Ring of readable trees inside the gameplay frustum.
const treeSlots = [
  [12, 2], [11, 7], [8, 11], [3, 13], [-2, 12.5], [-7, 11], [-11, 7], [-12.5, 1],
  [-12, -4], [-10, -9], [-5, -12], [1, -13], [6, -11], [10, -8], [12.5, -3],
  [14, 5], [-14, 5], [9, -13], [-9, 13], [0, 15]
];
for (let i = 0; i < 20; i += 1) {
  const [x, z] = treeSlots[i];
  const t = makeTree(x, z, 1.05 + (i % 5) * 0.08);
  trees.push(t);
  scene.add(t);
}

const bundled = {
  ...manifest,
  atlas: {
    ...manifest.atlas,
    // Filename only — SpriteUnit resolves via basePath.
    image: "runtime-atlas.png"
  }
};

/**
 * @typedef {{
 *   unit: SpriteUnit,
 *   clip: string,
 *   selected: boolean,
 *   ring: THREE.Mesh,
 *   hpBar: THREE.Object3D,
 *   hp: number,
 *   maxHp: number,
 *   vel: THREE.Vector3,
 *   waypoint: THREE.Vector3 | null,
 *   home: THREE.Vector3,
 *   gatherTarget: THREE.Vector3 | null,
 *   activityStarted: boolean,
 *   workYaw: number,
 * }} ProofCitizen
 */

/** @type {ProofCitizen[]} */
const citizens = [];
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

/** Activities stay off until the user opts in (button / A key). */
let activitiesArmed = false;

function placeForClip(clip, indexInClip) {
  if (clip === "walk") {
    const a = (indexInClip / 16) * Math.PI * 2;
    const r = 6.5 + (indexInClip % 4) * 0.55;
    return new THREE.Vector3(Math.cos(a) * r, 0, Math.sin(a) * r);
  }
  if (clip === "carry") {
    const a = (indexInClip / 8) * Math.PI * 2 + 0.2;
    const r = 11 + (indexInClip % 2) * 1.2;
    return new THREE.Vector3(Math.cos(a) * r, 0, Math.sin(a) * r);
  }
  if (clip === "gather") {
    // Near outer trees
    const tree = trees[indexInClip % trees.length];
    const p = tree.position.clone();
    p.x += 1.4;
    p.z += 0.6;
    return p;
  }
  // build — near houses
  const [hx, hz] = housePositions[indexInClip % housePositions.length];
  return new THREE.Vector3(hx + 2.2, 0, hz + 1.4);
}

async function spawnCitizens() {
  // Warm the main runtime atlas + dedicated idle sheet once (shared GPU uploads).
  const warmer = new SpriteUnit(bundled, { basePath: "sprites/village-manbun-wanderer/" });
  await warmer.applyManifest(bundled);
  await warmer._loadAtlasTexture();
  await warmer.setState("idle");
  warmer.freezeStanding(0);
  const sharedAtlas = warmer._atlasTexture;
  if (!sharedAtlas) throw new Error("runtime-atlas.png failed to load");
  const sharedIdle = warmer._clipAtlasTextures.get("idle") || null;

  const counts = { walk: 0, carry: 0, gather: 0, build: 0 };
  for (let i = 0; i < CLIP_PLAN.length; i += 1) {
    const clip = CLIP_PLAN[i];
    const idx = counts[clip]++;
    const unit = new SpriteUnit(bundled, { basePath: "sprites/village-manbun-wanderer/" });
    // Per-unit UV on geometry — one shared Texture (no clone = no VRAM×32).
    unit.useSharedAtlas(sharedAtlas);
    if (sharedIdle) {
      unit.useSharedClipAtlas("idle", sharedIdle);
    }
    await unit.applyManifest(bundled);
    await unit.setState("idle");
    unit.freezeStanding(0);
    const home = placeForClip(clip, idx);
    unit.setPosition(home);
    // Face camera-ish / varied facings while standing still.
    unit.setFacing(i % FACINGS_16.length);

    const rootGroup = unit.group;
    const ring = addSelectionRing(rootGroup);
    addBlobShadow(rootGroup);
    const hp = 55 + ((i * 17) % 45);
    const hpBar = addHealthBar(rootGroup, hp / 100);
    scene.add(rootGroup);

    const workYaw =
      clip === "gather"
        ? Math.atan2(-1.2, -0.4)
        : clip === "build"
          ? Math.atan2(-0.5, 1.0)
          : unit.yaw;

    /** @type {ProofCitizen} */
    const entry = {
      unit,
      clip,
      selected: false,
      ring,
      hpBar,
      hp,
      maxHp: 100,
      // Velocity stays zero until activities start — no idle root-motion drift.
      vel: new THREE.Vector3(),
      waypoint: null,
      home: home.clone(),
      gatherTarget: clip === "gather" ? home.clone() : null,
      activityStarted: false,
      workYaw
    };

    unit.setYawImmediate(workYaw);
    citizens.push(entry);
  }
}

/** Transition idle → assigned clip (fire-and-forget; do not block the RAF loop). */
function startAssignedActivity(entry) {
  if (entry.activityStarted) return;
  entry.activityStarted = true;
  if (entry.clip === "walk" || entry.clip === "carry") {
    const a = Math.atan2(entry.home.z, entry.home.x) + Math.PI * 0.5;
    const speed = entry.clip === "carry" ? 1.35 : 2.1;
    entry.vel.set(Math.cos(a) * speed, 0, Math.sin(a) * speed);
    entry.workYaw = Math.atan2(entry.vel.x, entry.vel.z);
  }
  entry.unit.playbackSpeed = 1;
  entry.unit
    .setState(entry.clip)
    .then(() => {
      if (entry.clip === "walk" || entry.clip === "carry") {
        entry.unit.setYawImmediate(Math.atan2(entry.vel.x, entry.vel.z));
      } else {
        entry.unit.setYawImmediate(entry.workYaw);
      }
    })
    .catch(console.error);
}

function startAllActivities() {
  if (activitiesArmed) return;
  activitiesArmed = true;
  for (const c of citizens) startAssignedActivity(c);
  updateStatus();
  const btn = document.getElementById("start-activities");
  if (btn) {
    btn.textContent = "Activities running";
    btn.disabled = true;
  }
}

function setSelected(entry, on) {
  entry.selected = on;
  entry.ring.visible = on;
}

function pickCitizen(clientX, clientY) {
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  // Ground plane hit → nearest citizen
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const hit = new THREE.Vector3();
  if (!raycaster.ray.intersectPlane(plane, hit)) return null;
  let best = null;
  let bestD = 1.6;
  for (const c of citizens) {
    const d = hit.distanceTo(c.unit.group.position);
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}

renderer.domElement.addEventListener("pointerdown", (ev) => {
  if (ev.button !== 0) return;
  const picked = pickCitizen(ev.clientX, ev.clientY);
  const additive = ev.shiftKey;
  if (!additive) {
    for (const c of citizens) setSelected(c, false);
  }
  if (picked) setSelected(picked, true);
  updateStatus();
});

// Default: locked AoE angle + smooth pan/zoom. Slow rotate remains opt-in (off) for facing QA.
let rotateCam = false;
let yawOffset = 0;
const rotateBtn = document.getElementById("toggle-rotate");
rotateBtn?.addEventListener("click", () => {
  rotateCam = !rotateCam;
  if (!rotateCam) yawOffset = 0;
  if (rotateBtn) rotateBtn.textContent = rotateCam ? "toggle slow cam rotate (on)" : "toggle slow cam rotate (off)";
});
document.getElementById("select-walkers")?.addEventListener("click", () => {
  for (const c of citizens) setSelected(c, c.clip === "walk");
  updateStatus();
});
document.getElementById("start-activities")?.addEventListener("click", () => {
  startAllActivities();
});
window.addEventListener("keydown", (e) => {
  if (e.key === "a" || e.key === "A") {
    if (!e.metaKey && !e.ctrlKey && !e.altKey) {
      startAllActivities();
      e.preventDefault();
    }
  }
});

const minimapCanvas = /** @type {HTMLCanvasElement | null} */ (document.getElementById("minimap"));
const minimapWrap = document.getElementById("minimap-wrap");
const minimapCtx = minimapCanvas?.getContext("2d") ?? null;

function worldToMinimap(x, z, w, h) {
  const u = (x + MINIMAP_HALF) / (MINIMAP_HALF * 2);
  const v = (z + MINIMAP_HALF) / (MINIMAP_HALF * 2);
  return { x: u * w, y: v * h };
}

function minimapToWorld(px, py, w, h) {
  const u = px / w;
  const v = py / h;
  return {
    x: u * MINIMAP_HALF * 2 - MINIMAP_HALF,
    z: v * MINIMAP_HALF * 2 - MINIMAP_HALF
  };
}

function panFromMinimapEvent(ev) {
  if (!minimapCanvas) return;
  const rect = minimapCanvas.getBoundingClientRect();
  const px = ((ev.clientX - rect.left) / rect.width) * minimapCanvas.width;
  const py = ((ev.clientY - rect.top) / rect.height) * minimapCanvas.height;
  const { x, z } = minimapToWorld(px, py, minimapCanvas.width, minimapCanvas.height);
  camCtrl.panTo(x, z);
}

let minimapDragging = false;
minimapWrap?.addEventListener("pointerdown", (ev) => {
  if (ev.button !== 0) return;
  minimapDragging = true;
  try {
    minimapWrap.setPointerCapture?.(ev.pointerId);
  } catch {
    /* ignore */
  }
  panFromMinimapEvent(ev);
  ev.preventDefault();
  ev.stopPropagation();
});
minimapWrap?.addEventListener("pointermove", (ev) => {
  if (!minimapDragging) return;
  panFromMinimapEvent(ev);
});
const endMinimapDrag = () => {
  minimapDragging = false;
};
minimapWrap?.addEventListener("pointerup", endMinimapDrag);
minimapWrap?.addEventListener("pointercancel", endMinimapDrag);

function drawMinimap() {
  if (!minimapCtx || !minimapCanvas) return;
  const w = minimapCanvas.width;
  const h = minimapCanvas.height;
  const ctx = minimapCtx;

  ctx.clearRect(0, 0, w, h);
  // Terrain wash
  const g = ctx.createRadialGradient(w * 0.5, h * 0.5, 8, w * 0.5, h * 0.5, w * 0.55);
  g.addColorStop(0, "#5f8f4c");
  g.addColorStop(0.7, "#3f6a38");
  g.addColorStop(1, "#243420");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);

  // Town plaza ring
  const center = worldToMinimap(0, 0, w, h);
  ctx.strokeStyle = "rgba(226,184,102,0.55)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.arc(center.x, center.y, (4.2 / (MINIMAP_HALF * 2)) * w, 0, Math.PI * 2);
  ctx.stroke();

  // Houses
  ctx.fillStyle = "rgba(216,196,160,0.85)";
  for (const [hx, hz] of housePositions) {
    const p = worldToMinimap(hx, hz, w, h);
    ctx.fillRect(p.x - 2.5, p.y - 2.5, 5, 5);
  }

  // Trees
  ctx.fillStyle = "rgba(36,90,40,0.9)";
  for (const t of trees) {
    const p = worldToMinimap(t.position.x, t.position.z, w, h);
    ctx.beginPath();
    ctx.arc(p.x, p.y, 2.2, 0, Math.PI * 2);
    ctx.fill();
  }

  // Unit blips
  for (const c of citizens) {
    const p = worldToMinimap(c.unit.group.position.x, c.unit.group.position.z, w, h);
    const playing = c.unit.clip;
    ctx.fillStyle = CLIP_BLIP[playing] || CLIP_BLIP[c.clip] || "#fff";
    ctx.beginPath();
    ctx.arc(p.x, p.y, c.selected ? 3.2 : 2.2, 0, Math.PI * 2);
    ctx.fill();
    if (c.selected) {
      ctx.strokeStyle = "#dfffd0";
      ctx.lineWidth = 1;
      ctx.stroke();
    }
  }

  // Camera viewport frustum on ground
  const corners = camCtrl.getGroundViewportCorners();
  if (corners.length === 4) {
    ctx.beginPath();
    for (let i = 0; i < 4; i += 1) {
      const p = worldToMinimap(corners[i].x, corners[i].z, w, h);
      if (i === 0) ctx.moveTo(p.x, p.y);
      else ctx.lineTo(p.x, p.y);
    }
    ctx.closePath();
    ctx.fillStyle = "rgba(255, 245, 200, 0.12)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 236, 170, 0.95)";
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  // Look-at crosshair
  const look = worldToMinimap(camCtrl.target.x, camCtrl.target.z, w, h);
  ctx.strokeStyle = "rgba(255,255,255,0.85)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(look.x - 4, look.y);
  ctx.lineTo(look.x + 4, look.y);
  ctx.moveTo(look.x, look.y - 4);
  ctx.lineTo(look.x, look.y + 4);
  ctx.stroke();
}

function updateStatus() {
  const sel = citizens.filter((c) => c.selected).length;
  const idleN = citizens.filter((c) => c.unit.clip === "idle").length;
  const mix = `walk=${citizens.filter((c) => c.clip === "walk").length} · carry=${citizens.filter((c) => c.clip === "carry").length} · gather=${citizens.filter((c) => c.clip === "gather").length} · build=${citizens.filter((c) => c.clip === "build").length}`;
  const phase = activitiesArmed ? (idleN === 0 ? "active" : `waking=${32 - idleN}/32`) : "idle-standing";
  const zoom = camCtrl.distance.toFixed(1);
  status.textContent = `32 sprite Citizens · ${mix} · ${phase} · idlePlaying=${idleN} · selected=${sel} · zoom=${zoom} · atlas ${manifest.atlas.width}×${manifest.atlas.height}`;
}

camCtrl.panTo(0, 0, { immediate: true });
camCtrl.setDistance(RTS_CAMERA.defaultDistance * 1.45, { immediate: true });

let last = performance.now();
let statusAcc = 0;
let minimapAcc = MINIMAP_INTERVAL;
let fpsFrames = 0;
let fpsWindowStart = performance.now();
let lastFps = 0;

function frame(now) {
  requestAnimationFrame(frame);
  // Target 60 Hz: clamp dt so hitch recovery does not explode lerps.
  const dt = Math.min(1 / 30, (now - last) / 1000);
  last = now;

  fpsFrames += 1;
  const fpsElapsed = now - fpsWindowStart;
  if (fpsElapsed >= 500) {
    lastFps = Math.round((fpsFrames * 1000) / fpsElapsed);
    fpsFrames = 0;
    fpsWindowStart = now;
    if (fpsEl) fpsEl.textContent = `FPS ${lastFps}`;
  }

  camCtrl.tick(dt);

  if (rotateCam) {
    yawOffset += dt * 0.12; // slow orbit for facing proof (opt-in only)
    const baseYaw = THREE.MathUtils.degToRad(RTS_CAMERA.yawDegrees) + yawOffset;
    const pitch = THREE.MathUtils.degToRad(RTS_CAMERA.pitchDegrees);
    const dist = camCtrl.distance;
    const lookX = camCtrl.target.x;
    const lookZ = camCtrl.target.z;
    const lookY = RTS_CAMERA.targetHeight;
    const horiz = dist * Math.cos(pitch);
    camera.position.set(
      lookX + horiz * Math.sin(baseYaw),
      lookY + dist * Math.sin(pitch),
      lookZ + horiz * Math.cos(baseYaw)
    );
    camera.lookAt(lookX, lookY, lookZ);
  }

  for (const c of citizens) {
    const u = c.unit;

    if (c.activityStarted && (c.clip === "walk" || c.clip === "carry")) {
      const p = u.group.position;
      p.addScaledVector(c.vel, dt);
      // Orbit around town center
      const r = Math.hypot(p.x, p.z);
      const targetR = c.clip === "carry" ? 11.5 : 7.2;
      if (r > 0.01) {
        const nx = p.x / r;
        const nz = p.z / r;
        p.x = nx * targetR;
        p.z = nz * targetR;
        // tangential velocity refresh
        const speed = c.vel.length();
        c.vel.set(-nz * speed, 0, nx * speed);
      }
      // Hysteresis inside setYaw softens facing pops while orbiting.
      u.setYaw(Math.atan2(c.vel.x, c.vel.z));
    }
    // idle / gather / build: no root motion

    // Health bars face camera (cached ref — no per-frame name walk)
    if (c.hpBar) c.hpBar.quaternion.copy(camera.quaternion);

    u.update(dt);
  }

  minimapAcc += dt;
  if (minimapAcc >= MINIMAP_INTERVAL) {
    minimapAcc = 0;
    drawMinimap();
  }

  statusAcc += dt;
  if (statusAcc > 0.5) {
    statusAcc = 0;
    if (citizens.length) updateStatus();
  }

  renderer.render(scene, camera);
}

spawnCitizens()
  .then(() => {
    updateStatus();
    drawMinimap();
    // Debug/QA hook for CDP probes (idle standing + FPS).
    globalThis.__citizenRtsProof = {
      citizens,
      get activitiesArmed() {
        return activitiesArmed;
      },
      startAllActivities,
      camCtrl,
      getFps: () => lastFps,
      panTo: (x, z) => camCtrl.panTo(x, z),
      clipSnapshot: () =>
        citizens.map((c) => ({
          assigned: c.clip,
          playing: c.unit.clip,
          started: c.activityStarted,
          frame: c.unit.frameIndex,
          speed: c.unit.playbackSpeed,
          pos: {
            x: Number(c.unit.group.position.x.toFixed(3)),
            z: Number(c.unit.group.position.z.toFixed(3))
          }
        }))
    };
  })
  .catch((err) => {
    console.error(err);
    status.textContent = `ERROR: ${err.message || err}`;
  });

requestAnimationFrame(frame);
