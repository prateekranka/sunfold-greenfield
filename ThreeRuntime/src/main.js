import * as THREE from "three";
import {
  BRIDGE_PROTOCOL_VERSION,
  SAVE_SCHEMA_VERSION,
  assertValidEnvelope,
  createEnvelope
} from "./protocol.js";
import { SimulationSession } from "./sim/session.js";
import { createRtsCamera, RtsCameraController, RTS_CAMERA } from "./rts-camera.js";
import { UnitPresentationLayer } from "./sprites/unit-layer.js";
import { createRegistry, assetIdForUnit } from "./asset-registry.js";
import { createProceduralUnit } from "./procedural-units.js";
import { GltfUnitLibrary } from "./gltf-units.js";
import assetRegistryData from "../assets/asset-registry.json";
import citizenVillagerGlb from "../assets/units/citizen_villager.glb";
import pathfinderScoutGlb from "../assets/units/pathfinder_scout.glb";
import spaceVillagerAtlasManifest from "../assets/citizens/sprites/space-villager/atlas-manifest.json";
import spaceVillagerAtlasPng from "../assets/citizens/sprites/space-villager/runtime-atlas.png";

// Logical unit-art registry (Fidelity Ladder). Every unit resolves through
// asset ids (sunwoven.citizen.foundation, …) with procedural.* debug fallbacks.
const assetRegistry = createRegistry(assetRegistryData);

// GLB prototypes are bundled as data: URLs (esbuild .glb dataurl loader) and
// parsed with GLTFLoader.parse — zero network, so the shipping CSP
// (connect-src 'none') cannot block them. Preload runs during the SwiftUI
// loading screen; units then spawn as SkeletonUtils clones of the cache.
const gltfLibrary = new GltfUnitLibrary();
gltfLibrary.registerBuffer("units/citizen_villager.glb", citizenVillagerGlb);
gltfLibrary.registerBuffer("units/pathfinder_scout.glb", pathfinderScoutGlb);

// Debug override: ?art=procedural renders every unit as its primitive
// stand-in, so the fallback path is visible and testable on device.
const forceProceduralArt = new URLSearchParams(location.search).get("art") === "procedural";

// Kick off prototype preloading immediately — while the loading screen shows.
gltfLibrary.preload(
  Object.values(assetRegistry.entries).flatMap((entry) =>
    (entry.lods ?? []).filter((lod) => lod.kind === "gltf").map((lod) => lod.gltf)
  )
);

const canvasRoot = document.getElementById("sunfold-root");
const fallback = document.getElementById("runtime-fallback");
const hud = document.getElementById("runtime-hud");
const status = document.getElementById("runtime-status");
const pauseButton = document.querySelector('[data-command="pauseGame"]');
let renderer;
let scene;
let camera;
let cameraController;
let animationFrame;
let running = false;
let paused = false;
let lastFrame = 0;
let elapsed = 0;
/** @type {UnitPresentationLayer | null} */
let presentationLayer = null;

/**
 * The one simulation this runtime owns. It is created by `startGame`,
 * recreated by `loadGame`, advanced only from render deltas through the fixed
 * clock inside it, serialised only on `saveGame`, and dropped on menu return.
 * The rules live in `sim/session.js`; the shell below only forwards commands.
 */
const session = new SimulationSession();

function postEvent(name, payload = {}, options = {}) {
  const message = createEnvelope("event", name, payload, options);
  window.webkit?.messageHandlers?.sunfold?.postMessage(message);
}

function setStatus(value) {
  if (status) status.textContent = value;
}

function reportFatal(error) {
  const message = error instanceof Error ? error.message : String(error);
  postEvent("fatalError", { code: "invalidBridgeMessage", message });
}

function reportSaveFailure(error) {
  const message = error instanceof Error ? error.message : String(error);
  postEvent("fatalError", { code: "invalidSaveDocument", message });
}

function setDPR() {
  renderer?.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
}

