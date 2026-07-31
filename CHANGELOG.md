# Changelog

## 0.5.0 — 2026-07-31 — there is somebody on the other side

The build where the map stops being empty. Gravemark now builds, trains and
attacks on a fixed schedule, and it walked over and destroyed the player's
Civilization Core at 5:59 while nobody touched the controls. Evidence in
`Docs/QA/G3/cp-c3/`.

That attack also closed **CP-C2 as CP-C2′**. Combat had been implemented and
test-proven the same day but deliberately not shipped, because no fight had ever
been *seen*: Gravemark had no AI, so two hostile units never met. There is now a
capture of a health bar draining next to the thing draining it, and of the
selection panel reading `Civilization Core · SUNWOVEN · 303 / 600`.

### Added
- `Adversary` — a scheduled opponent, not a planner. Every decision is a pure
  function of the tick count and the world state, with **no random draws at
  all**; the tagged `adversary` stream is reserved and deliberately unused, so
  a later planner cannot silently shift the numbers recorded here. It grows an
  economy toward twelve citizens, builds Formation Yards at 2:00 and 4:00,
  houses itself on a population rule, and dispatches attack waves every 90 s
  from 4:00. First wave arrives at **4:27**, inside the 3:30–4:30 bar.
- Wave pathing without a pathfinder: waves route via the Dominion centre, the
  map's only guaranteed contiguous spine, and hand off to their target with a
  dot-product test.
- `WorldHash` — the canonical FNV-1a world fingerprint that
  `05-RESOLUTIONS-R1.md` §6.13 specifies and that nothing had implemented.
  Quantises resources and life to hundredths and positions to millimetres, in
  ascending entity order. Two no-input runs from seed `20260726` produce
  `a9ee7bc2faeea255` at tick 12000, and identical event logs line for line.
- `SkirmishSimulation.setStance` — the adversary sets its waves aggressive on
  dispatch through the same path a player's tap would use.
- `-sunfoldNoAdversary` launch argument to freeze the opponent for tests and
  for economy work that wants a still map.
- Ten tests, 39 → **49**. They cover the world hash, the build and wave
  schedule, wave composition cell by cell against the spec table, arrival
  timing, that the wave draws blood with no player input, and that the
  adversary's Matter ledger closes.

### Notes
- **The adversary is granted nothing, and this is now enforced twice.**
  Structurally, `Adversary.plan` receives the resource pools **by value** and
  cannot write to them; everything it trains or builds is charged through the
  same methods a player's tap reaches. Measurably,
  `testTheAdversaryMatterLedgerCloses` reconstructs Gravemark's balance from
  starting stock, trickle, and its own deposits, minus everything standing,
  alive or queued, and asserts the books close to 0.5 units.
- **Five rows of the R1 §5 wave table are dropped, not substituted.** Lancer,
  Bastion Walker, Lumen Spire and Stride Yard do not exist in the roster yet,
  and the Dawn Loom's research does not. Nothing was invented in Swift to fill
  them (Directive 3); the drops are listed in `Adversary.deferredFromSpec` so
  the wave that finally fields a Lancer is a visible change.
- **Two schedule decisions the spec did not make**, both forced by measurement:
  a second Formation Yard at 4:00 standing in for the unbuildable Lumen Spire
  (with one Yard, wave 5 came out *smaller* than wave 4), and four Dwellings on
  a population rule (at three the adversary jammed at 34/34 with 340 Matter in
  the bank).
- By 10:00 the Gravemark home fragment is dug out. That traces to R1 §2's
  raised home yields not being implemented yet — a **CP-C9** dependency, since
  raising them changes the player's economy too.
- No performance smoke was taken. BC-02's checkpoint-close smoke is skipped
  deliberately this cycle, not forgotten.

## 0.4.0 — 2026-07-31 — production exists

The build where the game stopped being a fixed diorama. Evidence in
`Docs/QA/G3/cp-c1/`, `Docs/QA/G2/cp-g2b-nav/`, `Docs/QA/G2/p14/`.

The design reference changed: play-feel is now benchmarked against **Age of
Empires 2 / Rise of Rome, in space**, not Age of Empires IV. Recorded as
BC-01 in `Docs/Gauntlet/00-PLAN.md` with the old bar and the new bar side by
side. Performance is demoted from a blocking bar to a guardrail (BC-02).

### Added
- `ProductionSystem` — per-building FIFO queue, cost charged on enqueue,
  progress on the fixed 20 Hz tick in integer ticks so the frame rate cannot
  shift a spawn, deterministic ring spawn resolved through `WorldMap`, and a
  100% / 75% cancel refund split. Queued units reserve population, so the cap
  cannot be overshot by queueing. Before this the game had no way to train a
  unit at all: population sat at 4/8 for the entire match.
- A selection-aware command grid. Selecting a production building offers what
  it trains with a live cost badge; selecting a Citizen offers the build menu.
  **Every unavailable tile states its own reason** — "Needs 4.11 Provisions",
  "Population 10 of 10" — rather than being silently dark.
- Build tiles for Formation Yard, Expansion Outpost and Dawn Loom. All three
  already existed as `BuildingKind` cases with no way to reach them, which
  also made the Voyager age unreachable.
- Minimap navigation: tap to jump, drag to scrub. Face north, Go to Core and
  Expand map are wired. Place marker is dimmed and labelled rather than left
  as live-looking decoration for a feature that does not exist.
- A SwiftPM package at the repository root exposing `Sources/Domain` and
  `Sources/Simulation` as `SunfoldCore`, so `swift test` runs the simulation
  tests on the host in seconds. 31 tests pass.
- `Docs/Design/` — the content design specification: unit roster, building
  roster, combat model, tier progression, victory conditions, faction split.
  Critic-reviewed; all sixteen blocking defects answered in `05-RESOLUTIONS-R1.md`.

### Fixed
- **Land units can now leave the region they spawned in.** `Unit.region` was
  assigned at spawn and never updated while `MovementSystem` clamped every
  land unit to it. No land unit had ever been able to walk to another region,
  which made Conquest, Dominion and the Aether gate all unreachable — the
  single largest structural gap in the game. Land is now land; water still
  needs a boat.
- The build ghost no longer survives a successful placement. It used to stay
  on the foundation it had just created, read `BLOCKED` in red, and hold the
  camera hostage because gesture gates were never released (CP-G2a).
- Refunds display fractionally — 52.5 Matter reads as `52.5`, not `53`.
- Population cap 8 to 10; Dwelling grant 4 to 8.

### Performance
- `EntityPresenter` caches the seven per-unit `findEntity(named:)` limb lookups
  at spawn rather than walking the entity hierarchy every frame (P4).

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
