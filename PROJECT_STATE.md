# Project State

**The first file to read.** It records where Sunfold Greenfield actually is after each
checkpoint, so a new agent can start work without re-deriving the situation from the
source tree.

Rules for this file:

- The **checkpoint log** is updated at the close of every checkpoint, never mid-flight.
- The **In flight** section below is the exception: it carries an open checkpoint across a
  session boundary so the next agent resumes instead of restarting. It is deleted when that
  checkpoint closes and its log entry is written.
- It records what was **observed**, not what was intended. A claim here without evidence
  behind it is a bug in this file.
- It is short. Detail lives in the documents it points to; this file says where things
  stand and what to do next.

---

## Status at a glance

| | |
|---|---|
| **Last checkpoint** | CP-06 — density and palette · **closed** |
| **Closed** | 2026-07-28 |
| **Build** | 🟢 Green. `** BUILD SUCCEEDED **`, zero Swift errors, zero new warnings. |
| **Renders** | 🟢 Clean. The island reads as planted ground at concept 01's hue. |
| **Current frame** | `Docs/QA/AAA/cp06-density-palette.png` |
| **Version** | 0.3.0 · build 42 |
| **Gates** | G0 complete · G1 in progress · G2 in progress — neither passed |
| **Current direction** | Finish the AAA visual push toward concept 01. G2 gameplay is parked. |
| **Uncommitted work** | None. `visual/aaa-uplift-cp02` carries CP-06. |
| **Next checkpoint** | CP-07 — the Core pavilion. See the ladder below. |

---

## The remaining visual ladder

Reprioritized 2026-07-28 after measuring `cp05-hud-chrome.png` against concept 01 rather
than working from the running gap list. **The direction is confirmed: the frame is the
primary track and gameplay stays parked.** That is a decision, not a default — the trade it
makes is recorded under "The imbalance this accepts" below.

**Two assumptions the measurement killed.** The frame is *not* overexposed and the ground is
*not* oversaturated — CP-03's calibration held, and neither value nor saturation was
meaningfully off. Do not re-open either. What was actually wrong is recorded in CP-06's log
entry below, along with the two numbers in the original reprioritization that did not survive
re-measurement.

Two gaps needed no number, both visible in a side-by-side crop: the concept's ground was
**dense with vegetation** where ours was a large bare field — closed at CP-06 — and the Core
is a **value inversion**: the concept's ivory-and-gold pavilion is the brightest object in
frame, ours is a charcoal dome darker than the ground it stands on. That one is still open and
is the next checkpoint.

**CP-07 — The Core pavilion.** Largest single-object gap. Not only silhouette: a closed dark
dome has to become a bright *tented* pavilion — separate ivory canopy panels radiating from a
finial, gold armature, turquoise insets, a colonnade on an inlaid plinth. Expensive mesh work,
which is why it sits behind the cheap win.

**CP-08 — The void.** Nebula wash, the celestial body in frame, drifting debris. The bible
allots the void 45–60% of the frame and it is currently flat black. Isolated, no gameplay
coupling — the cheapest single checkpoint here if a quick win is wanted ahead of the Core.

**CP-09 — Rim, deposits and plant mass.** Pale crystalline rim spurs; larger crystal clusters.
Also the half of the planting gap CP-06 could not close: the island now carries *more* separate
plantings than concept 01 does (146 against 132) at 62% of its coverage, so what is left is not
count but **mass** — the concept's growth includes a few large branching masses where every one
of ours is a medium spiky clump. That is a mesh problem, and scattering more copies of the same
silhouette would read as a carpet rather than close it.

**CP-10 — HUD parity.** Top-bar centre emblem and speed controls, the alert row, pinned group
slots, selection portraits, health bars, and minimap fragment silhouettes rather than circles.

**CP-11 — Transport and pier.** Kill the dark spar; add the docked gold pier.

**Parked: animation.** The most expensive item on the list, and it needs per-unit activity
state the simulation does not expose yet.

### The imbalance this accepts

Recorded so it is a known cost rather than a surprise. `Sources/Rendering` is **12,069 lines,
77% of `Sources/`**. `Sources/Simulation` is 1,322 and `Sources/AI` is **empty**. Grepping the
simulation for construction, production, combat, capture or victory returns nothing: the
game's complete verb set is **select, move, gather**, which is why CP-05's command grid
renders 8 of its 9 buttons disabled. G3–G7 are unwritten and there is currently no way to win
or lose.

