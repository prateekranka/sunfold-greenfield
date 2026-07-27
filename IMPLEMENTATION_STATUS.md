# Implementation Status

**Current gate:** G2 — First Hearth economy — **in progress, not passed**
**Complete:** G0 — Clean native foundation
**Also open:** G1 — camera/selection sign-off items listed in `ROADMAP.md`
**Version:** 0.3.0 — build 42
**Locked seed:** `20260726`
**Last verified:** 2026-07-27, iPad Air 13 simulator, iPadOS 26.5

---

## What is proven in the rendered build

Every item below was observed in the running app on the simulator, not inferred
from a successful compile.

### G2 — economy and HUD

| Claim | How it was verified |
|---|---|
| A citizen gathers, carries, delivers and returns | Tapped a citizen, tapped a Matter node; panel moved through *Walking to Matter → Gathering Matter 6/10 → Delivering Matter* and the load cleared at the Core |
| Delivery credits the stock as a whole load | Rail read Matter 314 → 315 → **326** across ~12 s while Provisions moved 222 → 224 → 225, which is the Core trickle alone |
| Only the assigned resource climbs | Provisions rose 253 → 262 over 36.5 s — exactly `coreTrickle.provisions × 36.5` — while Matter rose 47 in the same span |
| The carried load is visible on the unit | Slate Matter pack drawn on the citizen's back, present on the walk home, gone after delivery |
| Gatherers do not stand inside each other | Four citizens on one node occupy separate stations; frame `g2-07` |
| Lasso selects without moving the camera | Held and dragged over four citizens; `focus −70, 22` and `zoom 58m` unchanged through the drag |
| Double-tap takes all of a kind on screen | One double-tap on a citizen selected all four; panel read *4 Citizens* |
| A node can be inspected | Tapped a node with nothing selected; panel read *Matter · 420 remaining · No one working it* |
| HUD panels are opaque | Star-bleed pixel re-measured after the fix at rgb(5, 6, 13), matching the panel field exactly |
| 60 fps with the HUD and four gatherers | Debug overlay steady at 60 fps |

Evidence, including what is **not** proven: `Docs/QA/G2/`.

### G0 — foundation

| Claim | How it was verified |
|---|---|
| Landscape-only iPad app | Device rotated to LandscapeLeft; app fills the frame in landscape |
| RealityKit world renders | All 7 authored fragments visible with correct faction colours |
| Orthographic camera at 57° | Fragment reads as tilted land with a visible rocky flank, no perspective convergence |
| Deterministic seed surfaced | Debug overlay reads `seed 20260726` on every launch |
| Fixed-step clock advances | `tick` and `elapsed` climb at 20 Hz independent of the 60 fps render loop |
| Core trickle applies to both sides | Resource readout climbs from the authored 180/160/40/0 start |
| Debug overlay is first-class | Seed, tick, elapsed, age, yaw, zoom, focus, stock, fps, pause, time scale |
| One-finger pan | Swipe moved `focus` from `-70, 22` to `-62, 22` |
| Pinch zoom | Two-finger gesture moved `zoom` 82m → 60m, inside the 55–165m band |
| Two-finger yaw | Twist moved `yaw` 0° → 56°; world visibly rotated |
| Return-north control | Tapping `north` restored `yaw 0°` and the north-up composition |
| 60 fps at G0 density | Debug overlay reads a steady 60 fps (7 fragments, 650 stars) |

Evidence: `Docs/QA/G0/`.

---

## Open items

### Blocked — needs your decision

**Unit tests compile but have not yet been executed.** `Tests/DeterminismTests.swift`
(15 tests covering seeded replay, fixed-step accounting, map symmetry, fragment
separation, the transport-only first crossing, dock/staging legality, and equal
Core trickle for both factions) builds and links cleanly as part of every build.

`xcodebuild test` is blocked by a PreToolUse hook in this environment, so the
suite has not been run and its results are **Proof Pending**.

The fix in progress removes the dependency rather than working around the hook:
`Sources/Domain` and `Sources/Simulation` import only Foundation and simd, so they
are being extracted into a SwiftPM `SunfoldCore` package that `swift test` can run
directly. That is the correct architecture regardless — it enforces at module level
the rule that simulation owns truth and cannot reach into rendering — and it turns
these results from Proof Pending into real ones.

### Carried into G1

- The habitable top surface is a single flat facet. It reads as clean low-poly
  placeholder land but has no relief; the Core, deposits, props and citizens that
  give it scale arrive in G1/G2.
- The celestial body is pinned to the camera rig, so it does not parallax when
  the camera yaws. Correct for an orthographic sky, but worth a second look once
  yaw is exercised in real play.
- Camera bounds are enforced against `WorldMap.bounds` but have not yet been
  play-tested for "void always visible at the edges" at maximum zoom-out.
- No HUD yet. The bible's HUD geometry is locked but unimplemented; the debug
  overlay is deliberately not a stand-in for it.

---

## Decisions made during G0

**Build location.** Created in the session working directory rather than as a
filesystem sibling of the historical `Sunfold/` app, on your instruction. This
serves the greenfield rule most strictly: there is no path by which the old dirty
app or its branches can be committed alongside this one. The five approved concept
images plus the visual bible and screen notes were copied read-only into
`Docs/Concepts/`, since they are not present on the historical repo's checked-out
branch.

**Orthographic sky.** A world-space star shell does not work under an orthographic
projection — with no perspective convergence, a distant sphere projects almost
entirely outside the ~110×82m view rectangle, and the first build rendered no stars
at all. The void is now a card parented to the camera rig, counter-scaled with zoom
so stars hold a constant apparent size. See `StarfieldFactory`.

**Orthographic scale is a half-extent.** RealityKit's `OrthographicCameraComponent.scale`
is half the vertical world extent, not the full extent. Measured against a
known-radius fragment in the rendered build; the initial reading made the visible
world exactly twice as wide as intended. `CameraRig` now applies `zoom * 0.5`.

**UIKit gesture layer.** SwiftUI's `RotateGesture` never fires over a `RealityView`
— verified three times in the rendered build, as separate `.simultaneousGesture`
modifiers, combined in one `SimultaneousGesture`, and as a peer of the pan gesture.
Each time a two-finger twist changed zoom and left yaw at 0°. Camera input now uses
explicit `UIPanGestureRecognizer` / `UIPinchGestureRecognizer` /
`UIRotationGestureRecognizer` with true simultaneity and per-gesture finger counts,
which is also what G1's lasso-versus-pan disambiguation needs.

**Causeways are woven by Outposts.** The map contract needed to force the first
crossing to be made by transport (G3) while still leaving a complete land route for
a Conquest Strike (G5). Home-to-expansion causeways therefore stay dormant until
that side's expansion Outpost exists; the central expansion–Dominion spine is always
open. Both sides are governed by the identical rule.
