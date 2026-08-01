# Riverlands void-water topology findings

## Lead verification

1. Confirmed. `WorldMap.riverlands(seed:)` authored `tarn` and `pool` as radial
   `VoidBody.basin` values, and included them in the water field.
   See `Sources/Domain/WorldMap.swift:347-425`.

2. Confirmed in part, then refuted as a current failure. `strait` uses separate
   `inland` and `seaward` reach values, and the original Riverlands values did not
   reach the perimeter. The pre-change headless probe found both home→expansion
   channel components away from the perimeter. The fix extends the two seaward
   reaches to 100 m and 92 m. The current authoring is at
   `Sources/Domain/WorldMap.swift:232-281` and `Sources/Domain/WorldMap.swift:391-400`.

3. Confirmed. The existing property test checked nominal land-plate contiguity
   only. See `Tests/DeterminismTests.swift:126-135`. The new focused invariant is
   in `Tests/TopologyTests.swift:8-120`.

4. Partially confirmed. `crossing` and `dockPoint` selected from the shared field,
   but they had no connected-component invariant. The final headless probe found
   both home→expansion docks navigable and in the exterior-joined component. It did
   not prove every future berth on every route. See
   `Sources/Domain/WorldMap.swift:891-980`.

## Change

- Riverlands now sends both named rivers through the land band to the map perimeter.
- The tarn remains connected to the Sunwoven river.
- The pool remains as a landmark and now has a curved outlet into the Grave river.
- The renderer still samples `WorldMap.waterDepth(at:)` in world space. Movement uses
  the same signed field through `isNavigableVoid` and `landField`. The minimap traces
  the same field through `LandContour`. See `Sources/Rendering/VoidWaterMeshFactory.swift:5-10`,
  `Sources/Domain/WorldMap.swift:663-699`, and `Sources/Domain/LandContour.swift:14-17`.
- No change was required in `Sources/Domain/LandShape.swift`,
  `Sources/Rendering/VoidWaterMeshFactory.swift`, or
  `Sources/Rendering/TerrainSurface.swift`.

## Connectivity result

The focused invariant uses a 1 m grid and the movement clearance of 0.75 m.
Perimeter cells represent the surrounding void outside the playable rectangle.
The final headless probe found four raster edge regions and no interior component.
Joining all perimeter regions to the exterior gives exactly one navigable component.
Both named channels reach that component.

See `focused-test-output.txt` for the complete output and the XCTest blocker.

## Visual and gameplay checks

- Final Riverlands land coverage: 75.6% of the playable bounds.
- The 75–80% land-band harness passed for Riverlands, Basin, and Fjords.
- Both home→expansion docks were navigable at the 0.75 m margin.
- The required `./scripts/agent-build.sh luna-topology` compile check failed on
  unrelated concurrent code in `Sources/Simulation/SkirmishSimulation.swift:613`:
  `error: extra argument 'playerFaction' in call`. That path is prohibited for this
  thread, so the blocker remains with the concurrent lifecycle thread.
- No simulator install, launch, or screenshot was performed. Visual coastline grading
  remains pending with the orchestrator.
- FI-02 transport traversal remains pending because live transport input is out of scope.