The largest unquantified risk is separate from that and still open: **the 13 determinism tests
in `Tests/DeterminismTests.swift` have never executed.** `xcodebuild test` is hook-blocked, so
they have compiled and linked on every build while proving nothing, and every gate from G3 on
assumes determinism holds. The fix is cheap and was verified viable during this
reprioritization — `Sources/Domain` and `Sources/Simulation` import **only** `Foundation`,
`Observation` and `simd`, which is the hard precondition for a SwiftPM extraction, and the
host has Swift 6.3.3 with `swift test` **not** hook-blocked. Roughly one checkpoint whenever
it is wanted.

---

---

## Read order for a new agent

1. **`AGENTS.md`** — the build path, the simulator path, the architecture rules, and the
   rendering facts already established in the running build. Non-obvious and expensive to
   rediscover. Read it before touching anything.
2. **This file** — where the project stands and what the next checkpoint is.
3. **`ROADMAP.md`** — the gate ladder G0…G7 and what each gate must prove.
4. **`Docs/Concepts/00-visual-bible.md`** + `Docs/Concepts/01-sunwoven-foundation-opening.png`
   — the locked art direction and the approved visual target.

Do not read `IMPLEMENTATION_STATUS.md`, `CHANGELOG.md` or `VERSION.md` first. They are
accurate about G0/G2 gameplay but they predate the visual work and say nothing about it.

---

## What this project is

A native iPadOS 26 real-time strategy game in Swift 6 + RealityKit, set in space and
explicitly benchmarked against **Age of Empires IV**. Landscape-only iPad, an 8–10 minute
skirmish, fully deterministic from seed `20260726`.

Five rules are locked and must never be broken:

1. **Simulation owns truth.** `Sources/Simulation` and `Sources/Domain` are pure Swift —
   Foundation and simd only. They must never import RealityKit or UIKit.
2. **The renderer projects state and decides no rules.**
3. **`WorldMap` is the single coordinate contract.**
4. **Fixed 20 Hz timestep.** Frame rate never changes outcomes.
5. **Determinism.** All randomness comes from `DeterministicRandom` on a tagged
   per-subsystem stream. Never `Double.random`, never `SystemRandomNumberGenerator`.
   Adding a draw in one subsystem must not shift another's numbers.

`project.yml` is the source of truth for the Xcode project and globs `Sources/`, so a new
`.swift` file anywhere under `Sources/` is picked up by `xcodegen generate` with no manifest
edit.

---

## Build and run — the short version

The obvious commands are blocked. `AGENTS.md` explains why; this is the summary.

Compile check (isolated per agent, parallel-safe):

```bash
./scripts/agent-build.sh <agent-name>
```

Full log lands at `build-agents/<name>.log`; the app bundle at
`build-agents/<name>/Build/Products/Debug-iphonesimulator/SunfoldGreenfield.app`.

Never run `xcodebuild`, `xcrun`, `simctl` or `launchctl` directly — a `PreToolUse` hook
blocks the first two and redirects to an unlicensed FlowDeck, and touching CoreSimulator by
hand has already cost this project one wasted agent cycle.

Install, launch and screenshot go through **argent MCP only**, against simulator
`A59055F8-1354-4936-97B8-7033DF90B0BB` ("Sunfold Cycle 1 iPad Air 13", iPadOS 26.5),
bundle id `com.sunfold.greenfield`.

Two things that will otherwise waste your time:

- **The app is landscape-only and renders nothing in portrait.** Rotate to LandscapeLeft
  after launching, before screenshotting.
- **Scene build takes several seconds in Debug** — procedural textures cost ~570 ms per
  recipe at `-Onone`. The first frames are black with `tick 0`. **Wait at least 12 s after
  launch before screenshotting**, or you will capture an empty void and report a false
  regression.

---

## Where the game actually is

### Proven in the rendered build

Gameplay, observed in play and evidenced under `Docs/QA/G0/` and `Docs/QA/G2/`:

- A 7-fragment authored map with gravity causeways, an orthographic camera at 57° with
  pan / pinch-zoom / two-finger yaw / return-north, a 20 Hz fixed-step clock, and the
  deterministic seed surfaced on every launch.
- The full economy loop: a citizen walks to a deposit, gathers, carries a visible load,
  delivers it to the Core and returns to the station it left. Only the assigned resource
  climbs; delivery credits the stock as a whole load.
- Six fixed work stations per node, so gatherers fan out instead of interpenetrating.
- A tactical HUD: resource rail, selection panel, load meter, deposit inspection.
- Selection lasso that does not fight camera pan, and double-tap to select all of a kind.
- 60 fps with the HUD and four gatherers.

