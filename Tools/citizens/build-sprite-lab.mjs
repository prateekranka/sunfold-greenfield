// Builds the AoE2-style sprite proof lab into ThreeRuntime/assets/citizens.
//
//   node Tools/citizens/build-sprite-lab.mjs
//
// Run bootstrap-sunwoven-sprites.py first if sprites are missing.

import { createRequire } from "node:module";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const runtimeSrc = resolve(root, "ThreeRuntime/src");
const outDir = resolve(root, "ThreeRuntime/assets/citizens");
const htmlSrc = resolve(runtimeSrc, "sprite-lab.html");
const htmlOut = resolve(outDir, "sprite-lab.html");
const bundleOut = resolve(outDir, "sprite-lab.bundle.js");

const require = createRequire(resolve(root, "ThreeRuntime/package.json"));
const { build } = require("esbuild");

await mkdir(outDir, { recursive: true });

await build({
  entryPoints: [resolve(runtimeSrc, "sprite-lab.js")],
  bundle: true,
  format: "iife",
  target: ["chrome110"],
  minify: true,
  sourcemap: false,
  outfile: bundleOut,
});

const bust = Date.now();
let html = await readFile(htmlSrc, "utf8");
html = html.replace(
  /sprite-lab\.bundle\.js(\?[^"']*)?/,
  `sprite-lab.bundle.js?v=${bust}`
);
await writeFile(htmlOut, html);

console.log("[build-sprite-lab] wrote sprite-lab.html + sprite-lab.bundle.js under assets/citizens/");
