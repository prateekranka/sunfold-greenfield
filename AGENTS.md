# Agent working brief — Sunfold Greenfield

Read this before touching anything. It encodes the environment facts that are not
discoverable from the source and that cost real time to rediscover.

## The project

Native iPadOS RTS in Swift 6 + RealityKit. `project.yml` is the source of truth for
the Xcode project; it globs `Sources/`, so a new `.swift` file anywhere under
`Sources/` is picked up by `xcodegen generate` with no manifest edit.

Architecture rules that must not be broken:

1. **Simulation owns truth.** `Sources/Simulation` and `Sources/Domain` are pure
   Swift — Foundation and simd only. They must never import RealityKit or UIKit.
2. **The renderer projects state.** `Sources/Rendering` turns simulation state into
   entities and decides no rules.
3. **One coordinate system.** All positions resolve through `WorldMap`.
4. **Fixed timestep.** 20 Hz; frame rate never changes outcomes.
5. **Determinism.** No `SystemRandomNumberGenerator`, no `Double.random`. All
   randomness comes from `DeterministicRandom` on a tagged per-subsystem stream.
   Adding a draw in one subsystem must not shift another's numbers.

## Building — do not use bare xcodebuild or simctl

A `PreToolUse` hook in this environment blocks `xcodebuild build`, `xcodebuild test`
and most `xcrun simctl` subcommands, routing them to FlowDeck. FlowDeck is installed
but **unlicensed**, so it cannot run. The working paths are:

- **Compile check (parallel-safe, use this):**
  ```
  ./scripts/agent-build.sh <your-agent-name>
  ```
  Builds to `build-agents/<name>/` so concurrent agents never share a module cache,
  and serializes `xcodegen generate` behind a lock. Prints only diagnostics.
  Full log at `build-agents/<name>.log`.

- The resulting bundle is at
  `build-agents/<name>/Build/Products/Debug-iphonesimulator/SunfoldGreenfield.app`

Never run `xcodebuild` directly and never run `xcrun simctl`.

## Running it on the simulator — argent MCP only

Simulator UDID: `A59055F8-1354-4936-97B8-7033DF90B0BB`
("Sunfold Cycle 1 iPad Air 13", iPadOS 26.5). Bundle id: `com.sunfold.greenfield`.

Load the argent tools with ToolSearch first:

```
ToolSearch: select:mcp__argent__reinstall-app,mcp__argent__launch-app,mcp__argent__screenshot,mcp__argent__run-sequence
```

Then, in order:

1. `mcp__argent__reinstall-app` — udid, bundleId `com.sunfold.greenfield`,
   appPath = the `.app` path above.
2. `mcp__argent__launch-app` — udid, bundleId.
3. `mcp__argent__run-sequence` — one step `{"tool":"rotate","args":{"orientation":"LandscapeLeft"},"delayMs":2500}`.
   **The app is landscape-only and renders nothing in portrait.** This step is not
   optional.
4. `mcp__argent__screenshot` — udid, `scale: 1.0`, `rotation: "LandscapeLeft"` for a
   full-resolution frame you can actually judge detail in.

**The simulator is a single shared resource.** Only install/launch/screenshot when
the orchestrator has told you it is your turn. Never do it concurrently with another
agent.

## Visual target

`Docs/Concepts/01-sunwoven-foundation-opening.png` is the approved AAA target frame
and the reference for blind A/B judging. `Docs/Concepts/00-visual-bible.md` holds the
locked art direction: camera pitch, HUD geometry, faction palettes, lighting rules.

The bible's "low-poly fidelity ceiling" section describes the *original* placeholder
scope and is superseded — the target is now the fidelity of concept 01 itself.
Everything else in the bible (camera, HUD geometry, palettes, faction identity,
fragment-to-void ratio, sparse starfield) still holds.

## Verified rendering facts — established in the rendered build, do not re-litigate

