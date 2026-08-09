# Round 14 — verdict & builder response

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; deepseek-v4-flash
+ gemini-3.6-flash vision; 21 full-image runs + 10 zoom-crop arbitrations +
independent PIL probes on all 8 directions)

VERDICT: REVISE — judged on the FRESH final render (frames 01:55, kit 01:56).

## What PASSED (do not regress)

1. **Walk bob genuinely fixed**: crown travel PF-S 5 / PF-N 8 / VIL-S 3 /
   VIL-N 9px @512 (all ≤10 bar; was 36px hop at round 10), with distinct
   gait phases (consecutive-frame diffs 49–94; f1/f5 = 18–38 mirrored) —
   real walk, no shimmer, no hop.
2. **E-mirror + carrying read solid**: E is a true mirrored frame (MD5
   distinct from W, pole opposite side), E walk reads "holds/held in hand"
   (never climbing), and the W "climbing" read is DEAD — fresh W reads
   "holding a tall wooden staff".
3. **Economy polish complete**: saturated gold node (254,213,106), warm
   ivory robe dominant (22–39% census, zero grey), restrained teal (3–7%),
   N-gather hand ON the deposit ("hand rests directly on top of the
   yellow-gold object"), villager load visible, all 256 frames
   MD5-distinct (no byte-copy).

## The gaps (round 15 scope)

1. **STRUCTURAL — the standard's base disc is off the feet line in 6/8
   views.** N HANGS +28–30px @512 below the figure's feet (regressed from
   round-13's planted Δ0/+1); W and NW are clipped by the canvas bottom
   (W ≥37px below feet, pole cut off by the frame edge); E/NE/SE FLOAT
   19–33px @512 above the feet. S/SW are the reference (Δ−2/+2). Root
   cause (confirmed second time): the disc rides the chest joint's
   yaw/pitch — the h=2.05 change pushed the BASE down instead of raising
   the TIP (tips moved ≤1–3px; bases moved 10–30px). **Fix: anchor the
   base disc to the character's ground point (identical world Y as the
   feet) in every direction** — a ground-anchored disc that does NOT
   inherit the chest joint's transform. Bar: |pole_bottom − feet| ≤ 3px
   @512 in all 8 directions.
2. **Tip clearance under bar in N/W/NW**: N 45, W 38, NW 22 @512 (bar
   ≥48px @512 = 12px @128). Re-tune the pole height so the tip clears in
   every direction AFTER the ground anchor (the anchor changes the
   projection).
3. **N figure height +34%** (186 vs 139px @512 — head+hood 48px @512
   excess over the citizen's head; NW +17–23%, NE +23%). The N hood/crest
   was NOT addressed. Decision: drop ~10–12px @128 to land within ±10%,
   keeping the hood readable (contract: citizen height). S −17% stays as
   the documented pitch-asymmetry floor.
4. **E/W pole-length symmetry**: diff ≥46px @512 (≈ round-13's 12px
   @128), unfixed. Normalize.

## Pathfinder contract, clause by clause

- Citizen height: FAIL — S −17% (pitch floor), N +34%, NW +17–23%,
  NE +23%; W/E/SW/SE pass (+3–4%).
- Leaner: PASS (torso 43 vs 49px @256 in S).
- Forward-leaning: NOT CONFIRMED (weakened) — no longer reproduces;
  side-view offsets ambiguous; vision reads neutral. Watch after the
  anchor fix.
- Tall thin standard: PASS as an object (2–3px shaft, ~2–2.3× figure
  height, pennant visible in all 8); FAILS as placed (grounded only in
  S/SW).
- Reads as fast from above: PARTIAL — pennant+pole read everywhere, but
  idle views read "standing NEXT TO a pole" and the grounding breaks the
  planted identity.

## SHIP RECOMMENDATION (critic)

**WITH FIXES** — would become SHIP with: (1) ground-anchored base disc in
all 8 views; (2) tip ≥48px @512 in N/W/NW; (3) N head+hood dropped ~10–12px
@128 (or accepted + documented); (4) E/W pole length normalized. Everything
else is green and must not be regressed.

## Builder response (round 15 changes)

Dispatched 2026-08-06 02:20. Scope: ground-anchored base disc (world-Y
anchor at the feet, decoupled from the chest joint), tip clearance
re-tuned after anchoring, N hood trim to citizen height, E/W pole-length
normalization. Re-render, post, evidence, pre-flight, determinism. This
file is updated when the round-15 verdict lands.
