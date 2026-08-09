# The Gauntlet — master plan

**What this is.** The standing plan for a long-running quality loop that takes Sunfold
Greenfield from "a beautiful frame with three verbs" to "a AAA-feeling iPad RTS at a solid
60 fps that can be submitted to the App Store." It is written for the *director* agent that
schedules waves and for the *builder* and *critic* subagents that execute them. Nobody
should need this conversation's history to run it.

Read in this order: **`AGENTS.md` → `PROJECT_STATE.md` → this file → `01-MANDATE.md` →
`02-PROMPTS.md`**. `03-LAUNCH-GATE.md` is consulted from Wave 5 onward and spot-checked
every wave. `workbench.html` is the live view for the human.

The two methods this synthesises are captured offline in `Docs/Method/gauntlet-loop.md`
(split · build · judge · repeat, with a fresh blind critic per piece) and
`Docs/Method/infinite-build.md` (a standing game-director mandate on a checkpoint cycle).
Read them if you want the reasoning; this file is the version specialised to this game.

---

## The workbench data contract

`workbench.html` is a static single file with no network dependencies. It reads
`workbench-data.json` from the same directory (with an inline fallback copy so it still
renders when a browser blocks `fetch` over `file://`). **Later agents append to the JSON;
they do not edit the HTML.** Schema:

```jsonc
{
  "meta":   { "updated": "ISO-8601", "version": "0.3.0", "build": 42,
              "branch": "…", "wave": 1, "waveTitle": "…" },
  "now":    { "piece": "P1", "title": "…", "why": "…", "owner": "builder|critic|smoothing",
              "model": "composer-2.5", "started": "ISO-8601", "round": 2,
              "lastCriticVerdict": "REVISE|PASS|null", "biggestGap": "…" },
  "next":   [ { "piece": "P4", "title": "…", "why": "…" }, … ],   // exactly the next three
  "bars":   [ { "id": "B1b", "axis": "Visual", "bar": "…", "target": "…",
                "current": "…", "state": "pass|fail|unmeasured",
                "evidence": "relative/path" }, … ],
  "log":    [ { "id": "CP-15", "date": "YYYY-MM-DD", "title": "…",
                "changed": "…", "taught": "…", "next": "…",
                "proof": { "version": "0.3.1", "build": 43, "play": "…",
                           "status": "local|testflight|appstore" },
                "before": "relative/path.png", "after": "relative/path.png" }, … ],
  "simLease": { "holder": "agent-name|null", "since": "ISO-8601", "queue": ["…"] }
}
```

**After every edit to the JSON, run `python3 Docs/Gauntlet/tools/sync-workbench.py`.** The
page fetches the JSON at runtime, which works when the folder is served over HTTP but is
blocked by every browser over `file://`; the script refreshes the inline fallback copy so
the page opens correctly either way. It rewrites only the text between the
`INLINE_DATA_START` / `INLINE_DATA_END` markers and validates the JSON on the way through.

Rules: `log` is newest-first and append-only. `next` holds **exactly three** entries —
adding a fourth means removing one, which forces the director to prioritise rather than
accumulate. Image paths are relative to `Docs/Gauntlet/`. `simLease` is the single source
of truth for who may touch the simulator (see *Serialization*).

---

## 1. Where the game actually stands

Everything below is either **verified** (I read the code, or I measured the committed
capture) or **inferred** (reasoned from code I could not run). I had no simulator access
while writing this — another agent held it — so nothing here is a fresh play observation.
Where the existing docs and the code disagree, I trust the code and say so.

### The player promise

A native iPadOS 26 landscape RTS in Swift 6 + RealityKit, explicitly benchmarked against
Age of Empires IV, set on celestial fragments where **space is the water**. An 8–10 minute
deterministic skirmish from seed `20260726`, two civilizations (Sunwoven / Gravemark), two
win paths. Source: `PROJECT_STATE.md` §"What this project is", `CONTEXT.md`.

### Strongest qualities — verified

- **The lighting and material work is genuinely good, and it is measured.** CP-03 through
  CP-09 closed real gaps against concept 01 with numbers, not vibes: sunlit regolith landed
  on the concept's 0.397 linear exactly; the Core's canopy-to-ground ratio went 0.57 → 1.13
  against a concept 1.15; cold shadow fell 0.207 → 0.029. `PROJECT_STATE.md` CP-03/06/07.
- **The rendering knowledge base in `AGENTS.md` is unusually hard-won and correct.** Facts
  like "bloom begins at `threshold - softKnee`", "a metal in this scene is mostly black",
  "the lower hemisphere of the IBL is the fragment, not the void" are the kind of thing
  that costs days to relearn. They are load-bearing and must not be re-litigated.
- **The architecture split is real, not aspirational.** `Sources/Simulation` and
  `Sources/Domain` import only Foundation / Observation / simd — I checked, and
  `Docs/research/sunfoldcore-extraction.md` confirms it is the precondition for a SwiftPM
  extraction. That is what makes determinism and testability reachable at all.
- **A procedural walk gait already exists and is wired.** See the correction below.
- **Construction shipped further than the docs claim.** `Sources/Simulation/ConstructionSystem.swift`,
  `ConstructionPlacement.swift`, `Sources/HUD/PlacementPanel.swift` are committed, and the
  `cursor/cp-g2a-r2-construction-integrity-a2b9` worktree carries
  `Tests/ConstructionIntegrityTests.swift` with a recorded **10 executed / 10 passed**.

### Four claims in the current docs that reality contradicts

These matter because the plan below would be wrong if they were true.