- **Shadows require `.fixed` projection, not `.automatic`.** Under this project's
  `OrthographicCameraComponent`, `DirectionalLightComponent.Shadow` with
  `.automatic(maximumDistance:)` renders **no shadows at all**, at any distance
  value. `.fixed(zNear:zFar:orthographicScale:)` works. `LightingRig.Tuning`
  already carries the working setting — leave `shadowUsesFixedProjection = true`.
- **A real post-process hook exists.** `content.renderingEffects.customPostProcessing
  = .effect(...)` on `RealityView` content is supported and in use
  (`Sources/Rendering/PostProcess/SunfoldPostProcess.swift`). Bloom, tonemap,
  vignette and chromatic aberration all run there. It applies to the whole frame
  buffer, so it hits the starfield and the far fragment too — but **not** the
  SwiftUI HUD, which composites above it.
- **Runtime IBL works.** `EnvironmentResource(equirectangular:)` accepts a
  procedurally built HDR float image; `ImageBasedLightComponent` +
  `ImageBasedLightReceiverComponent` light the scene without painting a background.
  Receivers must be tagged per model entity — see `LightingRigSystem`.
- **Scene build takes several seconds in Debug.** Procedural textures cost ~570 ms
  per recipe at `-Onone`. The first frames render black with `tick 0`. **Wait at
  least 12 s after launch before screenshotting**, or you will capture an empty
  void and report a false regression.
- The debug overlay is now opt-in via the `-sunfoldDebug` launch argument and is
  **off** by default, so captures are clean. Do not re-enable it by default.
- **The scene's exposure is one number.** `LightingRig.Tuning.exposureScale` multiplies
  key, fill, rim and the IBL together; the individual intensities are the art
  direction and their ratios should stay as they are. Reach for this rather than
  the post-process `exposure`, which moves emitters and lit surfaces alike — the
  gap between them is what makes anything look like it is glowing.
- **Bloom begins at `threshold - softKnee`, not at `threshold`.** Both were wrong
  for three sessions because only the threshold was being read. If the ground
  blooms, check the knee first.
- **`bloomIntensity` above 1 is correct here**, not a taste dial. A Gaussian blur
  conserves energy, so a small emitter's halo peak falls as `1/σ²`, and
  `RealityView` exposes no HDR path to carry the headroom instead.
- **`rotate` loses the first call after a launch.** It returns success and nothing
  turns, because the scene is still building. Send `Portrait` then `LandscapeLeft`,
  or you capture an empty void and report a regression that is not there.
- **The ground is not flat, and nothing may assume it is.** Sample it — through
  `TerrainSurface` in world space, or `FlatMeshBuilder.lift` / `groundHeight`
  in fragment-local space. Relief runs to 2 m and is pinned to zero only across
  the settlement pan.
- **Ground decals must clear `FragmentMeshFactory.chordError`.** The terrain grid
  stretches flat triangles between its samples, so it rides *above* the height
  field across every dip; a decal placed on the function is under the mesh and
  vanishes. Recompute that constant if a relief amplitude or cell count changes.
- **`WorldMap.bounds` is a camera limit, not the extent of the land.** It is
  `[118, 86]` against a fragment field of `94 × 55`, deliberately, so the camera
  can look past the edge. Anything fitting a view to the *world* must measure the
  fragments; fitting to `bounds` leaves the theatre small and off-centre.
- **A `Spacer` inside a SwiftUI column that has no width of its own makes the
  whole column greedy.** A HUD panel built this way stretches the length of the
  frame instead of sitting in its corner. Pin the row's width.

## Where the frame actually stands

Measured from the rendered frame, not guessed. Textures, IBL, shadows, the
post-process, exposure, bloom, soft stars, terrain relief and the HUD chrome all
landed across CP-01…CP-05 — `PROJECT_STATE.md` has the numbers. What is still
missing:

- **The void is flat black.** No nebula wash, and the celestial body does not
  appear in frame. Concept 01 has both. The largest gap.
- No animation. Units slide; nothing has an idle, walk or work cycle.
- No health bars — the one chrome surface of concept 01's five that is still
  absent. It belongs with combat, which is parked G2 work.
