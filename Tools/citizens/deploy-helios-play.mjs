#!/usr/bin/env node
/**
 * Full redeploy: build site → upload Worker assets → deploy Worker (keep_assets).
 *
 * Requires Cloudflare API access via one of:
 *   - Cloudflare MCP execute (recommended)
 *   - CLOUDFLARE_API_TOKEN env var
 *
 * Quick local steps:
 *   1. node Tools/citizens/build-helios-play-site.mjs
 *   2. Get ASSETS_UPLOAD_JWT from Pages upload-token or workers assets-upload-session (MCP)
 *   3. ASSETS_UPLOAD_JWT=... node Tools/citizens/upload-helios-play-assets.mjs
 *      → prints COMPLETION_JWT=...
 *   4. Deploy worker with COMPLETION_JWT via MCP or CLOUDFLARE_API_TOKEN
 *
 * Public URL: https://helios.contenthelper.in/
 */
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolsDir = resolve(dirname(fileURLToPath(import.meta.url)));
const token = process.env.CLOUDFLARE_API_TOKEN;
const uploadJwt = process.env.ASSETS_UPLOAD_JWT;

execSync(`node ${resolve(toolsDir, 'build-helios-play-site.mjs')}`, { stdio: 'inherit' });

if (!uploadJwt) {
  console.log('\nNext: create assets-upload-session JWT (Cloudflare MCP) then run:');
  console.log('  ASSETS_UPLOAD_JWT=<jwt> node Tools/citizens/upload-helios-play-assets.mjs');
  process.exit(0);
}

const out = execSync(`node ${resolve(toolsDir, 'upload-helios-play-assets.mjs')}`, {
  env: { ...process.env, ASSETS_UPLOAD_JWT: uploadJwt },
  encoding: 'utf8',
});
const match = out.match(/COMPLETION_JWT=(.+)/);
if (!match) {
  console.error('No COMPLETION_JWT from upload step');
  process.exit(1);
}
const completionJwt = match[1].trim();

if (!token) {
  console.log('\nCOMPLETION_JWT=' + completionJwt);
  console.log('Deploy worker helios-rift-play with keep_assets:true and assets.jwt set to COMPLETION_JWT (Cloudflare MCP).');
  process.exit(0);
}

const script = readFileSync(resolve(toolsDir, '../../Docs/QA/helios-rift-play/worker/index.js'), 'utf8');
const headersConfig = readFileSync(resolve(toolsDir, '../../Docs/QA/helios-rift-play/site/_headers'), 'utf8');
const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const meta = {
  main_module: 'index.js',
  compatibility_date: '2026-08-09',
  bindings: [{ type: 'assets', name: 'ASSETS' }],
  keep_assets: false,
  assets: {
    jwt: completionJwt,
    config: {
      html_handling: 'auto-trailing-slash',
      not_found_handling: 'none',
      run_worker_first: true,
      _headers: headersConfig,
    },
  },
};
const boundary = `----cfworker${Date.now()}`;
const body = [
  `--${boundary}`,
  'Content-Disposition: form-data; name="metadata"',
  'Content-Type: application/json',
  '',
  JSON.stringify(meta),
  `--${boundary}`,
  'Content-Disposition: form-data; name="index.js"; filename="index.js"',
  'Content-Type: application/javascript+module',
  '',
  script,
  `--${boundary}--`,
  '',
].join('\r\n');

const put = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/scripts/helios-rift-play`, {
  method: 'PUT',
  headers: {
    Authorization: `Bearer ${token}`,
    'Content-Type': `multipart/form-data; boundary=${boundary}`,
  },
  body,
});
const putJson = await put.json();
if (!putJson.success) {
  console.error(putJson);
  process.exit(1);
}
console.log('Deployed https://helios.contenthelper.in/');
