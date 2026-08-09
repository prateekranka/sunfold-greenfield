# Round 10 — verdict (Hermes loop, merged-state critique)

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Context

Judged the MERGED render (256 frames, rendered 00:08, evidence regenerated
00:10) — the state combining both parallel loops' work: the sibling loop's
round-10 changes (head joint calibrated to citizen height y −0.10/z 1.02,
skirt hem raised 1.5cm, pole base disc, standard re-centred) plus this loop's
round-8 fixes (pole lateral x 0.26, deep gather reach). The sibling loop is
running its own round-11 critic on the same state (deleg_686372f3); this
verdict is the Hermes loop's independent read.

## Critic verdict (fresh blind critic, vision via modlens bridge; deepseek-v4-flash
+ gemini-3.6-flash vision; 22 vision runs + independent PIL pixel probes)

VERDICT: REVISE — but close.

## What PASSED (do not regress)

1. **S-view citizen-height contract: pathfinder 29px = citizen 29px on the
   pair image** (head tops y86/y87, feet y114/y115) — the head-joint + hem
   calibration landed in S.
2. **"Person carrying a standard" reads correctly in S/W/N** — zoom crops
   confirm a visible hand grip ("left hand reaches over to grip the pole");
   the round-9 "pole sprouting from the head" read is dead; no
   tower/probe/rocket read anywhere in 22 vision runs.
3. **N-gather hands ARE at the deposit** (zoom: "hand directly touches… zero
   vertical gap"; pixels: hands y169–174 against the mound face) and the
   palette lock is complete: saturated gold node (#f1c40f/#e5c15e), warm
   ivory robes (#e7dfd4/#d2c2a5), restrained teal (#52b8c5/#5ebac3) — no
   grey, no plume, no exhaust.

## The gaps (round 11 scope)

1. **STRUCTURAL — pole base not grounded in W and E.** Base disc pokes 9px
   below the feet in W (base y245 vs feet y236) and 3–10px below the feet in
   E (y141–143 vs y133–140); zoom vision independently confirms the base is
   the lowest element in E. The round-9 "pokes below feet in E" complaint is
   literally still present. Fix: seat the base disc on the ground row in W
   and E (raise base ~5–10px in those projections), re-verify all 8
   directions.
2. **STRUCTURAL — standard tip clearance below contract in N and E.** N:
   2px above the figure's topmost pixel (the hair crest at y86 — vision
   confirms the crest IS the head: "round brownish head/hair structure");
   E: 7–10px (tip y91 vs head y98–101). Builder claimed 12–15px in every
   view. The N crest also keeps the N figure at 116% of citizen height
   (crest-top-to-feet 50px vs citizen 43px). Fix: give N ≥12px of visible
   standard above the topmost pixel (lengthen/raise the tip or reduce the
   hair-crest height — the latter also pulls the N figure to citizen
   height); raise the E tip to ≥12px.
3. **E walk frame reads "climbing", not "carrying".** Walk-E: "clinging to
   and climbing a tall vertical pole" — in E the pole passes behind the
   head/body. Fix: re-check the E walk pose so the figure reads "carrying,"
   not "climbing" (pole visibly beside the body with the grip, in the E
   walk frames specifically).
4. **NEW — walk-cycle vertical bob reads as a hop.** Villager bob 36px =
   21% of figure height at 512-scale ("high-bobbing or hopping walk cycle");
   pathfinder 38px = 17% ("lower step/bob phase"). Measurement confirms
   both vision reads; this contradicts the earlier "gait passed" claims at
   the commercial bar. Fix: reduce the walk-cycle vertical bob to ≤10px at
   512-scale on both units while keeping the stride phases distinct (f1/f3/
   f5) — the gait must read walk, not hop.

## Pathfinder contract, clause by clause

- Citizen height: PARTIAL — S equal (29=29); N 116% (crest); E/W head-tops
  within ±4px.
- Leaner: PASS (torso ~14px vs citizen ~18px at pair scale).
- Forward-leaning: PARTIAL — clear in E, not visible in S/N, ambiguous in W.
- Tall thin standard readable from above: FAIL — thin + clear of body in
  S/W/N ✓, but clearance N 2px ✗ / E 7–10px ✗; base pokes below feet in
  W/E ✗.

## SHIP RECOMMENDATION

**WITH FIXES** — four contained, named items. All four closed + re-verified
(N ≥12px clearance with citizen-height figure, E ≥12px with a "carrying"
walk, base grounded in 8/8, bob ≤10px with distinct stride phases) = SHIP.
