# Fidelity pass spec — Sunwoven Citizen & Pathfinder (v2 character sheets)

**Source:** Docs/Concepts/generated-character-sheets/ (both PNGs + hermes-brief.md)
**Target:** ≥90% recreation of the sheets' kit + animation in the sprite pipeline.
**Mode:** gauntlet loop — builder implements, blind critic A/B's the render
against the sheets with modlens.

## Reading of the sheets (modlens-verified, 2026-08-06)

### Villager (Citizen)
- Proportion grid: **head:body ≈ 1:4.5**
- Yellow/saffron **turban** (wrap with drape volume — NOT a bare sphere),
  small **gold forehead gem** (emissive)
- Ivory tunic with **gold trims** (collar, cuffs) + **gold-trimmed flared skirt**
- **Teal waist sash** (restrained trim)
- **Orange/saffron diagonal shoulder strap**
- **Leather-tan satchel with scrolls** (visible load; "must read: satchel +
  headwrap" at 64–128px)
- Gold foot wraps; empty hands; no weapon
- Material legend: cloth ivory (matte–soft, roughness ≈0.75–0.9, slight
  self-luminous OK), woven gold (metallic 0.6–0.85, roughness 0.25–0.4,
  mild emissive), gem (emissive, visible at mid zoom), **soft glow seams =
  dedicated emissive material, not flat paint**

### Pathfinder (Scout)
- Same height as Citizen, **leaner**, waist-defined robe + **shoulder caps**
  (wider chest, cinched waist, flared hem)
- **Saffron hood BEHIND the skull** (face visible — NOT a dome on top)
- Small forehead gem; teal sash (restrained)
- **Hip bag opposite the pole** + diagonal strap
- **Tall thin gold standard ≈1.6× body height** with **turquoise cross-blade
  pennant** (4-pointed emblem, luminous, reads from all angles)
- **Forward lean 8–12°** through spine/chest (baked into idle + walk)
- Gold seam rings/trim (emissive); foot wraps; bent grip arm on the pole
- Top-down must read: tall standard + forward lean + turquoise pennant

### Animation targets (both)
- **idle**: Citizen — weight on one leg, slight sway/breath, arms relaxed
  empty; Pathfinder — forward weight, lean 8–12°, soft knees, bent grip arm,
  **pennant micro-sway**
- **walk**: bob, arm swing, **skirt hem sway**, feet stride (Citizen); faster
  cadence, keep lean, pole tracks grip, **pennant secondary sway**
- **gather**: reach → contact → pull up → **stow into satchel** (+ satchel
  pulse/bounce)
- Secondary motion: hem sway, wrap/hood drape, satchel bounce

## Locked deltas (builder must implement — with the existing gauntlet bars held)

1. **Materials** (the highest-leverage item):
   - `gold`: metallic 0.35→**0.7**, roughness 0.45→**0.3**, emission 0.2 (woven
     gold per legend)
   - `gold_line` (seam rings): dedicated **emissive seam** look — emission
     0.5, thin torus/quads at collar, cuffs, hem (both units)
   - `gold_l` (gem): emission 0.8, stays visible at 128px
   - `ivory`: roughness 0.85 (matte), emission 0.34→0.25 (cloth, not glow)
   - `turq`: roughness 0.6, emission 0.35 — keep restrained
   - `pack`/satchel: **leather-tan** (not saffron) per sheet read; roughness 0.7
2. **Villager**: turban = wrap volume + drape (e.g. 2-3 offset torus/sphere
   bands or a flattened wrap cap, NOT a single sphere); forehead gem already
   present — verify emissive read; satchel reads **leather with scrolls**
   (add 1-2 small scroll cylinders/edge highlights in gold_l on the satchel
   face); strap diagonal across chest (currently gold_line vertical-ish —
   angle it); skirt hem: gold trim ring at the flared hem (gold_line torus
   already at waist — add hem ring).
3. **Pathfinder**: shoulder caps (2 small ivory domes on the shoulders);
   hood behind skull (verify the saffron sphere is behind/above the face, not
   a dome — reposition if needed); **pole h: current 2.184 ≈ 1.15× body —
   grow toward ~1.5–1.6× body height (≈2.9–3.0m) IF the S/SW tip-clearance
   ≥48 bar and canvas-edge bars still hold** (measure; if the S/SW clearance
   breaks, keep the max that holds the bars and record the deviation);
   pennant: verify 4-pointed cross read (two blades already — ok).
4. **Animation**: idle pennant micro-sway (pathfinder, ±2–3px, deterministic
   sine on the pennant/tip); walk hem sway + satchel bounce (villager,
   ±2px); gather stow already exists — verify the motes visibly enter the
   satchel region.
5. **Proportion**: measure head:body on the new render (crown of wrap to
   chin : feet) — target ≈1:4.5 (±10%); adjust head r ±5% if far off.

## Bars that MUST hold (do not regress — rounds 1–26)

- 256/256 frames fresh + MD5-distinct; E/W structural mirror + pole opposite
  side; grounding (BC-03: no floating/climbing/mounted reads); tip clearance
  ≥48 all 8 dirs; figure height vs villager ±10% (pathfinder = citizen
  height); walk bob ≤10 with real gait phases; N-gather hand ON deposit;
  S gather f3/f4 ≤497; nothing touches canvas edge; person-with-standard
  read in every view; soft true-black shadow (plateau (0,0,0,153), no blob);
  seed 20260726 unchanged; no new non-deterministic draws.
