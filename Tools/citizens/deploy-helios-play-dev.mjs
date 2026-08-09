#!/usr/bin/env node
/**
 * Full redeploy to DEV: build site → upload Worker assets → deploy Worker.
 *
 * Worker: helios-rift-play-dev
 * Route:   dev.helios.contenthelper.in/*
 * Public:  https://dev.helios.contenthelper.in/
 *
 * Does NOT touch production helios-rift-play / helios.contenthelper.in.
 *
 * Usage:
 *   ASSETS_UPLOAD_JWT=<jwt> node Tools/citizens/deploy-helios-play-dev.mjs
 *   CLOUDFLARE_API_TOKEN=<token> ASSETS_UPLOAD_JWT=<jwt> node Tools/citizens/deploy-helios-play-dev.mjs
 */
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolsDir = resolve(dirname(fileURLToPath(import.meta.url)));
const workerName = 'helios-rift-play-dev';
const publicUrl = 'https://dev.helios.contenthelper.in/';
const workerDir = resolve(toolsDir, '../../Docs/QA/helios-rift-play-dev/worker');
const siteDir = resolve(toolsDir, '../../Docs/QA/helios-rift-play/site');
const token = process.env.CLOUDFLARE_API_TOKEN;
const uploadJwt = process.env.ASSETS_UPLOAD_JWT;
const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || '920d78e6c05a8e15380d6205aa3f38b4';
const zoneId = process.env.CLOUDFLARE_ZONE_ID || '8841e3bf6bc649fe54ee45ccecfb2e68';

execSync(`node ${resolve(toolsDir, 'build-helios-play-site.mjs')}`, {
  stdio: 'inherit',
  env: { ...process.env, HELIOS_PLAY_SITE_DIR: siteDir },
});

if (!uploadJwt) {
  console.log('\nNext: create assets-upload-session JWT (Cloudflare MCP) then run:');
  console.log(`  ASSETS_UPLOAD_JWT=<jwt> node Tools/citizens/deploy-helios-play-dev.mjs`);
  process.exit(0);
}

const out = execSync(`node ${resolve(toolsDir, 'upload-helios-play-assets.mjs')}`, {
  env: { ...process.env, ASSETS_UPLOAD_JWT: uploadJwt, HELIOS_PLAY_SITE_DIR: siteDir },
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
  console.log(`Deploy worker ${workerName} with keep_assets:false and assets.jwt set to COMPLETION_JWT (Cloudflare MCP).`);
  console.log(`Then attach route dev.helios.contenthelper.in/* → ${workerName}`);
  process.exit(0);
}

const script = readFileSync(resolve(workerDir, 'index.js'), 'utf8');
const headersConfig = readFileSync(resolve(siteDir, '_headers'), 'utf8');
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

const put = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/scripts/${workerName}`, {
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

const routePattern = 'dev.helios.contenthelper.in/*';
const routesRes = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/workers/routes`, {
  headers: { Authorization: `Bearer ${token}` },
});
const routesJson = await routesRes.json();
const existing = (routesJson.result ?? []).find((r) => r.pattern === routePattern);
if (existing) {
  if (existing.script !== workerName) {
    const patch = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/workers/routes/${existing.id}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ pattern: routePattern, script: workerName }),
    });
    const patchJson = await patch.json();
    if (!patchJson.success) {
      console.error('route update failed', patchJson);
      process.exit(1);
    }
    console.log('Updated route', routePattern, '→', workerName);
  }
} else {
  const create = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/workers/routes`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ pattern: routePattern, script: workerName }),
  });
  const createJson = await create.json();
  if (!createJson.success) {
    console.error('route create failed', createJson);
    process.exit(1);
  }
  console.log('Created route', routePattern, '→', workerName);
}

console.log('Deployed', publicUrl);
