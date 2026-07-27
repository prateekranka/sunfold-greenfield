# Sunfold Visual Bible — Concepts Gate (Infinite Build)

Shared continuity rules for the five gameplay concept screens. Abstracted from AoE settlement/HUD grammar and 2001 cosmic negative-space principles. Original space-fantasy identity only — no AoE trade dress, faction logos, or copied compositions.

---

## Camera & Frame

| Spec | Value |
|------|--------|
| Aspect | Landscape 16:9 (iPad Air 13" gameplay composition) |
| Orientation | Landscape-left / landscape-right only |
| Pitch | ~55–60° down from horizontal (stable isometric/top-down RTS) |
| Zoom band | Mid-settlement: ~1 home fragment fills ~45–55% of playable viewport height; void always visible at edges |
| Rotation | North-up default; one-tap return-north implied by small compass/N control near minimap |
| Motion | Pan / pinch / 360° yaw — screens show static “paused moment” of that camera |

**Fragment-to-void ratio:** Habitable land ~40–55% of frame; deep cosmic void ~45–60%. Never fill the frame with contiguous terrain.

---

## HUD Geometry (identical every screen)

Icon-first, minimal readable glyphs. Soft dark translucent panels, thin light edges. No stone parchment AoE chrome.

1. **Top bar (full width, ~6% height)**  
   Left→right: Provisions · Matter · Lumen · Aether · Population · Age badge · Pause · Speed  
2. **Alerts** — thin strip directly under top bar (contest/victory/arrival cues)  
3. **Bottom-left** — circular or rounded-rect **minimap** with fog; enemy Core as restrained marker  
4. **Left edge above minimap** — vertical stack of **pinned group** slots (2–4)  
5. **Bottom-center** — selection panel: unit/building cards, life points, tasks, production queue  
6. **Bottom-right** — contextual command grid (construct / form / tech / abilities)

HUD must sit outside or lightly over void/edge — never obscure the central gameplay focus.

---

## Low-Poly Fidelity Ceiling

- Generic asset-pack RTS look: simple materials, flat/soft PBR, limited texel detail  
- Clear silhouette buildings; no hand-painted premium final art  
- Units readable at mid zoom via equipment + faction color accents  
- Target density: early screen ~8–20 units; battle screen ~40–80 total across both sides — still “60 FPS plausible”  
- Soft selection rings; life bars only on selected / damaged  

---

## Civilizations

### Sunwoven
- **Palette:** warm ivory, saffron, woven gold, solar fabric, restrained turquoise accents  
- **Feel:** mobile, adaptive, luminous; fabric canopies, light lattice, soft glow seams  
- **Strengths shown:** scouting, logistics, transport, expansion, Lumen  
- **Weakness shown:** lighter static defenses  
- **Landmark (Voyager+):** Dawn Loom — tall luminous loom/arch of woven light  
- **Signature unit:** Pathfinder (light mobile scout-logistics silhouette)

### Gravemark
- **Palette:** charcoal, layered slate, mineral blue, oxidized metal, copper seams  
- **Feel:** heavy, deliberate, territorial; plated volumes, stacked mass, bunker edges  
- **Strengths shown:** Matter, resilient buildings, defensive rings, deliberate military  
- **Weakness shown:** slower expansion / fewer transports  
- **Landmark (Voyager+):** Gravity Citadel — dense stacked mineral keep with copper seams  
- **Signature unit:** Bastion Walker (heavy quadruped/walker silhouette)

Neither good nor evil. ~60% shared RTS grammar, ~40% differentiated.

---

## Recurring Models & Landmarks

| Asset | Notes |
|-------|--------|
| Civilization Core | Mid-size central building; Sunwoven = luminous ivory hub; Gravemark = dark plated keep |
| Citizens | Small bipeds; faction cloth/armor color; gather/build animations readable |
| Scout / Pathfinder | Slim, elevated sensor/pack; Sunwoven turquoise trim |
| Light transport | Flat barge/skiff; dockable on fragment rim; unload ramp |
| Farms | Soft rectangular renewable plots (Provisions) |
| Matter nodes | Rocky mineral deposits at fragment edges |
| Dominion Anchor | Neutral monumental ring/pillar on central fragment; contested glow; ownership recolors to winner |
| Dawn Loom | Sunwoven Voyager landmark — vertical woven-light structure |
| Gravity Citadel | Gravemark Voyager landmark — heavy citadel mass |
| Warships | Angular void craft; stay in void, never on land |

---

## Unit Scale & Formations

- Citizen ≈ 1/4–1/3 building height  
- Vanguard / Ranged / Mobile / Siege silhouettes distinct  
- Formations: Line · Column · Wedge · Guard — spacing ~1.2–1.8 unit widths  
- Soft counter tags implied by silhouette only (Light / Armored / Massive / Structure)  
- Life bars above selected/damaged only  

---

## Dominion Anchor Design

- Neutral monumental geometry: low ring + central pillar/spire on largest central fragment  
- Contested: restrained amber/red pressure light (not full red-black screen)  
- Controlled: faction palette wash + subtle ownership banners/glow  
- Victory transform: Sunwoven Lumen weave into void; Gravemark would use mineral plating (screen 4 is Sunwoven win)

---

## Lighting & Starfield

- Deep black–indigo void; **sparse** stars; 1–2 distant celestial bodies max  
- Soft directional key from “above-camera”; gentle rim on fragment edges  
- Sunwoven Lumen = warm gold spill; Gravemark = cool mineral fill  
- Saturated red-black reserved for danger/pressure/contested alerts only  
- No busy nebulae dominating the playfield  

---

## Ages (slice)

- **Foundation** — sparse builds, light transport, no Voyager landmark  
- **Voyager** — landmarks appear; denser military; Dominion contest viable  
- Dominion / Ascension ages not shown as reached in this five-screen slice (Ascension = future path only)

---

## Continuity Checklist (every accepted frame)

- [ ] Same camera pitch & mid-zoom band  
- [ ] Same HUD placement  
- [ ] Low-poly placeholder, not promo poster  
- [ ] Buildings on land; ships in void  
- [ ] Correct civ / age / narrative beat  
- [ ] Achievable density  
- [ ] Readable faction ownership  
- [ ] No AoE UI chrome or copied refs  