### The AAA visual push — now seen running

Roughly 11,900 lines under `Sources/Rendering`, written 2026-07-27 14:30–17:41 and first
rendered at CP-01. What `Docs/QA/AAA/cp01-baseline-green.png` shows, judged against
concept 01:

**Landed and clearly working.** The Civilization Core now reads as a domed hall on a stone
plinth with gold ribs and glazed turquoise panels — a real building rather than the plain
tent of the earlier round. Deposits have distinct silhouettes: golden crystal clusters, grey
rock outcrops, dark-stalked plants. Units are recognisable figures carrying faction livery.
The transport is a proper vessel with a gold spar. The ground carries a mottled sand texture
with gold seam lines, and the Core casts a real shadow. Star fringing is gone.

**Fixed at CP-03.** Stars are soft points. The frame's exposure matches concept 01. Bloom
selects emitters and the turquoise glazing carries a halo.

**Fixed at CP-04.** The ground has relief, and everything that stands on it — units, props,
deposits, decals — sits on that relief rather than on a datum plane.

**Fixed at CP-05.** The frame now carries four of concept 01's five chrome surfaces: the
resource rail, a live minimap, the selection panel and the command grid.

**Fixed at CP-06.** The island reads as planted ground rather than a bare field — 146 separate
plantings against concept 01's 132 — at the concept's hue (32.7° against 33.0°) and without the
pit lattice that was speckling the sand.

**Still short of concept 01**, measured against `cp06-density-palette.png`:

- **The Core is a plain dome** where concept 01 has an ornate pavilion with a tented canopy
  and a fine gold armature — and it is *darker* than the ground it stands on where the
  concept's is the brightest object in frame. The largest remaining gap, and the next
  checkpoint.
- **The void is empty** — flat black, no nebula wash, and the celestial body does not appear
  in frame. Concept 01 has both.
- **Vegetation is spiky low-poly** against the concept's fine golden branching. CP-06 closed
  the count; the remaining coverage gap (0.167 against 0.271) is plant *mass*, which is a mesh
  problem.
- **No health bars.** The fifth chrome surface, and the only one CP-05 did not add — it
  belongs with combat, which is parked G2 work.
- **The transport's dark spar** reads as a slab crossing the frame rather than a vessel part.
- **The second fragment is clipped by the frame edge** and still reads as pasted on.

The subsystems behind all of that:

- Procedural texturing: UV generation for the custom meshes (`Texturing/MeshUV.swift`), a
  procedural texture synthesiser (`ProceduralTexture.swift`), and a material library with
  normal / roughness / AO / emissive maps (`MaterialLibrary.swift`).
- A lighting rig with runtime image-based lighting and working shadows
  (`LightingRig.swift`).
- A real full-frame post-process — bloom, ACES tonemap, split-tone grade, vignette,
  chromatic aberration (`PostProcess/`, including a Metal shader).
- Rebuilt meshes for the Civilization Core, deposits, units, buildings and the transport,
  plus terrain dressing (`TerrainDressing.swift`, 64 KB).

### Known open defects and risks

- **`Docs/QA/AAA/round-1-foundation.png` is stale.** Captured at 15:34, *before* the
  chromatic-aberration fix at 15:45 that dropped `aberration` from 0.0022 to 0.0006. Do not
  cite its rainbow fringing as a current defect — that complaint is already fixed in source.
  Same for `Docs/QA/AAA/blind/frame-A.png` and `frame-B.png` (15:39). Use
  `cp01-baseline-green.png` instead.
- **`scripts/agent-build.sh` has no stale-lock handling.** A build killed between the `mkdir`
  of `build-agents/.xcodegen.lock` and its `rmdir` leaves the lock held forever; every later
  build then spins for 180 s and *silently proceeds without running `xcodegen`*. This has
  already bitten once. The lock should carry its owner's pid and be reclaimed when that pid
  is gone, and a failed acquisition should be a loud error rather than a silent skip.
- **The unit tests have never been executed.** `Tests/DeterminismTests.swift` holds 15 tests
  covering seeded replay, fixed-step accounting, map symmetry, fragment separation, the
  transport-only first crossing, dock/staging legality and equal Core trickle. They compile
  and link on every build, but `xcodebuild test` is hook-blocked, so every result is
  **Proof Pending**. The planned fix is to extract `Domain` + `Simulation` into a SwiftPM
  `SunfoldCore` package that `swift test` can run directly — which is the right
  architecture anyway, since it enforces the simulation/rendering split at module level.
