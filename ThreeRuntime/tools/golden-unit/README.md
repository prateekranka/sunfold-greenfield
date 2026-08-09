# Golden Unit pipeline — 16-direction masked sprite bake + 48-unit lab

Turns a skinned GLB prototype into AoE2-style directional sprite sheets with
runtime-lit normal masks and authored emissive accents, then proves the result
at 60 fps with 48 simultaneous units.

## What ships

`assets/citizens/sprites/sunwoven-golden/` — the Sunwoven Foundation Citizen:

- `atlas-manifest.json` — `sunfold.sprite-manifest/2`, playback `atlas16`
- per clip (idle / walk / gather / carry) × per channel (albedo / normal /
  emissive) PNG atlases: 16 direction columns, one row per animation frame

The runtime consumes them through the asset registry
(`sunwoven.citizen.foundation` → `spriteSheet: "sunwoven-golden"`) with
`GoldenSpriteUnit` (`src/sprites/golden-unit.js`): one shader material,
world-space normal lighting, emissive mask fed to bloom, and textures shared
across all units (12 textures total for any crowd size).

## Bake (one-time per character)

```sh
node tools/golden-unit/serve.mjs 8788 &          # static server + /save
node tools/golden-unit/build-golden-bake.mjs     # bundle bake.js + lab
# open http://127.0.0.1:8788/tools/golden-unit/bake.html
```

`bake.html` loads `assets/units/citizen_villager.glb`, measures the figure,
samples AoE2-authentic frames (idle 4 @ 3 fps, walk 4 @ 10 fps, gather 6 @
5 fps, carry 4 @ 10 fps with an authored resource pack on `hand_R`, sickle for
gather), renders every direction under the locked camera (pitch 57°, yaw 45°,
orthographic), and POSTs the atlases + manifest back to the server.

Channels: **albedo** (flat material colors), **normal** (world-space, via a
`MeshNormalMaterial` `onBeforeCompile` override — skinned), **emissive**
(material `emissiveFactor × KHR_materials_emissive_strength`, clamped).

## Lab (perf + capture)

```sh
# open http://127.0.0.1:8788/tools/golden-unit/golden-lab.html
```

48 citizens (12 idle / 12 walk / 12 gather / 12 carry) on blob shadows with
selection + faction rings, real shadow map, bloom. Scripted camera phases:
default (16 m) → medium (26 m) → closest permitted (8.5 m) → camera movement
(pan + zoom) → settle. Measures per-phase fps, the spawn-window max frame
(no hitch), then captures 4 PNGs into
`assets/citizens/captures/golden-unit/` (3 zooms + 2560×1440 battlefield).

Results land on `window.goldenLab.result` (gates: avg ≥ 55 fps, p95 ≤ 22 ms,
spawn max ≤ 66 ms, 48 views). Verified run: avg 60 fps, all phases ≥ 60,
spawn max frame 17.7 ms, 125 draw calls / 1716 triangles.

## Gotchas (all hit, all fixed)

- **Single-element material arrays draw nothing** on geometries without
  `groups` — keep `object.material` bare when there's one material.
- **`AnimationAction` must be `.play()`ed** before scrubbing
  (`action.time = t; mixer.update(0)`); a paused action ignores `_update`.
- **`MeshNormalMaterial` onBeforeCompile**: declare the world-normal varying at
  global scope in BOTH shaders or the fragment fails to compile.
- **`Math.round(-0.5)` is `-0` in JS** — normalize yaw into `[0, 2π)` before
  rounding to the 16-cell facing.
- **three's `getObjectByName` returns `undefined`, not `null`**, when missing.
- **Shader + texture warmup before the spawn burst** — first-use compiles and
  uploads otherwise read as a "spawning hitch" (the lab pre-renders each clip
  with the bloom chain before spawning).
- **Measure first-frame deltas from the first RAF**, not from script load.
