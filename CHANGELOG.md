# Changelog

## Unreleased — Helios Rift Broken Ring

The Three.js Broken Ring is now the active product track. The inherited map source was
rebuilt and played before new visual work. It preserves four ring sectors, four broken
bridge gaps, four expansion islets, the solar objective, resources, 12 live units, and the
minimap.

### Added

- A dedicated Broken Ring visual contract and reference-versus-render evidence.
- Packaged Lumen Guard web assets and a standalone Guard proof used by the Helios build.
- A dev-only deployment path for `dev.helios.contenthelper.in`.
- Native iPad touch controls: one-finger camera pan, two-finger camera zoom, Citizen tap
  selection, and double-tap ground commands.
- Focused touch-camera tests for one-finger pan and two-finger pinch behavior.
- Deterministic deck cracks and instanced fragment-edge armor for all four Broken Ring
  sectors.
- A deterministic warped plasma texture, bright solar limb, annular halo, rotating glare,
  and 64 additive sparks for the central objective.
- A pure ground-navigation contract and five focused tests covering void rejection, authored
  bridge routes, disconnected islets, edge-safe formation slots, and flare route recovery.
- Blender-authored Sunwoven Civilization Core, Farm, and Formation Yard source files and
  optimized GLB runtime assets.
- Healthy, damaged, critical, and destroyed compositions for each building, with restrained
  building motion and a shared HP-to-state contract.
- Focused building-state tests and a GLB budget validator for node names, bytes, vertices,
  triangles, and material counts.

### Changed

- Helios geometry now uses four authored annular sectors, aligned bridge visuals and path
  targets, raised understructure, debris clearance, spawn pads, landmarks, and resource
  islets.
- The Helios proof now starts from a measured 43-degree, 80-unit hero overview. The ring
  remains fully readable while its inner walls and front understructure gain depth.
- The fragment stack is deeper. Basalt and deck materials now read as rough stone-metal
  instead of near-mirror metal. Warm edge ribs strengthen the broken-ring silhouette.
- The solar objective now has a larger emissive core, additive corona, radial halo, wider
  warm light, and explicit capture-zone and beam dimensions.
- Fog, tone mapping, exposure, and key/fill/rim lighting now preserve the upper fragments
  while keeping the void dark.
- The proof page now owns touch gestures instead of allowing Safari page zoom. Its first-use
  hint names both touch and mouse controls.
- Each ring fragment now uses four stepped armor bands, six inset deck plates, physical gold
  edge rails, staggered faceted edge chunks, larger termination sockets, and a darker slab
  palette. Logical platforms, bridges, pathing, and objectives are unchanged.
- Citizens and Guards now start on their movement-ready standing cell. Movement orders only
  change the animation clip when the requested activity differs, so a repeated order does not
  reset every selected unit's atlas UV state.
- The solar objective is larger and remains animated in neutral and flare states. Its visual
  contract now exposes limb, halo, glare, spark, and separate flare-corona controls without
  changing capture or hazard timing.
- Path graph routes now use separate bridge approach, crossing, and exit waypoints. Resources
  and objectives attach to their owning platform. Unreachable graph searches return no path.
- Twelve-unit movement now uses twelve unique formation slots. Slots near a fragment edge move
  inward to nearby ground instead of spilling into space.
- The north base now uses the authored building kit. Citizens and Guards spawn on an
  inward-facing arc, and the Matter node moved clear of the building footprints.
- The lab and dev-site builders can target only the Helios entry. They no longer regenerate
  unrelated dirty lab bundles during this deployment path.

### Fixed

- Removed avoidable full-group animation resets from repeated movement commands. The focused
  two-order gameplay gate rendered 600 frames in 10.0007 seconds at 59.996 FPS, with 17.6 ms
  p95, 17.8 ms maximum, and no frame above 20 ms.
- Removed the flat 55-percent corona shell that obscured the plasma texture during a flare.
  The accepted Cycle 05 run included a flare transition and two group orders: 600 frames in
  10.0071 seconds at 59.957 FPS, with 16.8 ms p95, 17.7 ms maximum, and no frame above 20 ms.
- Land units no longer accept destinations in open void or use a straight-line fallback when
  no graph route exists. Every path segment and runtime movement step now fails closed against
  the same authored platform and repaired-bridge rule.