- `Sources/Audio/` and `Sources/Accessibility/` exist but are empty. They belong to G7.
- **`rotate` loses the first call after a launch.** The app is still building its scene, the
  call returns `{"orientation":"LandscapeLeft"}` and nothing turns. Send it twice — a
  `Portrait` step then `LandscapeLeft` — or the capture is an empty void and reads as a
  regression that is not there.

### Parked, not abandoned

G2 gameplay still needs construction (Farm / Matter Extractor / Dwelling with placement,
cost and build progress), Core production with a queue, the objective rail and the
30/60/90-second hint ladder, and a timed first-time pass. `ROADMAP.md` holds the full list.
The current direction is visual, so these wait.

---

## Checkpoint log

Newest first. Each entry records what changed, what was observed, and what it cost.

### CP-06 — Density and palette · 2026-07-28 · closed

**Goal.** Three things at once, all of them parameters on systems that already existed: raise
planting density toward concept 01's, cut the sand speckle, and rotate the land hue off yellow.

**Found — the hue was one number, and it was not in the ground.** Sampled on hand-picked bare
ground in both frames, `cp05` read rgb(0.757, 0.682, 0.506) against the concept's
rgb(0.776, 0.655, 0.506). Red and blue already agreed to within 2%; the whole 9° error was
**green**. And it was not the ground's alone — every lit surface in the frame carried it:

| | concept 01 | cp05 |
|---|---|---|
| bare ground | 33.0° | 42.2° |
| rim stone | 34.6° | 41.8° |
| foliage | 31.8° | 40.3° |
| transport hull (near-white) | — | 41.1° |

A hull whose albedo is all but neutral cannot be 8° off on its own account, so the error was in
what lights it. The rotation went half into `LightingRig.Tuning.keyColor` (green 0.935 → 0.900)
and half into the two Sunwoven albedos, plus the regolith's bleach highlight — so neither the
sun nor the sand is dragged far enough on its own to stop reading as what it is.

**Found — the speckle was periodic, not noisy.** `regolith`'s impact pits run 12 cells per 4 m
tile, which is a pit every 33 cm, which at this camera is a dark dot every ~11 px: a polka-dot
lattice, and the single thing that made the ground read as a prototype. The cell gate went
0.62 → 0.76 (keeping the sparsest quarter), both colour amplitudes were halved, and the pit
dimple went 0.42 → 0.22. The broad dune term — the variation concept 01 actually has — is
untouched.

**Found — density is capped by site spacing, not by candidate count.** The first render made
this unmissable: nearly tripling the interior candidates moved planting coverage only
0.057 → 0.088. A minimum separation enforced by sequential rejection *jams* — the reachable
site count is about `0.55 · area / (π · spacing²)`, and past it every further candidate is
refused however many are offered. The second pass moved the spacings instead (interior
3.2 → 1.5 m, fringe 2.6 → 1.3 m) and raised cluster companions, which bypass `site` entirely.

**Done.** `SunfoldPalette`, `LightingRig.Tuning`, the `regolith` recipe, and the scatter
parameters in `TerrainDressing`. No new types, no new systems, no signature changes.

**Verified.** Build green, zero errors, zero new warnings. Installed, launched, rotated,
captured at full resolution as `Docs/QA/AAA/cp06-density-palette.png`.

| measured | concept 01 | cp05 | cp06 |
|---|---|---|---|
| bare-ground hue | 33.0° | 42.2° | **32.7°** |
| bare-ground saturation | 0.348 | 0.332 | **0.347** |
| planting clumps on the home island | 132 | 86 | **146** |
| planting coverage | 0.271 | 0.057 | **0.167** |
| sunlit regolith, linear median | 0.410 | 0.432 | **0.396** |
| frame over the bloom threshold | 1.54% | 0.60% | 0.61% |

Clump counts are connected components of a planting mask normalised against *each frame's own*
ground colour — an absolute threshold is unusable across a checkpoint that moved the exposure,
because ACES desaturates what it brightens and the same prop lands on either side of a fixed
cut. The speckle result is evidence by crop rather than by statistic; see below.

**A regression this checkpoint caused and corrected.** Rotating hue toward red is a cut in
green, and green carries 71% of luminance, so the palette work took sunlit regolith from 0.432
to **0.377** linear — through CP-03's locked 0.397 and out the other side. Caught by measuring
the first render rather than shipping it. `exposureScale` 0.67 → 0.72 puts it back at 0.396,
and because a uniform scale over all four lights is hue-neutral, it costs none of the rotation.
**Hue and exposure are separate dials on purpose; a hue change should expect to pay an exposure
correction.**

