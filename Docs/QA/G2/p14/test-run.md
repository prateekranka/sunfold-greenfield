# P14 SwiftPM test run

## Commands

```bash
cd /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield
swift --version
swift build
swift test
./scripts/agent-build.sh p14-swiftpm
```

Host toolchain:

```
swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Target: arm64-apple-macosx26.0
```

`swift build` completed successfully (exit 0).

`./scripts/agent-build.sh p14-swiftpm` ended with `** BUILD SUCCEEDED **` (exit 0).

## Pass / fail count

- **29 passed**, **0 failed** (XCTest suite)
- Swift Testing library reported 0 tests in 0 suites (no Swift Testing `@Test` cases in this target)

## Failing tests

None.

## Verbatim `swift test` output

```
warning: 'sunfoldgreenfield': found 42 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Diagnostics/PerfHarness.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/TopBar.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Meshes/DepositMeshes.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/TerrainDressing.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/SunfoldRealityView.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/App/Info.plist
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/ResourceRail.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Diagnostics/SceneScaleSnapshot.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/CommandGrid.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/SunfoldPalette.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Texturing/ProceduralTexture.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/Minimap.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/WorldScene.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Debug/DebugOverlay.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/MarqueeOverlay.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/PlacementPanel.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Meshes/CivilizationCoreMesh.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Meshes/TransportMesh.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/CameraRig.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/LightingRig.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Meshes/BuildingMeshes.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/StarfieldFactory.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/WorldController.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/App/RootView.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/HUDStyle.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/PostProcess/LuminousMaterial.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Diagnostics/PerfOverlay.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/PostProcess/SunfoldPostProcess.metal
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/PostProcess/SunfoldPostProcess.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Texturing/MaterialLibrary.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/App/SunfoldGreenfieldApp.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/FragmentMeshFactory.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Audio/FeedbackAudio.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Meshes/UnitMeshes.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/Texturing/MeshUV.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/FramePacing.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Diagnostics/FramePerfSampler.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Diagnostics/PerfLaunchFlags.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/TerrainSurface.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/HUD/SelectionPanel.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Input/CameraGestureLayer.swift
    /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/Sources/Rendering/EntityPresenter.swift
[0/1] Planning build
Building for debugging...
[0/5] /Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield/.build/arm64-apple-macosx/debug/SunfoldGreenfieldPackageTests.derived/runner.swift
[1/6] Write sources
[3/6] Write swift-version--58304C5D6DBC2206.txt
[5/9] Compiling SunfoldCoreTests DeterminismTests.swift
[6/9] Compiling SunfoldCoreTests ConstructionIntegrityTests.swift
[7/9] Emitting module SunfoldCoreTests
[8/11] Compiling SunfoldGreenfieldPackageTests runner.swift
[9/11] Emitting module SunfoldGreenfieldPackageTests
[9/11] Write Objects.LinkFileList
[10/11] Linking SunfoldGreenfieldPackageTests
Build complete! (9.48s)
Test Suite 'All tests' started at 2026-07-31 20:12:24.869.
Test Suite 'SunfoldGreenfieldPackageTests.xctest' started at 2026-07-31 20:12:24.871.
Test Suite 'ConstructionIntegrityTests' started at 2026-07-31 20:12:24.871.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testAddingBuildersDoesNotDropAlreadyAssignedOnSameSite]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testAddingBuildersDoesNotDropAlreadyAssignedOnSameSite]' passed (0.490 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testBoardingAndAboardCitizensCannotBeAssigned]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testBoardingAndAboardCitizensCannotBeAssigned]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testBuildersStayAssignedUntilFoundationCompletes]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testBuildersStayAssignedUntilFoundationCompletes]' passed (0.493 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testCancelRefundUsesExactFractionalMatter]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testCancelRefundUsesExactFractionalMatter]' passed (0.543 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testConstructionAssignmentDepositsCarriedLoadToStock]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testConstructionAssignmentDepositsCarriedLoadToStock]' passed (0.512 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testLightTransportOnlySelectionInspectsIncompleteFarm]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testLightTransportOnlySelectionInspectsIncompleteFarm]' passed (0.497 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testOrderConstructSetsMarkerOnlyWhenBuildersAssigned]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testOrderConstructSetsMarkerOnlyWhenBuildersAssigned]' passed (0.493 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testRefundLabelPreservesFractionalMatter]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testRefundLabelPreservesFractionalMatter]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testStalledFoundationAcceptsBuildersAgain]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testStalledFoundationAcceptsBuildersAgain]' passed (0.494 seconds).
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testTwoFoundationsHaveIndependentBuilderCaps]' started.
Test Case '-[SunfoldCoreTests.ConstructionIntegrityTests testTwoFoundationsHaveIndependentBuilderCaps]' passed (0.506 seconds).
Test Suite 'ConstructionIntegrityTests' passed at 2026-07-31 20:12:28.900.
	 Executed 10 tests, with 0 failures (0 unexpected) in 4.028 (4.029) seconds
Test Suite 'DeterminismTests' started at 2026-07-31 20:12:28.900.
Test Case '-[SunfoldCoreTests.DeterminismTests testBothFactionsReceiveTheIdenticalCoreTrickle]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testBothFactionsReceiveTheIdenticalCoreTrickle]' passed (0.551 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testClockDropsBacklogInsteadOfFastForwarding]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testClockDropsBacklogInsteadOfFastForwarding]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testClockRunsFixedStepsRegardlessOfFrameRate]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testClockRunsFixedStepsRegardlessOfFrameRate]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testCoastlineTracesClosedLoops]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testCoastlineTracesClosedLoops]' passed (3.716 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testCoresAreEquidistantFromTheDominion]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testCoresAreEquidistantFromTheDominion]' passed (1.584 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testDifferentSeedsDiverge]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testDifferentSeedsDiverge]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testEveryLandmassCarriesAPlateCentre]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testEveryLandmassCarriesAPlateCentre]' passed (3.170 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testHomeReachesExpansionOnlyByVoidUntilOutpostIsWoven]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testHomeReachesExpansionOnlyByVoidUntilOutpostIsWoven]' passed (1.440 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testLandCoversMostOfThePlayableMap]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testLandCoversMostOfThePlayableMap]' passed (6.473 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testLandmassIsContiguous]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testLandmassIsContiguous]' passed (1.510 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testNeitherSideIsHandedMoreGround]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testNeitherSideIsHandedMoreGround]' passed (5.221 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testPauseStopsSimulatedTime]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testPauseStopsSimulatedTime]' passed (0.482 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testPlateCentresAreDryLand]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testPlateCentresAreDryLand]' passed (1.400 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testSameSeedReplaysIdentically]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testSameSeedReplaysIdentically]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testStagingPointIsOnLandAndDockIsInVoid]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testStagingPointIsOnLandAndDockIsInVoid]' passed (1.461 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testTaggedStreamsAreIndependent]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testTaggedStreamsAreIndependent]' passed (0.000 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testTransportCrossingsHaveWaterToCross]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testTransportCrossingsHaveWaterToCross]' passed (1.495 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testUnitFloatStaysInRange]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testUnitFloatStaysInRange]' passed (0.003 seconds).
Test Case '-[SunfoldCoreTests.DeterminismTests testZeroSeedIsNotDegenerate]' started.
Test Case '-[SunfoldCoreTests.DeterminismTests testZeroSeedIsNotDegenerate]' passed (0.000 seconds).
Test Suite 'DeterminismTests' passed at 2026-07-31 20:12:57.408.
	 Executed 19 tests, with 0 failures (0 unexpected) in 28.507 (28.508) seconds
Test Suite 'SunfoldGreenfieldPackageTests.xctest' passed at 2026-07-31 20:12:57.408.
	 Executed 29 tests, with 0 failures (0 unexpected) in 32.535 (32.538) seconds
Test Suite 'All tests' passed at 2026-07-31 20:12:57.408.
	 Executed 29 tests, with 0 failures (0 unexpected) in 32.535 (32.540) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```
