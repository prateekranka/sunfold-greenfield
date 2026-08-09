# Round 26 — FINAL VERDICT: PASS — piece s1-p1 SHIPS

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven economy-unit sprite sheets,
stream sunwoven-sprites-r1) · **Critic:** fresh blind critic, vision via
modlens bridge (deepseek-v4-flash + gemini-3.6-flash free tier), 24 images
+ 4 arbitration crops + independent pixel probes

## VERDICT: PASS — SHIP

"The re-check list is green on every item, verified independently (not taken
from the director's table): grounding ✓ (BC-03, no floating/climbing/mounted
in any of 8+8 vision reads), tip clearance 69–185 ≥48 ✓, height ±10% ✓,
bob ≤9 ≤10 with real gait phases ✓, person-with-flag-standard in every view
incl. E ✓, no regressions (N-gather hand, gold saturation, ivory palette,
teal restraint 0.019–0.068, no plume/stray above crown in any dir, load
visible, E structurally mirrored + MD5-distinct, 256/256 unique) ✓, shadow
soft/true-black/all-dirs ✓. Nothing regressed."

**Single largest gap: "None — all named gaps closed."** (One cosmetic note:
walk-E vision says "lever or pole mechanism" — a phrasing wobble on a
correct person-standing-next-to read, not on the re-check list.)

## The 26-round arc (what it took to ship)

- R5–R6: walk shimmer → real gait; node invisible → gold ore; Pathfinder
  tower/rocket read
- R7–R9: N-gather hands never at node → reach fixed; pole merged body edge
  → radius/offset; **sibling-loop collision** → serialized by human
- R10–R13: post-merge W/E grounding, N tip clearance 2px → pole h 2.05;
  E "climbing" → mirrored frames; 36px bob=hop → 3–9px; W occlusion;
  contact-E byte-copy bug; N hood height
- R14–R16: grounding bar proven GEOMETRICALLY IMPOSSIBLE → **BC-03 bar
  change** (off-axis projection is correct 3D; planted = world z=0 + no
  clip + no floating/climbing read); EEVEE determinism measured (0.004%
  shipped-sheet impact, documented)
- R17–R18: rigid ground-anchored standard + per-direction feet pinning;
  **pipeline integrity failure caught by critic** (stale pathfinder frames
  packed into the kit) → cleanup fix + --python-exit-code 1 discipline
- R19–R21: critic's "no art change predicted" disproven by director vision
  completion (no shadows at all → the grounding-cue root cause); shadow
  implemented, keying fixed (greenness mask ate shadows → alpha-derived),
  deposit/crouch clip fixed (S gather 509–511 → 492)
- R22–R23: shadow lit-color invisible in dark kit (color ≈ bg, alpha
  irrelevant) → true black; opaque blob (black Transparent BSDF flips Mix
  into EEVEE opaque pass) → one-line fix
- R24–R25: E "mounted on pole" — x-move disproven (E column is set by world
  Y); standard moved forward of the body axis; E "streetlight" → pennant
  was a single X-plane blade, edge-on from E/W → **cross-blade pennant**
  (teal visible all 8 dirs, 6 → 37+ px in E)
- R26: PASS

## Final shipped state (on disk, 08:26–08:31)

- build_sprites.py: round-25 state (pole + disc ground-anchored (0.26,0.18),
  pole h 2.184, cross-blade pennant, ground-anchored grip, true-black soft
  shadow plateau (0,0,0,153), seed 20260726 unchanged)
- 256 frames rendered 08:26–08:30 single serial pass, EXIT=0, 0 Tracebacks,
  all fresh by mtime, 0 MD5 duplicates
- post.py packed all variants (RGBA, alpha-derived masks); dark kit + pairs
  regenerated 08:31; evidence regenerated 08:31:16
- Tip clearance (critic's independent table): S 95 / SW 69 / W 80 / NW 120 /
  N 166 / NE 185 / E 183 / SE 142 — all ≥48
- Height ratios: S 0.974 / E 1.000 (±10%)
- Walk bob 7–9px, gait phases distinct (f1↔f3 diff 15–31)
- Pennant teal 37–57px per dir (strict classifier)
- S gather f3/f4 lowest rows 489–494 (≤497)

## Bar changes (recorded)

- BC-03 (round 17): grounding bar amended from "|disc − feet| ≤3px all 8
  dirs" (geometrically impossible for the 0.26m off-axis standard) to
  "disc at world z=0 vertex-verified + no canvas clip + no
  floating/climbing/mounted vision read". The screen-row offset is correct
  3D projection for the orbiting camera.

## For the record

1. E/W mirror: critic's independent E-vs-flip(W) RGB-mean diff on raw 512
   frames = 3.19; the recorded ~75 was a different method on the round-24
   baseline. Gate (pole opposite side + MD5-distinct + structural mirror)
   passes.
2. Determinism: EEVEE Next has no render-seed hook; cross-process renders
   differ ~0.004% of shipped pixels (silhouette edges). Sheets are
   committed baked assets — gameplay determinism (B6: map + sim) unaffected.
3. **If a future polish pass touches build_sprites.py, re-run the full-256
   MD5 audit — that gate is load-bearing** (critic's note).

## Next checkpoints (per s1-p1 log entry)

- Military roster sprites (Vanguard/Quarrel) — same pipeline, fresh piece
- Swift app loop CP-C6 age progression
- Workbench: s1-p1 closed; update workbench-data.json + GOAL.md status