- Solar-flare bridge locks now restore each bridge's physical repaired state when the flare
  ends. The old inactive callback returned no affected bridge IDs, leaving valid routes closed.
- The final Cycle 06 route moved all 12 selected units through an enabled core bridge. It
  sampled 600 frames in 9.9906 seconds at 60.056 FPS, with 16.8 ms p95, 17.7 ms maximum,
  zero frames above 20 ms, and zero invalid ground samples.

### Dev delivery

- Composition commit `0e7a09c` is deployed only to `dev.helios.contenthelper.in` as Worker
  version `9f2686b6-978d-4453-8ffd-ac8ae1422241`.
- The hosted Helios bundle SHA-256 is
  `3ba75808df82521d00dd082a6c175b6aa3dbd3258f9cce8cf309aaf7c0e9ae8c`, identical to
  the local site artifact. The hosted render showed 12 units, FPS 60, and no startup error.
- Native-touch commit `5e94a46` is deployed only to `dev.helios.contenthelper.in` as Worker
  version `539e004a-b016-44d9-9c5e-1a23ee0ee914`.
- Its hosted and local Helios bundle SHA-256 values both equal
  `1e9c59b7940bd36a4d6b3217c07519162bbeedb177cf7cee25dbcc799f6d7219`. A clean hosted
  reload showed 12 Citizens, FPS 60, the touch hint, and no browser exception.
- Combined fragment-relief and movement-state commit `4cb24fa` is deployed only to
  `dev.helios.contenthelper.in` as Worker version
  `4381c0dd-bbad-48e3-97b5-4d433a09e915`.
- Its committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `64590a5a627ad4100aae2827f3007eb7c6e0c2e57b8db7f570ba2af120f2d018`. The hosted
  frame showed the four detailed ring sectors, 12 Citizens, FPS 60, and no startup error.
- Molten-core commit `b97a3ce` is deployed only to `dev.helios.contenthelper.in` as Worker
  version `7910078f-a95f-4195-a3a0-8e1b8604a552`.
- Its committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `45bdbeeb23398b583bc96282ee49eef7185992767b38b968d38399e15a2599b3`. The hosted
  frame showed the molten core, 12 Citizens, FPS 60, and no startup error.
- Land-legality commit `fdc8267` is deployed only to `dev.helios.contenthelper.in` as Worker
  version `4e87a23c-ec73-467c-918e-a69e2f3af98b`.
- Its committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `e175c7d42f31a3a1b22cdbaea6dc26e62714c49b103693eba1b8060bd146cc7b`. A hosted
  open-void command produced the stable-ground message, left all 12 paths empty, kept every
  unit on valid ground, and reported FPS 60.
- Sunwoven-building commit `7ca4824` is deployed only to `dev.helios.contenthelper.in` as
  Worker version `34be548a-39e3-494f-9188-a4f72e4bac74`.
- Its committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `455026547b1a66434501bee27a912a34cc3c8e321898fe2c89b35b8029eecab7`. The hosted
  build loaded all three healthy structures, reported FPS 60, and completed a 600-frame
  movement, camera, and damage-state stress run without a startup exception.

### Proof pending

- The one-minute local Chromium stress pass held 60.00 FPS average, 18.5 ms p95, and no
  frame above 20 ms with 12 moving Citizens, camera changes, core capture, one repaired
  bridge, and a flare.
- A 45-second real-touch run on the iPadOS 26.5 simulator selected and moved all 12
  Citizens, pinched, panned, captured the core, and moved again. Forty-three one-second HUD
  samples averaged 59.9767 FPS; 41 read 60, one read 58, and the next read 61. The video is
  recorded at 30 FPS, so this proves the in-game requestAnimationFrame counter, not device
  GPU frame-time percentiles.
- Cycle 03 normal active play rendered 600 frames in 10 seconds at 60.0 FPS, with 17.1 ms
  p95, 17.6 ms maximum, and no frame above 20 ms.
- One earlier central-objective run produced a non-deterministic 66.6 ms frame. An instrumented
  repeat measured the command handler at 4.7 ms with no frame above 20 ms. The final two-order
  gate stayed below 17.8 ms after redundant animation resets were removed.
- The molten core is a partial reference match. Its fissures remain smoother than the
  reference. The map still lacks substantial crystal islets, dense debris, and nebula depth.
