// Helios Rift — playable RTS space map proof.
// Data-driven map via rts-maps framework; sprite Citizens + path graph navigation.

import * as THREE from "three";
import { SpriteUnit } from "./sprites/sprite-unit.js";
import { createRtsCamera, RtsCameraController, RTS_CAMERA } from "./rts-camera.js";
import { FACINGS_16 } from "./sprites/facing.js";
import { createRtsMapWorld } from "./rts-maps/rts-map-world.js";
import manifest from "../assets/citizens/sprites/village-manbun-wanderer/atlas-manifest.json";
import guardManifest from "../assets/citizens/sprites/lumen-guard/atlas-manifest.json";

const MAP_ID = "helios-rift";
const LOCAL_PLAYER = 0;
const MOVE_SPEED = 4.2;
const GATHER_RANGE = 2.2;
const BRIDGE_REPAIR_RANGE = 4.5;
const BRIDGE_REPAIR_COST = 50;
const HELIOS_CAMERA = Object.freeze({
  minDistance: RTS_CAMERA.minDistance,
  maxDistance: 110,
  fovDegrees: 50,
  far: 240
});

const root = document.getElementById("proof-root");
const status = document.getElementById("status");
const fpsEl = document.getElementById("fps");
const flareBanner = document.getElementById("flare-banner");
const toastEl = document.getElementById("toast");

const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: "high-performance" });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(1);
root.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x020612);
scene.fog = new THREE.Fog(0x020612, 72, 140);

const camera = createRtsCamera(1, HELIOS_CAMERA);
const mapWorld = createRtsMapWorld(MAP_ID, scene);
const HALF = mapWorld.definition.bounds.halfExtent;

const camCtrl = new RtsCameraController(camera, renderer.domElement, {
  target: new THREE.Vector3(0, 0, 0),
  distance: HELIOS_CAMERA.maxDistance,
  minDistance: HELIOS_CAMERA.minDistance,
  maxDistance: HELIOS_CAMERA.maxDistance,
  fovDegrees: HELIOS_CAMERA.fovDegrees,
  far: HELIOS_CAMERA.far,
  panRadius: HALF + 6,
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

scene.add(new THREE.HemisphereLight(0xd7e4ff, 0x080d18, 1.0));
const key = new THREE.DirectionalLight(0xffd09a, 1.8);
key.position.set(-18, 30, 14);
scene.add(key);
const fill = new THREE.DirectionalLight(0x6ac8d0, 0.55);
fill.position.set(14, 16, -12);
scene.add(fill);
const rim = new THREE.DirectionalLight(0x5574ae, 0.3);
rim.position.set(16, 10, 20);
scene.add(rim);

const selectionMat = new THREE.MeshBasicMaterial({
  color: 0x3ecfc0,
  transparent: true,
  opacity: 0.55,
  depthWrite: false
});

function addSelectionRing(parent) {
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.75, 1.05, 32), selectionMat);
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
  const g = ctx.createRadialGradient(32, 34, 1, 32, 32, 26);
  g.addColorStop(0, "rgba(0,0,0,0.28)");
  g.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(1.0, 1.0),
    new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(canvas), transparent: true, depthWrite: false })
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.012;
  parent.add(mesh);
}

const bundled = {
  ...manifest,
  atlas: { ...manifest.atlas, image: "runtime-atlas.png" }
};

const guardBundled = {
  ...guardManifest,
  atlas: { ...guardManifest.atlas, image: "runtime-atlas.png" }
};

/** @type {{ unit: SpriteUnit, playerId: number, selected: boolean, ring: THREE.Mesh, hp: number, path: {x:number,z:number}[], pathIdx: number, activity: string, gatherTarget: string | null, stock: Record<string, number> }[]} */
const citizens = [];

let playerStock = { energy_materials: 120, matter: 80, lumen: 40, aether: 0 };

function showToast(msg, ms = 2500) {
  if (!toastEl) return;
  toastEl.textContent = msg;
  toastEl.style.display = "block";
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => {
    toastEl.style.display = "none";
  }, ms);
}

