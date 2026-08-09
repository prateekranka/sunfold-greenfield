# Hermes brief — Sunwoven Citizen & Pathfinder (Three.js)

**Audience:** Hermes agent + DeepSeek Flash building **Three.js-animatable** assets  
**Primary deliverable:** skinned meshes / GLTF-friendly hierarchy / idle + move cycles  
**Not primary:** 2D sprite atlases (sprites exist elsewhere; this pack is for 3D)

**Sheet PNGs (authoritative visual pack, v2):**

- `sunwoven-villager-character-sheet.png` — Citizen / Villager
- `sunwoven-pathfinder-scout-character-sheet.png` — Pathfinder / Scout

**Text sources only (do not open other unit sprites/textures/refs):**

- `Docs/Concepts/00-visual-bible.md` (Sunwoven palette & feel)
- `Docs/Design/01-UNIT-ROSTER.md` §5 silhouette contracts
- `sunwoven-sprites/README.md`, `build_sprites.py`, `gauntlet_evidence.py` (kit / palette census vocabulary)

---

## 1. Unit identities & roles

| Unit | Aliases | Role | Roster notes |
|------|---------|------|--------------|
| **Citizen** | Villager | T1 economy worker (Civilization Core) | Smallest humanoid; gather/build readable; can fight weakly |
| **Pathfinder** | Scout | T1 scout-logistics (Formation Yard) | Same height as Citizen, leaner; 20 m sight; fast (4.6 m/s) |

Faction feel (visual bible): mobile, adaptive, luminous — fabric canopies, light lattice, **soft glow seams**. Signature scout silhouette is the Pathfinder.

---

## 2. Palette (exact hex + material roles)

Use these hexes as material base colors. Prefer **separate materials** for emissive seams vs matte cloth.

| Name | Hex | RGB census target | Role |
|------|-----|-------------------|------|
| **Ivory** | `#F0E4C8` | 240, 228, 200 | Body cloth / solar fabric (matte–soft, slight self-luminous fabric OK) |
| **Saffron** | `#EBA84A` | 235, 168, 74 | Head volume (Citizen wrap / Pathfinder hood) + satchel/bag accents |
| **Turquoise** | `#3FA7A6` | 63, 167, 166 | **Trim only** — sash, pennant; never flood the body |
| **Woven gold** | `#DEA84F` | ~222, 168, 79 | Seams, standard pole, gems, foot wraps — metallic / luminous |
| **Warm tan skin** | `#CC9C6B` | ~204, 156, 107 | Skin |

**Material classes (both units):**

| Class | Surface | Three.js hint |
|-------|---------|---------------|
| Cloth (ivory / saffron) | Matte–soft | `metalness≈0`, `roughness≈0.75–0.9`; optional low emissive tint |
| Woven gold | Metallic / luminous | `metalness≈0.6–0.85`, `roughness≈0.25–0.4`; mild emissive |
| Gem | Polished emissive | Separate material; `emissive` ≈ gold, strength visible at mid zoom |
| Soft glow seams | Emissive bands | **Dedicated emissive material** — not flat albedo paint |
| Leather / tan bag | Matte | Darker saffron/tan; no metal |

---

## 3. Silhouette contracts (incl. top-down)

From `01-UNIT-ROSTER.md` §5:

| Unit | Contract |
|------|----------|
| **Citizen** | Smallest humanoid. **Carries a visible load.** **No weapon at rest.** |
| **Pathfinder** | Citizen height, **leaner**, **forward-leaning** stance, a **tall thin standard** — reads as *fast* from directly above. |

### RTS readability at ~64–128px

| Unit | Must-read shapes (top-down / from-above) |
|------|------------------------------------------|
| **Citizen** | **Satchel bulge** + **headwrap volume** |
| **Pathfinder** | **Tall standard** + **forward lean** (COM offset) + **turquoise pennant** tip |

