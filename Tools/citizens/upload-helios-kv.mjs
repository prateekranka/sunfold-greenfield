#!/usr/bin/env node
/**
 * Upload Helios review media to Cloudflare KV via REST API.
 * Requires: CLOUDFLARE_API_TOKEN (or wrangler OAuth — run `npx wrangler login` first).
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const namespaceId = '5dcf1b5efb9d4ddfa945f6ca468be548';
const token = process.env.CLOUDFLARE_API_TOKEN;

if (!token) {
  console.error('Set CLOUDFLARE_API_TOKEN or run via Cloudflare MCP execute.');
  process.exit(1);
}

const kvDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../Docs/QA/helios-rift-review/kv-uploads',
);
const keys = [
  '01-overview',
  '02-starting',
  '03-core',
  '04-resource',
  '05-gameplay',
  'preview-mp4',
];

async function putKv(key, value) {
  const url = `https://api.cloudflare.com/client/v4/accounts/${accountId}/storage/kv/namespaces/${namespaceId}/values/${encodeURIComponent(key)}`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'text/plain',
    },
    body: value,
  });
  const json = await res.json();
  if (!json.success) {
    throw new Error(`${key}: ${JSON.stringify(json.errors)}`);
  }
  return json;
}

for (const key of keys) {
  const b64 = readFileSync(resolve(kvDir, `${key}.b64`), 'utf8').trim();
  process.stdout.write(`Uploading ${key} (${b64.length} chars)...`);
  await putKv(key, b64);
  console.log(' OK');
}

console.log('All 6 media keys uploaded.');
