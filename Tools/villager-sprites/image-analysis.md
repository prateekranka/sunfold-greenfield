# Image analysis — Sunwoven Villager (layered observation protocol)

Refs: `refs/villager-front.png`, `refs/villager-back.png`, `refs/villager-side-props.png`
(all 1400×1400 PNG, flat navy `#0d1b3e`-ish backdrop, three-quarter-key studio lighting).

Observation is separated from inference. Inference lines are marked `INFER`.

---

## Layer 1 — Identification & classification

- **Work type:** full-body humanoid character turnaround sheet of a *agrarian gatherer/porter*
  figure — a farming villager, not a soldier.
- **Broad classification:** character (articulated organic assembly) + four rigid props
  (back-carried basket with pack frame, rope-handled hand pail, hafted sickle, and the boots/belt
  hardware group).
- **`primaryDomain`:** `hybrid` — the figure is `character`, but four identity-carrying props are
  hard-surface objects with their own component trees. The props are shown *detached* in
  `villager-side-props.png`, which is an explicit modelling invitation.
- **Confidence:** 0.93. The three views agree on silhouette, palette and prop inventory.

## Layer 2 — Overall form & silhouette

- **Stance:** symmetric standing rest, feet ~1 foot-length apart, arms held ~20° out from the
  torso (a modelling/A-pose, not a natural idle). Weight is even; no contrapposto.
- **Symmetry:** bilateral for the body; **asymmetric for the loadout** (basket on the back, pail
  on one hip, sickle in one hand).
- **Bounding volume:** upright cuboid ≈ 0.42 W × 0.34 D × 1.00 H in body units. The back basket
  pushes depth to ≈ 0.55 D behind the spine.
- **Primitive decomposition:** tapered cylinders (limbs, neck), a lofted trapezoidal torso, a
  sphere-plus-jaw-wedge head, a **barrel/drum** for the back basket (a cylinder with a convex
  bulged wall, capped by a domed lid), a **truncated cone** for the hand pail, a swept arc for
  the sickle blade, and a cylinder for the sickle haft.
- **Shape language:** organic body inside geometric, hand-made cargo. The read is *soft cloth
  over a hard woven cage*.
- **Head-unit proportion (measured off `villager-front.png`):** crown → sole spans ≈ 1235 px;
  head height (crown of the hair bun excluded, hairline-to-chin extended to skull top) ≈ 152 px.
  → **≈ 7.6 head-units** = realistic adult proportion, NOT stylized or chibi.
  `INFER` for an RTS unit read at 57° pitch this must be re-proportioned; see the contract.

## Layer 3 — Macro → meso → micro decomposition

**Macro (independent major parts)**
1. Head group
2. Torso group
3. Arm groups (×2)
4. Leg groups (×2)
5. Back-basket assembly
6. Hand-pail assembly
7. Sickle assembly

**Meso (sub-assemblies)**
- Head: skull, face, hair top-knot (single bun), wrapped cloth headband with a rear tie + two
  short tails, ears.
- Torso: crossed-wrap tunic body (right panel over left), a shorter open **vest/tabard** layer on
  top, a sash belt, a **cast disc buckle** with a radiating sun motif, a hanging front apron panel
  with a printed geometric border, a teal drape/scarf tail down the left front and another down
  the back, tasselled cord ends.
- Arms: upper arm, forearm, sleeve rolled to just below the elbow with a **cuff band**, bare
  wrist stacked with **3–4 flat metal bangles per wrist**, hand.
- Legs: loose gathered trousers, calf **wrap bindings** in a crossed lattice from ankle to below
  the knee, ankle boots with a rolled collar and a strap over the instep.
- Back-basket: barrel body, domed lid, rope lashings (girth rings + vertical ribs), a rigid
  side-mounted **carry frame** (a curved bent-rod spine + horizontal rungs), two shoulder straps,
  a lower retaining strap, and a teal cloth tab.
- Hand-pail: tapered woven body, a wide banded midriff with a stamped pattern, a rope bail
  handle, a knotted rope girth, and a hanging cloth tail.
- Sickle: crescent blade, a decorated **bolster/ferrule** with a radial rosette, a wrapped grip
  with regular binding rings, and a butt ring.

**Micro (feature groups)**
- Basketry weave: an over-under plait, ~28 vertical staves × ~22 horizontal courses on the back
  basket; a finer plait on the pail.
- Gold trim piping along every cloth edge (collar, vest opening, apron border, cuffs, boot seams).
- Teal accent bands: collar lining, sleeve stripes, apron border, sash tail, basket rim band,
  pail midriff band.
- Boot toe-caps and heel counters in polished brass, plus a **four-point stud rosette** on each
  outer ankle.
- Stitch and fold lines: waist cinch gathers, elbow crease, knee bag, trouser gather at the calf.

## Layer 4 — Spatial relationships (scene graph)

- `<headband, wraps, skull>` — overlap contact, sits above the brow, ties at the occiput.
- `<top-knot, embedded-in, crown>` — socket contact at the parietal apex.
- `<vest, overlaps, tunic>` — layered shell, opens down the sternum.
- `<sash-belt, girdles, waist>` — overlap, closed at the front by the disc buckle.
- `<disc-buckle, flush-with, sash-belt>` — embed contact, front-centre.
- `<apron-panel, hangs-from, sash-belt>` — butt contact at the belt's lower edge.
- `<basket-frame, attached-to, upper-back>` — carried by two shoulder straps that pass over the
  trapezius and return to the frame; a third strap crosses the lumbar. Contact is **strap-borne,
  not fused** — the basket must be a child of a back socket, never welded to the torso mesh.
