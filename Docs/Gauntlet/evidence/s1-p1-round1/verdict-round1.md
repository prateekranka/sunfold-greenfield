# Round 1 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (blind, evidence-based; model recorded: deepseek-v4-flash — the
template's claude-opus-5-thinking-max was not pinnable via the available
delegation tool, noted for the record)

VERDICT: REVISE

Largest gap (structural): palette family absent — villager census
ivory_robe 0.271 · gray_shadow 0.710 · saffron_gold 0.0 · teal 0.0; measured
ivory tops at (220,210,205) vs spec ~(240,228,200). The units read dark gray,
i.e. Gravemark's family, and the bible's mid-zoom readability mechanism
(faction colour accents) has nothing to attach to.

Second gap (structural): Pathfinder contract — 3 of 4 clauses fail/unproven:
"citizen height" (reads +12-13px taller), "leaner" (width identical to
citizen), "forward-leaning" (com_x delta 1.7px, not readable), "tall thin
standard" (6px above the head = ~1px tick at mid zoom; needs 15-25px with a
pennant/glow that reads from above).

Protected (must not regress): S-walk symmetry (0.173 / 0.015), two-phase
gather (node_gold 16 contact vs 0 rest, hands to 126 vs feet 128),
8-direction consistency (24-27px widths), activity separation
(non-overlapping energy bands 0.41 / 0.70 / 0.83; idle-vs-gather 0.843).
Caution: walk_vs_gather 0.431 is the smallest margin — keep the cycles distinct.

## Builder response (round 2 changes)

1. **Lighting retuned for the palette family** (build_sprites.py):
   - key sun 4.2 → 6.0 energy, warm colour (1.0, 0.92, 0.78);
   - fill changed from cool blue (0.62, 0.72, 1.0) to warm amber (1.0, 0.86, 0.62), 0.8 energy;
   - new warm rim light from behind (0.5 energy, (1.0, 0.78, 0.5)) for the luminous edge;
   - gentle emission on fabrics: ivory 0.10, saffron 0.18, turquoise 0.14, gold_l 1.2.
   Measured after (same buckets): gray 0.71 → 0.12, saffron 0.0 → 0.091, teal 0.0 → 0.035, bright ivory 0.12.
2. **Pathfinder contract** (build_sprites.py):
   - body joints lowered to exact citizen height (root 0.45→0.44, head 0.95→0.94);
   - torso narrowed (r1 0.125→0.11, r2 0.075→0.065) → measurable "leaner";
   - forward lean 0.06 → 0.14 rad threaded through idle/walk poses;
   - standard: pole now 1.0m tall (tip 1.63m, ~17px above the head at 128),
     thicker (r 0.013), pennant moved to 1.44m near the top, glowing tip
     enlarged (r 0.022, emission 1.2).
3. Gather cycle untouched (critic caution).

Evidence for round 2: evidence.md / evidence.json in this directory (re-extracted
after the re-render; palette census numbers supersede round 1's).
