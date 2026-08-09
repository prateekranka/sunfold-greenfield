#!/usr/bin/env node
/**
 * Generate per-asset KV upload payloads for helios review pack.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/site');
const outDir = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/kv-uploads');

const routes = [
  { path: '/', file: 'index.html', key: 'index', type: 'text/html; charset=utf-8' },
  { path: '/assets/01-overview-zoomed-out.png', file: 'assets/01-overview-zoomed-out.png', key: '01-overview', type: 'image/png' },
  { path: '/assets/02-starting-position.png', file: 'assets/02-starting-position.png', key: '02-starting', type: 'image/png' },
  { path: '/assets/03-solar-core-centre.png', file: 'assets/03-solar-core-centre.png', key: '03-core', type: 'image/png' },
  { path: '/assets/04-resource-area.png', file: 'assets/04-resource-area.png', key: '04-resource', type: 'image/png' },
  { path: '/assets/05-gameplay-zoom.png', file: 'assets/05-gameplay-zoom.png', key: '05-gameplay', type: 'image/png' },
  { path: '/assets/helios-rift-preview.mp4', file: 'assets/helios-rift-preview.mp4', key: 'preview-mp4', type: 'video/mp4' },
];

const manifest = routes.map((r) => {
  const bytes = readFileSync(resolve(site, r.file));
  const b64 = bytes.toString('base64');
  return { ...r, b64Len: b64.length, bytesLen: bytes.length };
});

writeFileSync(resolve(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
for (const item of manifest) {
  writeFileSync(resolve(outDir, `${item.key}.b64`), readFileSync(resolve(site, item.file)).toString('base64'));
}
console.log('wrote', manifest.length, 'assets to', outDir);
