# AoE2-style sprite presentation (Sunwoven Weaver, Sunwoven Villager)

Issue #24+ pivot: **in-world units are sprite sheets**, not skinned GLBs. GLBs remain the authoring and bake source only.

Two bake paths now feed the same runtime and the same manifest schema:

| Unit | Bake path | Source art | Status |
|------|-----------|-----------|--------|
| Sunwoven Weaver | Blender render of `sunwoven_lab.blend` (`Tools/citizens/bake_sprites.py`) | rigged GLB | idle/walk/gather/build baked |
| Sunwoven Villager | **2D cutout puppet** (`Tools/villager-sprites/`) | painted turnaround, no 3D model | all four clips, all eight facings, no placeholders |

## Locked RTS camera

Gameplay, labs, and sprite bakes share one rig (`ThreeRuntime/src/rts-camera.js`):

| Parameter | Value | Source |
|-----------|-------|--------|
| Pitch | **57°** above ground | `TUNING.cameraPitchDegrees` |
| Yaw | **45°** (NE dimetric corner) | fixed — no gameplay orbit |
| FOV | **38°** | perspective |
| Default distance | **16 m** | `cameraDefaultZoom / 4` |
| Look-at height | **0.9 m** | citizen torso |

Pan (drag) and zoom (wheel) only. Orbit is disabled in `main.js`, `sprite-lab.js`, and `sunwoven-lab.js`.

Blender bake equivalent: `Tools/citizens/bake_sprites.py` (`PITCH_DEG`, `YAW_DEG`, `FOV_DEG`).

## AoE2 reference measurements

Local copies: `Tools/citizens/build/aoe2-refs/` (Fandom serves animated **WebP**; saved with `.gif` names for wiki parity).

Machine-readable summary: `Tools/citizens/build/aoe2-refs/analysis.json`.

| Ref | Preview frames | Inferred gameplay cycle | Playback | Cycle time | Pose language |
|-----|----------------|-------------------------|----------|------------|---------------|
| Male walk (`villager_walk.gif`) | 14 (interpolated preview) | **4** (Genie dat) | **10 fps** | **400 ms** | contact / passing leg swap; counter-swing arms |
| Hunt/gather (`hunting_gather.gif`) | 74 (multi-unit preview) | **6** key poses | **5 fps** | **1200 ms** | stoop → chop downstroke → contact → recovery |
| Build (`villager_build.gif`) | 101 (interpolated preview) | **6** key poses | **5 fps** | **1200 ms** | hammer wind-up → overhead strike → settle → raise |
| Sheet context (`superiorvillagers.png`) | static sheet | 8-dir rows | — | — | facing layout reference only |

Wiki previews add in-between frames; **do not paste ref pixels into shipped assets**. Bake from our Weaver GLB clips at the sampled source frames above.

## Sprite asset layout

```
ThreeRuntime/assets/citizens/sprites/sunwoven-weaver/
  manifest.json
  idle/{0..7}.png
  walk/{0..7}/{0..3}.png
  gather/{0..7}/{0..5}.png
  build/{0..7}/{0..5}.png
```

```
ThreeRuntime/assets/citizens/sprites/sunwoven-villager/
  manifest.json                  # per-frame bake contract
  atlas-manifest.json            # runtime UV sheet (Gemini-style)
  runtime-atlas.png              # packed idle/walk/gather/build × 8 facings
  idle/{0..7}/{0..3}.png
  walk/{0..7}/{0..3}.png
  gather/{0..7}/{0..5}.png
  build/{0..7}/{0..5}.png
```

`main.js` and the sprite lab prefer `atlas-manifest.json` when present
(`playback: "atlas"` → one texture, `texture.offset` / `repeat` per frame).
Rebuild the atlas after a bake:

```sh
python3 Tools/citizens/pack-runtime-atlas.py
```

Manifest schema: `sunfold.sprite-manifest/1`.

### Manifest fields the player reads

| Field | Meaning | Absent means |
|-------|---------|--------------|
| `worldHeight` | the whole frame in metres, padding included | fall back to `frameHeight/frameWidth × 3.5` |
| `unitHeightMeters` | the unit itself, ground line to crown | — |
| `anchor.y` | where the figure meets the ground, as a fraction of the frame from the top | 0, so the frame bottom is the ground |
| `mirrorAtRuntime` | `false` when facings 5–7 are already flipped on disk | `true`, which is what the older weaver sheets expect |

A sheet baked with all eight facings pre-mirrored **must** set
`mirrorAtRuntime: false`, or NW, W and SW come out facing backwards.

## Clip status

Weaver (Blender bake):