async function spawnCitizens() {
  const warmer = new SpriteUnit(bundled, { basePath: "sprites/village-manbun-wanderer/" });
  await warmer.applyManifest(bundled);
  await warmer._loadAtlasTexture();
  await warmer.setState("idle");
  warmer.freezeStanding(0);
  const sharedAtlas = warmer._atlasTexture;
  const sharedIdle = warmer._clipAtlasTextures.get("idle") || null;

  let uid = 0;
  for (const spawn of mapWorld.spawns) {
    const n = spawn.startingCitizens;
    for (let i = 0; i < n; i += 1) {
      const unit = new SpriteUnit(bundled, { basePath: "sprites/village-manbun-wanderer/" });
      unit.useSharedAtlas(sharedAtlas);
      if (sharedIdle) unit.useSharedClipAtlas("idle", sharedIdle);
      await unit.applyManifest(bundled);
      await unit.setState("idle");
      unit.freezeStanding(0);

      const angle = (i / n) * Math.PI * 2;
      const r = 2.5 + (i % 3) * 1.1;
      const px = spawn.position.x + Math.cos(angle) * r;
      const pz = spawn.position.z + Math.sin(angle) * r;
      unit.setPosition({ x: px, y: 0, z: pz });
      unit.setFacing((i + spawn.playerId * 3) % FACINGS_16.length);

      const rootGroup = unit.group;
      const ring = addSelectionRing(rootGroup);
      addBlobShadow(rootGroup);
      if (spawn.playerId !== LOCAL_PLAYER) {
        const tint = new THREE.Mesh(
          new THREE.CircleGeometry(0.9, 16),
          new THREE.MeshBasicMaterial({
            color: spawn.color,
            transparent: true,
            opacity: 0.12,
            depthWrite: false
          })
        );
        tint.rotation.x = -Math.PI / 2;
        tint.position.y = 0.02;
        rootGroup.add(tint);
      }
      scene.add(rootGroup);

      citizens.push({
        unit,
        playerId: spawn.playerId,
        selected: spawn.playerId === LOCAL_PLAYER && i < 4,
        ring,
        hp: 100,
        path: [],
        pathIdx: 0,
        activity: "idle",
        gatherTarget: null,
        stock: {},
        _uid: uid++
      });
    }
  }
  for (const c of citizens) c.ring.visible = c.selected;
}

/** Four Lumen Guards mixed into Helios — shared guard atlas, combat silhouette. */
async function spawnGuards() {
  const warmer = new SpriteUnit(guardBundled, { basePath: "sprites/lumen-guard/" });
  await warmer.applyManifest(guardBundled);
  await warmer._loadAtlasTexture();
  await warmer.setState("idle");
  warmer.freezeStanding(0);
  const sharedAtlas = warmer._atlasTexture;
  if (!sharedAtlas) return;

  const spawn = mapWorld.spawns.find((s) => s.playerId === LOCAL_PLAYER) || mapWorld.spawns[0];
  if (!spawn) return;

  for (let i = 0; i < 4; i += 1) {
    const unit = new SpriteUnit(guardBundled, { basePath: "sprites/lumen-guard/" });
    unit.useSharedAtlas(sharedAtlas);
    await unit.applyManifest(guardBundled);
    await unit.setState("idle");
    unit.freezeStanding(0);
    const px = spawn.position.x + 6 + i * 1.4;
    const pz = spawn.position.z - 4 - (i % 2) * 1.2;
    unit.setPosition({ x: px, y: 0, z: pz });
    unit.setFacing((i * 4) % FACINGS_16.length);

    const rootGroup = unit.group;
    const ring = addSelectionRing(rootGroup);
    addBlobShadow(rootGroup);
    scene.add(rootGroup);

    citizens.push({
      unit,
      playerId: LOCAL_PLAYER,
      selected: false,
      ring,
      hp: 140,
      path: [],
      pathIdx: 0,
      activity: "idle",
      gatherTarget: null,
      stock: {},
      _uid: 900 + i,
      _isGuard: true
    });
  }
}

function setSelected(c, on) {
  if (c.playerId !== LOCAL_PLAYER) return;
  c.selected = on;
  c.ring.visible = on;
}