Camera context: gameplay pitch ~55–60° down; units must still read at mid zoom via equipment + faction accents (visual bible).

---

## 4. Kit inventory (mesh / part checklist)

### Citizen / Villager

- [ ] Skin body (warm tan)
- [ ] Saffron headwrap (volume on / around crown + drape)
- [ ] Forehead gem (woven gold, emissive)
- [ ] Torso robe (ivory)
- [ ] Flared skirt / hem (ivory)
- [ ] Turquoise waist sash (trim)
- [ ] Satchel body (saffron / leather–tan) — **visible load**
- [ ] Satchel strap
- [ ] Gold seam rings (collar, cuffs, hem) — **emissive seams**
- [ ] Foot wraps / sandals (woven gold)
- [ ] Hands empty at rest (no weapon mesh)

### Pathfinder / Scout

- [ ] Skin body (warm tan) — same overall height as Citizen, leaner waist
- [ ] Ivory robe + shoulder caps (wider chest, waist cinch, flared hem)
- [ ] Turquoise sash (restrained accent)
- [ ] Saffron hood **behind skull** (hair/hood volume — face visible)
- [ ] Forehead gem (small)
- [ ] Hip bag (saffron/tan) on side **opposite** the pole
- [ ] Diagonal strap across torso
- [ ] Tall thin gold standard pole (~**1.6× body height**)
- [ ] Turquoise **cross-blade pennant** (luminous; reads from all angles)
- [ ] Gold seam rings / trim (emissive)
- [ ] Foot wraps / sandals
- [ ] Grip hand / bent arm on pole

---

## 5. Hierarchy suggestion (Three.js / GLTF)

Shared humanoid core; attachments as children or skinned extras.

```
Root (unit origin / ground anchor)
└── Hips
    ├── Spine
    │   └── Chest
    │       ├── Neck
    │       │   └── Head
    │       │       ├── HeadwrapOrHood   (Citizen wrap / Pathfinder hood mesh)
    │       │       └── ForeheadGem
    │       ├── Shoulder_L → UpperArm_L → LowerArm_L → Hand_L
    │       └── Shoulder_R → UpperArm_R → LowerArm_R → Hand_R
    │           └── [Pathfinder] StandardSocket  → StandardPole → Pennant
    │               (or parent pole to Hand_R if rigidly gripped)
    ├── UpperLeg_L → LowerLeg_L → Foot_L
    └── UpperLeg_R → LowerLeg_R → Foot_R
SatchelOrHipBag  (parent to Chest or Hips; strap as skinned or rigid)
Sash             (parent to Hips/Chest)
Robe / Skirt     (skinned to spine + legs; soft secondary optional)
```

**Pathfinder notes:**

- Prefer a **StandardSocket** on the gripping hand or chest so the pole stays planted in grip space.
- Add **1–2 soft bones** on the pennant (or simple vertex sway) for secondary motion.
- Bake **forward lean** into the rest/bind or into idle/walk clips (~**8–12°** through spine/chest), not only into a static mesh tilt.

**Citizen notes:**

- Satchel as separate mesh (readable load); strap skinned or constrained across torso.
- Gather cycle should animate hands + slight satchel pulse/squash on stow.

**Export:** GLTF/GLB, reasonable poly for RTS crowds, **separate materials** for cloth / gold / turquoise / emissive seams / skin.

---

## 6. Animation targets

| Clip | Citizen | Pathfinder |
|------|---------|------------|
| **idle** | Weight on one leg; slight sway/breath; arms relaxed **empty** | Weight **forward**; lean ~8–12°; soft knees; bent grip arm on pole; pennant micro-sway |
| **walk / run** | Bob, arm swing, skirt hem sway, feet stride | Scout move: faster cadence; keep lean; pole tracks with grip; pennant secondary sway |
| **gather** | Reach → contact → pull up → **stow into satchel** | — (not required) |
| **scout move** | — | Primary locomotion identity; tall standard remains vertical read from above |

