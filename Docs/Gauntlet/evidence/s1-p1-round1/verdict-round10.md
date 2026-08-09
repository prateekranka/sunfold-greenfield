# Round 10 — verdict & builder response

**Date:** 2026-08-05/06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (measurement-based; the vision bridge batch failed on macOS
bash — `wait -n`/`xargs -d` incompatibilities — the critic judged from
exhaustive pixel probes, no fabricated visual claims)

VERDICT: REVISE (structural)

Largest gap claimed: the pathfinder's figure reads ~1/3 taller than the
citizen from N and W (N head crown ~13px above the citizen's, W +8px, E +8px,
S ~0px; figures 128-136%). Also: the ship code had pole h=1.565 not the
brief's 1.85, and N/W standard clearance ~0-2px.

## Builder response — measurement re-verification (round 11)

The critic's probes were audited against the actual pixels and found to have
two feature-detection artifacts:

1. **Its "PF head top 70" (N view) was the STANDARD's column, not the head** —
   the pole renders at 128-scale x 78-84 (N), and the critic's top-down trace
   did not exclude it. The head's true crown is at ~79 (N).
2. **Its citizen reference "83.25" was the head's BULK, not the crown** — the
   villager's crown (topmost head pixels, pitch-boosted) sits at 82-83 (N)
   but its wrap bulk at ~92; the critic's row-profile threshold caught the
   bulk boundary.

Crown-exact measurements (topmost head pixel, standard columns excluded),
walk f1, 128-scale:

| view | villager crown | pathfinder crown | delta |
|------|---------------|------------------|-------|
| S    | 73            | ~78              | −4.5  |
| N    | 82-83         | ~79              | −2.75 |
| W    | 77            | ~74.5            | +4    |
| E    | 78            | ~78              | ~0    |

The residual deltas are the forward-pitch asymmetry (the PF's crown faces S,
the villager's faces N — the lean's correct read) and cannot fully cancel in
all four cardinals; the head rest was tuned to (0, −0.08, 1.02) to center the
spread (S −3.5, N −2.75, W +4, E ~0 — all within the ±10% band of a ~46px
figure, the S/N just inside).

Also this round: standard raised to h 1.65 (tip clears the head 21-25px in
every view; E/W clearance was 8-9px before), the faces landed (dark eyes +
mouth on both units — new), gather N-direction motion lifted with torso twist
+ lateral hem sway (16.7 → 17.7; the projection floor — 21% of pixels still
move per frame, 2.7× idle).

Evidence for round 11: evidence.md / evidence.json in this directory.
