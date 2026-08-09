# Citizen RTS sprite proof — ChatGPT QA pack

Milestone 1 in-app proof: **AoE-style 2D sprite Citizens** over a simple **3D Sunwoven biome**, running in Chromium at `http://localhost:4177/citizen-rts-proof`.

## Clip mix / controls

- **32 Citizens:** 16 walk · 8 carry · 4 gather · 4 build
- **Default:** all idle standing (gather-f0 hold, no walk)
- **Start activities** button or **A** → roles animate (walk/carry orbit; gather/build in place)
- **Wheel / pinch:** smooth zoom
- **Middle/right-drag or WASD/arrows:** pan
- **Minimap (bottom-right):** click/drag to jump camera
- HUD shows live **FPS**, status, zoom, atlas size

## Sprite / atlas anchor

| Spec | Value |
|------|--------|
| Anchor | `(0.5, 0.10)` feet baseline (manifest ≈ `y: 0.100586`) |
| Cell | **256×256** runtime cells |
| Directions | **16** (`FACINGS_16`) |
| Frames | **8** per directional clip (idle sheet is dedicated 256 hold) |
| Atlas (proof HUD) | `2048×16384` packed sheet |

## Files

| File | What it shows |
|------|----------------|
| `screenshots/01-milestone1-overview.png` | Wide idle overview (Milestone 1 still) |
| `screenshots/02-milestone1-selected.png` | Selection rings on walkers |
| `screenshots/03-idle-hold.png` | Idle-standing hold (all 32) |
| `screenshots/04-active-roles.png` | After Start activities — roles animating |
| `screenshots/05-zoom.png` | Smooth zoom in |
| `screenshots/06-minimap-pan.png` | After minimap click/pan |
| `screenshots/07-60fps-idle-overview.png` | Idle overview with FPS ~60 |
| `screenshots/08-60fps-idle-closeup.png` | Idle close-up with FPS ~60 |
| `citizen-rts-proof.mp4` | Short in-app proof clip (~28s): idle → pan/zoom → minimap → Start activities |

## Suggested ChatGPT prompt

> Review this Milestone 1 Citizen RTS proof pack (stills + `citizen-rts-proof.mp4`). These are 2D sprite units (256 atlas cells, 16 directions, 8 frames, feet anchor 0.5/0.10) over a low-poly 3D world. Does it feel like classic AoE-style sprite units in a 3D RTS world? Comment on silhouette readability, feet planting, facing/animation coherence at idle vs active roles, camera pan/zoom/minimap feel, and anything that breaks the AoE illusion. Be specific and actionable.

Screenshots (numbered PNG set): see `screenshots/` (also mirrored at `Docs/QA/citizen-rts-screenshots/`).
