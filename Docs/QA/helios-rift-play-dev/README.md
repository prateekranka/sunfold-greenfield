# Helios Rift — dev playable deploy

**URL:** https://dev.helios.contenthelper.in/
**Also:** https://dev.helios.contenthelper.in/lumen-guard-proof
**Worker:** `helios-rift-play-dev` (custom domain, separate from production)
**Production:** https://helios.contenthelper.in/ — **not modified by dev deploys**

## What it is

Latest Helios Rift proof with Lumen Guard mix (Citizens + Guards), built from
`ThreeRuntime/src/helios-rift-proof.js`. Includes quantized sprite atlases for both
`village-manbun-wanderer` and `lumen-guard`.

## Rebuild + redeploy

```bash
# Build site (npm run build:labs → copies html/bundle/atlases into site/)
node Tools/citizens/build-helios-play-site.mjs

# Deploy to dev only (wrangler OAuth login required)
cd Docs/QA/helios-rift-play-dev/worker && wrangler deploy
```

Or use the scripted path:

```bash
ASSETS_UPLOAD_JWT=<jwt> CLOUDFLARE_API_TOKEN=<token> node Tools/citizens/deploy-helios-play-dev.mjs
```

## MIME / download fix

Same as production: `worker/index.js` forces correct `Content-Type` per extension,
strips `Content-Disposition`, and `run_worker_first = true` in the assets binding.
