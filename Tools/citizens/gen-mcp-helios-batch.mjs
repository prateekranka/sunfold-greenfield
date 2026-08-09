#!/usr/bin/env node
/**
 * Generate MCP execute JSON args for each KV upload + worker deploy.
 * Parent agent reads /tmp/mcp-helios/*.json and calls user-cloudflare execute.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const outDir = '/tmp/mcp-helios';
mkdirSync(outDir, { recursive: true });

const callsDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../Docs/QA/helios-rift-review/mcp-kv-calls',
);
const keys = ['index', '01-overview', '02-starting', '03-core', '04-resource', '05-gameplay', 'preview-mp4'];

for (const key of keys) {
  const code = readFileSync(resolve(callsDir, `${key}.code.txt`), 'utf8');
  writeFileSync(resolve(outDir, `kv-${key}.json`), JSON.stringify({ code }));
  console.log('kv', key, code.length);
}

const ns = '5dcf1b5efb9d4ddfa945f6ca468be548';
const workerScript = `const ROUTES = {
  '/': { key: 'index', type: 'text/html; charset=utf-8' },
  '/assets/01-overview-zoomed-out.png': { key: '01-overview', type: 'image/png' },
  '/assets/02-starting-position.png': { key: '02-starting', type: 'image/png' },
  '/assets/03-solar-core-centre.png': { key: '03-core', type: 'image/png' },
  '/assets/04-resource-area.png': { key: '04-resource', type: 'image/png' },
  '/assets/05-gameplay-zoom.png': { key: '05-gameplay', type: 'image/png' },
  '/assets/helios-rift-preview.mp4': { key: 'preview-mp4', type: 'video/mp4' },
};

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\\/$/, '') || '/';
    const route = ROUTES[path];
    if (!route) return new Response('Not found', { status: 404 });
    const b64 = await env.HELIOS_ASSETS.get(route.key);
    if (!b64) return new Response('Missing asset: ' + route.key, { status: 404 });
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    return new Response(bytes, {
      headers: {
        'content-type': route.type,
        'cache-control': 'public, max-age=3600',
      },
    });
  },
};
`;

const workerCode = [
  'async () => {',
  `  const ns = '${ns}';`,
  `  const script = ${JSON.stringify(workerScript)};`,
  '  const metadata = JSON.stringify({',
  '    main_module: "index.js",',
  '    compatibility_date: "2026-08-09",',
  '    bindings: [{ type: "kv_namespace", name: "HELIOS_ASSETS", namespace_id: ns }],',
  '  });',
  "  const boundary = '----cfworker' + Date.now();",
  '  const body = [',
  "    `--${boundary}`,",
  "    'Content-Disposition: form-data; name=\"metadata\"',",
  "    'Content-Type: application/json',",
  "    '',",
  "    metadata,",
  "    `--${boundary}`,",
  "    'Content-Disposition: form-data; name=\"index.js\"; filename=\"index.js\"',",
  "    'Content-Type: application/javascript+module',",
  "    '',",
  "    script,",
  "    `--${boundary}--`,",
  "    '',",
  "  ].join('\\r\\n');",
  '  const put = await cloudflare.request({',
  "    method: 'PUT',",
  "    path: `/accounts/${accountId}/workers/scripts/helios-rift-review`,",
  '    body,',
  "    contentType: `multipart/form-data; boundary=${boundary}`,",
  '    rawBody: true,',
  '  });',
  '  return { success: put.success, status: put.status, errors: put.errors };',
  '}',
].join('\n');

writeFileSync(resolve(outDir, 'deploy-worker.json'), JSON.stringify({ code: workerCode }));
console.log('worker', workerCode.length);
