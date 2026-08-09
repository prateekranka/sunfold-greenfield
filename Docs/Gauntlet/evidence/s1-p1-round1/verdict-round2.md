# Round 2 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, evidence-based; model recorded:
deepseek-v4-flash — the template's claude-opus-5-thinking-max was not pinnable
via the available delegation tool, noted for the record)

VERDICT: PASS

The critic's convergence rule applied: "cosmetic-only gaps = the loop stops".
This is a ship-with-notes round. All round-1 REVISE grounds closed by pixel
movement (same census/silhouette/motion matchers as round 1):

- palette family: ivory dominant (villager 0.497, pathfinder 0.398),
  gray_shadow 0.226 / 0.277 (was 0.71 / 0.64), saffron 0.113 / 0.152,
  teal 0.145 / 0.115 — accents carry real pixel surface;
- pathfinder contract, clause by clause (critic's words):
  - citizen height — SATISFIED (body 43px vs villager 45px at S; the
    49-68px bboxes include the 24px standard);
  - leaner — SATISFIED (idle torso 16-23px vs villager 22-25px; at S
    16 vs 24, −33%);
  - forward-leaning — SATISFIED but weakest clause (com_x Δ1.2px vs
    villager's 0.6px; com_y Δ4.9px; S-facing mass 8.5px below bbox
    centre — real but subtle);
  - tall thin standard — SATISFIED (24px above the head at 128 cells,
    ~36% of body height; S silhouette aspect 0.43 tall-and-thin; the
    standard carries saffron 0.152 — highest gold share of either unit —
    and teal 0.115 trim);
- activity legibility — three non-overlapping energy bands
  (idle 0.437 / walk 0.682 / gather 0.758 villager; 0.388 / 0.552
  pathfinder) + gather contact anchored (node_gold 14↔0, lowest_warm
  127 at contact vs 119 rest, feet 128);
- protected: S-walk symmetry 0.164 / 0.013; 8-direction consistency;
  chroma hygiene intact (corners pure #00FF00 on all variants).

## Single largest gap (carried as the round-3 tuning note)

The Pathfinder is the darkest, grayset, least-turquoise sprite in the set:
gray 0.277 vs villager 0.226, ivory 0.398 vs 0.497, teal 0.115 vs 0.145.
Cause identified by the builder: the 0.14 forward lean tilts the torso away
from the above-camera key, cutting the lit ivory surface. COSMETIC — not a
dominance violation (ivory > gray on both units). Not acted on this round:
the loop stopped at PASS; a round 3 could lift the pathfinder's fill/rim or
reduce the lean to 0.11.

## Builder response (recorded for the pipeline)

Root causes found and fixed during round 1→2 (all in build_sprites.py):

1. `transform_apply(scale=True)` in Blender 5.2 zeroes the object location —
   every cube in the build (satchel, strap, feet, pack) rendered displaced
   by ~0.5m. Fixed by keeping scale on the object (verified: cubes render at
   analytic positions from every azimuth; per-direction height spread
   collapsed from ~20px to ≤8px).
2. AgX view transform (Blender 4.x default) compresses and desaturates warm
   colours — the palette could not render. Fixed: Standard view transform.
3. `material()` defaulted Emission Color to gold — every fabric emission
   (turq, saffron, ivory) added gold on top of its base colour, muddying the
   teal to olive and washing the saffron pale. Fixed: emission defaults to
   the material's own colour.
4. The turquoise sash torus sat inside the robe cone (R 0.125 vs robe
   radius 0.131 at the waist) — invisible. Fixed: R 0.165, tube 0.035, plus
   own-colour emission 0.5 so it reads through the warm key.
5. Lighting rig: above-camera warm key (energy 1.4, az 12°, el 62°), warm
   fill (0.35) + warm rim (0.25) — replaces the cool-blue fill that grayed
   the shadow side; ivory albedo 0.86 so the lit robe lands on the bible's
   (240,228,200) without clipping.
6. Pathfinder contract build: body at exact citizen height, torso/shoulders/
   arms narrowed, lean 0.14 threaded through idle/walk, standard rebuilt
   (1.63m pole, pennant at 1.44m, enlarged glowing tip, r 0.013).

Evidence for round 3 (if any): re-run gauntlet_evidence.py after any change.
