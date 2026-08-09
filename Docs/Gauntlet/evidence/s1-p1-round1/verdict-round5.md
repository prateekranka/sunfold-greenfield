# Round 5 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; model recorded:
deepseek-v4-flash + gemini-3.6-flash vision)

VERDICT: REVISE

Single largest gap (STRUCTURAL): **the walk cycle is not a walk — a near-static
pose with low-amplitude jitter, indistinguishable from idle.** The critic's own
measurements: mask IoU f1-vs-f5 = 0.997, f1-vs-any 0.984-0.997, only 4-13% of
pixels change per frame pair (a real stride cycle shows 40-60%), pair_walk vs
pair_idle differ in 0.72% (villager) / 0.46% (pathfinder) of pixels. Vision
described both as static. This was the over-correction from rounds 3-4
("reads as running") into a shimmer.

Second gap (STRUCTURAL): the gather node still invisible to vision — exists
(175-193px, avg 202,188,156 — warm gold, grounded, hands bridging to it) but
too small (11px on the 160px frame), hue too close to the saffron robe, and
occluded from the rear views.

Third (new): the pathfinder's silhouette now object-reads as "a small
tower/outpost with mast" / "waypoint pole with flag and glowing circle" — the
standard dominates the humanoid; the opposite of "reads as fast".

Also recorded: citizen-height clause marginal/borderline (+12-27% body height
vs the villager — crest/wrap trim needed); leaner clause contested at the
hips (pack vs back-load); load reads dark against the dark bg.

## Builder response (round 6 changes)

1. **Walk rebuilt as a real gait** (build_sprites.py walk_pose v3):
   - root cause of the run-read found: the knee lift was a CONSTANT 1.15 rad
     (66°) at every amplitude — static thighs + high knees = run. Knee now
     scales with the stride: knee = -max(0, cos) * 0.6 * amp (21° at 0.62).
   - amp 0.62/0.66 (villager/pathfinder), arm pump 0.85/0.9, bob 0.02,
     hem sway 0.14, upper-body counter-roll 0.04*sin(2ph), ankle flick.
   - measured after: 40% of villager pixels change f1→f3 (was ~5%);
     motion energy villager idle 9.98 / walk 18.64 (was 13.55);
     pathfinder idle 4.45 / walk 10.12 (was 6.14).
2. **Gather deepened** so its peak exceeds the walk's: contact reach
   (sh 0.18, hnd 0.14), pull-stow (sh 0.45, hnd 0.35, elb 0.40 at f6).
   Measured: gather mean 16.70, peak 26.64 > walk peak 21.72; frame-1
   separation idle_vs_gather ~38, walk_vs_gather ~40.
3. **Node made unmistakable**: repositioned front-left (0.12, 0.14) so the
   front views show it beside the robe; nuggets enlarged (r 0.042-0.075,
   ~0.2m cluster) and re-materialed to the saturated "mote" gold; glow disc
   r 0.13; motes arc from the deposit up into the satchel.
   Measured: node_gold 82 at contact (rest 1), hands 127 vs feet 128.
4. **Pathfinder humanized**: arms thickened (0.028/0.025/0.030) so the figure
   reads humanoid; lean 0.18 → 0.16; crest trimmed (h 0.05) and wrap
   (r 0.078) to close the citizen-height margin.
5. **Satchel brightened** (saffron emission 0.50) so the load reads against
   the dark ground.

Evidence for round 6: evidence.md / evidence.json in this directory
(re-extracted after the re-render).
