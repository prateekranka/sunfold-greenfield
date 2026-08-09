#!/usr/bin/env node
/**
 * Deploy helios-rift-review Worker via Cloudflare API token in CLOUDFLARE_API_TOKEN.
 * Fallback when Pages direct-upload auth is flaky from shell.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const token = process.env.CLOUDFLARE_API_TOKEN;
if (!token) {
  console.error('Set CLOUDFLARE_API_TOKEN');
  process.exit(1);
}

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const zoneId = '8841e3bf6bc649fe54ee45ccecfb2e68';
const bundlePath = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/worker-bundle.js');
const script = readFileSync(bundlePath, 'utf8');

const metadata = JSON.stringify({
  main_module: 'index.js',
  compatibility_date: '2026-08-09',
});
const boundary = '----cfworker' + Date.now();
const body = [
  `--${boundary}`,
  'Content-Disposition: form-data; name="metadata"',
  'Content-Type: application/json',
  '',
  metadata,
  `--${boundary}`,
  'Content-Disposition: form-data; name="index.js"; filename="index.js"',
  'Content-Type: application/javascript+module',
  '',
  script,
  `--${boundary}--`,
  '',
].join('\r\n');

const put = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/scripts/helios-rift-review`, {
  method: 'PUT',
  headers: {
    Authorization: `Bearer ${token}`,
    'Content-Type': `multipart/form-data; boundary=${boundary}`,
  },
  body,
});
const putJson = await put.json();
if (!putJson.success) {
  console.error('worker put failed', putJson);
  process.exit(1);
}

const route = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/workers/routes`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ pattern: 'helios.contenthelper.in/*', script: 'helios-rift-review' }),
});
const routeJson = await route.json();
console.log(JSON.stringify({ worker: putJson.success, route: routeJson.success, url: 'https://helios.contenthelper.in' }, null, 2));
