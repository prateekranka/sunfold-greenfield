# Changelog

## 0.3.0 — 2026-07-27 — G2 in progress

The first slice that is played rather than watched. Evidence in `Docs/QA/G2/`.

### Added
- `GatheringSystem` — the gather → carry → deliver → return loop. No phase field:
  which leg a citizen is on is derived from whether it holds a full load, so no
  stored phase can disagree with the cargo it describes. The one persistent
  decision, which node this citizen works, lives on the unit as `assignment`.
- Work stations — six fixed standing positions per node, each a pure function of
  the node and the unit's durable `EntityID`. Citizens fan out around a rock
  instead of converging on one point, and a citizen returning from a delivery
  walks back to the spot it left.
- `Cargo` on `Unit`, one resource kind at a time, with a tinted pack drawn on the
  citizen's back that grows with the load.
- Tactical HUD, first player-facing UI in the project: a resource rail flush to
  the top edge and a selection panel in the lower-left. Chamfered rather than
  rounded, to match a world made of flat-shaded facets and an octagonal Core.
- `ResourceGlyph` — a distinct silhouette per resource (leaf, faceted block,
  spiked star, concave star), so the rail is readable without relying on colour.
- Selection panel cards for a single unit, a group, a building and a deposit,
  including a load meter and activity wording derived from cargo and destination
  rather than from a stored label.
- Selection lasso: hold 0.22 s then drag. Suppresses camera pan while live and
  shows a running hit count before the player commits.
- Double-tap a unit to select every unit of that kind currently on screen,
  detected by timestamp and distance so an ordinary tap keeps zero added latency.
- Deposit inspection — tapping a node with nothing selected reports its remaining
  yield and how many citizens are already on it.
- `CameraRig.screenPoint(forWorld:viewportSize:)`, the exact inverse of the
  existing unprojection and sharing one basis with it, so the two cannot drift
  apart under yaw. Marquee hit-testing projects units into the rectangle the
  player drew rather than unprojecting the rectangle into a rotated world quad.
- `UnitKind.pluralName`, `BuildingKind.acceptsDropOff`, `SkirmishTuning.carryCapacity`.

### Fixed
- HUD panels were translucent enough for starfield squares to show through and
  chip the resource glyphs. Measured in the rendered build at rgb(21, 23, 32)
  against a panel of rgb(11, 13, 24) — a bright star bleeds through even 5% alpha.
  Panels are now opaque, and deeper than `voidDeep` so they still read as panels
  over open space.
- Selection panel stretched to full screen width; a greedy `Spacer` inside an
  unconstrained card. Now a fixed width, which also stops it resizing as its own
  activity text changes.
- Group card printed "4 Citizen".

## 0.2.0 — 2026-07-27 — G1 in progress

### Added
- Entity model: `UnitKind` / `BuildingKind` with speed, life, footprint, population
  cost and production; `Unit` / `Building` / `Deposit` keyed by durable `EntityID`.
- `WorldPopulator` — deterministic, mirror-symmetric starting state. Cores, four
  citizens per side in a loose arc facing their expansion, transports at the rim
  docks, and deposits on all seven fragments.
- `MovementSystem` — land legality enforced in the rules, so a unit can never be
  shown standing in void; an order past the rim slides along it rather than freezing.
- `SelectionModel` and `WorldPicker` — selection and orders in world space against
  simulation footprints, so touch and rules cannot disagree.
- Orthographic screen→world unprojection on `CameraRig`, shared by selection,
  move orders and future lasso.
- Tap recognizer that requires the pan to fail, so dragging never fires a stray order.
- `EntityPresenter` — one-way projection of simulation state into the scene, with
  selection rings, a pulsing destination marker and per-unit gait.
- Authored meshes from the specialist tracks: Civilization Core, five building types,
  four deposit types, light transport, five unit types, and a distance-driven
  locomotion rig with movement-state and facing hysteresis.
- `TerrainDressing` — the authored habitable surface. A darker shore band inside
  the rim, soft soil tone variation, a jittered cell network of gold seams for
  Sunwoven ground and gravity fractures for Gravemark, and a scatter of straw
  shrubs and rock that keeps clear of every circle the simulation already owns.
  Static, per-fragment, and baked into a handful of merged meshes per zone.
- Causeways rebuilt as a cool gravity field carrying two lit warm rails, instead
  of one flat gold plane.
- `SkirmishTuning.unitVisualScale` — the single home for how much larger a unit
  is drawn than its authored 1.80 m contract. `footprintRadius` carries the same
  factor so hit-testing, formation spacing and rim margin cannot drift from it.
- Craggy fragment rims: 30 sides, a shelf ring in the flank, height as well as
  radius jitter on both flank rings, and rock spurs hanging below the underside.
  Fragment `depth` raised across the map — it is read by the mesh factory alone.
