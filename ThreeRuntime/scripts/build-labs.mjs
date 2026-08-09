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
  ["src/citizen-rts-proof.js", "citizen-rts-proof.bundle.js", "src/citizen-rts-proof.html", "citizen-rts-proof.html"],
  ["src/helios-rift-proof.js", "helios-rift-proof.bundle.js", "src/helios-rift-proof.html", "helios-rift-proof.html"],
  ["src/lumen-guard-proof.js", "lumen-guard-proof.bundle.js", "src/lumen-guard-proof.html", "lumen-guard-proof.html"]
];

const onlyIndex = process.argv.indexOf("--only");
const only = onlyIndex >= 0 ? process.argv[onlyIndex + 1] : null;
const selectedEntries = only ? entries.filter(([entry]) => entry.includes(only)) : entries;
if (only && selectedEntries.length === 0) {
  throw new RangeError(`unknown lab entry requested by --only: ${only}`);
}

for (const [entry, outfile, htmlSrc, htmlDst] of selectedEntries) {
  const useDataurlAtlas = entry.includes("crowd-lab");
  const useBundledGlb = entry.includes("helios-rift-proof");
  await build({
    absWorkingDir: root,
    entryPoints: [resolve(root, entry)],
    bundle: true,
    format: "iife",
    target: ["safari15"],
    minify: false,
    sourcemap: false,
    loader: {
      ".json": "json",
      ...(useDataurlAtlas ? { ".png": "dataurl" } : {}),
      ...(useBundledGlb ? { ".glb": "dataurl" } : {})
    },
    outfile: resolve(outDir, outfile)
  });
  await copyFile(resolve(root, htmlSrc), resolve(outDir, htmlDst));
  console.log(`wrote ${outfile} + ${htmlDst}`);
}
