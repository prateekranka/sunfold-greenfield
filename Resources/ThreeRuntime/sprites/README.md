# Runtime sprite-sheet (atlas) playback

Gemini’s packed sprite-sheet suggestion is wired into the Three.js runtime as
**atlas UV animation**: one PNG + a small manifest, instead of hundreds of
per-frame files at draw time.

## How it works

1. Offline bake still produces the per-facing PNG tree (`idle/`, `walk/`, …).
2. `Tools/citizens/pack-runtime-atlas.py` packs those frames into
   `runtime-atlas.png` + `atlas-manifest.json`.
3. `SpriteUnit` with `playback: "atlas"` loads the sheet once and advances
   `texture.offset` / `texture.repeat` each frame (`src/sprites/atlas.js`).
4. `CitizenSpriteLayer` (`src/sprites/unit-layer.js`) mirrors sim citizens onto
   atlas billboards from `main.js`.

## Units

| Folder | Layout | Notes |
|--------|--------|-------|
| `village-manbun-wanderer/` | facing-grid 16 dirs × Walk+Carry+Gather+Build | **Current sprite LOD** — combined 256 premul atlas |
| `sunwoven-villager/` | facing-grid (8 facings × clip rows) | Earlier cutout bake |
| `space-villager/` | clip-rows (idle/walk/gather) | GPU-safe single-facing fallback when not `?art=sprite` |
| `sunwoven-golden/` | atlas16 masked | Golden-unit lighting experiment |

## Swap art

Replace `runtime-atlas.png` and update `atlas-manifest.json` (`frameWidth`,
`frameHeight`, clip `frames` / `originRow`, atlas `width`/`height`). Keep
`schema: "sunfold.sprite-manifest/1"`. Man-Bun export:

```bash
python3 Tools/gorest-2d-animation-spritesheet-generator/scripts/export_citizen_runtime_256.py \
  --master assets/sprites/village-manbun-wanderer/Citizen_Walk_16dir_8frames.png \
  --out-png assets/sprites/village-manbun-wanderer/runtime/Citizen_Walk_16dir_8frames_256.png \
  --out-json assets/sprites/village-manbun-wanderer/runtime/Citizen_Walk_16dir_8frames_256.json \
  --asset Citizen_Walk_16dir_8frames_256 --clip walk
```

## Verify

```bash
cd ThreeRuntime && npm test && npm run build:labs && npm run build
# Milestone 1 RTS proof (32 = 16 walk / 8 carry / 4 gather / 4 build):
npx --yes serve assets/citizens -p 4177
# open http://localhost:4177/citizen-rts-proof.html
# Crowd grid: http://localhost:4177/citizen-crowd-lab.html?count=32
# In-game: default art is sprite; ?art=gltf for GLB LOD
```

Repack after clip regenerations:

```bash
python3 ../Tools/citizens/pack-manbun-combined-atlas.py
```
