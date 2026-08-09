// AoE2-style sprite proof lab — locked RTS camera + 8-direction Sunwoven Weaver.

import * as THREE from "three";
import { SpriteUnit } from "./sprites/sprite-unit.js";
import {
  createRtsCamera,
  RtsCameraController,
  rtsCameraSpec,
  applyRtsCamera,
} from "./rts-camera.js";
import { FACINGS } from "./sprites/facing.js";

const W = 1280;
const H = 720;
const root = document.getElementById("sprite-root");
const el = (id) => document.getElementById(id);

const renderer = new THREE.WebGLRenderer({
  antialias: true,
  alpha: false,
  preserveDrawingBuffer: true,
});
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
root.appendChild(renderer.domElement);

function resize() {
  const w = root.clientWidth || W;
  const h = root.clientHeight || H;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050711);

const camera = createRtsCamera(W / H);
const camCtrl = new RtsCameraController(camera, renderer.domElement);
resize();
window.addEventListener("resize", resize);

const key = new THREE.DirectionalLight(0xffd28c, 2.4);
key.position.set(-4, 10, 5);
scene.add(key);
scene.add(new THREE.AmbientLight(0x404868, 0.55));

const ground = new THREE.Mesh(
  new THREE.PlaneGeometry(24, 24),
  new THREE.MeshStandardMaterial({ color: 0x3a4a38, roughness: 0.95 })
);
ground.rotation.x = -Math.PI / 2;
scene.add(ground);

const grid = new THREE.GridHelper(24, 24, 0x6a7a58, 0x2a3a28);
grid.position.y = 0.01;
scene.add(grid);

/** Units with a baked sheet under `sprites/`. */
const UNITS = ["sunwoven-weaver", "sunwoven-villager", "space-villager"];
const requested = new URLSearchParams(location.search).get("unit");
let unitName = UNITS.includes(requested) ? requested : UNITS[0];

const unit = new SpriteUnit({}, { basePath: `sprites/${unitName}/` });
scene.add(unit.group);

let clip = "idle";
let yaw = Math.PI / 4; // SE — default walk demo facing
let walkT = 0;
let playing = true;

/** AoE2-style straight-line walk: ~0.4 s / 4-frame cycle @ 10 fps. */
const WALK_SPEED = 1.25;
const WALK_PATH_HALF = 4.5;

async function init() {
  // Prefer atlas-manifest (single-sheet UV playback) when present.
  const atlasUrl = `sprites/${unitName}/atlas-manifest.json`;
  const legacyUrl = `sprites/${unitName}/manifest.json`;
  let loaded = null;
  try {
    const res = await fetch(atlasUrl);
    if (res.ok) {
      loaded = await unit.applyManifest(await res.json());
    }
  } catch {
    /* fall through */
  }
  if (!loaded) {
    await unit.loadManifest(legacyUrl);
  }
  // A sheet that declares its own world height is already at gameplay scale, so
  // frame the shot on the unit. HD Codex plates (1024²) have no such height and
  // are only readable close up.
  const hd = !unit.manifest?.worldHeight && unit.manifest?.frameWidth >= 512;
  camCtrl.distance = hd ? 7 : 9;
  applyRtsCamera(camera, camCtrl.target, camCtrl.distance);
  setYaw(yaw);
  if (el("camera-spec")) {
    el("camera-spec").textContent = JSON.stringify(rtsCameraSpec(), null, 0);
  }
  if (el("unit-name")) {
    const mode = unit.manifest?.playback === "atlas" ? "atlas" : "frames";
    el("unit-name").textContent = `${unitName} (${mode})`;
  }
  if (el("status")) el("status").textContent = "READY — drag pan, wheel zoom, keys 1/2/3/4 clip, U unit";
  window.spriteLab = { unit, camera, spec: rtsCameraSpec(), setClip, setYaw, togglePlay, unitName };
}

/** Reload the page on the other unit — the lab holds one unit at a time. */
function cycleUnit() {
  const next = UNITS[(UNITS.indexOf(unitName) + 1) % UNITS.length];
  const url = new URL(location.href);
  url.searchParams.set("unit", next);
  location.href = url.toString();
}

function setClip(name) {
  clip = name;
  walkT = 0;
  if (name === "walk") {
    unit.setPosition(new THREE.Vector3(0, 0, 0));
    setYaw(yaw);
  } else if (name === "idle") {
    unit.setPosition(new THREE.Vector3(0, 0, 0));
  }
  unit.setClip(name);
  if (el("current-clip")) el("current-clip").textContent = name;
}

function setYaw(rad) {
  yaw = rad;
  unit.setYaw(rad);
  if (el("facing")) el("facing").textContent = `${FACINGS[unit.facing]} (${unit.facing})`;
}

function togglePlay() {
  playing = !playing;
}

document.addEventListener("keydown", (e) => {
  if (e.key === "1") setClip("idle");
  if (e.key === "2") setClip("walk");
  if (e.key === "3") setClip("gather");
  if (e.key === "4") setClip("build");
  if (e.key === " ") { e.preventDefault(); togglePlay(); }
  if (e.key === "u" || e.key === "U") cycleUnit();
  if (e.key === "ArrowLeft") setYaw(yaw - Math.PI / 8);
  if (e.key === "ArrowRight") setYaw(yaw + Math.PI / 8);
});

const clock = new THREE.Clock();
function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.1);
  if (playing) {
    if (clip === "walk") {
      walkT += dt;
      const leg = walkT * WALK_SPEED;
      const ping = leg % (WALK_PATH_HALF * 2);
      const along = ping <= WALK_PATH_HALF ? ping : WALK_PATH_HALF * 2 - ping;
      unit.setPosition(
        new THREE.Vector3(
          Math.sin(yaw) * along,
          0,
          Math.cos(yaw) * along
        )
      );
    } else if (clip === "idle" || clip === "gather" || clip === "build") {
      unit.setPosition(new THREE.Vector3(0, 0, 0));
    }
    unit.update(dt);
  }
  renderer.render(scene, camera);
}

frame();
init().catch((err) => {
  console.error(err);
  if (el("status")) el("status").textContent = `LOAD FAILED: ${err.message}`;
});
