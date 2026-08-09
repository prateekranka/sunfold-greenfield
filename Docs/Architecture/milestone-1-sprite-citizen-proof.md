# Milestone 1 — Sprite Citizen RTS proof

```
Citizen_v1 FROZEN
clips: idle, walk, carry, gather, build
Do not regenerate art — next unit is Lumen Guard (silhouette test)
```

**Pipeline:** humanoids = sprites; machines/buildings = GLB.

## What shipped

- Combined Village Man-Bun runtime atlas: **Walk + Carry + Gather + Build**
  - `ThreeRuntime/assets/citizens/sprites/village-manbun-wanderer/runtime-atlas.png` (2048×16384)
  - `atlas-manifest.json` / `Citizen.sprite.json`
  - Clip rows: walk `0–15`, carry `16–31`, gather `32–47`, build `48–63`
- `SpriteUnit.setState(name)` API (alias of `setClip`) + `setFacing` / `update(dt)`
- In-game default Citizen art: **sprite** (Man-Bun). Opt out with `?art=gltf` or `?art=procedural`
- Proof scene: grassy Sunwoven biome, town center, 20 trees, 3 houses, **32 Citizens** (16 walk / 8 carry / 4 gather / 4 build)
- Proof polish: facing/HP debug overlays off by default (`?debugFacing=true` to enable); softened contact shadows

## Run the 32-citizen RTS proof

```bash
cd SunfoldGreenfield-threejs-wkwebview/ThreeRuntime
npm run build:labs   # optional if sources changed
npx --yes serve assets/citizens -p 4177
# open http://localhost:4177/citizen-rts-proof
# facing/HP debug overlays: http://localhost:4177/citizen-rts-proof?debugFacing=true
```

Controls: click a Citizen to select (Shift adds). HUD buttons toggle slow camera rotate / select walkers.

Crowd grid lab (same atlas): `http://localhost:4177/citizen-crowd-lab?count=32`

In-game (WKWebView / built runtime): open with default art (sprite) or `?art=sprite`.

## Repack atlas after clip regenerations

**Citizen_v1 is frozen — do not regenerate Man-Bun art.** The commands below are historical / emergency-only.

```bash
# Preferred one-command factory (skip regen; refresh pack + verify):
./scripts/sprite-from-ref.sh --unit village-manbun-wanderer --backend skip \
  --clips walk,carry,gather,build --stage all

# Or pack-only:
python3 SunfoldGreenfield-threejs-wkwebview/Tools/citizens/pack-unit-combined-atlas.py \
  --unit village-manbun-wanderer

cd SunfoldGreenfield-threejs-wkwebview/ThreeRuntime && npm run build:labs && npm run build
```

Full pipeline docs: `sprite-from-ref-pipeline.md`.

## Milestone 2 TODOs (do not start Citizen art)

- **Lumen Guard** unit sprite pipeline / runtime binding (silhouette test — next)
- Pathfinder unit sprite pipeline / runtime binding (after Guard)
- Optional: split or compress the 16k-tall atlas if iOS texture limits bite in shipping builds
