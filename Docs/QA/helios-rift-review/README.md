# Helios Rift — external review pack

**Status:** Helios Rift Phase 1 playable — awaiting design critique  
**Date:** 9 Aug 2026  
**Public page:** https://helios.contenthelper.in (ChatGPT-fetchable; text + scores + file list)  
**Pages project (asset mirror, in progress):** https://contenthelper-helios-rift.pages.dev

Playable proof: data-driven RTS space map **Helios Rift (The Broken Ring)** — 4-player ring, repairable bridges, solar core capture, sprite Citizens, solar flares.

## Run locally

```bash
cd SunfoldGreenfield-threejs-wkwebview/ThreeRuntime
npm run build:labs
npx --yes serve assets/citizens -p 4177
# http://localhost:4177/helios-rift-proof
```

## Files

| File | What it shows |
|------|----------------|
| `01-overview-zoomed-out.png` | Full ring / macro layout |
| `02-starting-position.png` | P0 north home fragment + citizens |
| `03-solar-core-centre.png` | Central solar core objective |
| `04-resource-area.png` | Home matter resource cluster |
| `05-gameplay-zoom.png` | Typical iPad gameplay zoom |
| `helios-rift-preview.mp4` | ~18s tour: overview → start → resources → bridge → core |
| `site/index.html` | Public review article (deployed to contenthelper.in) |

## iPad-first vision QA (honest)

| # | Criterion | Score | Notes |
|---|-----------|-------|-------|
| 1 | First 10s without minimap | **6/10** | Ring + core read at overview; enemy lanes and nearby resources not obvious without minimap |
| 2 | Touch readability | **5/10** | Platforms/core OK; citizens small; resource nodes tiny; bridge state moderate |
| 3 | Visual theme (lost star machine) | **4/10** | Tan blocks in void; core glow helps; needs megastructure art |
| 4 | Bridge repair state | **6/10** | Minimap clear; in-world stubs vs teal rails workable but subtle |
| 5 | Match / loop fantasy | **7/10** | Chokepoints + core contest structurally sound |

### Next polish (strategic readability)

- Faction spawn banners on home fragments
- Typed resource silhouettes (matter/lumen/aether/energy)
- Broken-bridge scaffolding + repair progress at midpoint
- Solar-flare telegraph on core + screen-edge warning
- Expansion islet callouts visible in overview
- Enemy approach decals on bridge lanes

## Acceptance (engineering)

| Criterion | Status |
|-----------|--------|
| 4 player spawns | ✅ |
| Path graph + bridges | ✅ |
| Resources + expansions | ✅ |
| Solar core objective | ✅ |
| AI hints API | ✅ |
| Distinct from grass proof | ✅ |

Architecture: `Docs/Architecture/rts-space-maps.md`

## Suggested ChatGPT prompt

> Critique this Helios Rift map as an iPad-first AoE-style RTS — does it create a compelling match? Use https://helios.contenthelper.in (screenshots + video). Comment on first-10-second readability without minimap, touch-scale silhouettes, bridge/core clarity, chokepoint interest, and the highest-impact art/readability pass for a broken orbital civilization fantasy.

## Capture notes

- Captured via Argent-managed Chromium CDP (`Tools/citizens/capture-helios-rift-review.mjs`)
- Camera helpers exposed on `window.__heliosRiftProof.setView(x, z, distance)`
