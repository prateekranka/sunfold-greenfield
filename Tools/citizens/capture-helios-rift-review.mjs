#!/usr/bin/env node
/**
 * Headless CDP capture for Helios Rift review pack.
 * Uses the Argent-managed Chromium on :9222 (no external Chrome).
 */
import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const outDir = resolve(root, "Docs/QA/helios-rift-review");
const CDP_PORT = 9222;
const TARGET_URL = "http://localhost:4177/helios-rift-proof";
const DEFAULT_DIST = 16;
const MAX_DIST = 41.25;

const VIEWS = [
  { file: "01-overview-zoomed-out.png", x: 0, z: 0, distance: 40 },
  { file: "02-starting-position.png", x: 0, z: -32, distance: 22 },
  { file: "03-solar-core-centre.png", x: 0, z: 0, distance: 18 },
  { file: "04-resource-area.png", x: -4, z: -29, distance: 14 },
  { file: "05-gameplay-zoom.png", x: 0, z: -32, distance: DEFAULT_DIST }
];

const VIDEO_FRAMES_DIR = resolve(outDir, ".video-frames");

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForJSON(url, options) {
  let lastError;
  for (let i = 0; i < 80; i += 1) {
    try {
      const res = await fetch(url, options);
      if (res.ok) return res.json();
    } catch (e) {
      lastError = e;
    }
    await delay(150);
  }
  throw lastError ?? new Error(`Timed out: ${url}`);
}

function decodeDataURL(value) {
  return Buffer.from(value.slice(value.indexOf(",") + 1), "base64");
}

async function connectPage(url) {
  const list = await waitForJSON(`http://127.0.0.1:${CDP_PORT}/json/list`);
  const target = list.find((t) => t.type === "page");
  if (!target) throw new Error("No Chromium page target on CDP");
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolvePromise, reject) => {
    socket.addEventListener("open", resolvePromise, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  let seq = 0;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      const cb = pending.get(msg.id);
      pending.delete(msg.id);
      cb(msg);
    }
    if (msg.method === "Page.screencastFrame" && screencastHandler) {
      screencastHandler(msg.params);
    }
  });

  const send = (method, params = {}) =>
    new Promise((resolvePromise) => {
      const id = ++seq;
      pending.set(id, resolvePromise);
      socket.send(JSON.stringify({ id, method, params }));
    });

  const evaluate = async (expression) => {
    const res = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (res.result?.exceptionDetails) {
      throw new Error(JSON.stringify(res.result.exceptionDetails));
    }
    return res.result?.result?.value;
  };

  let screencastHandler = null;
  const setScreencastHandler = (fn) => {
    screencastHandler = fn;
  };

  await send("Page.enable");
  await send("Runtime.enable");

  if (!target.url?.includes("helios-rift-proof")) {
    await send("Page.navigate", { url });
    for (let i = 0; i < 80; i += 1) {
      const ready = await evaluate("document.readyState");
      if (ready === "complete") break;
      await delay(150);
    }
    await delay(800);
  }

  return { socket, send, evaluate, setScreencastHandler };
}

async function waitForProof(evaluate) {
  for (let i = 0; i < 120; i += 1) {
    const ready = await evaluate("Boolean(globalThis.__heliosRiftProof?.setView)");
    if (ready) return;
    await delay(200);
  }
  throw new Error("__heliosRiftProof not ready");
}

async function setView(evaluate, x, z, distance) {
  await evaluate(`globalThis.__heliosRiftProof.setView(${x}, ${z}, ${distance})`);
  await delay(350);
}

async function capturePNG(send, evaluate) {
  await evaluate("new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))");
  const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  return Buffer.from(shot.result.data, "base64");
}

async function recordVideo(send, evaluate, setScreencastHandler) {
  await mkdir(VIDEO_FRAMES_DIR, { recursive: true });
  const frames = [];
  let frameIdx = 0;

  setScreencastHandler(async (params) => {
    const name = `frame-${String(frameIdx).padStart(4, "0")}.jpg`;
    frameIdx += 1;
    const buf = Buffer.from(params.data, "base64");
    const path = resolve(VIDEO_FRAMES_DIR, name);
    await writeFile(path, buf);
    frames.push(path);
    await send("Page.screencastFrameAck", { sessionId: params.sessionId });
  });

  await send("Page.startScreencast", {
    format: "jpeg",
    quality: 82,
    maxWidth: 1280,
    maxHeight: 720,
    everyNthFrame: 1
  });

  const tour = [
    { x: 0, z: 0, distance: 40, hold: 2200 },
    { x: 0, z: -32, distance: 22, hold: 2800 },
    { x: -4, z: -29, distance: 14, hold: 2500 },
    { x: 18, z: -18, distance: 20, hold: 2200 },
    { x: 0, z: 0, distance: 18, hold: 2800 }
  ];

  for (const step of tour) {
    await setView(evaluate, step.x, step.z, step.distance);
    await delay(step.hold);
  }

  await send("Page.stopScreencast");
  await delay(300);
  return frames;
}

async function ffmpegEncode(frames, output) {
  if (!frames.length) throw new Error("No screencast frames captured");
  const pattern = resolve(VIDEO_FRAMES_DIR, "frame-%04d.jpg");
  return new Promise((resolvePromise, reject) => {
    const proc = spawn(
      "ffmpeg",
      ["-y", "-framerate", "12", "-i", pattern, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", output],
      { stdio: "inherit" }
    );
    proc.on("exit", (code) => (code === 0 ? resolvePromise() : reject(new Error(`ffmpeg exit ${code}`))));
  });
}

async function main() {
  await mkdir(outDir, { recursive: true });
  const { socket, send, evaluate, setScreencastHandler } = await connectPage(TARGET_URL);
  try {
    await waitForProof(evaluate);

    for (const view of VIEWS) {
      await setView(evaluate, view.x, view.z, view.distance);
      const png = await capturePNG(send, evaluate);
      const path = resolve(outDir, view.file);
      await writeFile(path, png);
      console.log(`wrote ${path}`);
    }

    const frames = await recordVideo(send, evaluate, setScreencastHandler);
    const mp4 = resolve(outDir, "helios-rift-preview.mp4");
    await ffmpegEncode(frames, mp4);
    console.log(`wrote ${mp4} (${frames.length} frames)`);
  } finally {
    socket.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