- Cycle 07 buildings and damage states are deployed and verified on the development host.
- The placeholder north bases are gone. The current build still uses a debug HUD, and the
  authored buildings do not yet match the reference's textured material richness. The
  iPad-first tactical and training HUD remains a separate checkpoint.
- Per user direction, Cycle 05 has no additional iPad touch check.

## 0.6.1 — 2026-08-01 — the economy pays for the game

The build where home deposits pay for a real Tier-1 opening. CP-C9 follows
`Docs/Design/05-RESOLUTIONS-R1.md` §2 (B4 + B5): home Matter rises to 700 and
home Lumen to 550, while off-home deposits keep 420 Matter and 300 Lumen. The
Dwelling now costs 55 Matter and takes 14 s. Evidence is in
`Docs/QA/G3/cp-c9/`.

At 9:00, seed `20260726`, riverlands, the economy-ceiling run reached **42/42
population** with four completed Dwellings, 12 Citizens, 13 Pathfinders, 9
Vanguards and 8 Quarrels. `noChoiceStallSeconds` was **0.000**. The raw
affordability delay was **38.650 s**, but all seven denial episodes had another
productive action available. This is resource pressure, not a no-choice stall.

### Added

- **Region-aware deposit yields.** The lookup requires both deposit kind and
  region. The off-home values remain unchanged for expansions, neutral outcrops
  and the Dominion. Deposit placement and seeded positions did not change.
- **The corrected nine-minute harness.** It measures capability through the
  production API, records denial episodes, separates raw affordability delay
  from no-choice stall, reports Pathfinder and trained-army counts, and writes
  mode/seed/duration-specific sample and denial CSVs.
- **Economy evidence.** Two full long runs produced byte-identical sample and
  denial CSVs. Regenerating the SVG from the same CSV was also byte-identical.

### Changed

- **Dwelling.** The cost changed from 80 Matter / 15 s to **55 Matter / 14 s**;
  the population grant stays +8. The device showed `Cancel · +41.25 Matter`
  after charging 55 Matter, then population moved 10 → 18 on completion.
- **The supply table is now honest about the boundary.** Home supply at nine
  minutes is ∞ Provisions, 1668 Matter, 644 Lumen and 0 Aether. The reference
  bill is 1920 Provisions, 1140 Matter, 615 Lumen and 80 Aether. The +29 Lumen
  headroom is thin by design, and home Aether is structurally absent because
  the home plan has no Aether node. `00-CONTENT-SPEC.md` requires leaving home
  to reach Voyager.
- **Deposit exhaustion reporting.** Home deposits now distinguish `absent`,
  `exhausted(at:)` and `neverExhausted`. The home Lumen deposit exhausted at
  **8:18.75** in the nine-minute reading.

### Fixed

- The old `usefulActionAvailable()` check incorrectly treated an incomplete
  foundation as a global building lock. It now uses
  `SkirmishSimulation.buildBlocker(for:faction:)`; the reference player's
  one-foundation policy remains only inside `act()`.
- The old `stallSeconds` counted a preferred purchase while another useful
  action was available. The decision bar is now `noChoiceStallSeconds`, with
  raw `affordabilityDelaySeconds` retained as a separate measurement.
- `Tests/AdversaryTests.swift` no longer freezes the Matter `420` ledger value
  or the Lumen Spire `89` affordability fixture. CP-C9 is what makes the
  no-frozen-tuning-literal statement true.

### Notes

The live iPad pass showed real Matter and Lumen gathering, including home Lumen
income of **+10/s** and stock movement from 40 to 175. With the adversary live,
the hand-played match ended **DEFEAT · CONQUEST at 5:58**, matching the headless
contested run at 5:59 within one second. The `-sunfoldNoAdversary` run reached
4:01 cleanly.

The full 9:00 arc to approximately 40 population with four Dwellings was not
hand-played to completion. Coordinate taps through a real-time RTS were the
limiting factor, not the economy. The arc is proven twice by the deterministic
harness, and the one device limitation remains open rather than being hidden.

## 0.6.0 — 2026-08-01 — the match can end

The build where this stops being a simulation you watch and becomes a game you
can win or lose. Two win paths, a match that genuinely stops when one of them
fires, and a Play Again that rewinds it. All of it was played on the iPad, not
inferred from tests. Evidence in `Docs/QA/G3/cp-c4/`.

