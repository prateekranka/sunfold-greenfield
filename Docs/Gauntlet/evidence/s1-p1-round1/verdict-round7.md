# Round 7 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; model recorded:
deepseek-v4-flash + gemini-3.6-flash vision, provider gemini-api — the FREE tier)

VERDICT: REVISE — but the round-6 structural blocker is CLOSED.

## The round-6 driver is dead

The Pathfinder no longer reads as a building anywhere. All six views + raw
frames + pair images read "humanoid person carrying a pole with a light-blue
flag". Raw f3/f5 verbatim: "The figure is a humanoid character, **not a
tower, rocket, or building**." The N view — round-6's "desert tower" — now
reads "clearly a humanoid person (scout/banner-bearer)". Head/shoulders/waist/
flared skirt/bent gripping arm/hand-on-pole all read. Root causes the round-7
builder found and fixed: the old "+0.16 forward lean" was a BACKWARD lean
(rx(+) tilts +Z toward −Y; character faces +Y); the gather chest +0.34 was
also bent backward, away from the node; and main() never deleted the
villager's meshes, so every pathfinder frame carried the villager's leftover
gather deposit + satchel (the "rocket exhaust" and "domes").

## The two remaining gaps (round 8 scope)

1. **STRUCTURAL — the N (front) gather view never shows hands at the
   deposit, in any frame.** Contact frame + raw f1/f3/f5 of the d4 (N) cycle:
   hands are "floating stubby cylinders at upper-torso/shoulder level",
   "completely away from the golden deposit"; a tool dangles near the node
   "close to without directly touching". Pixel data: N-gather motion energy
   15.6 vs S 25.7 — the front cycle has NO reach-down phase. The S view reads
   "bending down, harvesting" but the front view (the angle players most
   often watch a worker from) reads "standing next to gold". Fix: mirror the
   S-view reach pose into the N direction (arms/hands bending down to the
   node, tool contacting it) and re-pick the N contact frame from the reach
   phase.
2. **The standard's pole merges with the body edge in S/SE/SW.** Pole is
   2px wide, 1px from the body edge in the S family (S silhouette width 30 =
   villager's 30; pole inside the width envelope); clear gaps in W (9px) and
   N (4px). The builder's own verify script "no pole column found" is TRUE
   for the S family. The clause survives via the teal pennant in every view,
   but the pole is an independent silhouette element in only ~5 of 8
   directions. Fix: push the lateral offset out ~0.05–0.1 m (or +1px pole
   width) so the pole clears the body edge in S/SE/SW — verify script must
   find the pole column in 8/8 directions.

## What PASSED (do not regress)

- Structure-read gone everywhere; pole+flag reads as carried standard.
- Node reads as GOLD ORE: hue 41–42°, sat 0.48–0.50, value 0.82–0.83 (round
  6: value 0.73, robe-indistinguishable); vision "#eec74b / #ffd85a",
  node_gold 104 contact px vs 4 rest.
- Warm ivory robe (hsv 39–41°, sat 0.18–0.21), restrained teal 0.024–0.048,
  zero plume/glow read.
- Villager gait intact: motion energy 21.2, f1↔f5 mirrored heights, f3
  passing pose — vision "walking stride", never run/march/shimmer. Load
  visible. Height/lean contracts PASS clause by clause (pair: bodies 41 vs
  41px; torso 12–21 vs 20–25px; forward lean Δ4.0 vs Δ1.6).

## SHIP RECOMMENDATION

**WITH FIXES** — two contained items stand between this and SHIP: (1) N-gather
hands reach the node (mirror S reach pose, re-pick N contact frame);
(2) pole column detected in 8/8 directions (offset +0.05–0.1 m or +1px
width). Everything else passes as-is — do not touch it.

## Builder response (round 8 changes)

Dispatched 2026-08-05 23:20. Scope: N-family gather reach pose + N contact
frame re-pick; pole lateral offset / width so the S-family clears the body
edge and the verify script finds the pole column in all 8 directions.
Re-render, post.py, verify, evidence re-extraction, pre-flight modlens on
dark_villager_gather_N_contact.png. This file is updated when the round-8
verdict lands.
