#!/usr/bin/env node
/**
 * Deploy Helios Rift playable proof to Cloudflare Pages (contenthelper-helios-rift).
 * Usage:
 *   PAGES_UPLOAD_JWT=... node deploy-helios-play-pages.mjs
 * JWT from: GET /accounts/{account_id}/pages/projects/contenthelper-helios-rift/upload-token
 */
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, dirname, extname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const project = 'contenthelper-helios-rift';
const jwt = process.env.PAGES_UPLOAD_JWT;
const apiToken = process.env.CLOUDFLARE_API_TOKEN;

if (!jwt) {
  console.error('PAGES_UPLOAD_JWT required');
  process.exit(1);
}

const site = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-play/site');

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = resolve(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

function pagesHash(filePath) {
  const content = readFileSync(filePath);
  const extension = extname(filePath).slice(1).toLowerCase();
  const payload = content.toString('base64') + extension;
  return createHash('sha256').update(payload).digest('hex').slice(0, 32);
}

function contentType(filePath) {
  const ext = extname(filePath).slice(1).toLowerCase();
  return (
    ext === 'html' ? 'text/html; charset=utf-8' :
    ext === 'js' ? 'application/javascript; charset=utf-8' :
    ext === 'png' ? 'image/png' :
    ext === 'json' ? 'application/json' :
    'application/octet-stream'
  );
}

const files = walk(site);
const entries = files.map((full) => {
  const rel = relative(site, full).replace(/\\/g, '/');
  const hash = pagesHash(full);
  return { rel, hash, type: contentType(full), bytes: readFileSync(full) };
});

const manifest = Object.fromEntries(entries.map((e) => [e.rel, e.hash]));
console.log('files', entries.length, 'manifest keys', Object.keys(manifest));

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
console.log('missing assets', missing.size, 'of', entries.length);

const payload = entries
  .filter((e) => missing.has(e.hash))
  .map((e) => ({
    key: e.hash,
    value: e.bytes.toString('base64'),
    base64: true,
    metadata: { contentType: e.type },
  }));

for (let i = 0; i < payload.length; i += 3) {
  const batch = payload.slice(i, i + 3);
  const upload = await fetch('https://api.cloudflare.com/client/v4/pages/assets/upload', {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(batch),
  });
  const uploadJson = await upload.json();
  if (!uploadJson.success) {
    console.error('upload failed', uploadJson);
    process.exit(1);
  }
  console.log('uploaded batch', i / 3 + 1, `(${batch.length} files)`);
}

const boundary = `----cfpages${Date.now()}`;
const form = [
  `--${boundary}`,
  'Content-Disposition: form-data; name="manifest"',
  'Content-Type: application/json',
  '',
  JSON.stringify(manifest),
  `--${boundary}`,
  'Content-Disposition: form-data; name="branch"',
  '',
  'main',
  `--${boundary}--`,
  '',
].join('\r\n');

const deployAuth = apiToken ? `Bearer ${apiToken}` : `Bearer ${jwt}`;
const deploy = await fetch(
  `https://api.cloudflare.com/client/v4/accounts/${accountId}/pages/projects/${project}/deployments`,
  {
    method: 'POST',
    headers: {
      Authorization: deployAuth,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
    },
    body: form,
  },
);
const deployJson = await deploy.json();
if (!deployJson.success) {
  console.error('deployment failed', JSON.stringify(deployJson, null, 2));
  process.exit(1);
}

const d = deployJson.result;
console.log(JSON.stringify({
  success: true,
  id: d.id,
  url: d.url,
  environment: d.environment,
  aliases: d.aliases,
  stage: d.latest_stage,
}, null, 2));