0. **The simulator UDID in `AGENTS.md` is dead.**
   `A59055F8-1354-4936-97B8-7033DF90B0BB` no longer exists on this machine and cost an
   agent real time. The live device is **`75898CE1-A691-4973-817A-973D4249A38F`** —
   "Sunfold Cycle 1 iPad Air 13", iPad Air 13-inch (M2), `iPad14,11`, iOS 26.5, already
   booted. The durable lesson is bigger than the swap: **simulator devices are not
   permanent.** They get erased, deleted and recreated, and a UDID hardcoded in a document
   goes stale silently — the tool call succeeds against nothing, or worse, falls through to
   whatever else is booted. Verify the device exists before trusting any hardcoded UDID.
   **A second simulator is booted right now: an iPhone 17 Pro, "BillBandit Test",
   `CD369CF5-53C5-4EB2-9FC4-164D2716AAAC`, belonging to an unrelated project.** Never
   install, launch, screenshot, gesture on, shut down or erase it. Because two devices are
   booted, **pass the iPad UDID explicitly on every call** rather than relying on a tool's
   "the booted device" default — otherwise you will silently measure an iPhone, on an
   iPad-only game. Any measurement taken on a non-iPad device is discarded, not reported.
   *(`AGENTS.md` still carries the dead UDID. Correcting that line belongs to the agent that
   owns the simulator this session; this file records the correct values in the meantime,
   and `02-PROMPTS.md` carries them into every subagent prompt.)*

1. **"Animation. Units slide; needs per-unit activity state the sim does not expose."**
   (`AGENTS.md`, `PROJECT_STATE.md`.) **Stale on both halves.**
   `Sources/Simulation/Locomotion.swift` is 456 lines of gait: phase offset per unit,
   stride scale, leg/arm counter-swing, torso lean, bob, and a Reduced Motion path
   (`reducedMotionScale = 0.40`). `EntityPresenter.applyPose` drives a six-limb rig from it
   every frame. It has been in the tree since the **initial commit** `05c68b8`. And the sim
   *does* expose activity: `UnitActivity` in `WorldEntities.swift` carries
   `idle / moving / gathering / boarding / aboard / constructing / attacking`, at HEAD.
   **The real gap is narrower and much better bounded:** `EntityPresenter` reads
   `unit.activity` for exactly one case — `.boarding`, at line 96 — and nothing else.
   The gait is driven purely by observed position delta, so a citizen standing at a deposit
   *gathering*, or standing at a foundation *building*, plays no animation at all: it
   freezes. The task is not "build animation." It is "route the activity the simulation
   already publishes into poses the rig can already play." `CONTEXT.md` states this exact
   destination, so the design decision is closed; only the wiring is missing.
2. **"The unit tests have never been executed / `xcodebuild test` is hook-blocked."**
   `/Users/prateekranka/.codex/bin/xctest-focused.sh` exists and is executable, and
   `Docs/QA/G2/cp-g2a/r2-proof/build-proof.md` records it running `ConstructionIntegrityTests`
   at **10/10**. Tests are runnable today. `Tests/DeterminismTests.swift` (18 KB) still has
   no recorded execution, which is a different and smaller problem.
3. **"There is no performance bar."** `Docs/research/ipad-realitykit-60fps-budget.md`
   (untracked, by a concurrent agent) is a rigorous engineering budget sourced from Apple's
   RealityKit performance docs, with a bucket split, a density ladder, a first-risk ranking
   and a measurement protocol. It is not yet a *gate* — nothing has been measured against it
   — but the analysis is done and this plan adopts it wholesale rather than reinventing it.
   Likewise `Docs/research/aoe4-play-feel-reference.md` is a finished play-feel bar.
   **`Docs/QA/Feel/` does not exist yet**, despite being referenced.

### The weakest area, and it is not the one the docs are watching

**The frame lost its void, and the checkpoint that did it was logged as a success.**

Concept 01 is an ivory-and-gold island suspended in deep space: black void, a purple nebula
wash, a warm gas giant, drifting debris. That contrast *is* the art direction — the visual
bible says in bold "Never fill the frame with contiguous terrain," and specifies 40–55% land
against 45–60% void. CP-11 (`Docs/QA/AAA/cp11-pier.png`) hit it.

Then CP-12 → CP-13 → CP-14 replaced the fragment archipelago with an Age-of-Empires-style
continent at **75–80% land coverage**. The gameplay reasoning is sound and I am not
proposing to undo it. But the *rendered opening frame* was never re-judged against concept
01 after the change: CP-14's "Observed" table in `PROJECT_STATE.md` scores minimap
silhouette, void-floor cracking, causeway placement and land-coverage percentage. There is
no concept-comparison row — unlike CP-06, CP-07 and CP-08, which all carry one.

Measured with `Docs/Gauntlet/tools/framestat.py` (HUD masked out, so this is the rendered
world only):

| frame | void frac | soft-void | black point (luma p05) | dyn range | sat mean | dominant hue share |
|---|---|---|---|---|---|---|
| **concept 01 — the bar** | **0.530** | 0.137 | **0.001** | 0.515 | 0.484 | 0.789 |
| cp07-core-pavilion | 0.486 | 0.110 | 0.000 | 0.504 | 0.586 | 0.774 |
| cp08-void | 0.415 | 0.300 | 0.002 | 0.498 | 0.448 | 0.773 |
| cp11-pier | 0.415 | 0.311 | 0.002 | 0.496 | 0.451 | 0.777 |
| cp12-map1-continental | 0.207 | 0.214 | 0.002 | 0.525 | 0.440 | 0.737 |
| cp13-map1-coastland | 0.040 | 0.219 | 0.054 | 0.480 | 0.451 | 0.721 |
| cp14-map1-riverlands | 0.112 | 0.175 | 0.007 | 0.537 | 0.417 | 0.735 |
| **sparse-map1-riverlands (current baseline)** | **0.025** | 0.083 | **0.102** | 0.451 | 0.367 | **0.835** |
| 15-farm-complete-fullres (current CP-G2a) | 0.046 | 0.093 | 0.053 | 0.498 | 0.373 | 0.829 |

Read the two bold columns. Void went **0.530 → 0.025**, a 21× collapse. The black point
went **0.001 → 0.102**: the current frame contains no true blacks anywhere, which is why it
reads as a flat beige photograph rather than an object lit in space. Saturation fell and
the dominant-hue share *rose* to 0.835 — the frame got more monochrome, not less. Every one
of those numbers moved away from the bar across CP-12…CP-14, and no checkpoint recorded it.

This is the exact failure the Gauntlet method exists to prevent: **when the measurement
changed from "does it look like concept 01" to "is land coverage 75–80%", the work passed
the new measurement while failing the real one.** The structural fix is in §5.