- `<basket-body, socketed-into, basket-frame>` — the frame's curved spine runs down the basket's
  lateral face; the basket hangs *off* it.
- `<pail, hangs-from, belt-ring-or-hand>` — **ambiguous, see Layer 8.**
- `<sickle-haft, gripped-by, hand>` — socket contact; the blade's concave edge faces forward.
- `<calf-wrap, spirals-around, lower-leg>` — overlap, ankle → below-knee.
- `<boot-collar, overlaps, trouser-hem>` — the trouser tucks inside.

## Layer 5 — Materials & surface (PBR)

| Surface | metalness | roughness | Relief / notes |
|---|---|---|---|
| Cloth — cream tunic, vest, trousers | 0.0 | 0.85–0.92 | woven micro-grain; fold creasing at elbow, waist, knee |
| Cloth — teal accents / drape | 0.0 | 0.80 | same weave, higher saturation |
| Cloth — headband | 0.0 | 0.88 | slightly crisper, starched read |
| Skin | 0.0 | 0.45–0.55 | soft; specular concentrated on nose, cheek, forearm |
| Hair | 0.0 | 0.35 | dark brown, one glossy anisotropic band around the bun |
| Basketry (basket + pail) | 0.0 | 0.70 | strong over-under normal relief; this is the dominant texture of the design |
| Rope (lashings, bail, cords) | 0.0 | 0.80 | twisted-strand helical relief |
| Gold trim, buckle, bangles, boot caps | 0.85–0.95 | 0.30–0.40 | polished but not mirror; warm F0 |
| Sickle blade | 0.95 | 0.22 | polished steel with faint mottled forge patina |
| Leather — boots, straps | 0.0 | 0.55 | satin, edge-worn lighter at the toe |
| Wood — basket frame, sickle haft | 0.0 | 0.65 | axial grain |

## Layer 6 — Colour & finish

Sampled from `villager-front.png`, lighting not removed (`INFER` for albedo):

- Cream cloth: hue ≈ 40°, value high (~0.86), saturation low (~0.16) — **satin**.
- Teal accent: hue ≈ 190°, value mid (~0.52), saturation mid (~0.38) — **matte**.
- Gold: hue ≈ 44°, value mid-high, saturation mid-high — **metallic**.
- Basketry: a two-stop gradient, warm tan `hue ≈ 34°` at the lit crown → deeper amber-brown at
  the shaded underside.
- Skin: hue ≈ 26°, mid value, low-mid saturation.
- Hair / dark leather: near-neutral very low value.

This is exactly the project's locked Sunwoven livery — **ivory + gold + cyan/teal accent** —
so the palette does not need reinventing, only matching.

## Layer 7 — Identity-defining features

Ranked by how much each one carries the "this specific unit" read:

1. **The back basket** — the biggest single silhouette element; its barrel bulge, domed lid, rope
   girth rings, and the rigid side carry-frame.
2. **The sun-disc belt buckle** — a radiating star/sun rosette on a cast gold disc.
3. **The crossed calf wraps** into brass-capped ankle boots.
4. **The crescent sickle** with its rosette bolster and ring-wrapped grip.
5. **The rope-bailed hand pail** with its stamped teal midriff band.
6. **The wrapped headband + top-knot** silhouette.
7. **Stacked wrist bangles** (3–4 per side).
8. **Gold piping on every cloth edge** and the printed geometric border on the apron panel.
9. **The teal drape tail** hanging past the hip.

## Layer 8 — Uncertainty & single-image limits

- **`uncertain` — handedness is inconsistent between views.** In `villager-front.png` the sickle
  is in the figure's **left** hand and the pail sits on the figure's **right**. In
  `villager-back.png` the sickle reads as the **right** hand and the pail as the **left**. The two
  views disagree; one of them is mirrored. Resolution: build **both** hand sockets and make the
  tool hand a parameter. Do not hard-code it.
- **`uncertain` — how the pail is carried.** The front view reads as *hanging off the belt/harness
  beside a relaxed open hand*; the back view reads as *gripped by the bail*. Both are plausible
  and the animation needs both anyway (idle = stowed on the belt, carry = in hand).
- **`hidden` — the basket's interior, lid seam, and how the frame terminates at the lumbar.** The
  prop breakout in `villager-side-props.png` shows the frame from one side only.
- **`hidden` — sole tread, palm detail, back of the head under the bun.**
- **`occluded` — the tunic's lower closure behind the apron panel**, and the left flank behind the
  hanging drape.
- **`undetermined` — the figure's read gender.** The front view reads female-presenting, the
  side view reads male-presenting. This is a generic villager unit; build one androgynous
  silhouette rather than committing to either, which also matches AoE's interchangeable villager.
- **Perspective:** the three views are near-orthographic with mild lens compression. Usable as a
  front/side/back reference triad — this is a **strong** input, well above the single-view case
  the rubric warns about.

## Suitability verdict

**`character-conditional -> stylized`** (rubric §Character/Human Suitability).

Passes: one obvious target, three agreeing views, strong silhouette, all major materials visible,
hidden sides reasonably inferable, and every form reduces to procedural primitives (revolved
barrels, extruded profiles, swept arcs, tube-along-curve rope, instanced weave).

Conditional on: stylization is accepted (no photoreal skin, no strand hair, no cloth simulation),
and the target is a **real-time RTS unit read at ~60–90 px tall**, not a hero render.
