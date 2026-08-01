# Task B: New Game and civilization lifecycle diagnosis

## Reproduction

1. Install the debug app on `75898CE1-A691-4973-817A-973D4249A38F`.
2. Launch the app in landscape.
3. Start a match, then select `NEW GAME`.
4. Select Sunwoven or Gravemark.
5. Observe the frame before RealityKit finishes building the new scene.

The pre-fix frame showed HUD panels over the `voidDeep` background, with no world
entities: [sunwoven-in-play.png](./sunwoven-in-play.png). The old in-place Play Again
path still rendered the old scene: [before-play-again-result.png](./before-play-again-result.png).

## Actual root cause

The failure was a pre-attach loading gap, not a simulation restart failure.

- `RootView.startGame(as:)` creates a new `WorldController` and stores it in a new
  match session (`Sources/App/RootView.swift:133-145`).
- The new `RealityView` waits for `MaterialLibrary.preload()` before it calls
  `WorldController.attach` (`Sources/Rendering/SunfoldRealityView.swift:10-24`).
- `WorldController.attach` builds the complete `WorldScene` before it adds the root
  entity to RealityKit (`Sources/Rendering/WorldController.swift:71-99`).
- During that gap, the view exposes its `voidDeep` background
  (`Sources/Rendering/SunfoldRealityView.swift:39-41`).

The captured runtime log confirms the order. It records lighting at `20:41:00`,
terrain and `World built` at `20:41:04-05`, then the Core and transport entities.
See [runtime-lifecycle-log.txt](./runtime-lifecycle-log.txt). The final auto-start
frame shows the world and HUD after attachment: [final-auto-start.png](./final-auto-start.png).

## Fix and lifecycle result

- The session has a unique identity, and the RealityKit view uses that identity
  (`Sources/App/RootView.swift:80-89`).
- `WorldController.dispose()` removes the old root and subscription before the
  session is discarded (`Sources/Rendering/WorldController.swift:477-488`).
- `attach` rejects a disposed or already-attached controller
  (`Sources/Rendering/WorldController.swift:71-72`).
- `MatchLoadingView` replaces the void-only interval with a visible product-state
  surface (`Sources/App/MatchLoadingView.swift:3-35`).

The fixed loading state is shown in [sunwoven-loading-fixed.png](./sunwoven-loading-fixed.png).
The resulting Sunwoven match is [sunwoven-in-play-final.png](./sunwoven-in-play-final.png).
The resulting Gravemark match is [gravemark-in-play-final.png](./gravemark-in-play-final.png).
The defeat overlay and Play Again result are [defeat-final.png](./defeat-final.png)
and [restart-after-outcome.png](./restart-after-outcome.png).

## Remote hypothesis assessment

Partly right. A new controller and RealityKit identity are required for a clean new
match, so explicit session identity and disposal are part of the fix. The observed
black interval was caused by material preload and full scene construction before
the root entity was added. The evidence does not support a persistent stale-update
or `State(initialValue:)` teardown as the root cause of this reproduction.

## Faction perspective

`SkirmishSimulation.playerFaction` is explicit (`Sources/Simulation/SkirmishSimulation.swift:20,42-55`).
The adversary is the opponent faction, placement and commands use the chosen faction,
and victory severity and restart state use the same perspective
(`Sources/Simulation/SkirmishSimulation.swift:493-526`,
`Sources/Simulation/VictorySystem.swift:17-41`). Camera focus uses the chosen Core in
`Sources/Rendering/WorldController.swift:81-90`.

## Verification limitations

The requested focused XCTest command reached the test target but could not run because
existing test files import `SunfoldCore`, while the generated app module is
`SunfoldGreenfield`. The first output is [focused-check-module-resolution.txt](./focused-check-module-resolution.txt).
An override attempt produced duplicate module outputs; the second output is
[focused-check.txt](./focused-check.txt). The new lifecycle/faction tests remain in
`Tests/LifecycleFactionTests.swift` for the module-name repair.

The simulator verification used `xcrun simctl`, not argent. Final orchestrator verification
must repeat install, launch, landscape, and screenshot checks through argent.
