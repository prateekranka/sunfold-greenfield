import * as THREE from "three";
import {
  BRIDGE_PROTOCOL_VERSION,
  SAVE_SCHEMA_VERSION,
  assertValidEnvelope,
  createEnvelope
} from "./protocol.js";
import { SimulationSession } from "./sim/session.js";

const canvasRoot = document.getElementById("sunfold-root");
const fallback = document.getElementById("runtime-fallback");
const hud = document.getElementById("runtime-hud");
const status = document.getElementById("runtime-status");
const pauseButton = document.querySelector('[data-command="pauseGame"]');
let renderer;
let scene;
let camera;
let animationFrame;
let running = false;
let paused = false;
let lastFrame = 0;
let elapsed = 0;

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

  camera = new THREE.PerspectiveCamera(38, 1, 0.1, 120);
  camera.position.set(0, 7.5, 12.5);
  camera.lookAt(0, 0, 0);

  const ambient = new THREE.HemisphereLight(0x9ab5d9, 0x14172b, 1.8);
  scene.add(ambient);
  const key = new THREE.DirectionalLight(0xffd28c, 3.0);
  key.position.set(-4, 10, 5);
  scene.add(key);

  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(7, 64),
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
    scene.rotation.y = Math.sin(elapsed * 0.18) * 0.025;
  }
  renderer.render(scene, camera);
}

/** Brings the shell into the in-game presentation, starting the render loop. */
function enterGame(faction) {
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: "high-performance" });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    canvasRoot.appendChild(renderer.domElement);
    makeScene();
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

function startGame(payload) {
  session.start({ faction: payload.faction, seed: payload.seed, mapID: payload.mapID });
  enterGame(payload.faction);
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