I want to be careful about what this does and does not mean. It does **not** mean CP-14 was
wrong — an RTS needs walkable ground, and a 40%-land map is a bad AoE map. It means the
*camera, the water width and the opening composition* were never re-tuned after the land
went up, and the two goals were treated as if only one of them could be satisfied. Concept
01 itself is a mid-zoom settlement shot of a *single fragment*; nothing prevents a 78%-land
world from framing like that at play zoom, with void channels wide enough to read as space
and the rim, nebula and celestial body back in shot.

### The other weak areas — verified

- **No haptics at all.** `rg` across `Sources/` for `UIImpactFeedbackGenerator`,
  `UISelectionFeedbackGenerator`, `CoreHaptics` returns nothing. On an iPad RTS every
  commit — place, cancel, select, order — should have a tactile answer.
- **Audio is three system beeps.** `Sources/Audio/FeedbackAudio.swift` is 23 lines calling
  `AudioServicesPlaySystemSound(1104 / 1111 / 1053)`. No ambience, no music, no unit
  acknowledgment, no combat audio. `Resources/Audio/` contains only `.gitkeep`.
- **A stale alert has been on screen for five checkpoints.** "Light transport docked at
  home rim" appears in `cp08-void.png`, `cp11-pier.png`, `cp14-map1-riverlands.png`,
  `sparse-map1-riverlands.png` and `15-farm-complete-fullres.png`. An alert that never
  clears trains the player to ignore the alert strip.
- **The transport is beached.** In `sparse-map1-riverlands.png` the light transport and its
  gold pier sit on dry sand — the sparse retune shortened inland water without moving the
  dock. A boat in a desert is the kind of thing a first-time player notices in one second.
- **Farms are programmer art.** `15-farm-complete-fullres.png` renders a completed Farm as a
  flat brown rectangle with three vertical bars. Concept 01's farms are tilled plots with
  gold crop rows. This is the clearest single "not shipping quality" object in frame.
- **Units are unreadable at default zoom.** At zoom 64 the four citizens beside the Core are
  roughly 10 px tall with no visible selection ring and no life bar. Concept 01 shows teal
  selection ellipses and green life bars on every unit. The bible's own scale rule — citizen
  ≈ 1/4–1/3 building height — is not met on screen.
- **`Sources/Accessibility/` is empty** (0 files). `Sources/AI/` does not exist at all.
- **App icon is empty.** `Resources/Assets.xcassets/AppIcon.appiconset/` contains only a
  `Contents.json` declaring one 1024×1024 universal slot **with no filename and no PNG**.
  The app currently cannot be uploaded to App Store Connect.
- **Version drift.** `Sources/App/Info.plist` and `project.yml` both say
  `CFBundleShortVersionString 0.1.0` / `CFBundleVersion 1`; `VERSION.md` and
  `PROJECT_STATE.md` say **0.3.0 build 42**. The shipping artifact disagrees with the docs.
- **`UIRequiresFullScreen` is deprecated on iOS 26** and emits a build warning on every
  build (`build-agents/cp08-09.log:308`): *"has been deprecated starting in iOS 26.0 and
  will be ignored in a future release."* Landscape-only-full-screen is a product decision;
  the mechanism enforcing it is on its way out.
- **No privacy manifest.** No `PrivacyInfo.xcprivacy` anywhere in the tree.

### Technical risks — inferred, flagged as such

- **Input latency and the lasso/tap conflict.** `CameraGestureLayer.swift:71` sets
  `lasso.minimumPressDuration = 0.22` and line 82 makes the world tap
  `require(toFail: lasso)`. A quick tap resolves at touch-up, so I do **not** claim a
  blanket 220 ms penalty. What I do expect is that a tap held past ~220 ms — routine on a
  touchscreen — becomes a lasso instead of a selection, so selection will feel like it
  "sometimes doesn't take." Unverified without a device; Piece **P0.4** exists to measure it.
- **Per-unit presentation cost is the first CPU cliff.** `EntityPresenter.applyPose` calls
  `entity.findEntity(named:)` **seven times per unit per frame** — a string-keyed hierarchy
  walk — plus `syncCargo` and a terrain height sample. At the 80-unit battle density that is
  ~34,000 named lookups per second before any rendering. Apple's own guidance
  (`Docs/research/ipad-realitykit-60fps-budget.md` §2) is to cache child references at spawn.
  This is the cheapest large perf win available and it is invisible to the player.
- **4× MSAA is on** (`SunfoldPostProcess.swift:136/168`), and the file's own comment calls it
  "the single largest cost the pass adds," full-res at 2732×2048.
- **60 fps has only ever been observed with four gatherers, in Debug, on a simulator.** That
  is the entire performance evidence base. There is no Release build, no device trace, no
  percentile, and no measurement at 20/40/80 units.
- **`scripts/agent-build.sh` has no stale-lock handling** — a build killed mid-lock leaves
  every later build silently skipping `xcodegen`. Already bitten once
  (`PROJECT_STATE.md` §"Known open defects"). A concurrent agent owns `scripts/`.
- **Deployment target is iOS 26.0.** Correct for this project's stated constraint, but it
  means the addressable market is iPadOS 26+ devices only. That is a business decision the
  human should confirm before launch, not an engineering one.

---

## 2. The bars

One inspectable bar per axis. Each states what a fresh critic does to get the evidence.
**A bar is not a target the builder may edit** — see §5.

Where a bar needs an artifact that does not exist, the artifact is a numbered piece in §3.

---

### Bar-change log

Rule §5.1 says a bar may only be changed by the human, as its own recorded entry, with the
old and new bars side by side and the reason. This is that log. It is append-only.

#### BC-01 · 2026-07-31 · The feel bar moves from Age of Empires IV to Age of Empires II: The Rise of Rome

**Authorised by:** the human, directly, in the session brief that opened this run. Mandate
pause boundary #1 and plan rule §5.1 both reserve this change to the human; the human has
made it, so it is authorised. Recorded here so no builder can silently reinterpret it later.

