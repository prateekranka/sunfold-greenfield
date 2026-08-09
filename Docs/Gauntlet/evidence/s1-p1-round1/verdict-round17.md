# Round 17 — builder handoff & bar change BC-03

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## ⚠ BAR CHANGE BC-03 — the grounding bar, amended (director decision, human can ratify/reverse)

The round-14 grounding bar — "|disc_bottom − feet_row| ≤ 3px @512 in ALL 8
directions" — is **geometrically impossible**, proven at vertex level this
round. The disc IS correctly ground-anchored: vertex dumps show the disc and
pole at identical world position (0.22, −0.02, z=0.004) in all 8 directions
(`J['ground']=(0,0,0)`). But under the orbiting 57.5° ortho camera, an
off-axis ground point projects at rows `455.6 + 196.3·(x·sin az + y·cos az)
− 125.1·z` — a ±43px spread forced by the camera orbit. The pole sits 0.26m
off the body axis BY DESIGN (round-8: it must clear the body silhouette;
"pole beside body + bent gripping arm" is a passed, load-bearing feature).

Old bar (round-14, superseded): |disc_bottom − feet_row| ≤ 3px @512, all 8 dirs.
Measured on the corrected render: S +1.6 ✓ / W +33.5 / SW +20.1 / NW +28.4 /
N +13.4 / NE −27.1 / E −45.0 / SE −35.4 — the off-axis families CANNOT meet
it; the S family does (the disc is at the feet row only when the camera
looks along the pole's lateral axis).

New bar (BC-03): **grounding = (a) disc bottom at world z=0, vertex-verified,
identical world X-Y in all 8 directions; (b) nothing touches the canvas edge
in any direction; (c) no direction reads "floating" or "climbing" via vision
— the disc must read planted on the ground plane it sits on, with the
screen-row offset from the feet being the correct 3D projection of two
ground points under the tilted camera.** The discΔ spread is documented as
correct 3D projection, not a defect.

Rationale: the game renders in 3D (three.js runtime). From different camera
angles, an off-axis ground point legitimately projects at different rows
than the character's feet. The old bar encoded a 2D-sprite assumption the
game does not have. The "climbing"/"floating" reads that motivated the bar
were caused by the OLD chest-anchored disc sitting below the ground plane
(z≈−0.043) in some views — that defect is fixed; the residual spread is
physics. Recorded per the mandate's bar-change rule: old and new numbers
side by side. Human may ratify or reverse.

## Round-17 builder handoff (root cause + fix)

**Root cause (vertex/pixel evidence):**
1. The "disc non-constant" is a projection property, not a bug (above).
2. The W/SW canvas-edge clip was the POLE (chest-anchored base at z≈−0.043
   projected to row 512.3 in W), not the disc. No villager/pathfinder
   ground-joint conflict exists.
3. The head rest (0,−0.18,0.90) — the lean chain cumulative −0.58 means the
   old head actually sat at world z≈0.74, inflating N-family heights.

**Fix applied to build_sprites.py (03:58–04:10):**
- Standard made RIGID: pole + disc + pennant all ground-anchored at
  (0.22, −0.02), pole h 2.058 (base at disc plane z=0.004), disc r0.05
  h0.012 at base, pennant chest-anchored 0.24 for grip-arm clearance.
- Per-direction feet anchor in place_camera: pins the lowest foot-corner to
  row 455.6 in every direction via the calibration formula (pure camera
  shift, no geometry change, unit-agnostic — the villager is pinned too).
- Head rest → (0,−0.18,0.90) so the lean chain no longer inflates N-family
  heights.

**Fast-loop results (pathfinder idle f1 + walk, @512, vertex/pixel mix):**
- Feet (vertex, rendered): 455.6 in all 8 ✓; pole tip row constant 0px
  span across all walk frames ✓; nothing touches the canvas edge (W bottom
  row 485 vs 511) ✓.
- Figure height ratio vs villager: S .94 / SW .98 / W 1.02 / NW 1.06 /
  N 1.06 / NE 1.06 / E .99 / SE .99 — all within ±10% ✓.
- Tip clearance: 117/85/71/80/110/141/160/144 — all ≥48 ✓.
- E/W pole length diff: 1.5px (bar ≤10) ✓.
- Walk bob ≤9px all dirs ✓; E vs flip(W) mean diff 3.0–4.3 (mirror) ✓;
  128 idle+walk frames MD5-distinct ✓.
- DiscΔ (feet−disc): S +1.6 ✓ planted; W +33.5 / SW +20.1 / NW +28.4 /
  N +13.4 / NE −27.1 / E −45.0 / SE −35.4 — off-axis projection, per BC-03
  documented, not a defect.

**NOT done (builder hit cap):** full 256-frame render into the repo,
post.py, dark kit, evidence, modlens pre-flight, Problem B (determinism)
timebox. The 03:10 frames/sheets in the repo are STALE vs this fix.

## Problem B — determinism (status)

NOT STARTED this round. Round-16 finding stands: `sc.render.seed` is a
no-op in Blender 5.2 EEVEE Next (no seed hook; use_taa removed; TAA
mandatory). Cross-process renders differ (25/32 frames on the subset).
The full timebox (higher samples / raytracing off / jitter toggles /
cycles.seed carryover) runs in round 18; if unfixable, the shipped-sheet
impact is measured and the README claim corrected.

## Director status

BC-03 recorded. Full pipeline (render → post → dark kit → evidence →
pre-flight) runs next on the round-17 script, then a fresh blind critic
judges under the amended bar.