At 0.5.0 the opponent destroyed the player's Core at 5:59 and the match kept
running over the corpse at population 0 of 10. It now says **DEFEAT · CONQUEST ·
"Sunwoven's Civilization Core was destroyed."** and stops.

### Added
- **Conquest.** Destroy the enemy Civilization Core. Mirrored as defeat when
  yours falls. Structural calamity beats fire once each at 75% / 50% / 25% on
  the way down.
- **Dominion.** Hold the Spire for 45 s continuous. Per `05-RESOLUTIONS-R1.md`
  §3 (B10) rather than `00-CONTENT-SPEC.md` §5 where they disagree: an enemy in
  the ring **decays** the holder's timer at half the fill rate instead of pausing
  it. A pause rule deadlocks forever if both sides keep one unit standing there,
  which is exactly what two schedules would do, and a deadlock breaks the "no
  draw state, no hard timer" promise. Timers are per faction, not a tug-of-war.
- **The Dominion Spire** — the fifteenth building and the only one nobody builds.
  Neutral, pre-placed at the contested fragment's centre, indestructible by rule.
  `Building.faction` is now `Faction?`; `nil` is neutral.
- **The escalation ladder.** The hold requirement shortens 45 s → 30 s (7:00) →
  20 s (9:00) as a pure function of the clock, so a stalemate becomes a fight
  over one piece of ground rather than a timeout. Visible in the rail.
- **`ObjectiveRail`**, replacing `AlertStrip`. Match clock, both Dominion timers,
  both Core meters, a live alert line, and resign. The strip it replaces printed
  "Light transport docked at home rim" for an entire match whatever happened.
- **`MatchOverlay`** — verdict, the win path named honestly, elapsed time and
  Play Again. It dims rather than hides: where the fight ended is information.
- **Resign**, as two taps on the rail. The spec puts it in a pause menu; there is
  no pause menu, and leaving `resign()` unreachable would have made it dead code.
  It reports **RESIGNATION**, not a Conquest that never happened.
- **Play Again** — `SkirmishSimulation.restart()` rebuilds the world in place
  from the same seed, and the renderer drops the selection, any half-placed ghost
  and the rising-building set, all of which name entities that no longer exist.
- Health bars on damaged units and buildings, so a Core being chewed on is
  legible without selecting it.
- Twenty-three tests, 49 → **72**.

### Fixed
- **Three of the six buildings could not be placed at all.** 0.4.0 gave the
  Formation Yard, Expansion Outpost and Dawn Loom command tiles — lit, priced and
  tappable — while `ConstructionPlacement.placeableKinds` still listed only the
  three construction-checkpoint kinds, so `beginBuildGhost` bounced off it in
  silence. The Formation Yard is the only building that trains a military unit,
  so the player could reach **neither** win path. Found on device while trying to
  build the Yard that trains the Vanguard that captures the Spire. Two rules now
  hold the line: everything with a price is placeable, and nothing free is.
- The Dominion fragment's deposits are pushed outside the Spire's footprint plus
  a citizen's working ring. A Matter node could sit *inside* the objective, which
  turned the one piece of ground the match is fought over into a mine.

### Notes
- **The CP-C3 determinism bar is restated, not weakened.** Tick 12000 is now
  unreachable — the untouched player is wiped at tick 7192 and a finished
  simulation refuses to step — so two no-input runs must stop on the **same
  tick** with the **same outcome** and the **same hash**. The fingerprint moved
  from `a9ee7bc2faeea255` to **`4645f2d24d31018c`** because the world changed:
  the Spire is folded into the hash and the Dominion deposits moved.
- **`canCaptureDominion` is its own list, not `isMilitary`.** The two are
  identical today, and that is the trap: `isMilitary` answers a combat question
  and would silently answer a victory question the next time a unit is added.
- **The 8–10 minute promise is not met yet by any observed match.** The no-input
  match resolves at 5:59; the played Conquest took 15:55. The ladder shortens the
  Dominion requirement and does nothing about walking an army across the map and
  chewing through 600 HP. A pacing question for CP-C5 / CP-C9.
- **The contest rule has never been seen in play.** Decay-at-half-rate and the
  no-deadlock property are test-proven only — the adversary sends every wave at
  the player's Core and never walks into the ring.

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