**Two numbers in the 2026-07-28 reprioritization did not survive re-measurement.** Recorded so
they are not carried forward as fact:

1. **"Land saturation 0.359 against 0.422 — slightly under."** On masked bare ground the build
   measured *more* saturated than the concept (0.332 against 0.348 by spot sample, 0.328
   against 0.239 by mask), not less. Nothing was done about saturation, and it landed at 0.347
   against 0.348 anyway — carried there by the hue rotation, since cutting green at fixed red
   widens the channel spread.
2. **"Open-ground luma σ 40.6 against 20.1 — twice the local noise."** Local σ does not
   reproduce that ratio under any mask tried, and it inverts depending on the mask: on the
   automatic ground mask the build is noisier (7.0 against 5.5), on hand-picked patches the
   *concept* is (8.8 against 11.9). σ is simply the wrong statistic here — it lumps the pit
   lattice together with veining, cast shadow and broad mottling, and the two frames differ in
   all of those. The defect was periodic, and the honest evidence for its removal is a
   native-resolution crop of the same ground in both frames, not a variance number.

### CP-05 — HUD chrome · 2026-07-28 · closed

**Goal.** Concept 01 carries five pieces of chrome; the build shipped two. Add the minimap
and the command grid, and re-lay the bottom strip so map, selection and orders take the
three thumb positions of a landscape iPad.

**Done.**

- **`Minimap`** — `Canvas`-drawn from `WorldMap` and the live simulation rather than from a
  baked image, so it cannot drift out of step with the terrain. Causeways underneath (dashed
  where they must be woven first), fragments tinted by owner, deposits, buildings as squares,
  units as dots, and the camera's footprint as a **yaw-rotated quad** — an axis-aligned
  rectangle would be a lie the moment the player yaws, and yaw is a control this game ships.
  Four tool tiles and a compass reading sit with it.
- **`CameraRig` is `@Observable`**, so that quad tracks `focus` / `yaw` / `zoom`. Without it
  the reticle is placed once at scene build and never moves again, which is worse than
  having no reticle.
- **`CommandGrid`** — a fixed 3×3 whatever is selected. A card that reflows forces the player
  to re-find every button, and muscle memory for a command's *position* is most of what makes
  an RTS fast, so a command that does not apply is dimmed in place rather than removed. Only
  `stop` is wired, as a move order to the unit's own position — the simulation clears a
  destination on arrival, so that is exactly "cancel" without a second verb. Everything else
  is parked G2 work and renders disabled: an enabled button that silently does nothing is
  worse chrome than a dimmed one.
- **`RootView.bottomStrip`** — minimap · spacer · selection · spacer · command grid. The
  selection panel is the only one of the three that comes and goes, so the centre column
  takes the slack and the two anchored panels never move under it.

**Verified.** Build green, zero errors, zero new warnings. Installed, launched, rotated,
captured at full resolution as `Docs/QA/AAA/cp05-hud-chrome.png`. The reticle was then
checked under an actual camera pan rather than assumed: swiping the world moved the quad
with it, which is the one claim `@Observable` is there to make.

**Two Swift type-checker cliffs, both in `CommandGrid`.** Each fails as `failed to produce
diagnostic for expression`, which names neither the cause nor a useful line:

1. A nested `[[Cell]]` literal — nine memberwise inits with defaulted arguments is more than
   the checker will spend. Fixed by building each row as a separately annotated `[Cell]`.
2. `hasUnits ? stop : nil` — inferring `(() -> Void)?` from a bare method reference against
   `nil`. Fixed with an explicit `let stopAction: (() -> Void)? = hasUnits ? { self.stop() } : nil`.

**Two layout defects the render caught that reasoning had not.**

1. **A `Spacer` in a column with no width of its own makes the whole column greedy.** The
   minimap's header `HStack` held one, and the panel stretched the length of the frame
   instead of sitting in its corner. Pinning the header to the map's width fixes it.
2. **`WorldMap.bounds` is a camera limit, not the land.** It is deliberately wider than the
   rock — `[118, 86]` against a fragment field of `94 × 55` — so a well fitted to it showed
   the theatre at 80% × 47% of its own area, pushed off-centre and floating. The well now
   measures the land from the fragments themselves and takes **the land's aspect** rather
   than a forced square; the bible allows a rounded rectangle here, and a square showing a
   1.7:1 theatre can only ever be half empty. Land area on screen roughly doubled.

