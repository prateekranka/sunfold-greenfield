import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const assets = resolve(root, "ThreeRuntime/assets/citizens");
const outDir = resolve(root, "Tools/citizens/build/sprite-lab-proof");
const profile = resolve(outDir, "chrome-profile");
const port = 9232;
const pagePort = 8765;

await mkdir(outDir, { recursive: true });

const server = spawn("python3", ["-m", "http.server", String(pagePort), "--directory", assets], {
  stdio: "ignore",
});
const chrome = spawn(
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    "--disable-background-networking",
    "--no-first-run",
    "about:blank",
  ],
  { stdio: "ignore" },
);

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForJSON(url, options) {
  for (let i = 0; i < 80; i += 1) {
    try {
      const res = await fetch(url, options);
      if (res.ok) return res.json();
    } catch {}
    await delay(100);
  }
  throw new Error(`Timed out: ${url}`);
}

function decodeDataURL(value) {
  return Buffer.from(value.slice(value.indexOf(",") + 1), "base64");
}

try {
  await delay(400);
  const target = await waitForJSON(
    `http://127.0.0.1:${port}/json/new?http://127.0.0.1:${pagePort}/sprite-lab.html`,
    { method: "PUT" },
  );
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolvePromise, reject) => {
    socket.addEventListener("open", resolvePromise, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  let seq = 0;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    const cb = pending.get(msg.id);
    if (cb) {
      pending.delete(msg.id);
      cb(msg);
    }
  });
  const send = (method, params = {}) =>
    new Promise((resolvePromise) => {
      const id = ++seq;
      pending.set(id, resolvePromise);
      socket.send(JSON.stringify({ id, method, params }));
    });
  const evaluate = (expression) =>
    send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });

  for (let i = 0; i < 120; i += 1) {
    const res = await evaluate("window.spriteLab?.unit ? 'ready' : null");
    if (res.result?.result?.value === "ready") break;
    await delay(100);
  }
  await evaluate("window.spriteLab.setClip('walk')");
  await delay(600);
  const shot = await send("Page.captureScreenshot", { format: "png" });
  await writeFile(resolve(outDir, "walk-straight-line.png"), decodeDataURL(shot.result.data));
  const meta = await evaluate(
    "JSON.stringify({ clip: window.spriteLab.unit.clip, facing: window.spriteLab.unit.facing, pos: window.spriteLab.unit.group.position.toArray(), manifestFps: window.spriteLab.unit.manifest.clips.walk.fps })",
  );
  await writeFile(
    resolve(outDir, "walk-proof.json"),
    `${meta.result?.result?.value ?? "{}"}\n`,
  );
  socket.close();
  console.log(`[capture-sprite-lab] wrote ${outDir}/walk-straight-line.png`);
} finally {
  chrome.kill("SIGTERM");
  server.kill("SIGTERM");
}