| Clip | Status | Source action | Sample frames (@ 30 fps) | Playback |
|------|--------|---------------|----------------------------|----------|
| **idle** | Real (Codex bootstrap) | — | 1 | 10 fps |
| **walk** | Real | `sunwoven_walk_inplace` | 0 / 9 / 18 / 27 | **10 fps** |
| **gather** | Real | `sunwoven_gather_loop_R` | 0 / 4 / 8 / 12 / 20 / 28 | **5 fps** |
| **build** | Real | `sunwoven_construct_loop_L` | 0 / 6 / 12 / 14 / 18 / 24 | **5 fps** |

Villager (2D cutout bake). Same AoE2 timing, authored as puppet keys rather than
sampled from a 30 fps action:

| Clip | Keys | Playback | Cycle | Event |
|------|------|----------|-------|-------|
| **idle** | 4 | 3 fps | 1333 ms | — |
| **walk** | 4 | **10 fps** | **400 ms** | `footfall` @ 0, 2 |
| **gather** | 6 | **5 fps** | **1200 ms** | `gatherContact` @ 3 |
| **build** | 6 | **5 fps** | **1200 ms** | `constructContact` @ 3 |

## Villager cutout bake

No 3D model. The painted turnaround is cut into rigged parts, posed as a 2D
puppet and baked frame by frame, so every shipped pixel is the original painting.
Full pipeline: `Tools/villager-sprites/README.md`.

```sh
python3 Tools/villager-sprites/cut_parts.py Tools/villager-sprites/rig/rig-S.json --out-dir parts
python3 Tools/villager-sprites/qa_render.py S --rest build/rest-S.png
python3 Tools/villager-sprites/bake_sprites.py \
  --out ThreeRuntime/assets/citizens/sprites/sunwoven-villager
node Tools/citizens/build-sprite-lab.mjs
```

Painted views are **S, E, N**. SE and NE are those views narrowed to 0.90 and
twisted 3.5°; NW, W and SW are mirrors. Mirroring swaps the sickle hand, exactly as
AoE2's own mirrored facings do — recorded in `manifest.provenance.honesty`.
Feet are pinned to a shared ground line after each pose so walk bob cannot hop.

Contract: `ThreeRuntime/tests/villager-sprites.test.js` pins the manifest fields
and proves every promised frame exists on disk.

## Bake commands

```sh
blender --background --python Tools/citizens/bake_sprites.py -- \
  --blend Tools/citizens/assets/sunwoven_lab.blend \
  --out ThreeRuntime/assets/citizens/sprites/sunwoven-weaver \
  --step bake-walk

# gather + build
blender --background --python Tools/citizens/bake_sprites.py -- \
  --step bake-gather

blender --background --python Tools/citizens/bake_sprites.py -- \
  --step bake-build
```

Bootstrap idle from Codex refs (does not overwrite multi-frame clips if already baked):

```sh
python3 Tools/citizens/bootstrap-sunwoven-sprites.py
node Tools/citizens/build-sprite-lab.mjs
```

## Proof lab

Open (static server on `ThreeRuntime/assets/citizens/`):

```
sprite-lab.html                          # weaver
sprite-lab.html?unit=sunwoven-villager   # villager
```

Keys: `1` idle · `2` walk (straight line) · `3` gather · `4` build · arrows change facing · `U` switches unit · walk animates along ground plane (no orbit/bob).

`window.spriteLab` exposes unit, camera, and `rtsCameraSpec()`.

A unit whose manifest carries `worldHeight` is already at gameplay scale, so the
lab frames it at 9 m. Sheets without one (the 1024² weaver plates) are only
readable at 7 m.

## Walk tuning vs AoE2 reference

| Aspect | Classic AoE2 villager | Sunwoven (this pass) |
|--------|----------------------|----------------------|
| Frames / cycle | 4 per facing | 4 — contact @ 0/18, passing @ 9/27 |
| Playback | ~10 fps | **10 fps** → 0.4 s cycle |
| Vertical bob | Baked in leg poses; minimal at contacts | Baked via `@hips_loc`; **no runtime Y bob** |
| Facing | 8-dir snap | 8-dir + mirror (NW/W/SW) |
| Shadow | Small ellipse under feet | Not baked yet (transparent PNG) |
| Lab demo | Units slide on ground in move dir | Straight ping-pong along `yaw`; ←→ retarget facing |

Sprite-lab previously orbited the unit and added a sine Y bob — removed to match ground-plane RTS feel.

## GLB pipeline (authoring only)

Unchanged: `Tools/citizens/run_sunwoven.sh` → `sunwoven_lab.glb`, `sunwoven-lab.html` (GLB sequence proof at locked camera). Do not delete; use for rig validation and sprite bakes.
