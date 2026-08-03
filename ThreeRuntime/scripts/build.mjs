import { build } from "esbuild";
import { mkdir, rm, copyFile } from "node:fs/promises";
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
  outfile: resolve(outputDir, "sunfold-runtime.js")
});