Changes confined to `Sources/HUD`, `Sources/App` and one `@Observable` on `CameraRig`.
`Simulation` and `Domain` import neither RealityKit nor UIKit; no ad-hoc randomness anywhere
in `Sources/`.

### CP-04 — Terrain relief · 2026-07-28 · closed

**Goal.** Make the habitable surface read as land rather than as a beige disc.

**Found.** The top was never a flat facet — `FragmentMeshFactory` has built it as a radial
height-field grid since G1. The relief was there and invisible, because its amplitude was
capped at **0.55 m across a 24 m fragment**: half a percent of the diameter.

The cap had nothing to do with how the land should look. `groundHeight` had exactly **two
callers, both inside `FragmentMeshFactory` itself** — the top grid and the flank. Nothing
else in the project knew where the ground was, so every unit, prop, deposit and decal was
placed on the datum plane, and the file's own "datum rule" set the amplitude at the largest
value that kept that error unnoticeable. The terrain was flat to hide a missing contract.

**Done.**

- **`TerrainSurface`** resolves a world point to its fragment and samples the height field.
  `EntityPresenter` places units, buildings, deposits and the order marker through it; units
  re-sample every frame, because they walk. Relief stays presentational — the simulation is
  planar, and nothing here feeds back into it.
- **`FlatMeshBuilder.lift`** displaces positions as they are added, ahead of the winding fix
  and the normal, so a draped decal is lit by the slope it lies on. One hook expresses both
  answers to "where is the ground": return the height at the sampled point and a decal
  drapes; return a constant and a prop translates rigidly. `TerrainDressing` uses the first
  for seams, tone patches and the shore band, and the second per scattered prop — draping a
  trunk would shear it.
- **Amplitude** raised across the block: swell 0.24 → 2.1, micro 0.07 → 0.08, dish
  0.11 → 0.30, rim fall 0.15 → 0.55; range now `-2.0 … 0`. Rings 14 → 24.

**Verified.** Build green, zero errors, zero new warnings. Installed, launched, rotated,
captured as `Docs/QA/AAA/cp04-terrain-relief.png`. Units sit flat on the surface with no
gap. CP-03's calibration held: sand median 0.400 linear against its 0.397, saturation 0.358,
0.61% of frame over the bloom threshold.

**Two things the render caught that reasoning had not.**

1. **fbm is far gentler than its amplitude.** The swell went in at 0.95 and the rendered
   relief measured a low-frequency luminance swing of only ±0.07 against the flat build —
   present, but not something you would call terrain. A sinusoid of that height would have
   given three times the slope; three octaves of fbm do not. 2.1 is that measurement scaled
   to the swing the ground needs, and it lands at −0.094…+0.196.
2. **A height-field grid sits *above* the function it samples.** The mesh stretches flat
   triangles between its corners, so across every dip the chord runs above the curve.
   Anything laid on the ground by sampling the continuous function is then underneath the
   mesh and never drawn — the first CP-04 render came back with the gold seam network thin
   and broken, at the old 0.022 m lift. `FragmentMeshFactory.chordError` (0.155 m) is that
   gap, derived as `A · (π · h / λ)² / 2` summed over the field's two terms at the widest
   grid spacing, and `TerrainDressing.Height` now sits on it. It is a property of the grid,
   not a safety margin: it has to be recomputed if an amplitude or a cell count changes.

### CP-03 — Make the light read · 2026-07-28 · closed

**Goal.** Stars as soft points rather than flat squares, and bloom that lands on the
emitters instead of nowhere.

**Found.** Three symptoms, one cause, all measured off `cp02-magenta-fixed.png` rather than
estimated:

- The post-process *was* running. The void backdrop is an unlit plane, and its blue channel
  falls smoothly 6.9 → 4.6 from centre to corner — a gradient only a vignette can put on
  unlit geometry. The run-02 premise that `install(into:)` is never called was wrong;
  `WorldController.attach(to:)` calls it at line 66.
- **The ground was overexposed by 36%.** Sunlit regolith measured a median **0.540** linear
  against concept 01's **0.397**. That single fact caused all three visible defects: nothing
  glowed, because emissive seams are authored independently of the lights and an over-bright
  ground closes the gap they need (glazing 0.744 against sand 0.672); bloom was a flat haze,
  because 15% of the frame — nearly all terrain — cleared the bright pass; and the frame read
  chalky, because ACES desaturates what it rolls off (saturation 0.301 against 0.345).
