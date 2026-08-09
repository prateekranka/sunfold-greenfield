# Round 25 — builder handoff & director completion

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Builder result (round 25) — investigation, no repo changes

The builder hit its cap mid-investigation (no repo files touched), but
delivered three verified findings:
1. **The round-24 gold classifier was broken on real pixels** — rendered
   pole gold is r≈110–140 (the r>170 threshold finds ~45 px), and lit skin
   highlights (183,159,118) PASS r>170. A pure RGB classifier cannot
   separate pole from hand/head; the pole must be found column-wise (tallest
   narrow structure in the top band). Calibrated a light-teal classifier
   (b>190, g>190, 150≤r≤205, b−r>20) that cleanly separates pennant turq_l
   from the darker sash.
2. **Real tip-clearance table** (column-based classifier, round-24 baseline):
   S 94 · SW 106 · W 78 · NW 118 · N 165 · NE 222 · E 181 · SE 140 — all ≥48.
3. **E/W mirror NOT clean on the round-24 baseline** (E vs flip(W) diff ~75,
   best alignment dy=+8, residual in the head band + grip-arm region).
   Hypothesis: the grip arm extends at world +X (toward E), so E shows the
   near arm reaching to the pole while W hides it behind the body — a
   genuine 3D visibility asymmetry, not a projection bug. The round-19
   "3.96" was measured on the round-17 geometry and is not reproducible on
   round-24's.

## Director action — cross-blade pennant (the E-read fix)

The pennant was a single flat turq_l blade in the world-X plane (scale
(0.08, 0.008, 0.04)): face-on from N/S, **edge-on from E/W** — measured
6 teal px in E vs ~70 in N. That is why E read "streetlight / water pump
mechanism": ~163px of bare pole above the head with no flag cue.

**Fix (build_sprites.py, surgical):** added a second turq_l quad in the
world-Y plane at the same tip position (scale (0.008, 0.08, 0.04), centered
(0.26, 0.18, 2.113)) — a cross-blade pennant. Every direction now sees a
blade face-on. Blades stay on the pole axis in the tip band (narrow from N:
no round-7 "hat" trap). Seed unchanged, no new draws.

## Verification (director, fast loop 32 idle frames, EXIT=0, 0 Tracebacks)

- **Pennant teal px per direction (idle f1):** 79 / 108 / 80 / 105 / 79 /
  96 / 77 / 99 — visible in ALL 8 (E was 6 before, now 79).
- **Modlens gates (dark composites):**
  - E idle: **"character model viewed from behind holding a tall staff or
    pole"** — PASS (was "streetlight/water pump mechanism")
  - W idle: "character model interacting with a tall vertical pole" — PASS
  - N idle: "character standing next to a tall wooden pole" — PASS
  - villager S: passing (unchanged)

## Open items for the completing agent / director

1. Full 256-frame render (in flight, single serial pass, --python-exit-code
   1), then post.py → dark kit → evidence → probes → pre-flights → fresh
   critic.
2. The E/W mirror deviation (~75 diff, grip-arm visibility asymmetry) is
   REAL and physical (near arm visible from E, hidden behind the body from
   W) — record the honest number in the evidence, do not chase artificial
   symmetry; the mirror gate is "pole opposite side + MD5-distinct", which
   still holds.
3. Tip-clearance table must be re-derived on the round-25 render with the
   column-based classifier (round-25 baseline numbers are pre-pennant).