| | **Old bar (superseded)** | **New bar (in force)** |
|---|---|---|
| Named reference | Age of Empires IV | **Age of Empires II: The Rise of Rome**, in space |
| Reference document | `Docs/research/aoe4-play-feel-reference.md` | Same document, retained for the four *axes* only |
| What is judged | Weight, feedback, pacing, readability against AoE IV moments | The same four axes **plus** the dense-economy RTS grammar below |
| Roster shape | Not specified; "depth over breadth" | **Breadth is now required.** A broad roster of cheap readable units with an explicit counter structure, and a broad roster of buildings that each unlock something concrete |
| Progression | Two ages, Foundation → Voyager | Age/tier progression that **visibly changes what you can build** — still small, still not a tech tree |
| Economy | Villager-driven gathering | Villager-driven, **distinct resource types with drop-off buildings** |
| Readability | AoE IV's readability | **Fast, legible, high contrast** — you can tell at a glance what every unit is and what it is doing |
| Match shape | 8–10 minute skirmish | Unchanged: 8–10 minutes, **short build times, tight loop, a match that resolves** |

**The reason, in the human's words:** *"AoE 2 Rise of Rome, but in space."*

**What this is a statement about.** Game design, not art style. It is **not** a demand to
become a 2D sprite game. The 3D RealityKit renderer, the ~55–60° camera, concept 01 as the
visual bar and every verified rendering fact are unchanged. What the human is pointing at is
the classic dense-economy RTS grammar that AoE 1/2 have and AoE IV softened.

**What this does NOT change** — all still locked, all still preserved:
the two civilizations and their palettes and temperaments; the 3D RealityKit renderer; the
~55–60° camera; "space is the water"; the deterministic seed `20260726`; landscape-only
iPad; the 8–10 minute skirmish; two win paths; concept 01 as the visual bar (B1 is
untouched); and every item on `ROADMAP.md` §"Explicitly out of scope" — no multiplayer, no
campaign framework, no tech-tree sprawl, no diplomacy, no monetisation, no analytics, no
accounts.

**Consequences already applied in this document:** B3's header and B3c below; the §"Depth
over breadth" line in the mandate is partially overridden (depth per verb still gates
shipping a verb, but breadth of roster is now a requirement, not a distraction); and the
roster this bar demands is specified in `Docs/Design/`, which is a hard dependency of every
gameplay checkpoint from here on.

#### BC-02 · 2026-07-31 · B2 (performance) is demoted from a blocking bar to a guardrail

**Authorised by:** the human, same session brief. Recorded separately from BC-01 because it
is a separate decision with a separate reason.

| | **Old bar (superseded)** | **New bar (in force)** |
|---|---|---|
| Status | B2 blocks a checkpoint from closing | **B2 never blocks a gameplay checkpoint** |
| Routine work | Wave 3 is a dedicated performance wave; density ladder, MSAA/shadow/post A/B matrix, Instruments campaign, thermal sustain | **A cheap regression smoke at the close of a checkpoint. Minutes, not a checkpoint.** Run the existing `-sunfoldPerf` harness once, record p95/p99, move on |
| Failure response | Fix before closing | If p99 regressed > ~15% against the previous checkpoint, **log it as a known issue and keep going.** Stop only if the game became *visibly* unplayable |
| Device work | B2a on a physical device | **Deferred to end of project.** No device perf work, no Instruments campaign, no thermal sustain, no quality A/B matrix until roster, production, combat and victory all exist and a match can be won and lost |
| Deferred pieces | — | **P0.3, P5, B2a, B2c are deferred. Do not start them.** |
| Exception | — | **P4 only** (cache the per-unit `findEntity` lookups). Cheap, invisible, zero visual risk, buys headroom for the larger unit counts a bigger roster implies. Timeboxed to one checkpoint |

**The reason, in the human's words:** *"i want it to focus on the gameplay and building the
game up in terms of more units and buildings."* The previous run of this loop got stuck on
60 fps work and shipped no gameplay. That is the failure this change exists to prevent.

**The circuit breaker.** If the director ever finds itself on a **third consecutive
checkpoint whose subject is frame time**, it stops, says so plainly in its report, and goes
back to gameplay.

---

### B1 — Visual fidelity · bar: **concept 01, judged blind and measured numerically**

> *The rendered frame must be indistinguishable in kind from `Docs/Concepts/01-sunwoven-foundation-opening.png` — same composition language, same value structure, same colour families — to a critic who is not told which frame is ours.*

**B1a — Blind A/B.** Run
`python3 Docs/Gauntlet/tools/framestat.py pair <ours.png> Docs/Concepts/01-….png <outdir>`.
It centre-crops both to one aspect ratio, resamples both to one pixel size, writes them as
`frame-1.png` / `frame-2.png` in randomised order, and seals the mapping in `answer.txt`.
This normalisation is not cosmetic: our captures are 2732×2048 (4:3) and the concepts are
1536×1024 (3:2), so **the existing pair in `Docs/QA/AAA/blind/` could be solved by aspect
ratio alone** — both are 1536×1024, meaning ours was already resampled to the concept's
shape, but nothing in the tooling guaranteed it. The critic is handed only the two PNGs and
the bible, picks the better frame, and names the largest gap.
**Pass:** the critic either picks ours, or picks the reference and the named gap is
cosmetic rather than structural. **Fail:** the critic identifies ours by a *category* defect
— no void, flat lighting, placeholder geometry.

**B1b — Composition statistics.** `framestat.py measure <ours.png>`, HUD masked.
**Pass:** `void_frac ≥ 0.35`, `luma_p05 ≤ 0.010`, `dynamic_range ≥ 0.48`,
`sat_mean ≥ 0.42`, `dominant_hue_share ≤ 0.80`. Those thresholds are CP-11's measured
values, not aspirations — the project has already rendered every one of them. Current
baseline fails four of five. **This bar is un-gameable because it is arithmetic on a PNG a
critic produces itself.**

**B1c — Concept 02/03/04 parity** (from Wave 5). Same procedure against
`02-transport-landing-expansion.png` (expansion beat), `03-voyager-dominion-battle.png`
(battle density and combat readability) and `04-sunwoven-dominion-victory.png` (win beat).
These need a build that can *reach* those states, so they are gated behind G3–G5.

### B2 — Performance · bar: **Apple's RealityKit frame budget on device, at four densities**

> *On a physical iPad Air 13-inch (M2) in Release, the app holds p50 ≤ 12 ms and p99 ≤ 16.67 ms on main and render threads at 8, 20, 40 and 80 units — the budget Apple publishes and `Docs/research/ipad-realitykit-60fps-budget.md` already derived for this app.*

