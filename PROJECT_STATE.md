# Project State

**The first file to read.** It records where Sunfold Greenfield actually is after each
checkpoint, so a new agent can start work without re-deriving the situation from the
source tree.

Rules for this file:

- It is updated **at the close of every checkpoint**, never mid-flight.
- It records what was **observed**, not what was intended. A claim here without evidence
  behind it is a bug in this file.
- It is short. Detail lives in the documents it points to; this file says where things
  stand and what to do next.

---

## Status at a glance

| | |
|---|---|
| **Last checkpoint** | CP-02 — Kill the magenta · **closed** |
| **Closed** | 2026-07-27 |
| **Build** | 🟢 Green. `** BUILD SUCCEEDED **`, zero Swift errors, zero Swift warnings. |
| **Renders** | 🟢 Clean. No missing materials — 64,490 magenta samples → **0**. |
| **Current frame** | `Docs/QA/AAA/cp02-magenta-fixed.png` |
| **Version** | 0.3.0 · build 42 |
| **Gates** | G0 complete · G1 in progress · G2 in progress — neither passed |
| **Current direction** | Finish the AAA visual push toward concept 01. G2 gameplay is parked. |
| **Uncommitted work** | Large. One commit (`05c68b8`) sits behind ~a full day of source changes. |
| **Next checkpoint** | CP-03 — close the remaining gap to concept 01 (stars, bloom, terrain relief, HUD chrome). |

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

**Still short of concept 01.** Stars are flat white squares rather than soft points. No
visible bloom on the turquoise glazing despite the post-process running. The terrain is
still one flat facet with no relief. The second fragment reads as pasted-on rather than
sitting in the same space. There is no HUD chrome beyond the resource rail — no minimap, no
command grid, no selection portraits.

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
- **Almost nothing is committed.** A single commit sits behind a full day of work. A
  checkpoint commit is advisable before any further large change.
- `Sources/Audio/` and `Sources/Accessibility/` exist but are empty. They belong to G7.

### Parked, not abandoned

G2 gameplay still needs construction (Farm / Matter Extractor / Dwelling with placement,
cost and build progress), Core production with a queue, the objective rail and the
30/60/90-second hint ladder, and a timed first-time pass. `ROADMAP.md` holds the full list.
The current direction is visual, so these wait.

---

## Checkpoint log

Newest first. Each entry records what changed, what was observed, and what it cost.

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
