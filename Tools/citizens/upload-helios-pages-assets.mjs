#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const jwt = process.env.PAGES_UPLOAD_JWT;
if (!jwt) {
  console.error('PAGES_UPLOAD_JWT required');
  process.exit(1);
}

const site = resolve(dirname(fileURLToPath(import.meta.url)), '../../Docs/QA/helios-rift-review/site');
const files = [
  ['index.html', '70d3129aa036922165c397c4a5664885a081af77e4cfba5b303546e78bbdb0dc', 'text/html'],
  ['assets/01-overview-zoomed-out.png', '06b07dd2981e50462060f7d23f4e9dbaf5c48d8c3ec8920883675588433c52d4', 'image/png'],
  ['assets/02-starting-position.png', '1de1dad3c932832f3c00e5e4050c1a8340ec2e5f8b84b0e65420465e367aa834', 'image/png'],
  ['assets/03-solar-core-centre.png', 'e09d64d5b17ecee32ca67438bed0a2c84e537e061ed487cbf4093c9048cd7ced', 'image/png'],
  ['assets/04-resource-area.png', '39b26035ff184eea680dc891ec9b62dc5571b6667c34d90694e480d898bf3301', 'image/png'],
  ['assets/05-gameplay-zoom.png', '8db12908936a1d3047c9cfa33185c86c6ad31dd96c6b10c18254fa82f9697fc0', 'image/png'],
  ['assets/helios-rift-preview.mp4', 'e113fde37e94929db2b03307794038baeb8cc18f3f235aa10e68f6131b57c1bc', 'video/mp4'],
];

const payload = files.map(([rel, hash, contentType]) => ({
  key: hash,
  value: readFileSync(resolve(site, rel)).toString('base64'),
  base64: true,
  metadata: { contentType },
}));

const check = await fetch('https://api.cloudflare.com/client/v4/pages/assets/check-missing', {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${jwt}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ hashes: files.map(([, h]) => h) }),
});
const checkJson = await check.json();
console.log('missing', checkJson.result?.length ?? checkJson);

const upload = await fetch('https://api.cloudflare.com/client/v4/pages/assets/upload', {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${jwt}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify(payload),
});
const uploadJson = await upload.json();
if (!uploadJson.success) {
  console.error(JSON.stringify(uploadJson, null, 2));
  process.exit(1);
}
console.log('uploaded', payload.length, 'assets');
