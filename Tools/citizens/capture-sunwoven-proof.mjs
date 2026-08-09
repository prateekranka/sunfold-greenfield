// Captures the Sunwoven sequence proof from headless Chrome.
//
//   node Tools/citizens/capture-sunwoven-proof.mjs
//
// Serves ThreeRuntime/assets/citizens, loads sunwoven-lab.html?proof=1, waits
// for the ~24 s authored sequence to finish, then writes:
//   Tools/citizens/build/browser-proof-sunwoven.json
//   Tools/citizens/build/renders/sunwoven-seq-<label>.png  (per capture frame)

import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const assets = resolve(root, "ThreeRuntime/assets/citizens");
const build = resolve(root, "Tools/citizens/build");
const renders = resolve(build, "renders");
const profile = resolve(build, "chrome-sunwoven-profile");
const port = 9232;

await mkdir(renders, { recursive: true });
await rm(profile, { recursive: true, force: true });
await mkdir(profile, { recursive: true });

const server = spawn("python3", ["-m", "http.server", "8767", "--directory", assets], { stdio: "ignore" });
const chrome = spawn(
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    "--disable-background-networking",
    "--disable-default-apps",
    "--disable-extensions",
    "--no-first-run",
    "about:blank",
  ],
  { stdio: "ignore" },
);

const delay = (ms) => new Promise((resolvePromise) => setTimeout(resolvePromise, ms));

async function waitForJSON(url, options) {
  let lastError;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(url, options);
      if (response.ok) return response.json();
    } catch (error) {
      lastError = error;
    }
    await delay(100);
  }
  throw lastError ?? new Error(`Timed out waiting for ${url}`);
}

function decodeDataURL(value) {
  return Buffer.from(value.slice(value.indexOf(",") + 1), "base64");
}

try {
  const target = await waitForJSON(
    `http://127.0.0.1:${port}/json/new?http://127.0.0.1:8767/sunwoven-lab.html?proof=1`,
    { method: "PUT" },
  );
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolvePromise, reject) => {
    socket.addEventListener("open", resolvePromise, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  let sequence = 0;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    const callback = pending.get(message.id);
    if (callback) {
      pending.delete(message.id);
      callback(message);
    }
  });
  const evaluate = (expression) =>
    new Promise((resolvePromise) => {
      const id = ++sequence;
      pending.set(id, resolvePromise);
      socket.send(JSON.stringify({ id, method: "Runtime.evaluate", params: { expression, returnByValue: true } }));
    });

  let proof;
  for (let attempt = 0; attempt < 400; attempt += 1) {
    const result = await evaluate(
      "window.sunwovenProof ? JSON.stringify(window.sunwovenProof) : null"
    );
    const value = result.result?.result?.value;
    if (value) {
      proof = JSON.parse(value);
      break;
    }
    await delay(250);
  }
  if (!proof) throw new Error("Sunwoven sequence proof did not complete in time.");

  await writeFile(resolve(build, "browser-proof-sunwoven.json"), `${JSON.stringify(proof, null, 2)}\n`);
  for (const [label, dataURL] of Object.entries(proof.captures)) {
    await writeFile(resolve(renders, `sunwoven-seq-${label}.png`), decodeDataURL(dataURL));
  }
  socket.close();
  console.log(
    JSON.stringify(
      {
        ok: proof.ok,
        clips: proof.clip_inventory_matches_manifest,
        events: proof.sequence.event_trace.length,
        facts: proof.facts,
        captures: Object.keys(proof.captures),
      },
      null,
      2,
    )
  );
} finally {
  chrome.kill("SIGTERM");
  server.kill("SIGTERM");
  await Promise.race([
    new Promise((resolvePromise) => chrome.once("exit", resolvePromise)),
    delay(2000),
  ]);
  await rm(profile, { recursive: true, force: true });
}
