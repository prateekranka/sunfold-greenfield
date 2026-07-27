# G1 Evidence — Camera, selection, orders, and an authored surface

**Status: G1 substantially proven; not yet signed off.** Captured 2026-07-27 on
**Sunfold Cycle 1 iPad Air 13**, iPadOS 26.5 simulator, seed `20260726`. Latest
frames are from build 36 (`** BUILD SUCCEEDED **`, no warnings in project
sources). `60 fps` held in every frame below.

| File | What it shows |
|---|---|
| `g1-00-before-authored-meshes.png` | Presenter first light: Core, four citizens and deposits rendering from simulation state, with my stand-in transport visibly broken — an oversized white dart clipping the causeway. |
| `g1-01-populated-home-fragment.png` | After swapping in the authored meshes. Core, citizens, four deposit types, transport docked at the rim. Surface still bare. |
| `g1-02-selection-ring.png` | First proof that tapping a citizen raises the selection ring. |
| `g1-03-dressed-home-fragment.png` | The dressed fragment: cell seams, straw shrub fringe, scattered rock, soil tone variation, shore band, and the rebuilt causeway. |
| `g1-04-selection-ring.png` | Tap on a citizen → turquoise ring. |
| `g1-05-order-marker.png` | Tap on open ground with that citizen selected → pulsing destination marker at the tapped point. |
| `g1-06-citizen-arrived.png` | Same citizen, seconds later, standing at the tapped point with its ring; the marker has expired on schedule. Three siblings still by the Core. |
| `g1-07-close-zoom-55m.png` | Full-resolution frame at what used to be minimum zoom. |
| `g1-08-authored-surface-final.png` | Build 31, full resolution, default framing: the dressed fragment at the corrected default zoom with unit scale applied. The reference frame for this gate. |
| `g1-09-selection-after-scale.png` | Selection still lands on a citizen after the footprint change, so the drawn silhouette and the tappable area still agree. |
| `g1-10-craggy-rim.png` | The rim after the third pass: broken outline, a shelf in the flank, cool stone under warm ground, and rock spurs hanging below the underside. The reference frame for this gate. |
| `g1-build-36-succeeded.log` | Build log for the frames above. |
| `rejected/` | The six rendered states rejected along the way, kept because each one is why a value in the code is what it is. |

## Proven in the rendered build

- **Tap to select.** Tapping a citizen raises its ring; the orthographic
  screen→world unprojection agrees with the simulation's own footprints.
- **Tap to move, with feedback.** Tapping open ground issues the order, the
  destination marker appears and pulses at the tapped point, the citizen walks
  there and stops on it, and the marker expires by itself.
- **Selection survives the order.** The ring stays on the unit through the walk.
- **Pinch zoom**, with the sky counter-scaling correctly as it changes.
- **Simulation projection**: 1 Core, 4 citizens, 1 transport, 5 deposits per home
  fragment plus deposits on all seven fragments, at 60 fps.
- Authored meshes replaced every stand-in. The only remaining fallback is the
  Dawn Loom, unauthored until G4, which logs a visible warning when used.

## Not yet proven — why G1 is not signed off

- **The gait itself.** Units have been observed departing, travelling and
  arriving, but no frame yet isolates a mid-stride pose, so the anti-lockstep
  phase offset, the walk/idle hysteresis band and facing-on-stop remain
  **unverified in play**. They are unit-testable and untested — see below.
- **Camera-relative motion under yaw** has not been re-checked with units present.
- **Deterministic tests remain `Proof Pending`.** They compile and link but cannot
  be executed in this environment; the `SunfoldCore` SwiftPM extraction that will
  run them is the next structural task.
- No independent reviewer has done a side-by-side against concept 01.

## This cycle: closing the "empty cream plate" gap

The previous cycle's largest mismatch was that the habitable surface was blank.
It took five rejected rendered states to close, each kept in `rejected/`:

1. **`r1-crossing-families-graph-paper.png`** — two crossing straight families of
   seams. Read as graph paper. Concept 01's seams enclose irregular *cells*.
2. **`r2-hex-lattice-honeycomb.png`** — a jittered hex tiling at `radius × 0.215`
   with 0.30 wander. Still unmistakably a honeycomb. Cells had to drop to
   `radius × 0.115` with wander past *half* the spacing before the hexagon
   dissolved into the crack network the concept shows.
3. **`r3-shrubs-as-gold-urchins.png`** — foliage as a clump of splayed blades on a
   tall crown. From a 57° camera that reads as a spiked ball, not a plant. Fixed
   by making the crown wider than it is tall and the fronds short and broad, so
   they break a dome instead of radiating off a cone. Colour pulled 38% toward
   ivory: full-strength gold was competing with the Core's own ribbing.
