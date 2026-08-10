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

## In flight

### Helios Rift — Broken Ring reference parity · ACTIVE 2026-08-09

The user made the Three.js Helios Rift battlefield the active game direction. Resume from
the existing Broken Ring and Lumen Guard work. Do not restart the map or resume the native
CP-C6 sequence unless the user changes direction.

| | |
|---|---|
| **Goal** | Match the approved Broken Ring reference at the real gameplay camera while preserving a playable four-sector RTS map. |
| **Current proof** | Cycle 01 provides the measured 43-degree Helios camera, closer full-ring framing, deeper fragment walls, brighter rough-metal materials, and a dominant solar objective. Cycle 02 adds native one-finger pan, pinch camera zoom, tap selection, and double-tap ground commands without page zoom or mouse regressions. Cycle 03 replaces smooth fragment wedges with four stepped armor bands, 26 instanced edge chunks, six inset deck plates, eight cracks, physical gold rails, and larger end sockets per sector. Cycle 04 primes every Citizen and Guard on the movement-ready standing cell and skips redundant clip resets. Cycle 05 replaces the flat solar disk with a larger molten objective and is deployed as `b97a3ce`. Cycle 06 makes land movement fail closed and is deployed as `fdc8267`. Cycle 07 replaces the north placeholder bases with Blender-authored Civilization Core, Farm, and Formation Yard assets. Cycle 08 replaces the desktop debug overlay with a compact iPad-first tactical HUD. Cycle 09 replaces alternating deck panels with one deterministic world-space terrain field. Cycle 10 adds a seven-draw-group crystal-islet and debris field without walkable ground. Cycle 11 adds a deterministic 256×256 warped fBm and ridged nebula texture on one camera-centered sky sphere, plus cool distance fog. The final hosted 12-unit stress run rendered 600 frames in 9.9842 seconds at 60.095 FPS, with 17.8 ms p95, 18.7 ms maximum, zero frames above 20 ms, and zero invalid samples across 7,200 ground checks. Nebula commit `b436188` and versioned-review commit `f7a6142` are visible on `origin/main`; Worker version `44bf6fed-c17a-4490-bce8-7e7d9eda94d0` serves Cycle 11. The review page requests the exact versioned bundle, and the committed, deploy-site, and hosted hashes match. |
| **Current mismatch** | The ring now has a coherent weathered surface, crystal-bearing islets, and layered blue-purple void depth, but the strict side-by-side still does not blind-match the concept. The reference's fragment sidewalls use thicker stacked masonry, warm structural ribs, stronger contact shadows, and richer edge silhouettes. Vegetation and building materials also remain simpler. The frame proof uses `requestAnimationFrame`; it is not a device GPU frame-time percentile export. |
| **Write scope** | `ThreeRuntime/src/helios-rift-proof.js`, `ThreeRuntime/src/rts-camera.js`, `ThreeRuntime/src/rts-maps/`, required Helios/Lumen Guard web assets and proofs, dev-only deploy tooling, and Helios evidence/devlog files. |
| **Do not touch** | Production `helios.contenthelper.in`, unrelated native systems, other maps, completed dirty art, secrets, ownership, or access. |
| **Reference** | Dedicated 1672×941 Broken Ring image from Codex task `019fe6b7-3b48-7be0-b1b3-caf0d1eb4bf8`; the original three-map board supplies gameplay semantics. The Cycle 09 material direction also uses `https://simondev.io/demos/gamedev/#customizing-materials` and `https://x.com/iced_coffee_dev/status/2084276803833581736`. |
| **Evidence** | `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/` and `Docs/QA/ThreeJS/helios-broken-ring-aaa/DEVLOG.md`. |
| **Cadence** | One bounded visual correction per commit. Push each validated commit. Deploy and verify each accepted cycle at `dev.helios.contenthelper.in`. |
| **Next correction** | Deepen the fragment sidewalls with layered structural blocks, warm ribs, and restrained contact shadow. Preserve the top deck, logical platforms, bridges, controls, and the 60 FPS gate. |

### CP-C5 — Military roster breadth · CLOSED 2026-08-01

Opened and closed the same day. The army is no longer Vanguard spam: the Formation Yard
trains Pathfinder and Vanguard, the new Lumen Spire trains Quarrel and is gated behind a
completed Yard, and the six-unit opening was played end to end on the iPad. Full record
in `Docs/QA/G3/cp-c5/STATUS.md`.

Proven on device: trainer exclusivity in both directions (the Yard never offers Quarrel,
the Spire never offers Pathfinder or Vanguard, and unused slots say `No additional unit is
trained here.`); the prerequisite gate flipping from a named `Requires a completed Formation
Yard.` to `Lumen Spire. Trains Quarrels. Costs 90 Matter · 45 Lumen.` on **completion**;
every cost charged to the unit against the Core trickle; `BLOCKED · Move onto clear home
ground` refusing an illegal site without charging; `Population 10/10.` surfacing a real
production hold; and one group move of `6 Selected · 1 Pathfinders · 2 Vanguards ·
3 Quarrels · 345/345` arriving intact. `swift test` 72 → **86 tests, 0 failures**. World
hash `4f761a7b50d6df3c` at tick 7192, identical across two runs. **The CP-C5 entry here used
to claim no frozen literal existed anywhere in `Tests/`. That was false:**
`Tests/AdversaryTests.swift` carried the frozen tuning literals `420` (deposit yield) and
`89` (Lumen Spire affordability) until CP-C9 replaced both with reads from tuning. What is
true is the narrower claim — no test now re-states a tuning value it does not own, which is
what let the `String`-backed `.ranged` → `.quarrel` rename land safely. Approved constants
still appear as literals in `Tests/EconomyTuningTests.swift`, deliberately: that file is the
one place the economy's approved values are asserted, and a tuning test that read tuning
would assert nothing. Host and device agree on the no-input outcome: Gravemark by conquest
at 5:59.

