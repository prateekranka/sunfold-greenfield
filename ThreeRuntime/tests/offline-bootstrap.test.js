import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceHTML = await readFile(path.join(root, "src/index.html"), "utf8");
const sourceRuntime = await readFile(path.join(root, "src/main.js"), "utf8");
const generatedHTML = await readFile(path.join(root, "../Resources/ThreeRuntime/index.html"), "utf8");
const generatedRuntime = await readFile(path.join(root, "../Resources/ThreeRuntime/sunfold-runtime.js"), "utf8");

test("HTML has a local-only CSP and local runtime script", () => {
  assert.match(sourceHTML, /connect-src 'none'/);
  assert.match(sourceHTML, /script src="sunfold-runtime\.js"/);
  assert.doesNotMatch(sourceHTML, /https?:\/\//i);
  assert.equal(generatedHTML, sourceHTML);
});

test("runtime fallback clears when the runtime marks itself ready", () => {
  assert.match(sourceHTML, /#runtime-fallback\[hidden\], #runtime-hud\[hidden\] \{ display: none; \}/);
  assert.match(sourceRuntime, /fallback\.hidden = true/);
  assert.match(sourceRuntime, /postEvent\("runtimeReady"/);
  assert.match(generatedHTML, /#runtime-fallback\[hidden\]/);
});

test("runtime HUD buttons remain interactive above the WebGL canvas", () => {
  assert.match(sourceHTML, /#runtime-hud button \{[^}]*pointer-events: auto;/);
  assert.match(generatedHTML, /#runtime-hud button \{[^}]*pointer-events: auto;/);
});

test("runtime uses bundled WebGLRenderer and contains no remote fetch path", () => {
  assert.match(sourceRuntime, /new THREE\.WebGLRenderer/);
  assert.doesNotMatch(sourceRuntime, /fetch\s*\(|XMLHttpRequest|https?:\/\//i);
  assert.match(generatedRuntime, /WebGLRenderer/);
  assert.match(generatedRuntime, /BRIDGE_PROTOCOL_VERSION|protocolVersion/);
});

test("runtime bridge surface contains only high-level lifecycle messages", () => {
  assert.match(sourceRuntime, /runtimeLoaded/);
  assert.match(sourceRuntime, /runtimeReady/);
  assert.match(sourceRuntime, /saveReady/);
  assert.doesNotMatch(sourceRuntime, /postEvent\("(?:unit|units|frame|camera|selection|animation)/i);
});

test("a restored paused match renders paused status before the first frame", () => {
  assert.match(
    sourceRuntime,
    /paused = session\.paused;\s*setStatus\(paused \? "PAUSED"/,
    "enterGame must derive the initial HUD status from restored simulation state"
  );
});