**The device, settled.** The target is an **iPad Air 13-inch (M2)**, `iPad14,11`, 2732×2048,
with a **standard 60 Hz display — not ProMotion**. 60 fps is therefore the hardware cap and
the frame budget is exactly **16.67 ms**. There is no 120 Hz ambiguity to resolve on the Air.
Record for later and do not chase: the iPad Pro 13-inch is 120 Hz ProMotion, an 8.33 ms
budget, and out of scope.

**Report the miss rate, not the mean.** The headline number for every perf run is **p95 and
p99 against 16.67 ms, plus how often the frame exceeds it**. A comfortable mean hides
exactly the stutter a player feels, and "feels like 60 fps" is decided by the tail.

**Measure the refresh rate, never assume it.** Every run records the observed
`UIScreen.maximumFramesPerSecond`. The simulator can misreport it, and a misreport is itself
a durable fact worth writing down. Anything other than 60 gets stated plainly.

**B2a — Device, Release, Instruments (the product bar).** RealityKit Trace, warm textures,
landscape, HUD on, the density matrix from the research doc §"Pass D".
**Pass:** at every rung, p50 frame ≤ 12.0 ms, p99 ≤ 16.67 ms, zero *sustained* red deadline
frames. **Requires the human to provide a device**; see §"Pause boundaries" in the mandate.

**B2a-floor — the M2 Air is not the floor, and a pass on it is not a launch claim.**
`IPHONEOS_DEPLOYMENT_TARGET: "26.0"` plus `TARGETED_DEVICE_FAMILY: "2"` means every
iPadOS 26 iPad can install this app. The weakest of those is an **A12 Bionic with 3 GB of
RAM** — iPad Air 3rd gen (2019), iPad 8th gen (2020), iPad mini 5th gen (2019) — several
generations and a large multiple of GPU throughput below an M2 with 8 GB. Given that the app
runs 4× MSAA and a full-resolution post composite, the A12 tier is a genuine risk to the
"solid 60 fps" promise and not a rounding error. **No report may say "60 fps proven" without
naming the device class.** Validating the true floor, or deliberately narrowing what the app
admits, is launch-gate item §14 in `03-LAUNCH-GATE.md` — not routine checkpoint work.

**B2b — Simulator regression bar (available today, and the one the loop runs on).**
A concurrent agent has just landed the harness this bar needs — **adopt it, do not rebuild
it**: `Sources/Diagnostics/{FramePerfSampler,PerfHarness,PerfLaunchFlags,PerfOverlay,
SceneScaleSnapshot}.swift`, driven by `scripts/perf-capture.sh` +
`scripts/perf-scenarios.json` and aggregated by `scripts/perf-aggregate.py`. Flags:
`-sunfoldPerf` (enable), `-sunfoldPerfOverlay`, `-sunfoldPerfScenario <tag>`,
`-sunfoldPerfDuration <seconds>`. It emits mean / p95 / p99 / worst / fps / dropped / long
frames plus sim and presenter split, as JSON in the app's Documents directory, and it costs
nothing when the flag is absent. The scenario file already defaults to Release, a 14-second
warm-up and 3 repeats — all three of which are the right calls.

Simulator timings are **not** device proof and may never be quoted as the product bar. They
are a *relative* gate: **no checkpoint may raise simulator p99 by more than 5% against the
previous checkpoint's run of the identical scenario.** That catches regressions between
device sessions. The one thing the harness cannot do yet is vary unit count — that is P0.3.

**B2c — Thermal and sustain.** Ten minutes of continuous device play; `ProcessInfo.thermalState`
must not reach `.serious`, and the final minute's mean frame rate must be ≥ 58 fps.

**B2d — The interlock that makes B2 un-gameable.** The obvious cheat is to buy frame time by
degrading the picture — MSAA off, bloom off, shadows off, dressing thinned. So:
**every perf result must record the exact quality settings it was measured at
(`antialiasing`, `downsample`, `aberration`, shadow tuning, dressing density), and a perf
checkpoint does not close until B1a/B1b are re-run at those same settings and still pass.**
Symmetrically, a visual checkpoint does not close until B2b is re-run. Neither bar may be
paid for with the other.

Evidence lands in `Docs/QA/Perf/`. A concurrent agent owns that path right now — until it
releases, Gauntlet perf evidence goes to `Docs/Gauntlet/evidence/perf/` and is moved later.

### B3 — Game feel & responsiveness · bar: **AoE II Rise of Rome's grammar, on four axes, plus two countable tests**

> *(Bar changed 2026-07-31 — see BC-01 above. The named reference was Age of Empires IV.)*
>
> *Weight, feedback, pacing and readability at the level of **Age of Empires II: The Rise of Rome**, expressed in space: a broad roster of cheap readable units with an explicit counter structure, buildings that each unlock something concrete, tier progression that visibly changes what you can build, short build times and a match that resolves. The four axes and the moment-by-moment method in `Docs/research/aoe4-play-feel-reference.md` are still the measurement instrument; the game being measured against has changed. And a player must be able to tell what a unit is doing without looking at the HUD.*

**B3-roster — the content bar the new feel bar implies.** The roster, costs, counters,
tiers, victory conditions and combat model are specified in `Docs/Design/` and are a hard
dependency of every gameplay checkpoint. A builder may not invent a unit, a building, a
cost or a counter relationship that is not in that specification; if the specification is
wrong, the fix is a specification change with a critic, not an improvisation in Swift.
**Check:** every new `UnitKind` / `BuildingKind` case traces to a row in the spec.

**B3a — Response latency, counted in frames.** Needs an instrumented probe (**P0.4**): under
`-sunfoldLatencyProbe`, a 40 px white square is painted in the top-left corner for exactly
one frame on `touchesBegan` (hooked above game logic), and a second square in the top-right
on the first frame the game state actually changes. A 60 fps screen recording then yields
the frame delta by pixel inspection with `ffmpeg`.
**Pass:** acknowledgment ≤ **2 frames (33 ms)** and committed state ≤ **6 frames (100 ms)**
for all six verbs: tap-select unit, tap-ground move order, lasso commit, command-tile press,
placement commit, cancel. **Un-gameable: it is frame counting on a video, and the probe sits
above the code being judged.**