Two defects were found during review and fixed in scope: the Vanguard's missing `+8 vs
siege` (R1 B2), and `ProductionSystem.step` dropping a charged queue item with no unit and
no refund.

**Left open, by name:** the Spire does not accept Lumen drop-off (`acceptsDropOff` is a
plain `Bool` and cannot express "Lumen only"); faction modifiers absent (CP-C8); R1 §6.4's
`id.raw % ringSlotCount` spawn rule deliberately not adopted; citizen gathering never
exercised on device this pass; the ledger pass ran with `-sunfoldNoAdversary` and combat was
verified separately; not built
from a clean clone. Three findings recorded rather than fixed: a dimmed tile's
accessibility label loses the building's identity, the panel reads `1 Pathfinders`, and
the Vanguard/Quarrel read works by elongated-versus-compact rather than by the vertical
line `01-UNIT-ROSTER.md:156-176` claims.

| | |
|---|---|
| **Checkpoint** | CP-C5 — Military roster breadth (Directive 3; design `04` §3 calls it CP-G3c) |
| **Opened** | 2026-08-01 · at `3166af3` |
| **Owner** | director (orchestrating), Codex implementation agents |
| **Goal** | An army that is more than Vanguard spam: `Formation Yard → Pathfinder + Vanguard → Lumen Spire → Quarrel`, with a counter read a stranger can see. |
| **Write scope (exact)** | `.lumenSpire` building (90 Matter / 45 Lumen / 18 s / footprint 3.0 / 210 HP / trains Quarrel / gated behind a completed same-faction Formation Yard). `.ranged` → `.quarrel` rename (R1 B13 — a rename, not a second unit). Formation Yard trains Pathfinder + Vanguard only, and its cost corrected 110 Matter / 40 Lumen → 110 Matter / **20** Lumen per `02-BUILDING-ROSTER.md`. Tier-1 combat profiles wired to `01-UNIT-ROSTER.md` + R1 (Vanguard gains the missing `+8 vs siege` from R1 B2; Quarrel range stays 9.0 per R1 B8). Typed simulation blockers so a prerequisite is enforced in the sim and not only in the HUD. Two-page command grid per `02` §6 with a **visible** on-screen reason for every dimmed tile. Held front production item so a charged queue item can never vanish. Adversary Lumen Spire deferral closed (Yard tick 2400, Spire tick 4800, second-Yard stand-in removed). Files: `Sources/Domain/EntityKinds.swift`, `SkirmishTuning.swift`, `Sources/Simulation/{ConstructionPlacement,SkirmishSimulation,ProductionSystem,Adversary}.swift`, `Sources/HUD/{CommandGrid,HUDStyle}.swift`, `Sources/Rendering/{EntityPresenter,WorldController,Meshes/BuildingMeshes,Meshes/UnitMeshes}.swift`, `Tests/*`, and evidence under `Docs/QA/G3/cp-c5/`. |
| **Do not touch** | Rebuilding `CombatSystem` or `Adversary` from scratch · CP-C2 / CP-C3 / CP-C4 victory rules · CP-C6 age research · CP-C9 economy retune (**closed 2026-08-01; do not reopen without new evidence**) · faction modifiers (CP-C8) · per-resource drop-off migration · perf campaigns / 60 fps · app icon / P15a · Flowdeck · Tier-2 units and buildings in the simulation. |
| **Preserved dirty work** | Large foreign dirty surface: `Sources/Diagnostics/`, `Sources/Rendering/FramePacing.swift`, `Sources/Simulation/BoardingSystem.swift`, app icon / `PrivacyInfo.xcprivacy`, perf scripts and `Docs/QA/Perf/`, `Docs/Method/`, `Docs/agents/`, `Docs/research/`, `CONTEXT.md`, and the handoff family. **Never `git add -A`.** Commit by explicit path only; `RootView.swift` carries a perf overlay on top of committed MatchOverlay and must be staged surgically if it is touched at all. |
| **Evidence** | `Docs/QA/G3/cp-c5/` (live naming wins over the design's `cp-g3c/`). |
| **Carried open** | The Dominion leak (adversary banks progress crossing the ring) stays **open** — re-measured in CP-C5, not fixed. The 8–10 minute promise stays unmet. The contest rule stays test-only. |

### CP-C4 — CLOSED 2026-08-01

Victory and defeat shipped. Two win paths, a terminal state that stops the world,
and Play Again — all four played on the iPad. Log entry below;
full record in `Docs/QA/G3/cp-c4/STATUS.md`.

### CP-C2 / CP-C3 — CLOSED 2026-07-31

CP-C2 combat was implemented and test-proven on 2026-07-31 but deliberately **not**
closed, because no fight had ever been observed in play — Gravemark had no AI, so
two hostile units never came into contact. CP-C3 built that adversary and the
device pass folded into it closed CP-C2 as **CP-C2′** the same day. Both records:
`Docs/QA/G3/cp-c2/STATUS.md` and `Docs/QA/G3/cp-c3/STATUS.md`.

### CP-G2a — CLOSED 2026-07-31 (historical block below kept for the record)

| | |
|---|---|
| **Checkpoint** | CP-G2a — Construction |
| **Opened** | 2026-07-30 |
| **Owner** | construction agent |
| **Write scope (exact)** | Finish shipping Farm / Matter Extractor / Dwelling construction: promote Soft ghost out of prototype chrome; command-grid pick with cost + purpose; drag-ghost legal/illegal; place with cost on commit; citizens construct with linear multi-builder progress; cancel incomplete with `cancelRefundFraction` refund; construction progress readable in HUD/world; completion visual + audio feedback. Files limited to construction path: `Sources/Debug/BuildGhostPrototype.swift` (or its shipping successor), `Sources/Simulation/ConstructionSystem.swift`, construction hooks in `SkirmishSimulation` / `WorldController` / `EntityPresenter` / `CameraGestureLayer` / `CommandGrid` / `RootView` / `SelectionPanel` / `SkirmishTuning` / `EntityKinds` / `WorldEntities` as needed for cancel+purpose+feedback, plus minimal Audio stub for completion cue, and evidence under `Docs/QA/G2/`. |
| **Do not touch** | Production (CP-G2b), objective/hints (CP-G2c), control groups / activity anim (CP-G2d), combat, transport boarding beyond preserving existing dirty `BoardingSystem` / boarding hooks, fog paint/minimap fog (explored treated as home land for G2a legality until a fog system exists), unrelated visual/map dirty work. |
| **Preserved dirty work** | Leave all non-construction modified/untracked files intact (boarding, map/movement, TopBar, SelectionModel, DeterminismTests, research docs, etc.). |
| **Pre-edit play** | Played `build-agents/transport-void/.../SunfoldGreenfield.app` on iPadOS 26.5 (`A59055F8-…`). Prototype chrome + proto command tiles live; Soft locked per #11. |
| **Implemented** | Farm / Matter Extractor / Dwelling command tiles, purpose and cost copy, full-footprint placement checks, dedicated placement gestures, cost commit, citizen construction, progress presentation, cancellation refund, and completion feedback. Native iPadOS 26.5 captures are under `Docs/QA/G2/cp-g2a/`. |
| **Independent review** | `REVIEW_REVISE`. The primary defect is the successful-placement state: the ghost remains on the new foundation and immediately reads `BLOCKED`. See `Docs/QA/G2/cp-g2a/read-only-kimi-review.md`. |
| **Proof state** | The isolated staged source snapshot builds for the iPadOS 26.5 simulator; see `Docs/QA/G2/cp-g2a/staged-build-proof.md`. Rendered Farm flow is captured. Focused tests, all three building variants, cancel/deny states, audio, and Reduced Motion remain unproved. Do not call CP-G2a closed. |
| **Resume here** | Fix the post-place ghost state first. Then prove the bounded interaction matrix on iPadOS 26.5 and request an independent re-review. Do not begin CP-G2b production yet. |

### CP-G2a — resolved 2026-07-31 · closed on its primary defect, remainder re-scoped

**The primary defect is fixed and photographed.** The r2 worktree's fixes were **ported by
hand rather than merged**, because the same files carry three other agents' in-flight work.
Place a Farm now and the ghost clears, the camera is immediately usable, and the refund reads
`+52.5 Matter`. Eight landscape captures on the iPad Air 13 simulator, full write-up:
`Docs/QA/G2/cp-g2a/r3-resolution.md`.

**Explicitly re-scoped out to CP-G2a′, not silently dropped:** completion audio (not
verifiable from screenshots — a pause boundary, and I am not substituting a weaker
measurement), Reduced Motion, the illegal/unaffordable/cancel-placement states, and Matter
Extractor and Dwelling completion.

**Correction to the CP-G2a-R2 log entry.** It recorded `ConstructionIntegrityTests` at
**10 of 10 passed**. That was not real test output — that worktree's own
`IMPLEMENTATION_STATUS.md` records `xcodebuild test` as hook-blocked there. **No test in this
repository had ever executed.** Fixed the same day under P14: a root `Package.swift` exposes
`Sources/Domain` + `Sources/Simulation` as a testable `SunfoldCore` module, and **29 tests now
genuinely run and pass on the host in ~60 s** with no simulator and no app host. Verified by
the director, not taken from the builder. Evidence: `Docs/QA/G2/p14/test-run.md`.

---

## Status at a glance

| | |
|---|---|
| **Last checkpoint** | CP-C9 — Economy tuning and nine-minute proof · **shipped** 2026-08-01 |
| **In flight** | Helios Rift — Broken Ring reference parity. The native CP-C6 sequence is paused. |
| **Shipped 2026-07-31** | CP-G2a closed · P14 test harness · CP-C1 production · CP-G3a2 traversal · CP-G2b-NAV navigation · P4 pose caching · CP-C2′ combat · CP-C3 adversary |
| **Shipped 2026-08-01** | CP-C4 victory and defeat · CP-C5 military roster breadth · CP-C9 economy tuning and nine-minute proof |
| **Build** | 🟢 `** BUILD SUCCEEDED **` on iPadOS 26.5, installed and played on `75898CE1-…`. **99 tests pass; 2 opt-in long-run tests skipped** under `swift test`. |
| **Renders** | 🟢 Sparse retune: open Core plazas, thinned props, shorter inland water. Land still **75–80%**. |
| **Current frame** | Hosted Cycle 11 overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-overview.png`. Reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-reference-comparison.png`. |
| **Version** | 0.6.5 · build 50 |
| **Gates** | G0 complete · G1 in progress · G2 in progress · G3 opened — none passed |
| **Play-feel reference** | **Age of Empires 2 / Rise of Rome, in space** (BC-01, 2026-07-31). Was Age of Empires IV. |
| **Current direction** | Three.js Helios Rift. Match the approved Broken Ring at gameplay scale before adding parallel maps or systems. Preserve the native campaign work as history. |
| **Can a match be won or lost?** | **Yes.** Both paths were played to a result on the iPad and photographed: Dominion at 3:55, Conquest at 15:55, defeat by Conquest at 5:59, defeat by resignation, and Play Again back to 0:01. A finished match genuinely stops stepping. **What it is not yet:** inside the 8–10 minute promise (nothing observed landed in that window), and the contest rule has never been exercised in play. |
| **Commit boundary** | Committed narrowly by explicit path. Other agents' dirty work (`Sources/Rendering/FramePacing.swift`, `Sources/Diagnostics/`, `Sources/Simulation/BoardingSystem.swift`, `scripts/`, `Docs/QA/Perf/`, `Docs/QA/Launch/`, app-icon and launch-gate files) left untouched and uncommitted. At CP-C4 `RootView.swift` carried both CP-C4 work and a perf overlay, so its index entry was staged surgically rather than committing the whole file. |
| **Next checkpoint** | Cycle 12 fragment sidewall architecture and contact shadow. Cursor owns the separate second-civilization 2D sprite workflow; Blender-authored 3D buildings remain on this track. |

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
was a **value inversion**, the concept's ivory-and-gold pavilion being the brightest object in
frame against our charcoal dome darker than the ground it stood on. Closed at CP-07.

**CP-08 — The void.** · **closed.** Nebula wash, celestial body in frame, drifting debris.

**CP-09 — Rim, deposits and plant mass.** · **closed.** Pale rim spurs, larger lumen clusters,
tree-scale branching masses. Ground-inlay rosette near the Core still carried (terrain drape).

**CP-10 — HUD parity.** · **closed.** Top-bar centre emblem and speed controls, alert row,
pinned group slots, selection portraits + life meters, minimap fragment silhouettes.

**CP-11 — Transport and pier.** · **closed.** Dark spar gone (unwoven causeway field suppressed);
docked gold pier on the sunwoven hull.

**CP-12 — Mostly-land maps + leftovers + neutral terrain.** · **closed.** Two mostly-land
layouts; shared land palette; rosette / pier / rim / speed wired. *(Superseded on composition
by CP-13 — blob pair replaced with contiguous landmasses.)*

**CP-13 — Contiguous land maps.** · **closed.** `coastland` / `isthmus` replace
`continental` / `crescent`; overlapping plates; coastal docks; opening camera on interior land.
*(Superseded on composition by CP-14 — one continent cut by void water.)*

**CP-14 — AoE land cut by void water.** · **closed.** `riverlands` / `basin` / `fjords`.
Authored coasts + carved void bodies; minimap contours the land field; void floor under
channels; causeway decks only across water.

**Parked: animation.** Needs per-unit activity state the simulation does not expose yet.
**Parked: control groups.** Slots remain chrome only.

### Decisions that override earlier docs

- **The feel bar (2026-07-31, BC-01) — human-authorised bar change.** The play-feel
  reference moves from **Age of Empires IV** to **Age of Empires II: The Rise of Rome, in
  space**. Full old-vs-new table, reason and consequences: `Docs/Gauntlet/00-PLAN.md`
  §"Bar-change log" → BC-01. In one line: a broad roster of cheap readable units with an
  explicit counter structure, a broad roster of buildings that each unlock something
  concrete, tier progression that visibly changes what you can build, villager economy with
  distinct resources and drop-off buildings, high-contrast readability, short build times, a
  match that resolves. This is a statement about **game design, not art style** — the 3D
  RealityKit renderer, the ~55–60° camera and concept 01 as the visual bar are unchanged, as
  are both civilizations, the seed, landscape-only iPad and the roadmap's out-of-scope list.
  The roster it demands is specified in `Docs/Design/` and no builder may invent content
  outside it.
- **Performance demoted (2026-07-31, BC-02) — human-authorised bar change.** B2 is a
  **guardrail, not a blocking bar**. It never holds a gameplay checkpoint open. Routine perf
  work is one cheap `-sunfoldPerf` regression smoke at checkpoint close; a >15% p99
  regression is logged as a known issue, not fixed, unless the game became visibly
  unplayable. Device perf, Instruments, thermal sustain and the quality A/B matrix are
  deferred to end of project. **P0.3, P5, B2a and B2c are deferred — do not start them.**
  P4 (`findEntity` caching) is the single exception. See BC-02 for the table and the reason.
- **Composition (2026-07-28, CP-14):** playable maps are **one continent cut by void
  water** (space substitutes for rivers, lakes, inlets). CP-13's overlapping-plate
  silhouette is superseded — it still read as discs on the minimap. Land covers
  **75–80% of the playable map** (`WorldMap.bounds`); the bible's older 40–55%
  land / 45–60% void ratio remains historical concept-screen guidance only.
- **Fairness (2026-07-28, CP-14):** only civilization Cores need equal distance from
  the Dominion. Maps need not be mirrored or symmetrical — organic asymmetry is fine.
- **Neutral land (2026-07-28):** fragments are never color-coded by civilization. Shared
  `landSurface` / `landRock`; minimap land fill is neutral. Faction identity stays on units,
  buildings, HUD, and Core livery.

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
explicitly benchmarked against **Age of Empires II: The Rise of Rome** for play-feel — the
human's phrase is *"AoE 2 Rise of Rome, but in space."* (Changed 2026-07-31 from Age of
Empires IV; the old and new bars sit side by side in `Docs/Gauntlet/00-PLAN.md`
§"Bar-change log" → BC-01.) Landscape-only iPad, an 8–10 minute skirmish, fully
deterministic from seed `20260726`. The visual bar is unchanged and remains concept 01.

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

Do **not** use Flowdeck / FlowDeck / `flowdeck` (banned). Prefer
`./scripts/agent-build.sh` for compile checks. Touching CoreSimulator by hand has
already cost this project one wasted agent cycle.

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

**Fixed at CP-07.** The Core is a tented pavilion and the brightest object in frame, matching
concept 01's canopy-to-ground ratio (1.13 against 1.15) and Core box median (0.391 against
0.394), with cold shadow down from 0.207 to 0.029.

**Fixed at CP-08 / CP-09.** Void wash + celestial body + debris; rim crystals, lumen mass,
tree-scale crowns.

**Fixed at CP-10 / CP-11.** Full top chrome (emblem, speed, alerts, groups, life on
selection); dark spar gone; gold pier at the dock.

**Still short of concept 01 / parked after CP-12:**

- **Control-group slots** — chrome only; no group wiring.
- **Animation** — parked; needs per-unit activity state.
- Pier / rim are closer but not a pixel-perfect concept match.

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

- **The adversary banks Dominion progress by accident.** Measured on device at CP-C4
  close: with nobody contesting, the objective rail read *"Dominion: you 0 of 45
  seconds, **enemy 11**"* at the end of the untouched match. CP-C3 routes every wave
  via the Dominion centre because there is no pathfinder, so waves cross the capture
  ring on their way to the player's Core and fill the Gravemark timer as they pass.
  Eleven of forty-five, and that match ended by Conquest first — but nothing caps it,
  and no schedule asked for it. A slower Conquest or a wave that stalls on the
  objective could hand Gravemark a Dominion win nobody designed, which is precisely
  the "killed by something you could not see coming" failure the checkpoint question
  asks about. **Decide before CP-C5**: route waves around the ring, exclude units in
  transit from capture, or accept it as emergent and make it legible.
- **A clean checkout of this branch does not build, and has not since CP-C2.** Found
  2026-07-31 while verifying the CP-C3 commit in a throwaway worktree. Two call sites are
  **committed** while the files that define them are **untracked**:
  `Sources/Rendering/WorldController.swift` calls `PerfHarness` / `PerfLaunchFlags` /
  `SceneScaleSnapshot` (all in the untracked `Sources/Diagnostics/`, committed at `47b0c33`),
  and `Sources/Simulation/SkirmishSimulation.swift` calls `BoardingSystem` (untracked
  `Sources/Simulation/BoardingSystem.swift`, committed at or before `a457011`). Every local
  build is green because the working tree has the files; anyone who clones gets four
  `cannot find … in scope` errors. **Not fixed here on purpose** — both belong to other
  agents' in-flight work, and committing them would be committing foreign changes. Whoever
  owns the perf and boarding work should commit those files, or the call sites should come
  back out. This is exactly the failure mode this project keeps hitting: the green build is
  measuring the working tree, not the repository. **CP-C4 deliberately did not deepen it**
  (2026-08-01): `Sources/App/RootView.swift` was staged surgically so the commit carries
  `MatchOverlay` / `ObjectiveRail` but *not* the working tree's `PerfOverlay` block or
  `perfDensity` pass-through, and `SunfoldRealityView.swift`'s `.sunfoldFramePacing()` hook
  was left out entirely. That exact committed file set was built green before committing.
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
- ~~**The unit tests have never been executed.**~~ **Fixed under P14 on 2026-07-31.** The
  planned SwiftPM extraction happened: a root `Package.swift` exposes `Domain` + `Simulation`
  as `SunfoldCore`, and **72 tests run and pass under `swift test`** (49 at CP-C3) on the host in about a
  minute, no simulator and no app host. The remaining wrinkle is that `Tests/` is *also*
  globbed into the Xcode `SunfoldGreenfieldTests` target, which cannot resolve
  `@testable import SunfoldCore` — so `xcodebuild` on the scheme fails on the test target in
  a clean checkout while `agent-build.sh` (app target only) is green. **Run tests with
  `swift test`, never with `xcodebuild test`.**
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

> The 2026-07-31 checkpoints (P14, CP-G2a, CP-C1, CP-G3a2, CP-G2b-NAV, P4) keep their
> full records under `Docs/QA/` rather than here. The entry below follows that
> practice: a summary and a pointer, not a duplicate.

### CP-C9 — Economy tuning and nine-minute proof · 2026-08-01 · closed

**Goal.** Make the approved home economy pay for the Tier-1 opening without treating
temporary unaffordability as a stall.

**What shipped.** Home deposits are region-aware: Matter 700 and Lumen 550, with the
pre-CP-C9 Matter 420 and Lumen 300 preserved outside home. The Dwelling is 55 Matter / 14 s
with the existing +8 population grant. Deposit placement and deterministic draws are
unchanged. The nine-minute harness now measures useful capability through the production
API, separates no-choice stalls from raw affordability delay, records denial episodes,
reports Pathfinder and the trained army separately, and writes mode/seed/duration-specific
sample and denial files.

**Observed.** At 9:00 in economy-ceiling mode, seed `20260726`, riverlands: population
42/42, four completed Dwellings, 12 Citizens, 13 Pathfinders, 9 Vanguards, 8 Quarrels,
one Light Transport, no Bastion Walker, and **0.000 s** of no-choice stall. Raw affordability
delay totals 38.650 s, and every denial episode had another productive action available.
The home Lumen deposit exhausts at **8:18.75**; home Aether is absent by design.

**Device.** The iPad pass showed the shipped 55 Matter copy, the 75% refund, the +8 grant,
real Matter/Lumen gathering, an adversary defeat at 5:58, and a clean no-adversary run to
4:01. The full nine-minute arc was not hand-played to completion; the deterministic harness
proved it twice with byte-identical CSVs. Full record: `Docs/QA/G3/cp-c9/STATUS.md`.

### CP-C4 — Victory and defeat · 2026-08-01 · closed

**Goal.** Make the match able to end. CP-C3 left an opponent that destroyed the
player's Core at 5:59 while the simulation kept running over the corpse.

**What shipped.** `Sources/Simulation/VictorySystem.swift` — Conquest and Dominion,
judged after every other system on the same tick, so a Core that falls to this
tick's combat ends the match on this tick. `MatchOverlay` and `ObjectiveRail` in
the HUD, `restart()` on `SkirmishSimulation`, and the Dominion Spire as the
fifteenth `BuildingKind` — neutral, indestructible, owned by nobody.

**Observed.** Played on `75898CE1-…` (iPad Air 13, iPadOS 26.5).

| claim | evidence |
|---|---|
| A player can win by Dominion | **VICTORY · DOMINION** at 3:55, rail at `45s / 45s` |
| A player can win by Conquest | **VICTORY · CONQUEST** at 15:55 |
| A player can lose, and be told why | **DEFEAT · CONQUEST** at 5:59; **DEFEAT · RESIGNATION** named as itself |
| The hold requirement escalates | rail reads `0s / 20s` at 15:55 |
| A finished match stops stepping | clock held at **0:21** across two accessibility reads seven seconds apart |
| Play Again rewinds the world | clock **0:01**, POP **4/10**, stock back to 180 / 160 / 40 |

**Cost.** 49 → **72 tests**, 0 failures (20 new `VictoryTests`). The CP-C3
determinism fingerprint is restated rather than weakened: tick 12000 is
unreachable now that the match ends at tick 7192, so the bar is that two no-input
runs stop on the same tick with the same outcome and the same hash — which moved
to `4645f2d24d31018c` because the Spire joined the world and the Dominion deposits
moved out of its footprint.

**One real defect found on the way.** The Formation Yard, Expansion Outpost and
Dawn Loom had command tiles since CP-C1 but were missing from
`ConstructionPlacement.placeableKinds`, so all three did nothing when tapped. The
Formation Yard is the only building that trains a military unit — the player could
reach **neither** win path. Fixed, with two tests holding the line.

**Full record.** `Docs/QA/G3/cp-c4/STATUS.md`, including a "What is not proven"
section: the 8–10 minute promise is met by no observed match (5:59 and 15:55), the
contest rule has never been exercised in play, and CP-C3's unexplained camera jump
is still unexplained — CP-C4 moves the camera only on restart.

### CP-C3 — Adversary v0 · and CP-C2′ — Combat, observed · 2026-07-31 · closed

**Goal.** Put somebody on the other side of the map, and use them to prove that
combat happens — CP-C2 had refused to close on a green test suite alone.

**What shipped.** `Sources/Simulation/Adversary.swift` — a deterministic schedule,
not a planner: every decision is a pure function of tick and world state, with **no
random draws at all**, so the tagged `adversary` stream is reserved and unused.
`Sources/Simulation/WorldHash.swift` — the canonical FNV-1a world fingerprint
R1 §6.13 asks for, which did not exist before and which the determinism bar is
defined in terms of.

**Observed.**

| claim | evidence |
|---|---|
| Two no-input runs share one world hash at tick 12000 | `a9ee7bc2faeea255` both runs, event logs identical line for line |
| First wave arrives inside the 3:30–4:30 bar | **4:27** (tick 5340) |
| Combat happens in play, with no player input | first blood 4:30 · first kill 4:33 · Core destroyed 5:59 · POP 0/10 |
| The adversary is granted nothing | `plan` takes `stock` by value; `testTheAdversaryMatterLedgerCloses` reconstructs the balance from first principles |

Device evidence on `75898CE1-…` (iPad Air 13, iPadOS 26.5): seven landscape frames
in `Docs/QA/G3/cp-c3/`, including the selection panel reading
**Civilization Core · SUNWOVEN · 303 / 600** while it is being hit. That frame is
what closed CP-C2 as **CP-C2′**.

**Cost.** 39 → **49 tests**, 0 failures. Two schedule decisions the spec did not
make (a second Formation Yard standing in for the unbuildable Lumen Spire; four
Dwellings on a population rule) and five spec rows **dropped rather than fudged**
because the units do not exist yet — all named in `Adversary.deferredFromSpec` and
in the STATUS doc, per Directive 3.

**Full records.** `Docs/QA/G3/cp-c3/STATUS.md` and `Docs/QA/G3/cp-c2/STATUS.md`,
including a "What is not proven" section (the wave is not measured as beatable, and
one unexplained camera jump is logged rather than guessed at).

### CP-14 — AoE land cut by void water · 2026-07-28 · closed

**Goal.** Replace CP-13's overlapping-disc silhouettes with Age of Empires–style
continents where **space is water**: rivers, lakes, and inlets carved from one land
field. Three variants. Cores equidistant from Dominion; everything else free to be
asymmetric.

**Verified frames.**

| frame | proves |
|---|---|
| `Docs/QA/AAA/cp14-map1-riverlands.png` | Pre-sparse baseline: dense props + inland lake near Core |
| `Docs/QA/AAA/cp14-map2-basin.png` | Great lakes / arms; void under dock; causeway spans water only |
| `Docs/QA/AAA/cp14-map3-fjords.png` | Deep inlets as starfield; causeway decks over black channel (not plate rock) |
| `Docs/QA/AAA/sparse-map1-riverlands.png` | Post-sparse: open Core plaza, thinned thickets, no near-Core tarn |
| `Docs/QA/AAA/sparse-map2-basin.png` | Basin with open plateau fight space |
| `Docs/QA/AAA/sparse-map3-fjords.png` | Fjords with open home plateau (blind inland sound removed) |

**Map design.**

| | riverlands (default) | basin | fjords |
|---|---|---|---|
| kind | branching rivers + flank tarns | great lakes + arms | long sounds / inlets |
| select | default / `-sunfoldMap riverlands` | `-sunfoldMap basin` | `-sunfoldMap fjords` |
| aliases | `coastland`, `continental`, `map1` | `isthmus`, `crescent`, `map2` | `fjord`, `inlets`, `map3` |
| fairness | Cores equal reach from Dominion | same | same |
| symmetry | organic / asymmetric OK | same | same |

**Contract.** `WorldMap.contains` / `region` read an authored land field
(`LandShape` lobes + `VoidBody` carve + `LandErosion`), not disc unions. Mesh drops
drowned cells, walls banks, and caps channels with an unlit void floor that tracks
the flank cone so rock never pokes through near the rim. Minimap contours the field
(`LandContour`). Causeway spars span only the wet stretch of a dock-to-dock line.

**Observed.**

| piece | observed |
|---|---|
| Minimap | One organic landmass with interior void — not seven stroked circles. Basin reads best; fjords still peninsula-heavy (inherent to deep sounds). |
| 3D carve | Channels and lakes are starfield black. Pre-fix frames showed cracked plate underside; void floor + cone-tracking drop closed that. |
| Causeways | Decks appear only across water crossings; no slab lying across dry ground. |
| Fairness | Core centres share one radius about the Dominion; coasts / water / expansions free. |
| Land coverage | Still **75–80% of playable `bounds`** after sparse retune (seed `20260726`, step 1.5): riverlands **75.8%**, basin **79.4%**, fjords **77.6%**. Asserted in `DeterminismTests` / `Tools/mappreview`. |
| Fight space | Post-CP-14 sparse retune: dressing site spacing ~2.6–3.0 m (was 1.3–1.5); Core plaza keep-clear +7.5 m; inland water shortened / pocket voids removed near cores. |

**Cost.** `LandShape.swift`, `LandContour.swift`, rewritten `WorldMap` layouts,
`FragmentMeshFactory` (water mask / banks / void floor), `WorldScene` water-crossing
causeways, `Minimap` / dressing / movement / populator / DeterminismTests, AGENTS /
bible / gauntlet / PROJECT_STATE. Launch-arg map switch remains the capture path
(rebuild default per variant — args hook-blocked). Sparse follow-up also retuned
`TerrainDressing` + inland water knobs; MapPreview entry renamed
`Tools/mappreview/MapPreviewEntry.swift` (Swift `@main` vs `main.swift` conflict).

---

### CP-13 — Contiguous land maps · 2026-07-28 · closed

**Goal.** Replace CP-12's separate land-blob pair with two contiguous landmasses (continuous
coast / continent silhouettes from map-kind refs — not AoE art style). Void only as a thin
edge ocean. Keep neutral terrain and Sunfold rendering language.

**Verified frames.**

| frame | proves |
|---|---|
| `Docs/QA/AAA/cp13-map1-coastland.png` | Map 1 contiguous interior land; ivory Core; minimap one landmass |
| `Docs/QA/AAA/cp13-map2-isthmus.png` | Map 2 contiguous land; different elongated minimap silhouette |

**Map design.**

| | coastland (default) | isthmus |
|---|---|---|
| kind | compact coastal continent | crescent-continent / land-bridge |
| fragments | 7 overlapping plates | 7 overlapping plates |
| home radius | 52 | 50 |
| expansion / dominion / neutrals | 38 / 40 / 30 | 34 / 34 / 26 |
| home centers | ±(52, 18) | ±(36, 38) |
| contiguity | one connected component (gap ≤ 0 edges) | same |
| fairness | 180° half-turn | 180° half-turn |
| select | default / `-sunfoldMap coastland` | `-sunfoldMap isthmus` |
| aliases | `continental`, `map1`, `1` | `crescent`, `map2`, `2` |

**Gameplay topology.** Region IDs still gate movement / deposits — units cannot walk onto
another plate without a region change. Transport-first home→expansion stays
(`wovenByOutpostOf` + void lanes). Docks sit on the **outer coast** via a deterministic void
finder (centerline docks would land inside overlapping neighbors). Always-open 3D causeway
spars are suppressed when plates already overlap (land *is* the crossing); minimap still
marks the logical spine.

**Observed.**

| piece | observed |
|---|---|
| Contiguous land | Opening frustum is wall-to-wall sand — no floating disk rim. Minimap shows one merged landmass, not separate islands. |
| Map pair | Coastland reads compact; isthmus reads more elongated / diagonal on the minimap. |
| Neutral land | Held from CP-12 — shared warm sand, no faction-tinted terrain. |
| Core | Ivory Sunwoven pavilion centered in opening frame on both maps. |

**Cost.** `WorldMap.swift` (new IDs + layouts + coastal `dockPoint` + contiguity helper),
`WorldScene` (skip spar over overlaps), `DeterminismTests` (contiguous replaces non-overlap),
App / tuning comments, AGENTS / bible / gauntlet / PROJECT_STATE.

---

### CP-12 — Mostly-land maps + visual leftovers + neutral terrain · 2026-07-28 · closed

**Goal.** Invert void-heavy composition to mostly land; author a second map; close doable
visual leftovers; stop painting land by civilization.

**Verified frames.**

| frame | proves |
|---|---|
| `Docs/QA/AAA/cp12-map1-continental.png` | Map 1 mostly land; neutral sand; rosette; pier; HUD |
| `Docs/QA/AAA/cp12-map2-crescent.png` | Map 2 mostly land; different minimap silhouette; same land palette |
| `Docs/QA/AAA/cp12-visual-ladder.png` | Same capture as map1 — leftovers in one frame |
| `Docs/QA/AAA/cp12-pier-lattice.png` | Pier lattice reference (same map1 capture) |

**Map design.**

| | continental (default) | crescent |
|---|---|---|
| fragments | 7 | 7 |
| home radius | 32 | 28 |
| expansion | 20 | 18 |
| dominion | 16 | 16 |
| neutrals | 12 | 12 |
| home centers | ±(66, 20) | ±(48, 32) |
| fairness | 180° half-turn | 180° half-turn |
| select | default / `-sunfoldMap continental` | `-sunfoldMap crescent` |

Both keep transport-only first home→expansion crossing (`wovenByOutpostOf`) and always-open
spine to Dominion. Camera default zoom 64 so a home nearly fills the opening vertical extent.

**Observed.**

| piece | observed |
|---|---|
| Mostly land | Opening view is land-dominant; void is a thin rim + peek of neighbor plates. Minimap shows packed plates, not sparse islands in a sea of void. |
| Neutral land | All fragments share warm sand; Gravemark home is not slate-blue. Minimap land fill is one beige for every plate. |
| Rosette | Gold plaza glow / inlay ring around the Core, draped on the settlement pan. |
| Pier | Lattice boards + slender posts readable at the dock (less of a solid gold wedge). |
| Rim / minimap | Stronger rim reach (~12–20%+ spurs); silhouettes less circular. |
| Speed chrome | Pause / 1× / 2× / 3× wired to `isPaused` + `timeScale`. |
| Groups / animation | Left parked (no control-group model; no sim activity state for honest anim). |

**Cost.** `WorldMap.swift` (MapID + two layouts), `SkirmishSimulation` / App / RootView (map
select), `SunfoldPalette` + TerrainDressing + Minimap (neutral land), TransportMesh (pier),
FragmentMeshFactory (rim), TopBar (speed), SkirmishTuning (zoom 64), DeterminismTests (both
maps), AGENTS / bible note / gauntlet workbench.

---

### CP-11 — Transport and pier · 2026-07-28 · closed

**Goal.** Kill the dark spar that read as a slab bolted to the docked transport; add the
concept 01 gold pier at the rim dock.

**Verified frame.** `Docs/QA/AAA/cp11-pier.png` (same capture as CP-10 try1).

**Observed.**

| piece | observed |
|---|---|
| Dark spar | Gone. The spar was the unwoven home→expansion causeway field sharing the transport's dock point — solid plane + rails suppressed when `!isAlwaysOpen`. Future route stays on the minimap as dashed intention. |
| Gold pier | Lattice deck + posts + braces off the port sheer toward the rim; readable gold block at the dock in frame. |
| Side ramp | Long ivory ramp replaced with a short boarding step so nothing else reads as a boom into the void. |

**Cost.** `WorldScene.swift` (unwoven causeway early-return), `TransportMesh.swift` (pier +
step). No simulation / stream changes.

### CP-10 — HUD parity · 2026-07-28 · closed

**Goal.** Close the chrome gap against concept 01: centre emblem and speed cluster, alert
row, pinned group slots, selection portraits and life meters, minimap silhouettes.

**Verified frames.** `Docs/QA/AAA/cp10-hud.png` · selection `Docs/QA/AAA/cp10-hud-selection.png`.

**Observed.**

| piece | observed |
|---|---|
| Top bar | Resource rail left, sunburst emblem centre, pause/1×/2×/3× cluster right. Speed tiles are chrome only (no clock control yet). |
| Alert strip | Seed cue under the rail: "Light transport docked at home rim". |
| Group rail | Three empty pinned slots on the left edge above the theatre. |
| Selection + life | Core card shows portrait-less building inspect + green `600 / 600` life meter. Unit portrait row is wired for unit selections; combat HP remains visual-only (G2 parked). |
| Minimap | Fragments drawn from `FragmentMeshFactory.rimOutline` (same rim stream replay) instead of ellipses. Irregularity is mild at map scale because rim reach is only ~10%. |

**Cost.** New `Sources/HUD/TopBar.swift`; `RootView`, `SelectionPanel`, `Minimap`,
`CommandGrid`, `FragmentMeshFactory.rimOutline`. HUD only + one pure outline helper.

### CP-09 — Rim, deposits and plant mass · 2026-07-28 · closed

**Goal.** Close the half of the planting gap CP-06 could not: not *count* but **mass** —
concept 01 carries a few tree-scale branching silhouettes where every prop of ours was a
medium spiky clump — plus pale crystalline rim spurs and larger lumen deposit clusters.

**Verified frame.** `Docs/QA/AAA/cp09-rim-mass.png` (same capture as CP-08 try4).

**Observed.**

| piece | observed |
|---|---|
| Rim crystal spurs | Pale ivory tips along the rim, readable against void. |
| Lumen deposits | Larger bright cluster left of the Core. |
| Branching mass | Tree-scale lobed crowns with pale limbs, mid-ring / fringe — Core stays clear. |

**What closed the mass gap.** A new `PropClass.branchingMass` alone was not enough. try2
enlarged crowns but almost none placed: the canopy pass jammed `site(..., spacing: 4.2)`
against the scrub list already packed at 1.3–1.5 m. Fix: a separate `canopySites` list that
only keeps clear of other canopy trunks, claimed ground (+2.8 m), and the rim. try3 then
*overshot* into a forest burying the pavilion — dialed to 7.0 m canopy spacing, mid-ring
placement, and smaller crowns (1.6–2.4·wide). Ground-inlay rosette still carried (terrain
drape under relief).

**Cost.** `TerrainDressing.swift` (branchingMass + canopy pass), `FragmentMeshFactory.swift`
(crystal rim spurs), `DepositMeshes.swift` (larger lumen clusters). Dressing stream draw
order ahead of the canopy pass unchanged.

### CP-08 — The void · 2026-07-28 · closed

**Goal.** Give the void depth: nebula wash (bible: not busy over the playfield), the
celestial body actually in frame, and drifting debris.

**Verified frame.** `Docs/QA/AAA/cp08-void.png` (Gauntlet try4).

**Measured (void-sides band, matching the pre-edit method):**

| | concept 01 | cp07 | try1b | **cp08 (try4)** |
|---|---|---|---|---|
| void floor luma (L&lt;0.08) | 0.032 | 0.006 | 0.007 | **0.036** |
| soft-void frac (0.02&lt;L&lt;0.18) | 0.338 | 0.023 | 0.033 | **0.362** |
| soft-void saturation | 0.57 | 0.47 | 0.47 | **0.49** |
| celestial body upper-right | warm gas giant | out of frame | in frame | **in frame** |

**Five things the renders taught.**

1. **The celestial body was never missing — it was outside the frustum.** Authored at
   `[46, 29]` with half-width ≈38.7. Reposition to `[18, 14]`, radius ~14, warm banded
   unlit texture.
2. **Nebula opacity must peak ~0.70 before ACES and the black plate.** try1b at softer
   opacity left soft-void at 0.05; 0.70 landed 0.36 against concept 0.34.
3. **Debris must sit inside the visible card (±~35), not ±120.** Off-frustum shards are
   invisible regardless of mesh. Mid-grey unlit (~0.44) angular tetrahedra; charcoal
   quads vanish.
4. **Screenshot rotation follows the *device* orientation that stuck.** After
   Portrait→LandscapeLeft, `rotation: "LandscapeLeft"` puts resources TL / Theatre BL.
   `LandscapeRight` flips the HUD 180°.
5. **Opaque void floor texture** (deep indigo + warm/cool mottling) is what moves floor
   luma; a shy transparent wash alone cannot.

**Cost.** `StarfieldFactory.swift` + `SunfoldPalette.swift` (void / celestial colours). New
streams `"nebula"` and `"debris"`; `"starfield"` / `"celestial"` draw order untouched.

### CP-07 — The Core pavilion · 2026-07-28 · closed

**Goal.** Turn the closed dark dome into concept 01's tented pavilion: separate ivory canopy
panels radiating from a finial, a gold armature, turquoise insets, a colonnade on an inlaid
plinth. The largest single-object gap in the frame, and the only one that was a *value
inversion* rather than a missing detail.

**Measured, before and after.** Core box, its own ground patches, same boxes in every build
frame. Six renders; the ones that moved a number are shown.

| | concept 01 | cp06 | try 4 | try 5 | **cp07** |
|---|---|---|---|---|---|
| canopy / ground linear luma | 1.15 | 0.57 | 0.64 | 0.90 | **1.13** |
| canopy luma median | 0.495 | 0.236 | 0.268 | 0.390 | **0.487** |
| canopy pixel fraction of box | 0.328 | 0.206 | 0.270 | 0.330 | **0.355** |
| Core box luma median | 0.394 | 0.162 | 0.277 | 0.346 | **0.391** |
| cold (blue > red) shadow fraction | 0.020 | 0.207 | 0.094 | 0.056 | **0.029** |
| ground luma median | 0.430 | 0.415 | 0.417 | 0.431 | **0.431** |
| sunlit regolith median | 0.463 | 0.436 | 0.451 | 0.459 | **0.459** |
| whole-frame lit median | 0.344 | 0.324 | — | — | **0.340** |

The Core now measures as concept 01's Core on every metric that defined the gap, and CP-03's
exposure calibration survived: the ground did not move except toward the concept.

**What actually closed the value inversion — two thirds of it was geometry, not albedo.**
A steep dome takes a 52° key at a graze along nearly all of its area. Petals drooping 36°
were still doing that. Flattening the droop to 20° — one edit, three tip heights — moved
`canopy / ground` from 0.64 to 0.90 on its own, more than every albedo change put together.
Value on a curved surface is mostly a question of what the surface is *pointing at*.

**Five things the renders taught, all of them paid for.**

1. **A petal converging to a point with concave sides is a spike, not a petal.** The first
   render grew a ring of thorns. The fix is geometric and specific: make the tip an *edge*
   rather than a vertex, bow the sides *outward*, and keep the root wider than the run is
   long. `StructureBuilder.addPetal` now takes `bulge` where it took a waist.
2. **A metal in this scene is mostly black.** `goldTrim` carries an authored `metallic: 0.85`,
   which is right for a glinting kerb and wrong for a whole armature of thin members: a
   conductor has no diffuse term, and what surrounds this building is a void with one warm
   lobe in it, so every batten off the mirror direction reflected empty space. The wheel,
   architrave, ribs and masts all came back dark bronze against the concept's pale gold.
   `MaterialLibrary.material` gained a `metallic:` override for this; the Core runs 0.30.
3. **The lower hemisphere is not void — it is the fragment.** Half of every canopy fold
   rendered navy because shaded faces were lit only by the cool fill over a near-black IBL
   floor. Below a structure standing on this island is thousands of square metres of sunlit
   regolith. Warming and raising `voidHorizon`/`voidNadir` to a real ground bounce, and
   cutting `fillIntensity` 520 → 430, took cold shadow from 0.207 to 0.029. It is a **global**
   change and was checked as one: the void card and starfield are unmoved to four decimals
   (they are unlit), and lit objects elsewhere gained a uniform ~0.015 — which put the
   whole-frame lit median at 0.340 against the concept's 0.344, closer than cp06's 0.324.
4. **Retinting cannot warm a surface whose spec reference is cold.** The plinth carried a warm
   tint over `.rimStone`, whose spec is authored around `[0.482, 0.487, 0.505]`; retinting
   divides by that reference, so the result came back muted, not warm — a slate cobble drum
   around the whole base, the largest cold mass left in the silhouette and squarely inside the
   measurement box. Moving it to `.wovenIvory` was worth 0.045 of Core box median by itself.
5. **A cone has no facet pointing at an overhead key.** The crown spire read as a brown plug
   in the middle of the tented top at 1.7 m of run. Shortened under a metre so it sits down
   in the petals, which is where the concept's finial rises from anyway.

Masts also had to be raised above the canopy (their cords crossed the building's face at
7.9 m) and taken from six to five — an odd count never lines two masts up on one axis.

**Cut from scope, deliberately.** The ground inlay rosette. The terrain around the Core is not
flat — the settlement pan eases from `panInner` to `panOuter` — so a flat apron beyond the
plinth would float visibly. It belongs in `TerrainDressing`, which already drapes decals onto
the height field correctly, and is carried to CP-09 with the other ground work.

**Cost.** Three files, all under `Sources/Rendering`: `Meshes/CivilizationCoreMesh.swift` (the
rewrite), `Texturing/MaterialLibrary.swift` (the `metallic:` override and its cache key), and
`LightingRig.swift` (fill and the two hemisphere colours). Simulation and Domain untouched; no
new randomness beyond the existing `core.sunwoven` stream.

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
