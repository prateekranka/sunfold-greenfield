// Builds the Sunwoven proof harness bundle into ThreeRuntime/assets/citizens.
//
//   node Tools/citizens/build-sunwoven-web.mjs
//
// Outputs (all under ThreeRuntime/assets/citizens/, self-contained offline):
//   sunwoven-lab.html            harness page
//   sunwoven-lab.bundle.js       esbuild bundle (three + GLTFLoader + harness)
//   locked-pose-sunwoven-source.png   Blender source render for the diff proof

import { createRequire } from "node:module";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const runtimeSrc = resolve(root, "ThreeRuntime/src");
const outDir = resolve(root, "ThreeRuntime/assets/citizens");

const require = createRequire(resolve(root, "ThreeRuntime/package.json"));
const { build } = require("esbuild");

await mkdir(outDir, { recursive: true });
await copyFile(resolve(runtimeSrc, "sunwoven-lab.html"), resolve(outDir, "sunwoven-lab.html"));
await copyFile(resolve(here, "build/renders/locked-pose-sunwoven-source.png"), resolve(outDir, "locked-pose-sunwoven-source.png"));
const bundlePath = resolve(outDir, "sunwoven-lab.bundle.js");
await build({
  entryPoints: [resolve(runtimeSrc, "sunwoven-lab.js")],
  bundle: true,
  format: "iife",
  target: ["chrome110"],
  minify: true,
  sourcemap: false,
  outfile: bundlePath,
});
const bundle = await readBundle(bundlePath);
await writeFile(bundlePath, bundle.replace(/[ \t]+$/gm, ""));
console.log("[build-sunwoven-web] wrote sunwoven-lab.html, sunwoven-lab.bundle.js, locked-pose-sunwoven-source.png");

async function readBundle(path) {
  const { readFile } = await import("node:fs/promises");
  return readFile(path, "utf8");
}
