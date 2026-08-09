# Round 16 — verdict & builder response

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Builder handoff (round 16, application round)

Applied the locked round-15 fix to build_sprites.py:
1. Base disc ground-anchored: `joint="ground"`, offset (0.26, −0.022, 0.004),
   with `rig.set_joint("ground", (0,0,0))` (was `joint="chest"`).
2. Pole h 2.05 → 2.15 (chest-anchored, chain=("chest",) — grip preserved).
3. Hood sphere r 0.06 → 0.048, head z 0.075 → 0.062.
4. E/W: no further change (residual 18px measured).

Full 256-frame render completed (exit 0), post.py packed, dark kit written,
evidence regenerated (03:20). Measurement table (builder's measure_r16.py,
@512, idle f1): tip clearance PASS all 8 (80–162px, bar ≥48); discΔ S +2 /
SW +28 / W +65 / NW +48 / N +15 / NE −30 / E −15 / SE −29 (bar ≤3px — NOT
met); figure height N +31% / NE +24% (NOT met; S/SW/W/E/SE −25%…−1% below
floor); E/W pole length diff 18px (improved from 68, bar ≤10 — NOT met).

## Director verification (independent probes, 03:25)

1. **Determinism is genuinely broken (round-blocker).** Two separate-process
   renders of the pathfinder idle subset: 25/32 frames differ, worst channel
   diff 19. Root cause: `sc.render.seed = SEED` is a SILENT NO-OP in Blender
   5.2 — `RenderSettings.seed` does not exist (the `hasattr` guard swallows
   it). EEVEE Next removed `use_taa` (TAA is mandatory); `taa_render_samples`
   1 or 24 both leave cross-process jitter. There is NO render seed hook in
   EEVEE Next. The pipeline's earlier "determinism re-renders
   pixel-identical" claim was never actually verifiable cross-process.
   Impact: the committed sheets are valid (baked once); re-render
   reproducibility is what's broken. Correction to the docs is required.
2. **Feet anchor is the deeper grounding root cause.** The disc joint change
   did not fix grounding because the UNIT itself sits ~55px too low in the
   W/SW views — my probe measured feet at row 511 (the CANVAS BOTTOM EDGE)
   in W and SW, vs S 463 / N 471. A constant feet anchor (ANCHOR_FRAC /
   ANCHOR_Y) does not hold per direction once the chest lean offsets the
   root. This clips the pole and makes the disc mismatch directionally.
3. Disc rows (my probe): S 456 (planted) / SW 423 / W 382 / NW 501 / N 465 /
   NE 420 / E 429 / SE 427 — NOT constant across directions, confirming the
   ground-anchor alone was insufficient.

## Round 17 scope

1. **Determinism (time-boxed):** try the remaining levers — higher
   `taa_render_samples` (64/128), `use_raytracing=False`, shadow jitter
   toggles (`use_shadow_jitter_viewport` is viewport-only but check for a
   render-time equivalent), `use_bokeh_jittered=False`. If byte-identical
   cross-process renders remain unreachable in EEVEE Next, MEASURE the
   practical impact at the shipped scale (diff % of pixels in the final
   128px/256px sheets between two full renders) and document the limitation
   with numbers — the sheets are committed assets; gameplay determinism
   (B6, map + sim) is unaffected. Correct the docs (README + this trail)
   to state what is actually true.
2. **Feet anchor per direction:** make the unit's feet sit at the ground
   row (~455.6 @512) in ALL 8 directions — fix the root-level anchor so
   W/SW no longer clip at the canvas edge, then re-check the disc (the
   ground anchor then has a correct reference) and the tip clearance.
3. Re-verify: disc |Δ| ≤3px in all 8, tip ≥48px in all 8, figure height
   ±10% (N/NW/NE hood trim verification), E/W length ≤10px diff, and ALL
   round-14 passes (bob, gait phases, E-mirror, carrying read, gather
   contacts, node gold, palette, MD5-distinct frames).

## Files

Builder's round-16 changes are in build_sprites.py (03:10:27); frames
re-rendered 03:10–03:17; evidence 03:20. No git operations performed.
