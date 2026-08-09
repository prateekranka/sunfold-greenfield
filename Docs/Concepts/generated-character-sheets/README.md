# Generated character sheets — Sunwoven Citizen & Pathfinder

**v2 production pack** (2026-08-06) for a Hermes + DeepSeek Flash agent building
**Three.js**-animatable assets (skinned meshes / GLTF-friendly hierarchy / idle +
move cycles). Generated **from written design sources only**. No existing unit
sprites, textures, concept PNGs, or Codex reference images outside this folder
were opened or viewed.

## Outputs

| File | Unit |
|------|------|
| `sunwoven-villager-character-sheet.png` | Sunwoven Citizen / Villager — v2 production pack |
| `sunwoven-pathfinder-scout-character-sheet.png` | Sunwoven Pathfinder / Scout — v2 production pack |
| `hermes-brief.md` | Sidecar brief for Hermes/Three.js (palette, kit, hierarchy, anim, prompts) |

Each PNG sheet includes: turnaround (Front / Side / Back / idle), RTS top-down
readability thumbnail, proportion grid, material legend, Do/Don’t, kit inventory,
pose notes, construction/seam-glow callouts, and palette hex + usage roles.

## Textual sources used

### Faction palette & feel

`Docs/Concepts/00-visual-bible.md` (Sunwoven):

- Palette: warm ivory, saffron, woven gold, solar fabric, restrained turquoise accents
- Feel: mobile, adaptive, luminous; fabric canopies, light lattice, soft glow seams
- Signature unit: Pathfinder (light mobile scout-logistics silhouette)
- Scout / Pathfinder note: slim, elevated sensor/pack; Sunwoven turquoise trim
- Citizens: small bipeds; faction cloth color; gather/build readable

### Silhouette contracts

`Docs/Design/01-UNIT-ROSTER.md` §5:

- **Citizen:** Smallest humanoid. Carries a visible load. No weapon at rest.
- **Pathfinder:** Citizen height, leaner, forward-leaning stance, a tall thin standard — reads as *fast* from directly above.

Role/stats (same file): Pathfinder is the T1 scout (Formation Yard); Citizen is the T1 economy worker.

### Economy-unit construction notes (procedural sprite builder)

`sunwoven-sprites/README.md` + `sunwoven-sprites/build_sprites.py` + `gauntlet_evidence.py`:

- Labels: “Sunwoven Citizen” (villager) and “Sunwoven Pathfinder”
- Bible palette census targets: ivory ≈ RGB(240,228,200) → `#F0E4C8`, saffron ≈ (235,168,74) → `#EBA84A`, turquoise ≈ (63,167,166) → `#3FA7A6`, warm tan skin → `#CC9C6B`, woven gold → `#DEA84F`
- **Citizen kit:** ivory robe + flared skirt, turquoise waist sash, gold seam rings, saffron headwrap + gold forehead gem, saffron hip satchel + strap, gold foot wraps, no weapon
- **Pathfinder kit:** same height, leaner waist-defined robe + shoulder caps, forward lean, saffron hood *behind* head, hip bag + diagonal strap, tall gold standard with turquoise cross-blade pennant, bent grip arm on the pole

## Design choices derived from text

1. **Shared faction read** — both sheets use ivory solar fabric + saffron + turquoise + woven gold so they read as one civilization at RTS scale.
2. **Worker vs scout** — Citizen has the satchel “visible load” and empty hands; Pathfinder drops the gather load emphasis and gains the tall thin standard + forward lean required by the silhouette contract.
3. **Pathfinder head** — saffron volume sits behind the skull (hood/hair), not as a dome on top, matching the builder’s written rebuild notes.
4. **Luminous soft seams** — emissive seam materials for Three.js (not flat paint), per visual-bible “soft glow seams,” without inventing heavy armor or Gravemark charcoal.
5. **Three.js consumer** — sheets + `hermes-brief.md` target GLTF/skinned animation, not sprite atlases as the primary deliverable.

## Explicitly not used

- Any `.png` / `.jpg` / `.webp` under `Docs/Concepts/references/`, `sunwoven villager/`, sprite atlases, contact sheets, or Blender renders
- img2threejs reconstruction (requires looking at reference images as rebuild targets; sheets here are the *output* refs for a later Hermes build)