**B3b — Activity legibility, blind.** Hand a critic a 10-second silent clip, HUD cropped
out, of a base with citizens walking, gathering, constructing and idling. For each of ≥ 20
unit-observations the critic names the activity. **Pass: ≥ 90% correct.** Today this fails
by construction — presentation reads `unit.activity` only for `.boarding`, so gather, build
and idle are the same frozen pose. This is the single largest AAA-feel gap and it is now a
wiring job, not a research job.

**B3c — Side-by-side against a named commercial moment.** For each shipped verb, the critic
watches Sunfold footage beside the corresponding commercial moment and scores weight /
feedback / pacing / readability. **Pass: ours loses on at most one of the four axes.**

*Post-BC-01:* the named reference is now Age of Empires II: The Rise of Rome — the Dark→Feudal
opening, a Barracks/Archery Range/Stable production beat, and a counter-triangle engagement.
The AoE IV moments in the research doc remain valid comparanda for *responsiveness* only.
**Real commercial footage of either game is a pause boundary** (mandate #7): the director does
not have it, and must not substitute a weaker measurement and call B3c passed. Until footage
exists, B3c is **UNPROVEN**, and B3a / B3b / B3d — which are all self-contained measurements
on our own artifact — carry the feel axis.

**B3d — The answer rate.** Every player-initiated verb produces a *distinct* audible cue
within 100 ms, and every committing or destructive verb produces a haptic.
**Check:** spectrogram of the recorded session's audio track (distinct cues are visibly
distinct events), plus `rg` for a feedback generator in `Sources/`. Current state: three
system beeps, zero haptics — **fail**.

### B4 — UI/HUD craft · bar: **concept 01's chrome, plus measurable legibility**

**B4a — Chrome blind A/B.** `framestat.py pair --region` on matched crops of the four HUD
regions. Same blind procedure as B1a.
**B4b — Legibility.** Every HUD text run ≥ **4.5:1** contrast against its own local
background, sampled from the capture; no glyph below 11 pt at 2×; the HUD must remain
readable with iPadOS Increase Contrast on. **Pass: zero violations.**
**B4c — No dead or lying chrome.** Zero enabled controls that do nothing; zero alerts that
persist after their condition clears; zero permanently disabled tiles by G5.
**Check:** a critic taps every visible control once and records the response. Current known
failures: the five-checkpoint stale transport alert; control-group slots that are chrome
only.

### B5 — RTS depth & readability · bar: **the glance test and a completable match**

**B5a — The glance test.** From one still frame at default zoom, a critic who has never seen
the game answers five questions: whose base is this, what is each visible unit doing, what
is being produced, where is the threat, what is the current objective.
**Pass: 5/5.** Against `sparse-map1-riverlands.png` today I can answer one (whose base).
**B5b — A match that ends.** Three unassisted playthroughs, no debug shortcuts, each
reaching a win or loss in **8–10 minutes** (roadmap G6). Currently unreachable: there is no
victory or defeat condition in the simulation.
**B5c — Every verb reachable.** No permanently disabled command tile by G5.

### B6 — Correctness · bar: **determinism proven, not assumed**

`Tests/DeterminismTests.swift` green under `swift test` after the `SunfoldCore` SwiftPM
extraction (**P14**), plus a replay check: the same seed and the same input script produce
byte-identical simulation state at tick 12000. Every gate from G3 assumes this and none of
it has ever run. **Pass:** green suite, recorded, on every checkpoint.

### Bars that need an artifact first

| Needed | Piece | Blocks |
|---|---|---|
| Frame-time telemetry with percentiles | P0.2 *(landing now — adopt)* | B2b, B2c |
| Deterministic density harness (`-sunfoldDensity N`) | P0.3 | B2a, B2b at 20/40/80 |
| Latency probe (`-sunfoldLatencyProbe`) | P0.4 | B3a |
| Normalised reference pack (concepts × current build) | P0.5 | B1a, B4a |
| A physical iPad Air 13-class device | *human* | B2a, B2c |
| AoE IV footage of the named moments | *human or licensed capture* | B3c |

---

## 3. The decomposition

Smallest units that can be improved and judged separately. **Par** = parallel-safe (no
simulator, no shared file). **Sim** = needs the simulator lease, therefore serialized.

### P0 — Instrumentation (makes the bars executable)

| # | Piece | Bar | How the critic inspects | Acceptance | Sched |
|---|---|---|---|---|---|
| P0.1 | `framestat.py` measure + blind pair | B1a/B1b | Runs the tool on a committed PNG and reproduces the table | Tool exists, reproduces the §1 numbers, pair output is size-identical | **Par** — *done, in `Docs/Gauntlet/tools/`* |
| P0.2 | Frame-time harness, `-sunfoldPerf` | B2b | Reads the JSON report; re-runs the scenario and gets p99 within 10% | Emits mean/p95/p99/worst/dropped; zero cost when the flag is absent | **Sim** — *landing now, owned by the concurrent perf agent; adopt it* |
| P0.3 | `-sunfoldDensity N` deterministic spawn harness | B2a/B2b | Launches at N=80, counts units on screen | N units spawn from the tagged RNG stream; determinism suite still green | **Sim** |
| P0.4 | `-sunfoldLatencyProbe` two-corner flash | B3a | Records 60 fps video, counts frames between corners | Probe fires above game logic; ≤ 1 frame of self-cost | **Sim** |
| P0.5 | Normalised reference pack for all five concepts | B1a/B4a | Opens the pairs; cannot tell which is ours by size | 5 world pairs + 4 HUD-region pairs, all size-identical | **Sim** (needs a fresh capture) |

### P1 — Composition: put the game back in space

| | |
|---|---|
| **Bar** | B1a + B1b |
| **Inspect** | `framestat.py measure` on a fresh default-zoom opening capture; then a blind pair against concept 01 |
| **Accept** | `void_frac ≥ 0.35`, `luma_p05 ≤ 0.010`, `dominant_hue_share ≤ 0.80`, **and** land coverage still 75–80% of `WorldMap.bounds` per `Tools/mappreview`, **and** the blind critic does not name "no void" as the gap |
| **Not** | Reverting CP-14. The continent stays. |
| **Sched** | **Sim** |

