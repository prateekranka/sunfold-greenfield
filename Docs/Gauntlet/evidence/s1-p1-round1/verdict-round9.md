# Round 9 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; deepseek-v4-flash
+ gemini-3.6-flash vision; 9 images + independent pixel probes)

VERDICT: REVISE (structural — the last calibration pass)

Landed (do not regress): unit identity, palette, node, gait, chroma, activity
separation ALL hold in every image; the E-view "pole sprouting from the head"
is dead (pole x 74-77 vs head x 78-89, 1-3px gap); E figure is citizen height
(108%); no tower/building read anywhere; node reads GOLD (#edd56e).

Largest gap: the pathfinder's FIGURE still not citizen height in 3 of 4
cardinals on the critic's pixel probes — N 49px vs citizen 38 (128%), W 48 vs
41 (118%), S 36-39 vs 41-43 (88-91%), E 43 vs 40 (108%). Analysis: the N/W
"over-height" is dominated by the skirt hem sitting 3cm lower than the
citizen's (the hem bottoms at z 0.28 vs the citizen's 0.31), not the head;
the head-top row itself is within ~±4px except E/W side-view crown
differences. Also: the standard extends only 2-3px above the head in N/E/W
(15px in S) — the contract's "tall thin standard that reads fast from
directly above" needs a head-height of clearance in every view; and the pole
base floats 4px above the ground in S / pokes 5px below the feet in E.

## Builder response (round 10 changes)

1. **Head joint calibrated by 4-view render sweep** (idle, 128-scale, vs the
   citizen's head-top rows S 77 / E 79 / N 82 / W 79):
   - y -0.145/z 1.02: S +2, E -4, N -12, W -4
   - y -0.08/z 1.035: S +6, E -3, N -14, W -3
   - y -0.05/z 1.04: S +7, E -3, N -15, W -3
   - **LOCKED: y -0.10, z 1.02 → S +1.2, E +0.8, N +3.8, W -3.2** (max ±4px,
     inside the ±10% band; the residual N delta is the crown-vs-back pitch
     asymmetry, not a height error).
2. **Skirt hem raised 1.5cm** (z 0.36 → 0.375) — the hem now bottoms at the
   citizen's hem row, closing the N/W figure over-read (the critic's 128%/118%
   were the hem's 3cm drop + the forward-lean stance, not the head).
3. **Standard lengthened**: tip 1.565 → 1.85 (clears the head by ~12-15px in
   every view — N/E/W were 2-3px), pennant 1.53 → 1.79, shaft re-centered.
4. **Base disc added** at the pole's foot (gold, r 0.035, z 0.008) — the shaft
   meets the disc and the disc reads planted on the ground from every view
   (the shaft's screen row varies with the y-offset by projection; the disc
   carries the grounding read).

Everything else untouched (the round 6-9 wins: structure-read dead, node
hue-distinct, real gait, warm palette, load, lean Δ5.6).

Evidence for round 10: evidence.md / evidence.json in this directory
(regenerated post-build).