function makeScene() {
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x050711);

  camera = createRtsCamera(1);

  const ambient = new THREE.HemisphereLight(0x9ab5d9, 0x14172b, 1.8);
  scene.add(ambient);
  const key = new THREE.DirectionalLight(0xffd28c, 3.0);
  key.position.set(-4, 10, 5);
  scene.add(key);

  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(48, 64),
    new THREE.MeshStandardMaterial({ color: 0x4c403d, roughness: 0.94, metalness: 0 })
  );
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(2.1, 0.04, 8, 64),
    new THREE.MeshBasicMaterial({ color: 0xe2b866, transparent: true, opacity: 0.85 })
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.02;
  scene.add(ring);

  const spire = new THREE.Mesh(
    new THREE.ConeGeometry(0.65, 1.8, 6),
    new THREE.MeshStandardMaterial({ color: 0xc29b5d, roughness: 0.55, metalness: 0.12, emissive: 0x2e1808, emissiveIntensity: 0.45 })
  );
  spire.position.y = 0.9;
  scene.add(spire);

  for (let index = 0; index < 8; index += 1) {
    const angle = index * Math.PI * 2 / 8;
    const beacon = new THREE.Mesh(
      new THREE.SphereGeometry(0.09, 12, 8),
      new THREE.MeshBasicMaterial({ color: 0xffd79a })
    );
    beacon.position.set(Math.cos(angle) * 3.7, 0.18, Math.sin(angle) * 3.7);
    scene.add(beacon);
  }

  // Unit art resolves through the asset registry. The registry's authored
  // source for the Sunwoven citizen is the full-fidelity sunwoven-villager
  // sheet; the shipping build overrides it with the GPU-safe space-villager
  // atlas, bundled as a data: URL so the WKWebView CSP (connect-src 'none')
  // can bind it without a network path. Remove the override to swap art.
  // Procedural primitives (asset-registry.json procedural.* entries) are
  // visible debug fallbacks — never the shipping visual target.
  presentationLayer = new UnitPresentationLayer({
    scene,
    registry: assetRegistry,
    assetId: assetIdForUnit,
    gltfLibrary,
    camera,
    proceduralFactory: createProceduralUnit,
    forceProcedural: forceProceduralArt,
    manifests: {
      "sunwoven.citizen.foundation": {
        manifest: {
          ...spaceVillagerAtlasManifest,
          atlas: {
            ...spaceVillagerAtlasManifest.atlas,
            image: spaceVillagerAtlasPng
          }
        },
        basePath: "sprites/space-villager/"
      }
    }
  });
  presentationLayer.init().catch((error) => {
    console.error("unit presentation layer failed", error);
    setStatus("SPRITES UNAVAILABLE");
  });
  // Surface first atlas texture failure on the HUD (file:// / CSP / size).
  window.addEventListener(
    "sunfold:spriteError",
    (event) => {
      const message = event?.detail?.message || "sprite load failed";
      console.error(message);
      setStatus(`SPRITES: ${String(message).slice(0, 48)}`);
    },
    { once: true }
  );
}

function resize() {
  if (!renderer || !camera) return;
  const width = Math.max(1, canvasRoot.clientWidth);
  const height = Math.max(1, canvasRoot.clientHeight);
  renderer.setSize(width, height, false);
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  setDPR();
}

function frame(now) {
  if (!running) return;
  animationFrame = requestAnimationFrame(frame);
  const delta = Math.min((now - lastFrame) / 1000 || 0, 0.1);
  lastFrame = now;
  if (!paused) {
    elapsed += delta;
    // Render cadence only ever *offers* time; the fixed 20 Hz clock inside
    // the simulation decides how many whole steps that time is worth.
    session.update(delta);
  }
  const sim = session.simulation;
  if (presentationLayer && sim) {
    presentationLayer.sync(sim.state, paused ? 0 : delta);
  }
  renderer.render(scene, camera);
}

/** Brings the shell into the in-game presentation, starting the render loop. */
async function enterGame(faction) {
  // Wait for GLB prototypes to finish preloading (started during the loading
  // screen) so units can spawn as clones immediately. Failures were absorbed
  // by the library — the registry cascade falls back to sprites/procedural.
  setStatus("LOADING PROTOTYPES");
  await gltfLibrary.ready();
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: "high-performance" });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    canvasRoot.appendChild(renderer.domElement);
    makeScene();
    cameraController = new RtsCameraController(camera, renderer.domElement);
    resize();
    window.addEventListener("resize", resize, { passive: true });
  }
  fallback.hidden = true;
  hud.hidden = false;
  running = true;
  paused = session.paused;
  setStatus(paused ? "PAUSED" : `${String(faction || "sunwoven").toUpperCase()} // ONLINE`);
  window.dispatchEvent(new Event(paused ? "sunfold:runtimePaused" : "sunfold:runtimeResumed"));
  cancelAnimationFrame(animationFrame);
  lastFrame = performance.now();
  animationFrame = requestAnimationFrame(frame);
}

