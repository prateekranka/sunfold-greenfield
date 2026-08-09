# Fidelity R1 — VERDICT: REVISE (director-verified)

**Date:** 2026-08-06 · **Piece:** s1-p1 fidelity pass (v2 character sheets) ·
**Critic:** fresh blind critic (modlens gemini + cursor-agent fallback), verdict
verified claim-by-claim by the director with independent probes on the fresh
512px render.

## VERDICT: REVISE — 6 confirmed items, 3 critic claims refuted

The fidelity build is structurally sound (height parity 0.968-0.985, hood
behind skull, shoulder caps, pennant micro-sway ±2px, thin gold pole, 256
MD5-unique frames, gather reach intact, satchel bounce present). The failures
are material/readability issues — gold invisible, saffron washed, gems absent
— plus two animation-read gaps (turban band separation, gather stow into
satchel) and a marginal lean.

## Confirmed REVISE items (director re-measured on fresh frames)

| # | Item | Evidence (independent measurement) |
|---|------|-----------------------------------|
| 1 | **Gold seams/trims/foot-wraps render near-invisible** | `gold` material = metallic 0.7 / roughness 0.3 / emission 0.2 — EEVEE with no envmap reflects void → dark. Villager N: **0 gold-class px in the entire frame** (r>170, g>110, b<120, r-g>40); collar band (y330-380) mean RGB (177,150,112); hem band (160,160,138); feet band (158,135,99) — no gold read anywhere. Root cause: material, not missing meshes (rings/cubes exist at lines 423-425/444/506/627). |
| 2 | **Saffron desaturated vs sheet** | Render saffron mean RGB (188,155,104), HSV sat **0.41-0.45**; sheet (202,142,53) sat **0.74**. Reads "brown" not saffron (hood + turban). Palette census share unchanged vs shipped (saffron_gold 0.1) — it's a hue/sat gap to the SHEET, not a regression. |
| 3 | **Forehead gems invisible** | **0 bright-warm px (r>225, g>160, b<150) in the head band** of BOTH units' S (front) idle. Villager gem r 0.026 at (0, 0.055, 0.935); PF gem r 0.022 at (0.01, 0.058, 0.95) — likely occluded by the wrap cap (cap top z 1.072 vs gem z 0.99) and/or too small (≈5px @512 → 1.3px @128). Spec: gem must read at 128px. |
| 4 | **Turban reads as smooth dome — no band separation** | Villager S idle width profile: monotonic 15→50→25px taper (y295-349), **no dips at the two band torus locations** (band r 0.013-0.016 too thin to read at this scale). Spec: "wrap volume + drape, NOT a sphere". |
| 5 | **Gather stow: motes do not visibly enter satchel region** | Director's L-check was print-only (vacuous PASS). Actual bright-warm px in the rise/satchel region = **0** at f3/f5/f6. Spec: "verify the motes visibly enter the satchel region". |
| 6 | **Satchel scrolls not readable** | Scroll cylinders r 0.009 (≈2px @512, sub-pixel @128). Vision at 3x zoom: "scrolls are small/stubby". Spec: reads at 64-128px. |
| 7 | **Lean marginal at chest level** | Rig math (authoritative): idle_pose cum = 0.174 rad ≈ **10° at head** (in spec 8-12°) but **6.2° at chest** (spine+chest). Pixel fits (mine AND critic's) are unreliable (robe/pole occlusion) — use the rig value. Nudge lean 0.06 → ~0.085 for chest ≈ 9°. |

## Critic claims REFUTED (do not fix — director re-measured)

| Critic claim | Refutation |
|---|---|
| "Tip clearance bar broken NE/E (top 18/22px)" | The critic measured **tip-to-canvas-top** (18/22px). The bar is **crown-to-tip** clearance = NE **273** / E **270** ≥ 48 ✓ all 8 dirs (S 180, SW 157, W 167, NW 207, N 254, NE 273, E 270, SE 228). Canvas-edge bar (nothing touches edge) also holds: min tip-to-top margin 20px. |
| "Villager walk is a hop (f1 vs f5 overlap 0.999)" | The critic's overlap counted the **transparent background** (0.999 ≈ empty-frame agreement). Silhouette-only f1 vs f5 = **971 changed px**; E feet x-spans vary 77-128px across frames; frame-to-frame silhouette overlap 0.75-0.91 = real stride. Walk pose is unchanged from the round-26 shipped PASS. |
| "N view pennant is a 1-23px sliver" | Teal census per dir (strict classifier): S 64, SW 91, W 82, NW 95, N **66**, NE 51, E 30, SE 50 — N has 66 ≥ the 37-57 range. Cross-blade reads in all 8 dirs. |

## Also noted (record, no action)

- **Pole length ≈1.9-2.2× body** (pole h 2.884m ≈ 2.9-3.0m per spec's meter value) vs spec's "1.5-1.6×" (which would be 2.5m for a 1.565m body — the spec's own numbers are inconsistent). Bars all hold with huge margin (min clearance 157). The builder chose the spec's 2.9-3.0m number; keep, record deviation.
- Pole base disc, cross-blade pennant, E/W mirror (E-vs-flip(W) diff 3.47, pole opposite side, MD5-distinct), S gather rows ≤ 492, N-gather hand on deposit, walk bob (crown) ≤ 9, head:body 1:4.30 — all pass.
- EEVEE determinism: cross-process jitter ~0.004% of pixels (silhouette edges) — documented, not a defect.

## Fix brief for the builder (in priority order)

1. **Gold visibility**: raise `gold` emission to ≥0.6 and/or drop metallic to ~0.3-0.4 (no envmap in this pipeline — metallic void renders black). Same for `gold_line` (emission 0.5 → verify visible at collar/hem/feet; if still sub-pixel, thicken torus r 0.008 → 0.012+). Verify with the N-frame gold-class probe (target: ≥100 gold px in villager N, including the hem + feet bands).
2. **Saffron saturation**: bump SAFFRON/SAFFRON_D toward sheet sat ~0.7 (e.g. (0.98, 0.60, 0.18)-family) and/or raise emission 0.30 → 0.45. Verify hood/turban mean HSV sat ≥ 0.6, no "brown" vision read.
3. **Forehead gems**: move gem proud of the wrap/hood surface (z above cap top), enlarge to r ~0.035-0.04, keep gold_l emission 0.8. Verify ≥30 bright-warm px in head band, both units, S view.
4. **Turban bands**: thicken band toruses (r 0.013-0.016 → 0.025+) and/or add a visible drape tail on the rear; target: width-profile dips ≥6px at band rows. Keep crown height (figure-height bar holds) and tip clearance.
5. **Gather stow**: route the mote rise toward the satchel (0.21, 0, 0.50) so bright-warm px appear in the satchel region at f5/f6; optional satchel pulse on stow frame.
6. **Satchel scrolls**: enlarge gold_l scroll cylinders (r 0.009 → 0.016-0.02, h up) so they read at 128px.
7. **Lean**: idle_pose lean 0.06 → ~0.085 (chest ≈ 9°, head ≈ 14° — keep ≤12° at head by trimming head factor to 0.4 if needed). Re-verify no bar regressions (crown bob, tip clearance, gather rows).

## Bars that MUST hold (do not regress)

256/256 fresh + MD5-distinct; E/W mirror; grounding; tip clearance ≥48 all 8
dirs; height ±10%; walk bob (crown) ≤10; N-gather hand ON deposit; S gather
≤497; nothing touches canvas edge; person-with-standard in every view; soft
true-black shadow; seed 20260726; no new non-deterministic draws.

## Next

- Builder implements fix brief → fast loop render → fid_check (director's
  corrected script: crown-bob, col-shift sway, first-narrow-row chin) →
  modlens/cursor vision gates → full pipeline → fresh blind critic (round 2).
