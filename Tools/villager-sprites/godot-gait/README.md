# Godot gait lab (cyninja walk IK)

Godot **4.7.1** authoring surface for the villager walk legs. The cyninja demo
this gait was ported from is Godot (`motion.gd` / `skeleton.gd`); this lab is
the place to tweak foot paths and knee bend signs, then push params back into
the Python cutout bake.

## What Godot is / is not for

| Godot does | Python cutout bake still does |
|---|---|
| Live 2-bone gait IK preview | Painted part compositing (healing, caps, dilate) |
| Per-facing `bendA`/`bendB` authoring | 256² frames + `manifest.json` for Three.js |
| Export `export/walk_angles.json` | Runtime sprite playback |

Do **not** replace the cutout pipeline with Godot SubViewport renders of stick
figures — shipped pixels must stay the painted turnaround. Optional later:
attach the cut `parts/*.png` as `Bone2D` sprites for WYSIWYG, still export via
the same bake contract.

## Open

Godot is on the Desktop (quarantine translocation may apply):

```sh
"/Users/prateekranka/Desktop/Godot.app/Contents/MacOS/Godot" \
  --path "$(pwd)" --editor
```

Run from this directory (`Tools/villager-sprites/godot-gait`).

## Keys

| Key | Action |
|-----|--------|
| `1`–`5` | Facing S / SE / E / NE / N |
| `[` `]` | Step walk frame |
| `Space` | Play / pause |
| `B` | Flip bendA/bendB on current facing (knock-knee knob) |
| `E` | Export `export/walk_angles.json` + save bends into `data/gait_config.json` |
| `R` | Reload config |

## Apply → bake

```sh
cd ..   # Tools/villager-sprites
python3 godot-gait/apply_godot_gait.py
python3 bake_sprites.py --out ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager
python3 assemble_atlases.py --sprites ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager
```

`bake_sprites.py` reads `viewGain.bendA` / `bendB` per facing. Frontal defaults
are opposite signs for **outward** knees (S/SE: A=+1 B=-1; N/NE: A=-1 B=+1);
profile keeps both +1. The inverted pair (S A=-1 B=+1) is what reads knock-kneed.
