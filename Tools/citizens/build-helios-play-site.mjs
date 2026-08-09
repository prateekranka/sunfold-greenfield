#!/usr/bin/env node
/**
 * Assemble static site folder for Helios Rift public deploy.
 * Run from repo root or ThreeRuntime:
 *   node Tools/citizens/build-helios-play-site.mjs
 */
import { copyFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const toolsDir = resolve(dirname(fileURLToPath(import.meta.url)));
const runtime = resolve(toolsDir, '../../ThreeRuntime');
const site = resolve(toolsDir, '../../Docs/QA/helios-rift-play/site');
const atlasDir = resolve(site, 'sprites/village-manbun-wanderer');

execSync('npm run build:labs', { cwd: runtime, stdio: 'inherit' });
await mkdir(atlasDir, { recursive: true });

await copyFile(
  resolve(runtime, 'assets/citizens/helios-rift-proof.html'),
  resolve(site, 'index.html'),
);
await copyFile(
  resolve(runtime, 'assets/citizens/helios-rift-proof.bundle.js'),
  resolve(site, 'helios-rift-proof.bundle.js'),
);
await copyFile(
  resolve(runtime, 'assets/citizens/sprites/village-manbun-wanderer/runtime-atlas.png'),
  resolve(atlasDir, 'runtime-atlas.png'),
);

console.log('Built deploy site at', site);
