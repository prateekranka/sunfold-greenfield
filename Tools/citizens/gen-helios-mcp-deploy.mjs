#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const bundlePath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../Docs/QA/helios-rift-review/worker-bundle.js',
);
const script = readFileSync(bundlePath, 'utf8');
const b64 = Buffer.from(script, 'utf8').toString('base64');
const outPath = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/mcp-deploy-code.json');

const code = [
  'async () => {',
  "  const accountId = '920d78e6c05a8e15380d6205aa3f38b4';",
  `  const script = new TextDecoder().decode(Uint8Array.from(atob(${JSON.stringify(b64)}), (c) => c.charCodeAt(0)));`,
  "  const metadata = JSON.stringify({ main_module: 'index.js', compatibility_date: '2026-08-09' });",
  "  const boundary = '----cfworker' + Date.now();",
  "  const body = [",
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
  "  const put = await cloudflare.request({",
  "    method: 'PUT',",
  "    path: `/accounts/${accountId}/workers/scripts/helios-rift-review`,",
  "    body,",
  "    contentType: `multipart/form-data; boundary=${boundary}`,",
  "    rawBody: true,",
  "  });",
  "  return { success: put.success, status: put.status, errors: put.errors, scriptBytes: script.length };",
  '}',
].join('\n');

writeFileSync(outPath, JSON.stringify({ code }));
console.log('wrote', outPath, `code ${code.length} chars, bundle ${script.length} bytes`);
