# Sunwoven Villager — 2D cutout sprite pipeline

Baked sprite sheets from painted turnaround art. No 3D model, no Blender, no
runtime skinning: the paintings are cut into rigged parts, posed as a 2D puppet,
and every frame is written to PNG. The runtime plays flat frames.

Output: `ThreeRuntime/assets/citizens/sprites/sunwoven-villager/` — 160 frames
(4 clips × 8 facings × 4–6 frames) at 256², plus `manifest.json`.

## Why cutout and not 3D

One painted turnaround cannot be reconstructed as a faithful 3D model, but it
can be cut up and re-posed. Every shipped pixel is the original painting, moved,
so the fabric, the gold piping and the face survive exactly as painted. The cost
is that only the three painted views are real; the other five are derived.

## Stages

```sh
# 1. key the studio backdrop to transparency (once per sheet)
python3 isolate_backdrop.py refs/front.png cutouts/front-alpha.png --tolerance 34

# 2. cut a view into rigged parts
python3 cut_parts.py rig/rig-S.json --out-dir parts --qa build/qa-parts-S.png

# 3. check the cut before trusting it
python3 qa_render.py S --rest build/rest-S.png --clips build/qa-clips-S.png

# 4. bake all eight facings
python3 bake_sprites.py --out ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager

# 5. assemble QA atlases (walk-atlas + labeled sprite-sheet)
python3 assemble_atlases.py --sprites ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager

# 6. rebuild the proof lab
node ../citizens/build-sprite-lab.mjs
```

## Files

| File | Role |
|------|------|
| `isolate_backdrop.py` | border-seeded flood fill in RGB distance space; keeps dark hair and boots that a global threshold would eat |
| `cut_parts.py` | cuts a view into part PNGs + `parts.json` |
| `rigpose.py` | forward kinematics and compositing; one affine per part |
| `qa_render.py` | rest-pose losslessness check and a clip contact strip |
| `bake_sprites.py` | eight facings × four clips → PNG frames + manifest |
| `assemble_atlases.py` | walk-atlas + labeled sprite-sheet + preview from a bake |
| `clips.json` | the four clips, authored once in profile and scaled per facing |
| `gait_ik.py` | cyninja-style foot-path + 2-bone IK for walk legs |
| `godot-gait/` | Godot 4.7 lab to preview/tune walk IK and export bend signs back into `clips.json` |
| `rig/rig-{S,E,N}.json` | one rig per painted view |
| `image-analysis.md` | the observation pass the rigs were measured from |

## How a rig works

A part never declares an outline. The painted alpha already carries it. A part
declares only where it lives:

* **`cuts`** — thick line segments that sever the silhouette at a joint.
* **`seeds`** — a flood fill from these points claims the region the cuts carved.
* **`regions`** — convex polygons, only for a prop painted in front of the body
  where no background gap exists.
* **`propSource` / `place`** — for the side sheet, which draws the basket, pail
  and sickle as loose objects rather than on the figure.

Then three repairs, in order:

* **healing** — cut pixels rejoin the nearest owner, so a seam leaves no gap.
* **`capRadius`** — a disc of silhouette at the pivot, shared with the parent, so
  a rotated limb does not open a wedge at its own joint.
* **`dilate`** — grows a part back under its child. Every part is drawn above its
  parent, so the overlap is invisible at rest and only shows as coverage once the
  joint moves.

`restAngle` is a constant added to every pose angle. The side sheet draws the
arms spread away from the body; the rest angle folds that back to neutral so one
set of clip keys reads the same in every view.

## Poses and view gains

`clips.json` authors each pose **once**, in profile semantics, as if the figure
faced screen-right. Positive degrees are counter-clockwise on screen: a limb
pointing down swings toward screen-right.

`viewGain` then scales each channel per facing. This is the whole reason one clip
can serve eight directions: a leg swing that reads as a stride in profile reads
as a scissor in a front view, so `stride`/`lift` are 1.00 for E and ~0.28 for S.

**Walk legs are not FK keys.** They use a port of the cyninja gait (tvanhens):
authored foot plant/swing paths, 2-bone IK for hip/knee (`gait_ik.py`), and
ankle world-aim that stays flat-to-plantarflex — never the tip-up dorsiflex the
old FK foot keys produced when shin curl stacked onto the boot.

`reachA` and `reachB` are separate **and signed**, because the two arms need
opposite rotations in a frontal view — the same rotation that brings the
screen-right arm down across the body throws the screen-left arm up and out.

## What is real and what is derived

| Facing | Source | Real art |
|--------|--------|----------|
| 0 S | front painting | yes |
| 1 SE | S narrowed to 0.90 and twisted 3.5° | no |
| 2 E | side painting | yes |
| 3 NE | N narrowed to 0.90 and twisted 3.5° | no |
| 4 N | back painting, mirrored on load | yes |
| 5 NW | mirror of NE | no |
| 6 W | mirror of E | no |
| 7 SW | mirror of SE | no |

Mirroring swaps which hand carries the sickle. AoE2's own mirrored facings have
the same artefact; it is recorded in the manifest rather than hidden.

Two deliberate cheats in the E rig, both standard for an eight-facing set:

1. A figure facing screen-right shows the camera its **right** side, so its left
   hand — the sickle hand in S and N — is the far hand and would be hidden. The
   sickle is given to the near arm so the unit stays readable.
2. The arms overlap the torso down to y 0.47, so a cut that follows the paint
   leaves a thin wedge. Each arm is cut generously into the torso and the torso
   is dilated back under it.

## Quality gate

`qa_render.py --rest` composites the rig with every rest angle cancelled and
diffs it against the crop the cutter saw.

| View | Holes | RGB drift > 16 |
|------|-------|----------------|
| S | 0 | 0 |
| E | 0 | drift only where the far leg and far arm are deliberately shaded |
| N | 0 | 0 |

Zero holes means the cut is lossless: no painted pixel was dropped.
