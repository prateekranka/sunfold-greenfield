# Round 20 — builder handoff & director note

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Why this round existed

The director completed the round-19 critic's vision review (parsing the 21
cached modlens JSONs the critic could not) and found the REAL remaining
defect: **the render had no ground shadows at all.** Pixel probe: in
pathfinder idle S, the lowest opaque pixel was row 456 and rows 458–500 had
ZERO alpha — no contact cue. Vision reads: idle_E "clinging to or climbing
… floating or hanging", idle_W "hanging or climbing… circular base of the
pole positioned below the figure", walk_W "clearly hanging or climbing above
the small circular base", walk_S "floating, hovering, or climbing slightly
above the floor level relative to the round base plate" — only N (on-axis)
read grounded. The repeated cause in every read: "no visible ground plane,
floor texture, or shadow". The geometry had been correct since round 17
(BC-03); the PERCEPTUAL grounding cue was missing.

## Root cause (two layers)

1. The render never drew a contact shadow (the old 2D ellipse in post.py was
   centered on the anchor, never on the pole base).
2. post.py's `make_mask` keyed on GREENNESS: a dark shadow over chroma green
   is still g-dominant → gness→1 → mask 0. **Every green variant ate the
   shadow.**

## Fix applied (round 20)

- build_sprites.py: `make_shadow_material()` (EEVEE Next alpha-blend node
  tree: Object texcoord → Length → Divide(r) → ColorRamp flat-to-0.6R +
  EASE falloff-to-0-R, dedicated ColorRamp Alpha → BSDF alpha; blend BLEND,
  shadow_method NONE; base color near-black indigo (0.016,0.012,0.045), max
  alpha 0.35) and `add_ground_shadow()` (20×20 grid plane, registered on the
  `ground` joint, deterministic, no seed change). Unit shadow at (0,0),
  z=0.001, R=0.25; standard shadow at (0.17,−0.02), z=0.002, R=0.10 —
  merging into one continuous contact patch with the pole base.
- post.py: removed the 2D ellipse; `process_frame` keeps RGBA through chroma
  compositing; `make_mask` derives the keying mask from the sheet's ALPHA
  channel (true coverage) — shadows survive at 35% instead of being
  greenness-keyed to 0; chroma variants save RGB sheets + alpha-derived LA
  masks. Pipeline is RGBA always.
- Fast loop passed: shadows verified in all 8 directions (plateau alpha 89,
  EASE falloff, uniform dark — shade, not paint/ring); lowest rows
  S 498 / SW 482 / W 486 / NW 486 / N 503 / NE 492 / E 489 / SE 489, all
  ≥6.6px above the edge flag.
- Full render: EXIT=0, 0 Tracebacks, 256/256 fresh by mtime, 0 MD5
  duplicates. post.py clean: all three variants + contact sheets + manifests.

## Open item → round 20b (director)

BBOX audit flagged 2 raw frames touching the bottom edge:
`villager_gather_d0_f3` (bbox bottom 512) and `_f4` (510) — the shadow disc
R=0.25 plus the gather deposit at (0.18,0.18) pushed the S-view gather
contact frames to the edge (pre-shadow they bottomed ~457). Director applied
the builder's recommended trim: SHADOW_R_UNIT 0.25 → 0.21 (bottoms ~500.5 in
every direction, still a large soft contact patch). Full re-render in
flight; then post.py → dark kit → evidence → modlens pre-flights (E/W MUST
read "standing beside a planted pole", N + villager grounded) → fresh critic.

## Not regressed (round-19 greens)

256/256 fresh + MD5-distinct; E/W mirror; grounding pins; tip clearance ≥48;
walk bob ≤10 with real gait; person-carrying-standard read; N-gather hand ON
deposit; gold ore node; ivory robe; teal accents; no exhaust/plume.