function pickCitizen(clientX, clientY) {
  const rect = renderer.domElement.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((clientX - rect.left) / rect.width) * 2 - 1,
    -((clientY - rect.top) / rect.height) * 2 + 1
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const hit = new THREE.Vector3();
  if (!raycaster.ray.intersectPlane(plane, hit)) return null;
  let best = null;
  let bestD = 1.8;
  for (const c of citizens) {
    if (c.playerId !== LOCAL_PLAYER) continue;
    const p = c.unit.group.position;
    const d = hit.distanceTo(p);
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}

function groundHit(clientX, clientY) {
  const rect = renderer.domElement.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((clientX - rect.left) / rect.width) * 2 - 1,
    -((clientY - rect.top) / rect.height) * 2 + 1
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const hit = new THREE.Vector3();
  return raycaster.ray.intersectPlane(plane, hit) ? hit : null;
}

function bridgeEndpoints(bridge) {
  return {
    from: bridge.visual?.from ?? bridge.from,
    to: bridge.visual?.to ?? bridge.to
  };
}

function bridgeMidpoint(bridge) {
  const { from, to } = bridgeEndpoints(bridge);
  return {
    x: (from.x + to.x) / 2,
    z: (from.z + to.z) / 2
  };
}

function nearestBrokenBridge(x, z) {
  let best = null;
  let bestD = BRIDGE_REPAIR_RANGE;
  for (const b of mapWorld.definition.bridges) {
    if (mapWorld.bridgeStates.get(b.id)) continue;
    const midpoint = bridgeMidpoint(b);
    const d = Math.hypot(x - midpoint.x, z - midpoint.z);
    if (d < bestD) {
      bestD = d;
      best = b;
    }
  }
  return best;
}

function nearestResource(x, z) {
  let best = null;
  let bestD = GATHER_RANGE + 1;
  for (const r of mapWorld.resources) {
    const d = Math.hypot(x - r.position.x, z - r.position.z);
    if (d < bestD) {
      bestD = d;
      best = r;
    }
  }
  return best;
}

function orderMoveSelected(x, z, gatherRes = null, repairBridge = null) {
  const selected = citizens.filter((c) => c.selected && c.playerId === LOCAL_PLAYER);
  if (!selected.length) return;

  for (let i = 0; i < selected.length; i += 1) {
    const c = selected[i];
    const ox = (i % 3 - 1) * 1.2;
    const oz = (Math.floor(i / 3) % 3 - 1) * 1.2;
    const tx = x + ox;
    const tz = z + oz;
    const p = c.unit.group.position;
    c.path = mapWorld.pathGraph.findPath(p.x, p.z, tx, tz);
    c.pathIdx = 0;
    c.gatherTarget = gatherRes?.id ?? null;
    c.activity = gatherRes ? "gather" : repairBridge ? "build" : "walk";
    c.unit.playbackSpeed = 1;
    c.unit.setState(c.activity === "gather" ? "gather" : c.activity === "build" ? "build" : "walk").catch(console.error);
  }

  if (repairBridge) {
    if (playerStock.energy_materials >= BRIDGE_REPAIR_COST) {
      playerStock.energy_materials -= BRIDGE_REPAIR_COST;
      mapWorld.repairBridge(repairBridge.id);
      showToast(`Bridge ${repairBridge.id} repaired (−${BRIDGE_REPAIR_COST} energy)`);
    } else {
      showToast("Need 50 energy_materials to repair bridge");
    }
  }
}

renderer.domElement.addEventListener("contextmenu", (e) => e.preventDefault());

renderer.domElement.addEventListener("pointerdown", (ev) => {
  if (ev.button === 0) {
    const picked = pickCitizen(ev.clientX, ev.clientY);
    if (!ev.shiftKey) {
      for (const c of citizens) {
        if (c.playerId === LOCAL_PLAYER) setSelected(c, false);
      }
    }
    if (picked) setSelected(picked, true);
    updateStatus();
    return;
  }
  if (ev.button === 2) {
    const hit = groundHit(ev.clientX, ev.clientY);
    if (!hit) return;
    const res = nearestResource(hit.x, hit.z);
    const bridge = nearestBrokenBridge(hit.x, hit.z);
    if (res && Math.hypot(hit.x - res.position.x, hit.z - res.position.z) < GATHER_RANGE + 2) {
      orderMoveSelected(res.position.x, res.position.z, res);
      showToast(`Gather ${res.kind} @ ${res.id}`);
    } else if (bridge) {
      const midpoint = bridgeMidpoint(bridge);
      orderMoveSelected(midpoint.x, midpoint.z, null, bridge);
    } else {
      orderMoveSelected(hit.x, hit.z);
    }
    updateStatus();
  }
});

document.getElementById("select-all")?.addEventListener("click", () => {
  for (const c of citizens) {
    if (c.playerId === LOCAL_PLAYER) setSelected(c, true);
  }
  updateStatus();
});

document.getElementById("repair-bridge")?.addEventListener("click", () => {
  const sel = citizens.find((c) => c.selected && c.playerId === LOCAL_PLAYER);
  const p = sel?.unit.group.position ?? camCtrl.target;
  const bridge = nearestBrokenBridge(p.x, p.z);
  if (bridge) {
    const midpoint = bridgeMidpoint(bridge);
    orderMoveSelected(midpoint.x, midpoint.z, null, bridge);
  }
  else showToast("No broken bridge in range");
});

document.getElementById("show-hints")?.addEventListener("click", () => {
  console.log("AI Hints:", mapWorld.getFreshAIHints());
  showToast("AI hints logged to console");
});

// Minimap
const minimapCanvas = /** @type {HTMLCanvasElement | null} */ (document.getElementById("minimap"));
const minimapWrap = document.getElementById("minimap-wrap");
const minimapCtx = minimapCanvas?.getContext("2d") ?? null;
const MINIMAP_INTERVAL = 1 / 12;

function worldToMinimap(x, z, w, h) {
  const u = (x + HALF) / (HALF * 2);
  const v = (z + HALF) / (HALF * 2);
  return { x: u * w, y: v * h };
}

function minimapToWorld(px, py, w, h) {
  return { x: (px / w) * HALF * 2 - HALF, z: (py / h) * HALF * 2 - HALF };
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
  panFromMinimapEvent(ev);
  ev.preventDefault();
});
minimapWrap?.addEventListener("pointermove", (ev) => {
  if (minimapDragging) panFromMinimapEvent(ev);
});
minimapWrap?.addEventListener("pointerup", () => {
  minimapDragging = false;
});

