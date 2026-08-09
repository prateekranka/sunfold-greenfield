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
const site = resolve(
  process.env.HELIOS_PLAY_SITE_DIR ||
    resolve(toolsDir, '../../Docs/QA/helios-rift-play/site'),
);
const citizenAtlasDir = resolve(site, 'sprites/village-manbun-wanderer');
const guardAtlasDir = resolve(site, 'sprites/lumen-guard');

execSync(`npm run build:labs`, { cwd: runtime, stdio: 'inherit' });
await mkdir(citizenAtlasDir, { recursive: true });
await mkdir(guardAtlasDir, { recursive: true });

await copyFile(
  resolve(toolsDir, '../../Docs/QA/helios-rift-play/robots.txt'),
  resolve(site, 'robots.txt'),
);

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
  resolve(citizenAtlasDir, 'runtime-atlas.png'),
);
// Quantize the deploy copy (source atlas stays bit-exact; saves ~13MB on first load).
execSync(
  `${process.env.PYTHON || 'python3'} ${resolve(toolsDir, 'optimize-atlas.py')} ${resolve(citizenAtlasDir, 'runtime-atlas.png')} ${resolve(citizenAtlasDir, 'runtime-atlas.png')}`,
  { stdio: 'inherit' },
);

await copyFile(
  resolve(runtime, 'assets/citizens/sprites/lumen-guard/runtime-atlas.png'),
  resolve(guardAtlasDir, 'runtime-atlas.png'),
);
execSync(
  `${process.env.PYTHON || 'python3'} ${resolve(toolsDir, 'optimize-atlas.py')} ${resolve(guardAtlasDir, 'runtime-atlas.png')} ${resolve(guardAtlasDir, 'runtime-atlas.png')}`,
  { stdio: 'inherit' },
);

await copyFile(
  resolve(runtime, 'assets/citizens/lumen-guard-proof.html'),
  resolve(site, 'lumen-guard-proof.html'),
);
await copyFile(
  resolve(runtime, 'assets/citizens/lumen-guard-proof.bundle.js'),
  resolve(site, 'lumen-guard-proof.bundle.js'),
);

console.log('Built deploy site at', site);
