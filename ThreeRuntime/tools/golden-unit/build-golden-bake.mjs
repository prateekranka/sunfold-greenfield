// Bundle the golden-unit pages (esbuild, single-file IIFE):
//   bake.bundle.js      — 16-direction atlas bake
//   golden-lab.bundle.js — 48-unit perf lab + capture
import { build } from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

await build({
  entryPoints: [resolve(root, "tools/golden-unit/bake.js")],
  bundle: true,
  format: "iife",
  target: ["safari15"],
  minify: false,
  outfile: resolve(root, "tools/golden-unit/bake.bundle.js")
});
console.log("bake.bundle.js written");

await build({
  entryPoints: [resolve(root, "tools/golden-unit/golden-lab.js")],
  bundle: true,
  format: "iife",
  target: ["safari15"],
  minify: false,
  outfile: resolve(root, "tools/golden-unit/golden-lab.bundle.js")
});
console.log("golden-lab.bundle.js written");