/** Frame the RTS camera on the player's civilization core (citizens spawn beside it). */
function focusPlayerCore() {
  const sim = session.simulation;
  if (!sim || !cameraController || !scene) return;
  const faction = sim.state.playerFaction;
  let core = null;
  for (const building of sim.state.buildings.ordered()) {
    if (building.kind !== "civilizationCore") continue;
    if (building.faction !== faction) continue;
    core = building;
    break;
  }
  if (!core) return;

  // Citizens stand on the expansion-facing arc; the default NE camera offset
  // sits among them. Aim at the citizen centroid and pull back so the whole
  // opening cluster (core + atlas billboards) fits the FOV.
  const citizens = [];
  for (const unit of sim.state.units.ordered()) {
    if (unit.kind !== "citizen" || unit.faction !== faction) continue;
    citizens.push(unit);
  }
  let tx = core.position.x;
  let tz = core.position.z;
  if (citizens.length > 0) {
    let sx = core.position.x;
    let sz = core.position.z;
    for (const unit of citizens) {
      sx += unit.position.x;
      sz += unit.position.z;
    }
    const n = citizens.length + 1;
    tx = sx / n;
    tz = sz / n;
  }
  cameraController.target.set(tx, 0, tz);
  cameraController.distance = Math.max(RTS_CAMERA.defaultDistance, 28);
  cameraController.update();
}

function startGame(payload) {
  session.start({ faction: payload.faction, seed: payload.seed, mapID: payload.mapID });
  enterGame(payload.faction);
  focusPlayerCore();
  postEvent("runtimeReady", { renderer: "WebGLRenderer", offline: "true", faction: payload.faction || "sunwoven" });
}

function loadGame(payload) {
  let document;
  try {
    document = JSON.parse(typeof payload.snapshot === "string" ? payload.snapshot : "");
  } catch (error) {
    reportSaveFailure(new TypeError(`The save document is not valid JSON: ${error.message}`));
    return;
  }
  let simulation;
  try {
    simulation = session.restore(document);
  } catch (error) {
    reportSaveFailure(error);
    return;
  }
  enterGame(simulation.state.playerFaction);
  focusPlayerCore();
  postEvent("runtimeReady", {
    renderer: "WebGLRenderer",
    offline: "true",
    faction: simulation.state.playerFaction || "sunwoven"
  });
}

function saveGame() {
  const document = session.save();
  if (!document) {
    reportFatal(new TypeError("saveGame arrived with no active simulation."));
    return;
  }
  postEvent(
    "saveReady",
    { snapshotID: `sunfold-${document.mapID}-tick-${document.tick}`, snapshot: JSON.stringify(document) },
    { saveSchemaVersion: SAVE_SCHEMA_VERSION }
  );
}

function pauseGame() {
  paused = true;
  session.setPaused(true);
  setStatus("PAUSED");
  window.dispatchEvent(new Event("sunfold:runtimePaused"));
  postEvent("runtimePaused");
}

function resumeGame() {
  paused = false;
  session.setPaused(false);
  setStatus("ONLINE");
  window.dispatchEvent(new Event("sunfold:runtimeResumed"));
  postEvent("runtimeResumed");
}

function returnToMenu() {
  running = false;
  presentationLayer?.dispose();
  session.dispose();
  hud.hidden = true;
  cancelAnimationFrame(animationFrame);
  postEvent("returnedToMenu");
}

function receive(message) {
  try {
    assertValidEnvelope(message);
  } catch (error) {
    reportFatal(error);
    return;
  }
  if (message.type !== "command") {
    reportFatal(new TypeError("Only command messages are accepted by the runtime."));
    return;
  }
  switch (message.name) {
    case "startGame": startGame(message.payload || {}); break;
    case "pauseGame": pauseGame(); break;
    case "resumeGame": resumeGame(); break;
    case "saveGame": saveGame(); break;
    case "loadGame": loadGame(message.payload || {}); break;
    case "returnToMenu": returnToMenu(); break;
    default: reportFatal(new TypeError(`Unknown command: ${message.name}`));
  }
}

for (const button of document.querySelectorAll("[data-command]")) {
  button.addEventListener("click", () => {
    const command = button.dataset.command;
    const request = {
      pauseGame: "pauseRequested",
      resumeGame: "resumeRequested",
      saveGame: "saveRequested",
      returnToMenu: "returnToMenuRequested"
    }[command];
    if (request) postEvent(request);
  });
}

window.addEventListener("sunfold:runtimePaused", () => {
  if (pauseButton) {
    pauseButton.dataset.command = "resumeGame";
    pauseButton.textContent = "RESUME";
  }
});

window.addEventListener("sunfold:runtimeResumed", () => {
  if (pauseButton) {
    pauseButton.dataset.command = "pauseGame";
    pauseButton.textContent = "PAUSE";
  }
});

window.sunfoldBridge = { receive, protocolVersion: BRIDGE_PROTOCOL_VERSION };
postEvent("runtimeLoaded", { renderer: "WebGLRenderer", offline: "true" });
