# Sprite-from-ref pipeline

One command turns a unit reference (and/or existing master sheets) into packaged
runtime atlases for ThreeRuntime, following the proven **Village Man-Bun** path.

## Entrypoint

From repo root (`aoe-space-edition`):

```bash
./scripts/sprite-from-ref.sh --unit <id> [options]
# or
make sprite-from-ref UNIT=<id> BACKEND=skip
```

### Acceptance (Man-Bun re-pack, no image gen)

```bash
./scripts/sprite-from-ref.sh \
  --unit village-manbun-wanderer \
  --backend skip \
  --clips walk,carry,gather,build \
  --stage all
```

### New unit bootstrap

```bash
./scripts/sprite-from-ref.sh \
  --unit pathfinder \
  --ref path/to/ref.png \
  --backend skip \
  --clips idle,walk,carry,gather,build \
  --stage init
```

## Stage diagram

```text
  ref.png ──► init ──► generate ──► postprocess ──► runtime ──► pack ──► register ──► verify
               │          │              │             │          │         │
               │          │              │             │          │         └─ asset-registry.json
               │          │              │             │          └─ combined runtime-atlas.png
               │          │              │             └─ 256 premul sheets (FACINGS_16)
               │          │              └─ master 16×8 @ 1024 (feet y≈921)
               │          └─ sources/<clip>/ grids  [AGENT / API — often skip]
               └─ assets/sprites/<unit>/ layout + equipment stub
```

| Stage | What it does | Skip-path behaviour |
|-------|--------------|---------------------|
| **init** | Create `assets/sprites/<unit>/` layout, copy ref, equipment stub, README | No-op if files exist |
| **generate** | Pluggable backend writes grids under `sources/<clip>/` | `--backend skip` assumes frames/masters already exist |
| **postprocess** | rembg (if available) → feet-anchor → `Citizen_<Clip>_16dir_8frames.png` | Reuses existing masters unless `--force-postprocess` |
| **runtime** | `export_citizen_runtime_256.py` per clip | Reuses existing 256 sheets unless `--force-runtime` |
| **pack** | `pack-unit-combined-atlas.py` → game + Resources copies | Always refreshes atlas + manifests |
| **register** | Idempotent `pipelineUnits[<unit>]` (+ optional `--registry-entry`) | Safe to re-run |
| **verify** | Sheet dims, feet baseline fields, print `build:labs` next steps | Fail-closed |

Run a subset:

```bash
./scripts/sprite-from-ref.sh --unit village-manbun-wanderer --backend skip \
  --stage pack,register,verify
```

Dry-run:

```bash
./scripts/sprite-from-ref.sh --unit village-manbun-wanderer --backend skip \
  --stage all --dry-run
```

## Layout

```text
assets/sprites/<unit>/
  refs/ref.png
  sources/<clip>/          # agent grids (optional when masters exist)
  citizen_equipment_states.json
  Citizen_<Clip>_16dir_8frames.png   # master 8192×16384
  runtime/
    Citizen_<Clip>_16dir_8frames_256.png
    runtime-atlas.png
    atlas-manifest.json
    Citizen.sprite.json

SunfoldGreenfield-threejs-wkwebview/ThreeRuntime/assets/citizens/sprites/<unit>/
  (same runtime outputs + combined atlas — what the game loads)
```

## Generate backends

| `--backend` | Behaviour |
|-------------|-----------|
| `skip` | No generation. Masters or `sources/<clip>/` frames must already exist. **Required for CI / Man-Bun acceptance.** |
| `generateimage` | Writes agent instructions under `sources/<clip>/`; does **not** call Cursor APIs. |
| `gemini` | Only if `SPRITE_GEN_GEMINI_MODULE=module:callable` is set; otherwise exits. **Not required** for packaging. |

Custom backend:

```bash
export SPRITE_GEN_BACKEND_MODULE=/path/to/my_backend.py:generate_clip_grids
./scripts/sprite-from-ref.sh --unit pathfinder --backend skip --stage generate
```

Python contract (`Tools/.../scripts/sprite_gen_backend.py`):

```python
def generate_clip_grids(*, ref_path, unit, clip, out_dir, equipment_states=None) -> list[Path]:
    ...
```

### What is still agent-only

- **Frame / grid generation** (Cursor GenerateImage, Gemini, or hand-paint)
- Vision QA of identity lock, tool readability, prop bans
- Equipment-contract authoring before regen

Everything after frames (or masters) exist is CLI: postprocess → runtime → pack → register → verify.

## Key scripts reused

| Script | Role |
|--------|------|
| `normalize_feet_anchored_action_grid.py` | Feet-anchor master pack from 128 frames |
| `export_citizen_runtime_256.py` | Master → cleaned premul 256 sheet |
| `pack-unit-combined-atlas.py` | Stack clips into `runtime-atlas.png` |
| `pack-manbun-combined-atlas.py` | Thin wrapper for Man-Bun defaults |

## Makefile

```bash
make sprite-from-ref UNIT=village-manbun-wanderer BACKEND=skip
make sprite-from-ref UNIT=pathfinder REF=assets/sprites/pathfinder/refs/ref.png STAGE=init BACKEND=skip
make sprite-from-ref UNIT=village-manbun-wanderer STAGE=pack,verify EXTRA='--force-runtime'
```

## After verify — proof scene

```bash
cd SunfoldGreenfield-threejs-wkwebview/ThreeRuntime
npm run build:labs
npx --yes serve assets/citizens -p 4177
# http://localhost:4177/citizen-rts-proof.html
```

## Related docs

- `milestone-1-sprite-citizen-proof.md` — Man-Bun RTS proof that this pipeline packages
- `aoe2-sprite-pipeline.md` — broader AoE2 presentation notes (Weaver / Villager)
- `assets/sprites/village-manbun-wanderer/PRODUCTION_STATUS.md` — **Citizen_v1 FROZEN** (idle/walk/carry/gather/build); do not regenerate; next unit Lumen Guard