**Secondary motion:** hem sway, hood/wrap drape, sash tail (if present), pennant soft bones, satchel bounce (Citizen).

Reference timings from sprite pipeline (optional parity): idle ~4f @ 3fps loop; walk ~8f @ 8fps; gather ~8f @ 6fps — translate to continuous Three.js clip lengths, not sprite cells.

---

## 7. Do / Don’t constraints

### Shared

- **DO:** ivory solar fabric + saffron + turquoise **trim** + woven gold seams; soft **emissive** seams.
- **DON'T:** Gravemark charcoal / heavy armor / dark plated volumes.
- **DON'T:** flood the body with turquoise (trim / pennant / sash only).

### Citizen

- **DO:** empty hands at rest; **visible** satchel load.
- **DON'T:** weapons at rest; hide the satchel.

### Pathfinder

- **DO:** saffron hood **behind** the skull (face readable); forward lean; bent grip arm; tall thin standard + turquoise pennant.
- **DON'T:** saffron **dome on top** of the head; missing standard; stiff upright parade stance with no lean.

---

## 8. Copy-paste generation / modeling prompts

### Citizen / Villager

```
Sunwoven Citizen (Villager), stylized miniature-quality RTS humanoid for Three.js/GLTF.
Warm tan skin #CC9C6B. Ivory solar-fabric robe #F0E4C8, knee-length flared skirt,
turquoise waist sash #3FA7A6 as trim only, woven-gold emissive seam rings at collar/
cuffs/hem #DEA84F, saffron headwrap #EBA84A with small gold forehead gem, saffron
hip satchel with strap (visible load), gold foot wraps. Empty hands — no weapon.
Soft glow seams as emissive materials, not flat paint. Readable at 64–128px via
headwrap + satchel. Hierarchy: hips→spine→chest→head; satchel attachment; skinned
robe. Anim: idle sway, walk, gather reach-and-stow. No Gravemark charcoal armor.
```

### Pathfinder / Scout

```
Sunwoven Pathfinder (Scout), same height as Citizen but leaner waist-defined robe
with shoulder caps, ivory #F0E4C8, turquoise sash #3FA7A6 trim only, saffron hood
#EBA84A BEHIND the skull (not a dome on top), face and small gold gem visible,
hip bag opposite pole with diagonal strap, tall thin woven-gold standard ~1.6×
body height #DEA84F with turquoise luminous cross-blade pennant #3FA7A6, bent grip
arm on pole. Forward lean ~8–12° through spine/chest. Soft emissive gold seams.
Top-down must read: tall standard + lean + turquoise pennant. GLTF-friendly bones;
pennant soft bones optional. Anim: idle lean, scout walk/run with secondary pennant
sway. No Gravemark charcoal/heavy armor; no turquoise-flooded body.
```

---

## 9. Asset contract (explicit)

- **Format:** GLTF / GLB preferred for Three.js.
- **Poly:** reasonable real-time RTS density (crowd-safe), not film sculpt.
- **Materials:** separate slots for ivory cloth, saffron cloth, turquoise trim, woven gold, emissive seams, skin, bag leather.
- **Pivot:** ground at feet center (sprite pipeline used feet-center anchor; keep a clear root).
- **Primary output is 3D animation-ready**, not a sprite atlas.

---

## 10. Sheet pointer checklist for the builder

1. Open `sunwoven-villager-character-sheet.png` and `sunwoven-pathfinder-scout-character-sheet.png`.
2. Match turnaround, palette hex strip, material legend, kit inventory, Do/Don’t, pose notes, and seam-glow callouts.
3. Validate top-down silhouette thumbnails against §3 of this brief.
4. Build hierarchy per §5; ship idle + locomotion (+ Citizen gather).
5. Re-check Do/Don’t before finalizing (hood behind skull; empty Citizen hands; no Gravemark kit).
