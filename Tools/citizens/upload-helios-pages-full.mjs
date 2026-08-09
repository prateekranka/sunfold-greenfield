#!/usr/bin/env node
/**
 * Upload helios review site assets to Cloudflare Pages asset store.
 * Requires PAGES_UPLOAD_JWT (from pages project upload-token endpoint).
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const jwt = process.env.PAGES_UPLOAD_JWT;
if (!jwt) {
  console.error('PAGES_UPLOAD_JWT required');
  process.exit(1);
}

const site = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/site-publish');

function pagesHash(filePath) {
  const content = readFileSync(filePath);
  const extension = extname(filePath).slice(1).toLowerCase();
  const payload = content.toString('base64') + extension;
  return createHash('sha256').update(payload).digest('hex').slice(0, 32);
}

const files = [
  'index.html',
  'assets/01-overview-zoomed-out.png',
  'assets/02-starting-position.png',
  'assets/03-solar-core-centre.png',
  'assets/04-resource-area.png',
  'assets/05-gameplay-zoom.png',
  'assets/helios-rift-preview.mp4',
];

const manifest = {};
const entries = [];
for (const rel of files) {
  const full = resolve(site, rel);
  const hash = pagesHash(full);
  manifest[rel] = hash;
  const ext = extname(full).slice(1).toLowerCase();
  const type =
    ext === 'html' ? 'text/html' :
    ext === 'png' ? 'image/png' :
    ext === 'mp4' ? 'video/mp4' : 'application/octet-stream';
  entries.push({ rel, hash, type, bytes: readFileSync(full) });
}

const check = await fetch('https://api.cloudflare.com/client/v4/pages/assets/check-missing', {
  method: 'POST',
  headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ hashes: entries.map((e) => e.hash) }),
});
const checkJson = await check.json();
if (!checkJson.success) {
  console.error('check-missing failed', checkJson);
  process.exit(1);
}
const missing = new Set(checkJson.result ?? []);
console.log('missing', missing.size, 'of', entries.length);

const payload = entries
  .filter((e) => missing.has(e.hash))
  .map((e) => ({
    key: e.hash,
    value: e.bytes.toString('base64'),
    base64: true,
    metadata: { contentType: e.type },
  }));

if (payload.length) {
  const upload = await fetch('https://api.cloudflare.com/client/v4/pages/assets/upload', {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const uploadJson = await upload.json();
  if (!uploadJson.success) {
    console.error('upload failed', uploadJson);
    process.exit(1);
  }
  console.log('uploaded', payload.length, 'assets');
}

console.log('MANIFEST=' + JSON.stringify(manifest));