function drawMinimap() {
  if (!minimapCtx || !minimapCanvas) return;
  const w = minimapCanvas.width;
  const h = minimapCanvas.height;
  const ctx = minimapCtx;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#080c18";
  ctx.fillRect(0, 0, w, h);

  // Platforms
  for (const p of mapWorld.definition.terrain.platforms) {
    const c = worldToMinimap(p.center.x, p.center.z, w, h);
    const r = (p.radius / (HALF * 2)) * w;
    ctx.fillStyle = p.id.includes("core") ? "rgba(255,120,40,0.35)" : "rgba(138,122,98,0.55)";
    ctx.beginPath();
    ctx.arc(c.x, c.y, Math.max(3, r), 0, Math.PI * 2);
    ctx.fill();
  }

  // Bridges
  for (const b of mapWorld.definition.bridges) {
    const a = worldToMinimap(b.from.x, b.from.z, w, h);
    const e = worldToMinimap(b.to.x, b.to.z, w, h);
    ctx.strokeStyle = mapWorld.bridgeStates.get(b.id) ? "rgba(62,207,192,0.7)" : "rgba(200,160,80,0.5)";
    ctx.lineWidth = mapWorld.bridgeStates.get(b.id) ? 2 : 1;
    ctx.setLineDash(mapWorld.bridgeStates.get(b.id) ? [] : [3, 3]);
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(e.x, e.y);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // Resources
  for (const r of mapWorld.resources) {
    const p = worldToMinimap(r.position.x, r.position.z, w, h);
    ctx.fillStyle = "#3ecfc0";
    ctx.fillRect(p.x - 2, p.y - 2, 4, 4);
  }

  // Spawns
  for (const s of mapWorld.spawns) {
    const p = worldToMinimap(s.position.x, s.position.z, w, h);
    ctx.fillStyle = `#${s.color.toString(16).padStart(6, "0")}`;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 4, 0, Math.PI * 2);
    ctx.fill();
  }

  // Units
  for (const c of citizens) {
    const p = worldToMinimap(c.unit.group.position.x, c.unit.group.position.z, w, h);
    ctx.fillStyle = c.playerId === LOCAL_PLAYER ? (c.selected ? "#3ecfc0" : "#5ad4ff") : "#888";
    ctx.beginPath();
    ctx.arc(p.x, p.y, c.selected ? 3 : 2, 0, Math.PI * 2);
    ctx.fill();
  }

  // Solar core zone
  const core = mapWorld.objectives[0];
  if (core) {
    const p = worldToMinimap(core.position.x, core.position.z, w, h);
    ctx.strokeStyle = "rgba(255,160,48,0.8)";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(p.x, p.y, (core.captureRadius / (HALF * 2)) * w, 0, Math.PI * 2);
    ctx.stroke();
  }
}

function updateStatus() {
  const sel = citizens.filter((c) => c.selected).length;
  const p0 = citizens.filter((c) => c.playerId === LOCAL_PLAYER).length;
  const core = mapWorld.objectives[0];
  const coreOwner = core?.controllingPlayer;
  const flare = mapWorld.hazards.find((h) => h.type === "solar_flare" && h.active);
  const brokenBridges = [...mapWorld.bridgeStates.entries()].filter(([, v]) => !v).length;
  status.textContent =
    `P0: ${p0} Citizens · selected=${sel} · core=${coreOwner === null ? "neutral" : `P${coreOwner}`} · ` +
    `bridges down=${brokenBridges} · stock energy=${playerStock.energy_materials} · ` +
    (flare ? "FLARE!" : "stable");
  if (flareBanner) flareBanner.style.display = flare ? "block" : "none";
}