- **The bloom onset was at 0.32, not 0.58.** Contribution begins at `threshold - softKnee`,
  so the 0.30 knee put the onset far below the ground regardless of the threshold.
- **Stars were hard quads.** A 2-pixel cliff from void floor to full brightness, with heavy
  red/cyan fringing on the straight edges. Bloom cannot fix this: a star covers so few pixels
  that spreading its energy across a wide Gaussian leaves a halo far below visibility.

**Done.**

- `LightingRig.Tuning.exposureScale` — one multiplier over key, fill, rim and the IBL. The
  individual intensities stay the art direction; this is the exposure. 0.67 is the solution
  of the composite chain, inverted numerically, for a regolith median of 0.397. Scaling the
  *lights* rather than the post-process `exposure` is the whole point: it moves lit surfaces
  only, leaving unlit stars and emissive seams where they are.
- `threshold` 0.58 → 0.62, `softKnee` 0.30 → 0.16, `bloomIntensity` 0.72 → 3.2. The
  intensity is above 1 because a Gaussian blur conserves energy and these emitters are
  small; `RealityView` exposes no HDR path, so the headroom an HDR source would carry has to
  be supplied here.
- Star quads carry per-quad UVs and a shared 64×64 radial mask used as an opacity texture.
  `FlatMeshBuilder` derives UVs from world position and cannot express a per-quad 0…1
  square, so the star mesh is assembled directly.

**Verified.** Build green, zero errors, zero new warnings. Installed, launched, rotated,
captured at full resolution as `Docs/QA/AAA/cp03-light-reads.png`.

| measured | CP-02 | CP-03 | concept 01 |
|---|---|---|---|
| sunlit regolith, linear median | 0.540 | **0.397** | 0.397 |
| lit-subject saturation | 0.301 | 0.361 | 0.345 |
| frame over the bloom threshold | 8.34% | **0.56%** | 1.54% |
| star edge, steepest single-pixel step | 0.62 | **0.12–0.16** | — |

Bloom was isolated by rendering the frame twice, once at `bloomIntensity` 0 and once at the
shipped value, and differencing. At 0.72 the contribution was correctly placed — 28× stronger
next to an emitter than away from one, and at 10× amplification it outlines exactly the
glazing, the gold finial, the crystal deposits and the stars — but +0.002 display luminance,
half a code value out of 255. At 3.2 the ring around the glazing measures +0.0053 and 73,102
pixels are lifted past 0.03, against 12,877 before.

Changes confined to `Sources/Rendering`. `Simulation` and `Domain` import neither RealityKit
nor UIKit; no ad-hoc randomness anywhere in `Sources/`. Committed as `af84c47`.

**Cost — one lesson worth keeping.** The three defects looked independent and were logged as
three separate items across two sessions. They were one number. Measuring the frame against
the concept — rather than reading the code and reasoning about what it should produce — found
that in one pass, and turned the fix into arithmetic: the predicted regolith median was
0.397 and the rendered frame landed on 0.397. **Measure the frame before theorising about
the renderer.**

### CP-02 — Kill the magenta · 2026-07-27 · closed

**Goal.** No magenta anywhere in a rendered landscape frame, with every fragment layer and
rim band drawn in the material its author intended — not collapsed to a flat repeat of
layer 0, and with the array derived from the layer enum so a future added layer cannot
silently reintroduce the bug.

**Found.** The fragment meshes tag faces with per-layer material indices —
`materialIndex: UInt32(layer.rawValue)` at `FragmentMeshFactory.swift:339` and
`UInt32(band.rawValue)` at `:626`, both reaching
`descriptor.materials = .allFaces(...)` — while `WorldScene` handed those meshes a
*single-element* array: `materials: [surfaceMaterial(...)]` at line 68 and
`[rockMaterial(...)]` at line 74. Every face with index ≥ 1 resolved to no material at all.
Index 0 is why the base sand still looked right.

**Done.** Both call sites now take `FragmentMeshFactory.topMaterials(...)` and
`cliffMaterials(...)`, built with `allCases.map` over the two `Int`-backed `CaseIterable`
enums — so the array index *is* the emitted material index by construction, not by a
hand-kept parallel list that happens to be the right length today.

| `TopLayer` | material intent |
|---|---|
| `pale` | regolith with fragment surface tint; open sun-bleached ground |
| `mid` | cooler, darker regolith blend |
| `rimDark` | rock-pulled, strongly darkened regolith |
| `path` | compacted, smoother darker regolith |

