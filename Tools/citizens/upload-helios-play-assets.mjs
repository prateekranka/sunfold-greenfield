#!/usr/bin/env node
/**
 * Upload static assets for helios-rift-play Worker and print completion info.
 * Usage:
 *   ASSETS_UPLOAD_JWT=cfwau_... node upload-helios-play-assets.mjs
 */
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, dirname, extname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const jwt = process.env.ASSETS_UPLOAD_JWT;
if (!jwt) {
  console.error('ASSETS_UPLOAD_JWT required');
  process.exit(1);
}

let completionJwt = '';

const site = resolve(
  process.env.HELIOS_PLAY_SITE_DIR ||
    resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-play/site'),
);

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = resolve(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
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

function pagesHash(filePath) {
  const content = readFileSync(filePath);
  const extension = extname(filePath).slice(1).toLowerCase();
  return createHash('sha256').update(content.toString('base64') + extension).digest('hex').slice(0, 32);
}

const files = walk(site)
  .filter((full) => !relative(site, full).startsWith('_'))
  .map((full) => {
    const rel = '/' + relative(site, full).replace(/\\/g, '/');
    return { rel, hash: pagesHash(full), type: contentType(full), bytes: readFileSync(full) };
  });

for (const file of files) {
  const boundary = `----cfasset${Date.now()}`;
  const form = [
    `--${boundary}`,
    `Content-Disposition: form-data; name="${file.hash}"; filename="${file.hash}"`,
    `Content-Type: ${file.type}`,
    '',
    file.bytes.toString('base64'),
    `--${boundary}--`,
    '',
  ].join('\r\n');

  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/assets/upload?base64=true`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${jwt}`,
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
      },
      body: form,
    },
  );
  const json = await res.json();
  if (!json.success) {
    console.error('upload failed for', file.rel, json);
    process.exit(1);
  }
  if (json.result?.jwt) completionJwt = json.result.jwt;
  console.log('uploaded', file.rel, file.hash, file.type);
}

if (!completionJwt) {
  console.error('No completion JWT returned from asset upload');
  process.exit(1);
}
console.log('COMPLETION_JWT=' + completionJwt);
