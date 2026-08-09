// Lumen Guard v1 — combat silhouette proof (idle / walk / attack).
// Foundation ref shield+spear · shared atlas · no Texture.clone() × N

import * as THREE from "three";
import { SpriteUnit } from "./sprites/sprite-unit.js";
import { createRtsCamera, RtsCameraController, RTS_CAMERA } from "./rts-camera.js";
import { FACINGS_16 } from "./sprites/facing.js";
import manifest from "../assets/citizens/sprites/lumen-guard/atlas-manifest.json";

const root = document.getElementById("proof-root");
const status = document.getElementById("status");
const fpsEl = document.getElementById("fps");

const CLIP_PLAN = [
  ...Array(4).fill("idle"),
  ...Array(4).fill("walk"),
  ...Array(4).fill("attack")
];

const renderer = new THREE.WebGLRenderer({
  antialias: false,
  alpha: false,
  powerPreference: "high-performance"
});
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(1);
root.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x1a1520);
scene.fog = new THREE.Fog(0x1a1520, 38, 88);

const camera = createRtsCamera(1);
const camCtrl = new RtsCameraController(camera, renderer.domElement, {
  panRadius: 28,
  zoomSmooth: 18,
  panSmooth: 20
});

function resize() {
  const w = Math.max(1, root.clientWidth);
  const h = Math.max(1, root.clientHeight);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
resize();
window.addEventListener("resize", resize);

scene.add(new THREE.HemisphereLight(0xffe8c8, 0x2a1838, 1.0));
const key = new THREE.DirectionalLight(0xffd090, 1.75);
key.position.set(-10, 20, 8);
scene.add(key);
const fill = new THREE.DirectionalLight(0x48d8c8, 0.45);
fill.position.set(8, 10, -6);
scene.add(fill);

const ground = new THREE.Mesh(
  new THREE.PlaneGeometry(56, 56),
  new THREE.MeshStandardMaterial({ color: 0x3a3248, roughness: 0.92 })
);
ground.rotation.x = -Math.PI / 2;
ground.position.y = -0.01;
scene.add(ground);

const selectionMat = new THREE.MeshBasicMaterial({
  color: 0xe2b866,
  transparent: true,
  opacity: 0.55,
  depthWrite: false
});

function addSelectionRing(parent) {
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.85, 1.15, 32), selectionMat);
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.03;
  ring.visible = false;
  parent.add(ring);
  return ring;
}

function addBlobShadow(parent) {
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 64;
  const ctx = canvas.getContext("2d");
  const g = ctx.createRadialGradient(32, 32, 4, 32, 32, 30);
  g.addColorStop(0, "rgba(0,0,0,0.45)");
  g.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  const tex = new THREE.CanvasTexture(canvas);
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(2.2, 2.2),
    new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false })
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.012;
  parent.add(mesh);
}

const bundled = {
  ...manifest,
  atlas: { ...manifest.atlas, image: "runtime-atlas.png" }
};

/** @type {{ unit: SpriteUnit, clip: string, ring: THREE.Mesh, vel: THREE.Vector3, home: THREE.Vector3, started: boolean }[]} */
const guards = [];
let activitiesArmed = false;

function placeForClip(clip, idx) {
  const row = clip === "idle" ? 0 : clip === "walk" ? 1 : 2;
  const col = idx;
  return new THREE.Vector3((col - 1.5) * 3.2, 0, (row - 1) * 4.5);
}

async function spawnGuards() {
  const warmer = new SpriteUnit(bundled, { basePath: "sprites/lumen-guard/" });
  await warmer.applyManifest(bundled);
  await warmer._loadAtlasTexture();
  await warmer.setState("idle");
  warmer.freezeStanding(0);
  const sharedAtlas = warmer._atlasTexture;
  if (!sharedAtlas) throw new Error("runtime-atlas.png failed to load");

  const counts = { idle: 0, walk: 0, attack: 0 };
  for (let i = 0; i < CLIP_PLAN.length; i += 1) {
    const clip = CLIP_PLAN[i];
    const idx = counts[clip]++;
    const unit = new SpriteUnit(bundled, { basePath: "sprites/lumen-guard/" });
    unit.useSharedAtlas(sharedAtlas);
    await unit.applyManifest(bundled);
    await unit.setState("idle");
    unit.freezeStanding(0);
    const home = placeForClip(clip, idx);
    unit.setPosition(home);
    unit.setFacing((i * 3) % FACINGS_16.length);

    const rootGroup = unit.group;
    const ring = addSelectionRing(rootGroup);
    addBlobShadow(rootGroup);
    scene.add(rootGroup);

    guards.push({
      unit,
      clip,
      ring,
      vel: new THREE.Vector3(),
      home: home.clone(),
      started: false
    });
  }
}

function startActivity(entry) {
  if (entry.started) return;
  entry.started = true;
  entry.unit.playbackSpeed = 1;
  if (entry.clip === "walk") {
    const a = Math.atan2(entry.home.z, entry.home.x) + Math.PI * 0.35;
    entry.vel.set(Math.cos(a) * 2.0, 0, Math.sin(a) * 2.0);
    entry.unit.setState("walk").then(() => {
      entry.unit.setYawImmediate(Math.atan2(entry.vel.x, entry.vel.z));
    }).catch(console.error);
  } else if (entry.clip === "attack") {
    entry.unit.setState("attack").catch(console.error);
  }
}

function startAll() {
  if (activitiesArmed) return;
  activitiesArmed = true;
  for (const g of guards) startActivity(g);
  status.textContent = "12 Lumen Guards — idle / walk / attack running";
  const btn = document.getElementById("start-activities");
  if (btn) {
    btn.textContent = "Activities running";
    btn.disabled = true;
  }
}

document.getElementById("start-activities")?.addEventListener("click", startAll);

let rotateCam = false;
let yawOffset = 0;
document.getElementById("toggle-rotate")?.addEventListener("click", () => {
  rotateCam = !rotateCam;
  if (!rotateCam) yawOffset = 0;
  const btn = document.getElementById("toggle-rotate");
  if (btn) btn.textContent = rotateCam ? "toggle slow cam rotate (on)" : "toggle slow cam rotate (off)";
});

window.addEventListener("keydown", (e) => {
  if (e.key === "a" || e.key === "A") startAll();
});

const clock = new THREE.Clock();
let fpsAcc = 0;
let fpsFrames = 0;

async function main() {
  status.textContent = "loading Lumen Guard atlas…";
  await spawnGuards();
  status.textContent = "12 Lumen Guards idle — press Start or A for walk/attack demo";
  function tick() {
    requestAnimationFrame(tick);
    const dt = Math.min(clock.getDelta(), 0.05);
    fpsAcc += dt;
    fpsFrames += 1;
    if (fpsAcc >= 0.5) {
      fpsEl.textContent = `FPS ${Math.round(fpsFrames / fpsAcc)}`;
      fpsAcc = 0;
      fpsFrames = 0;
    }
    camCtrl.tick(dt);
    if (rotateCam) {
      yawOffset += dt * 0.12;
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
    for (const g of guards) {
      g.unit.update(dt);
      if (g.started && g.clip === "walk") {
        const p = g.unit.group.position;
        p.x += g.vel.x * dt;
        p.z += g.vel.z * dt;
        g.unit.setYawImmediate(Math.atan2(g.vel.x, g.vel.z));
        if (p.distanceTo(g.home) > 8) {
          g.vel.multiplyScalar(-1);
        }
      }
    }
    renderer.render(scene, camera);
  }
  tick();
}

main().catch((err) => {
  status.textContent = `error: ${err.message}`;
  console.error(err);
});