- `StructureMaterial.blend`, so a colour that sits between two palette entries is
  derived in one place instead of at each call site.

### Fixed
- Facing was computed in two places with opposite handedness. `MovementSystem` used
  `atan2(x, -y)` against the locomotion layer's `atan2(-x, -y)`; the simulation copy
  was mirrored east–west. Facing now has a single owner.
- An alpha on an `UnlitMaterial`'s tint does nothing — the material renders fully
  opaque until `blending` is set. Every translucent surface in the build had been
  drawing at full strength since G0. Fixed in `StructureMaterial.glow`.
- Transparent surfaces do not reliably sort above one another: a bright rail drawn
  over a dim deck came back grey. Anything that must read as lit is now opaque, so
  it draws in the opaque pass and writes depth.
- Default framing. The home fragment spanned 41% of viewport width against concept
  01's 71%, so the diorama read as a distant model and citizens as specks.
  `cameraDefaultZoom` 82 → 58, `cameraMinZoom` 55 → 34.
- Rim jitter ran inward as well as outward (0.90…1.06) while `WorldMap.contains`
  treats the nominal circle as land, so a unit could legally stand up to 1.25 m
  past the drawn edge. Jitter is now strictly outward and the drawn land is always
  a superset of the legal land.

### Known gaps
- The walk cycle has been observed departing, travelling and arriving, but no frame
  isolates a mid-stride pose, so anti-lockstep, the hysteresis band and
  facing-on-stop are **unverified in play**.
- Camera-relative motion under yaw has not been re-checked with units present.
- The island carries one building where concept 01 carries five, and there is no
  HUD — both are G2 work rather than defects.
- Deterministic tests remain **Proof Pending**; the SwiftPM extraction that will run
  them is the next structural task.

## 0.1.0 — 2026-07-26 — G0 Clean native foundation

First greenfield build. Shares no code with the historical `Sunfold/` app.

### Added
- XcodeGen project targeting iPadOS 26.x, iPad-only, landscape-left/right only,
  Swift 6 with complete strict concurrency.
- `WorldMap` — the single map contract. Seven authored fragments (two homes, the
  central Dominion, two expansions, two neutral outcrops) laid out symmetrically
  under a half-turn about the origin, plus void lanes, gravity causeways, and
  dock/staging resolution.
- `SkirmishTuning` — every cost, rate, timing and radius in one structure.
- `DeterministicRandom` — SplitMix64 with per-subsystem tagged streams.
- `SimulationClock` — 20 Hz fixed timestep that discards backlog instead of
  fast-forwarding after a stall.
- `SkirmishSimulation` — seed, map, clock, per-faction stock and age; applies the
  Core trickle identically to both factions.
- RealityKit world: faceted low-poly fragments with habitable tops and rocky
  flanks, gravity causeways that render dim until woven by an Outpost, and a void
  card carrying sparse stars and one distant body.
- `CameraRig` — orthographic camera at 57°, free yaw, zoom band 55–165m,
  one-tap return to north, bounds clamping.
- `CameraGestureLayer` — UIKit pan/pinch/rotate recognizers with true simultaneity.
- `DebugOverlay` — seed, tick, elapsed, age, yaw, zoom, focus, stock, fps, plus
  pause, time scale and return-north controls.
- `DebugLog` — fail-closed warnings surfaced in the overlay.
- `Tests/DeterminismTests.swift` — 15 tests over seeded replay, fixed-step
  accounting, map symmetry and legality, and equal Core trickle.

### Fixed during the gate
- Stars and the celestial body rendered nowhere. A world-space star shell cannot
  work under an orthographic projection; the sky is now a rig-parented card,
  counter-scaled with zoom.
- The visible world was exactly twice its intended width. RealityKit's
  `OrthographicCameraComponent.scale` is a half-extent, not the full vertical
  extent; measured against a known-radius fragment in the rendered build.
- Fragments read as flat discs. The underside taper was pulled in far enough that
  the flank was hidden at a 57° view; the rocky band is now near-vertical below
  the rim.
- Two-finger twist changed zoom and never yawed. SwiftUI's `RotateGesture` does
  not fire over a `RealityView`; replaced with explicit UIKit recognizers.
- Key light at 5200 lux blew out the habitable surface; reduced to 2700 with an
  850 lux cool fill.
- The void read as pure black rather than black-indigo; lifted slightly.

### Known gaps
- Unit tests compile and link but cannot be executed in this environment — see
  `IMPLEMENTATION_STATUS.md`. Results are **Proof Pending**.
- No HUD, units, buildings, economy, AI or victory conditions yet; those are G1–G5.
