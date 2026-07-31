# CP-G2a — resolution

**Date:** 2026-07-31 · **Decided by:** director · **Verdict:** **CLOSED on the primary
defect, with the remaining proof gaps explicitly re-scoped out** (see §4). This is a partial
close, stated as one, not a claim that every item in the kimi review is proven.

**Device:** `75898CE1-A691-4973-817A-973D4249A38F` — Sunfold Cycle 1 iPad Air 13
(iPad Air 13-inch M2, iPad14,11), iOS 26.5, landscape.
**Build:** `build-agents/director-verify` from the combined working tree, `** BUILD SUCCEEDED **`.
**Evidence:** `Docs/QA/G2/cp-g2a/r3-device/`.

---

## 1. What was wrong

From `read-only-kimi-review.md`:

> After a successful placement, the placement session remains at the new foundation. The new
> foundation makes that same footprint illegal. The ghost therefore changes to red `BLOCKED`
> … The flow does not clearly return the player to normal control.

## 2. What changed

Ported by hand from the `cursor/cp-g2a-r2-construction-integrity-a2b9` worktree into the
main tree. **A port, not a merge** — the working tree carries several other agents' in-flight
edits to the same files (`PerfHarness` instrumentation in `WorldController`, `perfDensity` in
`SkirmishSimulation`/`WorldPopulator`, the whole `BoardingSystem`), and a merge would have
taken or clobbered them.

| # | Defect | Fix | Where |
|---|---|---|---|
| 1 | **Ghost survives a successful placement and reads `BLOCKED`** | Clear `buildGhost` on the success path, before returning | `Sources/Rendering/WorldController.swift:410` |
| 2 | Camera gestures stay suppressed after placement | Re-run `applyGhostGates(controller.buildGhost != nil)` after `endBuildGhostDrag()` | `Sources/Input/CameraGestureLayer.swift:189` |
| 3 | Refunds round `52.5` → `53` | `ResourcePool.displayAmount` renders 0/1/2 decimals as needed | `Sources/Domain/CoreTypes.swift:131`, `Sources/HUD/SelectionPanel.swift:150` |
| 4 | Boarding/aboard citizens get pulled into construction | `Unit.canBeAssignedToConstruction` gates every assignment path | `Sources/Simulation/WorldEntities.swift:77` + 4 call sites |
| 5 | Stalled foundations cannot receive builders again | `orderConstruct(_:on:)` + `respondToIncompleteFoundation`; a tap on an incomplete friendly foundation assigns builders | `SkirmishSimulation.swift:150`, `SelectionModel.swift:112`, `WorldController.swift:227` |
| 6 | Unbounded builders per site | `maxBuildersPerSite = 4` with diminishing returns | `SkirmishSimulation.swift:160` |
| 7 | Carried cargo disposition on construction start undefined | Defined as immediate stock credit, via `sendToConstruction` | `SkirmishSimulation.swift` |

## 3. Verified on device, this run

Sequence: launch → wait for the scene → select Citizen → Farm → drag-place → observe.

| Evidence | Shows |
|---|---|
| `01-launch-landscape.png` | Scene renders. Note it took **~55 s** in Debug, not the 12 s `AGENTS.md` documents |
| `02-citizen-selected.png` | Citizen selected, 40/40, Sunwoven; command grid lights |
| `03-ghost-active-ready.png` | Ghost placed, card reads `READY`, `70 Matter`, "Drag to place · Release to found · Tap to cancel" |
| `04-placed-no-ghost-refund-52p5.png` | **The fix.** Foundation founded, **no ghost anywhere on screen**, no red `BLOCKED`. Panel reads `Farm · Constructing 0% · 120/120 · Cancel +52.5 Matter` — defect 1 and defect 3 both resolved in one frame |
| `05-camera-pan-works-after-place.png` | A pan swipe immediately after placement moves the camera — defect 2 resolved |
| `06-farm-completed.png` | Farm completed, `120/120`, "Accepts deliveries", correct mesh and livery |

Defects 4–7 are code-level and are **not** proven by these captures. They are covered only by
`Tests/ConstructionIntegrityTests.swift`, whose status is §4.

## 4. What is NOT proven, and is re-scoped out of CP-G2a

Stated plainly rather than quietly dropped.

1. **`Tests/ConstructionIntegrityTests.swift` has never actually executed.** The r1
   worktree's recorded "**10/10 passed**" was produced in an environment where
   `xcodebuild test` was hook-blocked; it is not real test output. In *this* environment
   `xcodebuild test` runs but the app-hosted test bundle dies:
   `Early unexpected exit … Test crashed with signal kill before establishing connection` —
   the app host needs ~55 s to build its scene and the runner gives up first. **Every
   "tests pass" claim in this repository's history is therefore unverified.** Moved to
   **P14**, in flight now: a root `Package.swift` exposing `Sources/Domain` +
   `Sources/Simulation` as a testable `SunfoldCore` module that `swift test` can run on the
   host in seconds. Until P14 lands, defects 4–7 are *implemented and code-reviewed but
   unproven*.
2. **Completion audio** — not verifiable from screenshots and the simulator's audio path is
   not captured. Needs a human or a screen recording with audio. Pause boundary: not
   substituting a weaker measurement.
3. **Reduced Motion behaviour** — not exercised this run.
4. **The full placement-state matrix** — legal / illegal / unaffordable / cancel-placement /
   cancel-foundation. Legal and cancel-foundation-affordance are shown above; the other
   three are not. Cheap to prove once P14 gives a headless harness.
5. **Matter Extractor and Dwelling** placement and completion — only Farm was exercised.

Items 2–5 move to **CP-G2a′**, a small follow-up to run after P14, not a reason to hold the
checkpoint open. The primary player-visible defect — the one that made construction feel
broken — is fixed and photographed.

## 5. Two new defects found while verifying

Neither is in scope for CP-G2a; both go to the play report and the queue.

- **`Go to Core` does nothing.** `07-…` and `08-go-to-core-no-effect.png`: camera panned to
  the map rim, tapped the HUD's "Go to Core" affordance, camera did not move.
- **Minimap tap-to-navigate does nothing.** Same captures. Tapping the Core's position on
  the minimap does not move the camera.

Together these leave **drag-pan as the only working way to move the camera** in a game whose
map is several screens wide. For an RTS that is a top-tier usability defect, and it is
ranked accordingly in the play report.
