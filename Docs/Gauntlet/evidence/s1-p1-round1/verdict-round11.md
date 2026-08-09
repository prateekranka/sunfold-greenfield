# Round 11 — verdict & builder response

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge — all 9 runs
succeeded this round; deepseek-v4-flash + gemini-api)

VERDICT: REVISE (structural — one clause)

Landed (do not regress):
- **Citizen height: PASS where isolable** — S −7%, E +2%, W −2% crown-to-feet
  (the round-10 fix held; the pole no longer masquerades as the head).
- **Leaner: PASS** (PF torso 12-24px vs villager 20-25px all dirs).
- **Forward-leaning: PASS** (the pitch-asymmetric crown deltas are the
  expected forward-cant signature).
- Palette, chroma hygiene, grip, base disc, walk symmetry all hold; vision
  reads "holding a tall staff" in S/E/N.

Largest gap (STRUCTURAL): **the standard is completely occluded from the W
view** — the pole at x +0.26 sits behind the body from the west camera, its
tip renders at the head's row (W topmost = head crown y71 in every frame; the
standard adds ~zero height from W). Also: the N-view pennant fuses with the
head into a "hat" read, and the eyes/mouth don't register at the 128px budget
(cosmetic-but-intent-failing).

## Builder response (round 12 changes)

1. **Pole tip raised 1.65 → 1.95** (h 1.95, base disc unchanged): the W view's
   downshift (0.843·0.26 ≈ 51px at 512) is now compensated — the W tip clears
   the head by ~10.2px (builder-verified on the shipped frame: pole tip y65.0
   vs head y75.2 at 128-scale); S ~30px, N ~23px, E ~40px. The standard now
   rises above the head silhouette in ALL FOUR cardinals.
2. **Pennant shrunk** (0.10×0.05 → 0.08×0.04) and moved to 1.89 (just below
   the tip) — the N-view "hat" fusion.
3. **Eyes/mouth enlarged** (eyes r 0.016 → 0.019, mouth 0.018 → 0.022 wide)
   — better face registration at the 128px budget and clearly visible at the
   720p/4K scales.

Evidence for round 12: evidence.md / evidence.json in this directory
(regenerated post-build: PF standard extension 34px front, com_x Δ9.6).