camCtrl.panTo(0, 0, { immediate: true });
camCtrl.setDistance(HELIOS_CAMERA.maxDistance, { immediate: true });

let last = performance.now();
let minimapAcc = MINIMAP_INTERVAL;
let gatherAcc = 0;
let fpsFrames = 0;
let fpsWindowStart = performance.now();
let lastFps = 0;

function advanceCitizen(c, dt) {
  const p = c.unit.group.position;
  if (c.path.length && c.pathIdx < c.path.length) {
    const target = c.path[c.pathIdx];
    const dx = target.x - p.x;
    const dz = target.z - p.z;
    const dist = Math.hypot(dx, dz);
    if (dist < 0.25) {
      c.pathIdx += 1;
      if (c.pathIdx >= c.path.length) {
        c.path = [];
        if (c.activity === "gather" && c.gatherTarget) {
          const res = mapWorld.resources.find((r) => r.id === c.gatherTarget);
          if (res && Math.hypot(p.x - res.position.x, p.z - res.position.z) < GATHER_RANGE + 1) {
            const yieldAmt = 8;
            res.amount = Math.max(0, res.amount - yieldAmt);
            const kind = res.kind;
            if (kind === "energy_materials" || kind === "matter" || kind === "lumen" || kind === "aether") {
              playerStock[kind] = (playerStock[kind] ?? 0) + yieldAmt;
            }
            c.unit.setState("carry").then(() => c.unit.setState("gather")).catch(console.error);
          }
        }
        c.activity = "idle";
        c.unit.setState("idle").then(() => c.unit.freezeStanding(0)).catch(console.error);
      }
    } else {
      const step = MOVE_SPEED * dt;
      const s = Math.min(step, dist);
      p.x += (dx / dist) * s;
      p.z += (dz / dist) * s;
      c.unit.setYaw(Math.atan2(dx, dz));
    }
  }
}

function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(1 / 30, (now - last) / 1000);
  last = now;

  fpsFrames += 1;
  if (now - fpsWindowStart >= 500) {
    lastFps = Math.round((fpsFrames * 1000) / (now - fpsWindowStart));
    fpsFrames = 0;
    fpsWindowStart = now;
    if (fpsEl) fpsEl.textContent = `FPS ${lastFps}`;
  }

  camCtrl.tick(dt);

  const unitStates = citizens.map((c) => ({
    playerId: c.playerId,
    x: c.unit.group.position.x,
    z: c.unit.group.position.z,
    hp: c.hp
  }));
  mapWorld.tick(dt, unitStates);
  for (let i = 0; i < citizens.length; i += 1) {
    citizens[i].hp = unitStates[i].hp;
    if (citizens[i].playerId === LOCAL_PLAYER) advanceCitizen(citizens[i], dt);
    citizens[i].unit.update(dt);
  }

  // Pulse solar corona during flare
  const flare = mapWorld.hazards.find((h) => h.type === "solar_flare" && h.active);
  const corona = mapWorld.objectives[0]?.mesh?.getObjectByName("corona");
  if (corona) corona.scale.setScalar(flare ? 1.15 + Math.sin(now * 0.01) * 0.08 : 1);

  minimapAcc += dt;
  if (minimapAcc >= MINIMAP_INTERVAL) {
    minimapAcc = 0;
    drawMinimap();
  }
  gatherAcc += dt;
  if (gatherAcc > 0.5) {
    gatherAcc = 0;
    updateStatus();
  }

  renderer.render(scene, camera);
}

spawnCitizens()
  .then(() => spawnGuards())
  .then(() => {
    updateStatus();
    drawMinimap();
    globalThis.__heliosRiftProof = {
      mapWorld,
      citizens,
      playerStock,
      camCtrl,
      getAIHints: () => mapWorld.getFreshAIHints(),
      repairBridge: (id) => mapWorld.repairBridge(id),
      getFps: () => lastFps,
      panTo: (x, z, immediate = true) => camCtrl.panTo(x, z, { immediate }),
      setDistance: (d, immediate = true) => camCtrl.setDistance(d, { immediate }),
      setView: (x, z, distance) => {
        camCtrl.panTo(x, z, { immediate: true });
        camCtrl.setDistance(distance, { immediate: true });
        camCtrl.tick(1);
      }
    };
  })
  .catch((err) => {
    console.error(err);
    status.textContent = `ERROR: ${err.message || err}`;
  });

requestAnimationFrame(frame);
