// Bundle Milestone 1 lab pages into assets/citizens/*.bundle.js
import { build } from "esbuild";
import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = resolve(root, "assets/citizens");
await mkdir(outDir, { recursive: true });

const entries = [
  ["src/citizen-crowd-lab.js", "citizen-crowd-lab.bundle.js", "src/citizen-crowd-lab.html", "citizen-crowd-lab.html"],
  ["src/citizen-rts-proof.js", "citizen-rts-proof.bundle.js", "src/citizen-rts-proof.html", "citizen-rts-proof.html"]
];

for (const [entry, outfile, htmlSrc, htmlDst] of entries) {
  const useDataurlAtlas = entry.includes("crowd-lab");
  await build({
    entryPoints: [resolve(root, entry)],
    bundle: true,
    format: "iife",
    target: ["safari15"],
    minify: false,
    sourcemap: false,
    loader: useDataurlAtlas
      ? { ".json": "json", ".png": "dataurl" }
      : { ".json": "json" },
    outfile: resolve(outDir, outfile)
  });
  await copyFile(resolve(root, htmlSrc), resolve(outDir, htmlDst));
  console.log(`wrote ${outfile} + ${htmlDst}`);
}