The levers, in the order I would try them: default camera zoom and the opening frustum
(`SkirmishTuning`, currently 64); void-channel width in `LandShape` / `VoidBody` so water
reads as space at play zoom rather than as a thin crack; the celestial body and nebula back
inside the ±35 frustum limit `AGENTS.md` records; rim visibility at the map edge. This is
explicitly a *goal, not an implementation* — the builder chooses the route.

### P2 — Activity poses

| | |
|---|---|
| **Bar** | B3b |
| **Inspect** | 10 s silent HUD-cropped clip; name each unit's activity |
| **Accept** | ≥ 90% correct over ≥ 20 observations; gather, construct, idle and move are each distinguishable; determinism suite green; Reduced Motion still simplifies rather than freezes |
| **Sched** | **Sim** |

Route `UnitActivity` — already published by the simulation — into `LocomotionMath.pose`.
The rig, the Reduced Motion path and the sign conventions all exist. Do not add simulation
state; `.gathering`, `.constructing`, `.idle` and `.attacking` are already there.

### P3 — Selection, order and commit feedback

| | |
|---|---|
| **Bar** | B3a + B3d + B4c |
| **Inspect** | Latency probe video; audio spectrogram; tap every control |
| **Accept** | All six verbs ≤ 2 frames to acknowledge; selection rings and life bars visible at default zoom (concept 01 shows both on every unit); each verb has a distinct cue; committing verbs have a haptic; the lasso/tap conflict resolved |
| **Sched** | **Sim** |

### P4 — Per-unit presentation cost

| | |
|---|---|
| **Bar** | B2b at N=80, with B1b re-run unchanged |
| **Inspect** | Perf JSON at `-sunfoldDensity 80` before and after; `rg findEntity Sources/Rendering/EntityPresenter.swift` |
| **Accept** | Zero per-frame `findEntity` in the unit sync path; p99 at N=80 improves and no visual statistic moves |
| **Sched** | **Par** to write, **Sim** to prove |

Cache the six limb entities and the torso at spawn beside `torsoRestHeight`.

### P5 — GPU budget: MSAA / shadows / post A/B

| | |
|---|---|
| **Bar** | B2a/B2b **and** B1a/B1b at the shipped setting (the B2d interlock) |
| **Inspect** | Perf JSON per setting; blind visual pair at the winning setting |
| **Accept** | A documented setting that holds the frame budget at N=80 *and* passes the visual bar; a written table of what each lever costs and buys |
| **Sched** | **Sim** |

### P6 — HUD craft

