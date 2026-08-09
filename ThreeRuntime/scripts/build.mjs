import { build } from "esbuild";
import { cp, mkdir, rm, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputDir = resolve(root, "../Resources/ThreeRuntime");

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await copyFile(resolve(root, "src/index.html"), resolve(outputDir, "index.html"));
await build({
  entryPoints: [resolve(root, "src/main.js")],
  bundle: true,
  format: "iife",
  target: ["safari15"],
  minify: false,
  sourcemap: false,
  loader: { ".json": "json", ".png": "dataurl", ".glb": "dataurl" },
  outfile: resolve(outputDir, "sunfold-runtime.js")
});

// Ship GLB prototypes next to the runtime. The shipping build bundles them as
// data: URLs (esbuild dataurl loader) so the WKWebView CSP (connect-src 'none')
// can parse them with GLTFLoader.parse — zero network. The copied files serve
// the dev/lab fetch path under a permissive CSP.
const unitsSrc = resolve(root, "assets/units");
const unitsDst = resolve(outputDir, "units");
await cp(unitsSrc, unitsDst, {
  recursive: true,
  filter: (src) => !src.endsWith(".import")
});

// Ship atlas-backed sprite sheets next to the runtime (UV playback loads these).
const spriteSrc = resolve(root, "assets/citizens/sprites");
const spriteDst = resolve(outputDir, "sprites");
await cp(spriteSrc, spriteDst, {
  recursive: true,
  filter: (src) => {
    // Keep atlas payloads + manifests; skip per-frame trees and Godot .import noise.
    if (src.endsWith(".import")) return false;
    const base = src.split("/").pop();
    if (!base) return true;
    if (base === "idle" || base === "walk" || base === "gather" || base === "build") {
      return false;
    }
    return true;
  }
});
