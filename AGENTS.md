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

## Baseline weaknesses as of build 42

Measured from the rendered frame, not guessed:

- No shadows anywhere. `DirectionalLightComponent` is created without a `Shadow`.
- No image-based lighting; ambient is a single flat fill light.
- No textures of any kind. Every material is a flat `baseColor` tint with a scalar
  roughness. No normal, roughness, AO or emissive maps.
- Custom meshes emit no UV coordinates, so texturing needs UV generation first.
- No post-processing: no bloom, tonemap or vignette, despite a luminous faction.
- No animation. Units slide; nothing has an idle, walk or work cycle.
- The habitable surface is one flat facet with no relief.