Stale-alert lifecycle; contrast pass; minimap legibility (it currently renders as a grey
amoeba where concept 01's is a warm landmass with readable ownership); dead chrome.
**Bar** B4a/B4b/B4c. **Sched: Par** to write, **Sim** to prove.

### P7 — Building art: the Farm and its siblings

**Bar** B1a on a `--region core` crop containing a completed Farm. **Accept:** the blind
critic does not name the Farm as the frame's weakest object. **Sched: Sim.**

### P8 — Unit scale and readability at play zoom

**Bar** B1a + B5a. **Accept:** citizen silhouette ≈ 1/4–1/3 of Core height on screen at
default zoom (bible §"Unit Scale"), faction colour readable, selection ring and life bar
legible. **Sched: Sim.**

### P9 — Audio bed

Ambience, a distinct cue per verb, a mix that does not fatigue over 10 minutes.
**Bar** B3d. Real assets replace `AudioServicesPlaySystemSound`. **Sched: Par** to write,
**Sim** to prove. *Any paid asset or service is a pause boundary.*

### P10 — Close CP-G2a construction

The eight open defects in `Docs/QA/G2/cp-g2a/read-only-kimi-review.md`, several already
addressed on `cursor/cp-g2a-r2-construction-integrity-a2b9`. **Bar** B3c against AoE IV's
place/build moment. **Sched: Sim.**

### P11–P13 — G2b production queue · G2c objective rail + hints · G2d control groups

Scoped in `Docs/QA/AAA/gameplay-build-ladder.md`. **Bars** B3c, B4c, B5a. **Sched: Sim**,
serialized after P10.

### P14 — Determinism runnable (CP-G0.5)

Extract `Domain` + `Simulation` into a `SunfoldCore` SwiftPM package so `swift test` runs
`DeterminismTests` directly. `Docs/research/sunfoldcore-extraction.md` has the analysis and
the precondition is already satisfied. **Bar** B6. **Sched: Par** — it never touches the
simulator, which makes it the ideal filler while another piece holds the lease.

### P15 — App Store gate

Everything in `03-LAUNCH-GATE.md`. Split so the mechanical parts run early and in parallel:
**P15a** icon set, version reconciliation, `UIRequiresFullScreen` migration, privacy
manifest, launch screen — **Par**. **P15b** Release build with debug paths off, accessibility,
metadata, TestFlight — **Sim** + human.

### Serialization

**The simulator is the bottleneck and it is a single resource.** One agent installs,
launches, rotates and screenshots at a time. The lease lives in `workbench-data.json →
simLease`: an agent may touch the simulator only while it is the named `holder`, and must
clear the field when done. The director grants and revokes.

Everything else parallelises. At any moment the director should have one **Sim** piece in
flight plus one or two **Par** pieces (P14, P15a, P4's edit, P6's edit, P9's authoring), so
the lease is never the thing the whole loop waits on.

---

## 4. The wave plan

Each wave is a small set of pieces, then **one smoothing pass** by a fresh agent that
inspects the whole result and makes it feel like one thing rather than a pile of separately
improved parts. Ordered by player-visible impact, not by symmetry.

### Wave 1 — "Make it judgeable, and put the game back in space"

**P0.1** (done) · **P0.2** (adopt from the perf agent) · **P1** · **P4** · **P14** · **P15a**

The wave that stops the bleeding. P1 is the largest visible defect in the product. P0.2
makes every later perf claim checkable and is already arriving. P4 is a free 80-unit CPU
win with zero visual risk. P14 and P15a are pure-parallel and cost the lease nothing.
**Smoothing:** one pass over the opening frame — does the restored void, the existing
lighting and the CP-14 landmass read as one authored place?

### Wave 2 — "Make it feel alive"

**P0.4** · **P2** · **P3** · **P6**

Activity poses plus real selection/commit feedback plus honest chrome. This is where the
game stops looking like a diorama. P0.4 first, so P3 has a bar to hit.
**Smoothing:** one pass over the whole feedback language — do cue, haptic, ring, pose and
alert agree with each other, or are there five vocabularies?

### Wave 3 — "Make it hold 60"

**P0.3** · **P5** · re-run of B1/B2/B3 at the shipped settings

The first wave that produces a defensible frame-rate claim. Ends with a written
quality-vs-frame-time table and a chosen shipping configuration.
**Smoothing:** re-judge the frame at the shipped settings; a perf win that cost the look is
not a win.

### Wave 4 — "Make it a game"

**P10** · **P11** · **P12** · **P13**

Close G2. Construction, production, objectives, control groups. This is the wave that turns
select/move/gather/build into a loop with intent.
**Smoothing:** one pass over the first 90 seconds of play — does a new player understand
what to do without being told?

### Wave 5 — "Make it art"

**P7** · **P8** · **P0.5** · B1c against concepts 02/03

Building art, unit readability, the full reference pack, and parity on the expansion and
battle beats. Needs G3 to be reachable for concept 02.
**Smoothing:** one pass over the whole asset set — one hand, one world.

### Wave 6 — "Make it shippable"

**P9** · **P15b** · accessibility · TestFlight · `03-LAUNCH-GATE.md` in full

**Smoothing:** a full 10-minute play on device, start to finish, judged as a product.

Waves are not a schedule. A wave ends when its pieces pass their bars, and a piece that
fails three critic rounds gets re-scoped rather than retried a fourth time.

---

## 5. Rules that keep the bars honest

These exist because this project has already been burned by their absence.

1. **A bar may not be changed by anyone being judged against it.** Changing a bar is its own
   checkpoint, requires the human, and must record the old and new numbers side by side with
   the reason. CP-13/CP-14 silently substituted a land-coverage measurement for a
   concept-comparison measurement and passed; that must not be possible again.
2. **Every checkpoint re-runs the whole bar panel, not just its own bar.** B1b, B2b and B6
   are scripted and cost minutes. The regression sheet is all six axes, every time.
3. **The builder never grades itself.** The critic is a fresh subagent with the goal, the
   bar, the rules and the artifact — never the builder's prose, diff summary, or reasoning.
4. **The critic inspects the artifact.** Real pixels, a real recording, real JSON. A critic
   that reviews a written summary has reviewed nothing.
5. **Blind means blind.** The critic is handed `frame-1` and `frame-2` at identical size and
   aspect and is not told which is ours. `answer.txt` is opened only after the verdict.
6. **One gap per round.** When ours loses, the critic names the *single largest* remaining
   gap and returns the work. Not a list.
7. **No round limit.** Stop when the human is satisfied, when improvements stop mattering,
   or when the budget runs out.
8. **A green build proves nothing about the frame** (`PROJECT_STATE.md` CP-01). Every
   checkpoint ends with an installed build and a full-resolution landscape capture, or it
   does not close.

---

## 6. Role → model assignment

**Hard requirement. No exceptions, no substitutions.**

| Role | Model | Why |
|---|---|---|
| Director / planner | `claude-opus-5-thinking-max` | Chooses bars and decomposition; the judgement layer |
| **Every builder / implementer** | **`composer-2.5`** | All code and asset work |
| **Every critic / reviewer** | **`claude-opus-5-thinking-max`** | Blind A/B, perf critique, launch-gate audit |
| Smoothing-pass agent | `claude-opus-5-thinking-max` | It is a judging role wearing an editing hat |

Every prompt template in `02-PROMPTS.md` names its model in the first line. A builder
running on a critic model, or a critic on a builder model, is an invalid run — discard it.

---

## 7. Anti-regression rules — do not re-litigate

Breaking any of these fails a checkpoint outright, whatever the bars say.

**Architecture** (`AGENTS.md`):
1. `Sources/Simulation` and `Sources/Domain` are pure Swift — Foundation, Observation and
   simd only. Never RealityKit, never UIKit.
2. The renderer projects state and decides no rules.
3. All positions resolve through `WorldMap`.
4. Fixed **20 Hz** timestep. Frame rate never changes outcomes. A perf fix that couples
   simulation to frame rate is rejected however fast it is.
5. Determinism: `DeterministicRandom` on tagged per-subsystem streams only. No
   `Double.random`, no `SystemRandomNumberGenerator`. **Adding a draw in one subsystem must
   not shift another's numbers** — new randomness gets a new stream.

**Verified rendering facts.** The full list is in `AGENTS.md` §"Verified rendering facts."
They were established in the rendered build and are not open questions. The ones most likely
to be re-broken by this plan's work:

- Shadows require `.fixed` projection; `.automatic` renders none under this ortho camera.
  Leave `shadowUsesFixedProjection = true`.
- `bloomIntensity` above 1 is correct here and is not a taste dial.
- Bloom begins at `threshold - softKnee`, not at `threshold`.
- Exposure is `LightingRig.Tuning.exposureScale`, not the post-process `exposure` — the
  latter moves emitters and lit surfaces together and destroys the glow.
- A hue rotation costs exposure and must be paid for with `exposureScale`.
- The lower IBL hemisphere is warm sunlit regolith, not void.
- Sky props clip outside roughly ±35 at default zoom.
- Ground decals must clear `FragmentMeshFactory.chordError`; recompute it if relief
  amplitude or cell count changes.
- Do not judge a texture change by local σ, and do not classify pixels against an absolute
  threshold across an exposure change.
- The debug overlay stays opt-in behind `-sunfoldDebug`.
- `rotate` loses its first call after launch — send Portrait then LandscapeLeft.
- Wait ≥ 12 s after a Debug launch before capturing, or you photograph an empty void and
  report a regression that is not there.

**Product invariants:** landscape-only iPad; deterministic seed `20260726`; land coverage
75–80% of `WorldMap.bounds`; land is civilization-independent; only Core centres need equal
distance from the Dominion.