4. **`r4-causeway-brown-slab.png`** and **`r5-causeway-rails-sorted-grey.png`** —
   see below.

Two defects found here were real bugs, not taste:

- **Alpha on an `UnlitMaterial` tint does nothing.** The material renders fully
  opaque until `blending` is set. Every "translucent" surface in the build —
  ground seams, causeways, selection rings — had been drawing at full strength
  since G0. Fixed in `StructureMaterial.glow`.
- **Transparent surfaces do not reliably sort above one another.** With the fix
  in, the causeway's bright rails came back *grey*, because the dim deck under
  them composited back over the top. Rails are now opaque so they draw in the
  opaque pass and write depth.

The causeway also taught a colour lesson worth keeping: against a near-black
void, alpha *is* brightness, and dark gold is simply brown. It is now a cool
gravity field carrying two lit warm rails — which is also the more coherent read,
since gravity is the cool half of the locked identity.

## Second pass: readability of the people

Measuring rather than guessing: in concept 01 the home fragment spans about 71%
of the viewport width. In the build at the G0 default zoom of 82 m it spanned
41%. The diorama was reading as a distant model, and the citizens on it as pale
specks — which is a failure of the plan's human-scale stakes, not a matter of
taste. Two changes, both in `SkirmishTuning`:

- **`cameraDefaultZoom` 82 → 58**, derived from that measurement: a 48 m fragment
  at 71% of a 4:3 viewport needs a 68 m horizontal extent, so 51 vertical, and 58
  leaves breathing room around the rim. `cameraMinZoom` 55 → 34 so a player can
  get close enough to read one citizen.
- **`unitVisualScale` 1.25**, with `UnitKind.footprintRadius` carrying the same
  factor. A unit drawn 1.25× life-size must also be *tapped*, spaced and kept off
  the rim at 1.25×; splitting the two would make the silhouette and the hit area
  disagree. `g1-09` is the check that they still agree.

Planting then read as one repeated mound, so growth gained a tall variant — a
bare trunk under an offset crown — and a much wider size range. Three heights is
what makes concept 01's island read as a place rather than a scatter pass.

## Third pass: the rim

The fragment edge was a smooth polygonal skirt where concept 01 is broken rock.
`sideCount` 18 → 30, a shelf ring added between rim and taper, both flank rings
jittered in height as well as radius, and rock spurs hanging below the underside
at the spur vertices. `depth` roughly halved again in the map — it is read by the
mesh factory and nothing else, so a fragment can carry real mass without touching
a rule.

Three things were learned by looking rather than reasoning:

- **`r6-rim-spurs-as-horns.png`** — spur vertices reaching to 1.26× nominal, with
  spur bases spanning the full arc to both neighbours, produced flat sheets the
  size of the island. Reach dropped to 1.12 and the bases became narrow slivers
  hugging one vertex. That frame also cost 7 fps, all of it overdraw.
- **Rim jitter had to become strictly outward.** It ran 0.90…1.06, but
  `WorldMap.contains` treats the *nominal* circle as land, so a citizen could
  legally stand up to 1.25 m past the drawn edge. The drawn land is now always a
  superset of the legal land, and the craggy read comes from spurs pushing past
  the circle rather than bites taken out of it. This was a real defect, found only
  because the rim work forced a look at what the jitter meant.
- **Darkening the flank was the wrong variable.** In concept 01 the rim rock is
  close to the habitable top in value; the separation is *hue* and *mass*. The
  first attempt at 0.72 brightness barely moved and would have muddied the
  identity. Blending 46% toward a neutral cool grey, and jittering the flank
  rings' heights so adjacent facets get genuinely different normals, is what
  produced the facet contrast that reads as stone.

## Largest remaining mismatch against concept 01

**Density of settlement, and the HUD.** The island carries one building where the
concept carries five, and there is no resource rail, no selection panel and no
build affordance. Both are G2 work rather than defects. With those in place the
frame should be judged against concept 01 again by an independent reviewer.

## Corrected during integration

`MovementSystem` computed facing as `atan2(x, -y)` while the locomotion layer
uses `atan2(-x, -y)`. Deriving it: a mesh facing −Z rotated by θ about +Y points
at `(-sinθ, 0, -cosθ)`, so facing east requires θ = −π/2. The locomotion layer
was correct and the simulation copy was mirrored east–west. Facing now has
exactly one owner — the presentation-side `LocomotionState` — and `Unit.facing`
is documented as spawn facing only.
