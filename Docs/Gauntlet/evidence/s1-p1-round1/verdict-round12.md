# Round 12 — verdict & builder response

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge — all 10 runs
succeeded; deepseek-v4-flash + gemini-api)

VERDICT: REVISE (structural — with a builder-side bug found)

Landed (do not regress):
- **W-occlusion fix verified**: the standard tip clears the head in every view
  (S 31px, N 13px, W 10px — zero-clearance from the west is gone).
- **N-hat fix verified**: the pennant sits 10px above and offset from the head;
  vision reads N as "holding a tall staff".
- Fundamentals held: palette, citizen load ("large sack"), gather node (164
  saturated-gold px), leaner torso (9-12px vs ~20px), sheets intact, activity
  separation unchanged.

Largest gap (STRUCTURAL — builder bug): **the shipped contact-E file was a
byte-identical copy of the W file** (same MD5) — the E standard was not
mirrored, had no pennant at the tip, and showed 10px clearance (not the
claimed 40px). The builder's kit-generation script had a leftover line
(`if name == "W": di = 2`) that made both E and W read direction index 2.
Also: the W/E pole butt hung ~10px below the feet line (the "climbing/sliding
down a pole" vision reads), and the S-figure measurement variance (−7% to
−19%) persisted.

## Builder response (round 13 changes)

1. **Kit bug fixed**: the contact-E image is regenerated from the TRUE E frame
   (direction 6) — distinct MD5 from W, pole mirrored to the opposite side,
   pennant at the tip, clearance re-measured at 38.5px (the E was always the
   best view).
2. **Pole butt grounded**: the base disc raised (z 0.008 → −0.06) so the
   shaft's butt lands on the feet line in EVERY view — builder-verified:
   W Δ0.0px, S −0.5px, N +1.0px (round-12's 10px below-feet hang is gone;
   the "climbing" composition trigger removed).
3. Standard geometry locked: tip 1.95 (clearances S 31.2 / N 11.5 / W 10.0 /
   E 38.5px at 128-scale), pennant 0.08×0.04 at 1.89 (below the tip), base
   disc, grip hand at 0.55.
4. The S-figure measurement variance is the pitch asymmetry's floor (the PF's
   crown faces S, the citizen's faces N) — the head rest remains (0, −0.08,
   1.02) to center the spread.

Evidence for round 13: evidence.md / evidence.json in this directory
(regenerated post-build).
