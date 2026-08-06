// Golden-unit bake + lab static server.
//
// Serves the ThreeRuntime directory (so pages can fetch GLBs and sprite
// assets) and accepts POST bodies that land as files:
//
//   POST /save?path=sprites/sunwoven-golden/idle-albedo.png
//         body = raw PNG bytes → <ThreeRuntime>/sprites/sunwoven-golden/idle-albedo.png
//
//   POST /capture?path=captures/golden-battlefield.png  (same semantics)
//
// Usage:  node tools/golden-unit/serve.mjs [port]   (default 8788)

import { createServer } from "node:http";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, extname, resolve, sep, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.argv[2] ?? 8788);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".glb": "model/gltf-binary",
  ".svg": "image/svg+xml"
};

/** Prevent path traversal outside ROOT. */
function safePath(rel) {
  const target = normalize(rel).replace(/^[/\\]+/, "");
  const abs = resolve(ROOT, target);
  if (abs !== ROOT && !abs.startsWith(ROOT + sep)) return null;
  return abs;
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === "POST") {
      const kind = url.pathname === "/save" || url.pathname === "/capture";
      if (!kind) {
        res.writeHead(404).end("not found");
        return;
      }
      const rel = url.searchParams.get("path");
      const abs = safePath(rel ?? "");
      if (!abs || !extname(abs)) {
        res.writeHead(400).end(`bad path: ${rel}`);
        return;
      }
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      await mkdir(dirname(abs), { recursive: true });
      await writeFile(abs, Buffer.concat(chunks));
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, path: abs }));
      console.log(`saved ${abs} (${Buffer.concat(chunks).length} bytes)`);
      return;
    }
    const rel = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
    const abs = safePath(rel);
    if (!abs) {
      res.writeHead(403).end("forbidden");
      return;
    }
    try {
      const body = await readFile(abs);
      res.writeHead(200, { "content-type": MIME[extname(abs)] ?? "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404).end("not found");
    }
  } catch (error) {
    console.error(error);
    res.writeHead(500).end(String(error?.message ?? error));
  }
});

server.listen(PORT, () => {
  console.log(`golden-unit server: http://127.0.0.1:${PORT}  (root ${ROOT})`);
});
