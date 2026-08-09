// Builds the neutral-lab web harness bundle into ThreeRuntime/assets/lab.
//
//   node Tools/citizens/build-web.mjs
//
// Outputs (all under ThreeRuntime/assets/lab/, self-contained offline):
//   neutral-lab.html            harness page
//   neutral-lab.bundle.js       esbuild bundle (three + GLTFLoader + harness)
//   locked-pose-source.png      Blender source render for the diff proof
//   event-markers.json          committed marker manifest (copied by build_lab)

import { createRequire } from "node:module";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const runtimeSrc = resolve(root, "ThreeRuntime/src");
const outDir = resolve(root, "ThreeRuntime/assets/lab");

// esbuild lives in ThreeRuntime/node_modules; resolve it from there.
const require = createRequire(resolve(root, "ThreeRuntime/package.json"));
const { build } = require("esbuild");

await mkdir(outDir, { recursive: true });
await copyFile(resolve(runtimeSrc, "neutral-lab.html"), resolve(outDir, "neutral-lab.html"));
await copyFile(resolve(here, "build/renders/locked-pose-source.png"), resolve(outDir, "locked-pose-source.png"));
const bundlePath = resolve(outDir, "neutral-lab.bundle.js");
await build({
  entryPoints: [resolve(runtimeSrc, "neutral-lab.js")],
  bundle: true,
  format: "iife",
  target: ["chrome110"],
  minify: true,
  sourcemap: false,
  outfile: bundlePath,
});
const bundle = await readFile(bundlePath, "utf8");
await writeFile(bundlePath, bundle.replace(/[ \t]+$/gm, ""));
console.log("[build-web] wrote neutral-lab.html, neutral-lab.bundle.js, locked-pose-source.png");
