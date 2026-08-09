// 32–64 Village Man-Bun citizens — terrain anchor + 16-dir facing proof.
// Serve ThreeRuntime (or assets/citizens) and open citizen-crowd-lab.html

import * as THREE from "three";
import { SpriteUnit } from "./sprites/sprite-unit.js";
import { createRtsCamera, RtsCameraController } from "./rts-camera.js";
import { FACINGS_16 } from "./sprites/facing.js";
import manifest from "../assets/citizens/sprites/village-manbun-wanderer/atlas-manifest.json";
import atlasPng from "../assets/citizens/sprites/village-manbun-wanderer/runtime-atlas.png";

const root = document.getElementById("crowd-root");
const status = document.getElementById("status");
const countEl = document.getElementById("count");
const clipEl = document.getElementById("clip");

const params = new URLSearchParams(location.search);
const initialCount = Math.min(64, Math.max(32, Number(params.get("count") || 48)));
countEl.value = String(initialCount);

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, preserveDrawingBuffer: true });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
root.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050711);

const camera = createRtsCamera(1);
const camCtrl = new RtsCameraController(camera, renderer.domElement);

function resize() {
  const w = Math.max(1, root.clientWidth);
  const h = Math.max(1, root.clientHeight);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
resize();
window.addEventListener("resize", resize);

scene.add(new THREE.HemisphereLight(0x9ab5d9, 0x14172b, 1.4));
const key = new THREE.DirectionalLight(0xffd28c, 2.2);
key.position.set(-4, 10, 5);
scene.add(key);

const ground = new THREE.Mesh(
  new THREE.CircleGeometry(28, 64),
  new THREE.MeshStandardMaterial({ color: 0x3a4a38, roughness: 0.94, metalness: 0 })
);
ground.rotation.x = -Math.PI / 2;
scene.add(ground);
const grid = new THREE.GridHelper(40, 40, 0x6a7a58, 0x2a3a28);
grid.position.y = 0.01;
scene.add(grid);

/** @type {SpriteUnit[]} */
let units = [];
let spin = false;
let spinT = 0;
let last = performance.now();

const bundled = {
  ...manifest,
  atlas: { ...manifest.atlas, image: atlasPng }
};

async function spawn(count) {
  for (const u of units) scene.remove(u.group);
  units = [];
  const cols = Math.ceil(Math.sqrt(count));
  const spacing = 2.35;
  const origin = -((cols - 1) * spacing) / 2;
  for (let i = 0; i < count; i += 1) {
    const unit = new SpriteUnit(bundled, { basePath: "sprites/village-manbun-wanderer/" });
    await unit.applyManifest(bundled);
    await unit.setClip(clipEl.value);
    const row = Math.floor(i / cols);
    const col = i % cols;
    unit.setPosition(new THREE.Vector3(origin + col * spacing, 0, origin + row * spacing));
    // Spread facings so direction switching is visible in one screenshot.
    unit.setFacing(i % FACINGS_16.length);
    scene.add(unit.group);
    units.push(unit);
  }
  status.textContent = `${count} citizens · clip=${clipEl.value} · facings=16 · premul=${!!manifest.premultipliedAlpha}`;
}

async function init() {
  camCtrl.target.set(0, 0, 0);
  camCtrl.distance = 34;
  camCtrl.update();
  await spawn(Number(countEl.value));
}

countEl.addEventListener("change", () => spawn(Number(countEl.value)));
clipEl.addEventListener("change", async () => {
  for (const u of units) await u.setClip(clipEl.value);
  status.textContent = `${units.length} citizens · clip=${clipEl.value} · facings=16`;
});
document.getElementById("spin").addEventListener("click", () => {
  spin = !spin;
});

function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (spin) {
    spinT += dt;
    for (let i = 0; i < units.length; i += 1) {
      units[i].setYaw(spinT * 0.7 + (i * Math.PI * 2) / Math.max(1, units.length));
    }
  }
  for (const u of units) u.update(dt);
  renderer.render(scene, camera);
}

init().catch((err) => {
  console.error(err);
  status.textContent = `ERROR: ${err.message || err}`;
});
requestAnimationFrame(frame);