| `CliffBand` | material intent |
|---|---|
| `lip` | warm rim stone with a faint emissive lift |
| `bounce` | sand-bounce stone with subtle emissive warmth |
| `upper` | neutral cool fractured stone |
| `middle` | cooled, darkened fractured stone |
| `base` | coolest, deepest stone layer |

**Verified.** Build green. Installed, launched, rotated, captured at full resolution as
`Docs/QA/AAA/cp02-magenta-fixed.png`. Placeholder-magenta pixels counted on a 3 px grid
across both frames: **64,490 → 0**. The rim now reads as layered blue-grey fractured stone,
the underside spikes as rock, the mid-terrain as tonal sand variation with visible paths,
and the second fragment renders correctly. Changes confined to `Sources/Rendering`;
simulation and determinism untouched.

### CP-01 — Green tree and honest baseline · 2026-07-27 · closed

**Goal.** Restore a compiling tree, establish this document, and get a real rendered frame
of the current code so the visual work has a true baseline.

**Found.** The tree did not compile, and it held **three** independent mid-flight breaks in
three different files, left by parallel agents that never re-verified together — each one
hidden behind the last:

1. `Sources/Rendering/TerrainDressing.swift:1413` — a file-scope extension on a `private`
   nested type.
2. `Sources/HUD/HUDStyle.swift:274` — `fillStyle` read off `HUDGlyph.Kind` when it was
   declared on `HUDGlyph`.
3. `Sources/Rendering/Meshes/UnitMeshes.swift:1153,1155,1171,1173` — four calls to the
   main-actor-isolated `StructureMaterial.shade` from a `nonisolated` synchronous context,
   under Swift 6 complete strict concurrency.

Separately, `build-agents/` was missing from `.gitignore`, leaving **35,602** untracked
files in `git status`.

**Done.** `TerrainDressing.Instance` narrowed `private` → `fileprivate`, the extension and
its `top(for:)` helper intact. `fillStyle` moved onto `HUDGlyph.Kind`, so the call site
resolves without duplicating the `usesEvenOdd` winding rule. `StructureMaterial.blend` and
`.shade` marked `nonisolated` — both are pure `UIColor` channel arithmetic that touches no
main-actor state; `matte` and `glow` deliberately left isolated because they construct
RealityKit materials. `build-agents/` added to `.gitignore`; `git status` drops from 35,602
lines to 21.

**Verified.** `** BUILD SUCCEEDED **`, exit 0, zero Swift errors, zero Swift warnings — the
three remaining warnings are one `UIRequiresFullScreen` deprecation and two
`appintentsmetadataprocessor` notes, all pre-existing. `Simulation` and `Domain` import
neither RealityKit nor UIKit. No `Double.random` / `Int.random` /
`SystemRandomNumberGenerator` anywhere in `Sources/`. Installed and launched on the
simulator, rotated to LandscapeLeft, captured at full resolution:
`Docs/QA/AAA/cp01-baseline-green.png`.

**Found in that frame.** The magenta missing-material regression, described above — never
reported by any prior session because no prior session had ever rendered this code.

**Cost — two lessons worth keeping.**

1. **The implementer cannot build this project, and its self-reported blockers were wrong
   twice.** Every Codex-run build emits `Unable to discover any Simulator runtimes` and dies
   before compiling; every orchestrator-run build compiles cleanly. The cause is Codex's
   `-s workspace-write` seatbelt sandbox blocking the XPC connection `xcodebuild` needs to
   reach `simdiskimaged` for simulator-destination resolution. CoreSimulator was healthy the
   whole time. Before diagnosing that, the agent read its own command timeout (`exit 143` =
   SIGTERM on a multi-minute `xcodebuild`) as a dead service, ran `launchctl kickstart`
   against CoreSimulator twice mid-build, shut down the target simulator, and reported that
   a host reboot was required. It was not.
   **→ The loop is now: Codex edits source and never builds; the orchestrator runs every
   build and feeds back exact diagnostics.** Implementer prompts forbid `agent-build.sh`,
   `xcodebuild`, `xcrun`, `simctl` and `launchctl` outright.
2. **A green build proves nothing about the frame.** Three sessions of visual work compiled
   green while a third of the map rendered magenta. Every checkpoint from here ends with an
   installed build and a full-resolution landscape screenshot, or it does not close.

---

*Orchestration for this work runs under `.codex-orchestrator/runs/run-20260727-01/`. Claude
plans and verifies; Codex (gpt-5.6-luna, xhigh) implements. The journal there is the
append-only record of prompts, handoffs, verifications and decisions.*
