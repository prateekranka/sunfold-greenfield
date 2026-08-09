# Sunfold — Greenfield

A serene but pressured touch-first space RTS about shepherding a living starfaring
civilization. This project is a focused proof of one complete **Foundation → Voyager**
skirmish: establish the Sunwoven on a drifting fragment, gather four resources,
cross the void to expand, age into Voyager, withstand the Gravemark response, and
win by Dominion control or Conquest.

Target: native iPadOS 26.x, landscape, an 8–10 minute first-time-player match.

This is a greenfield build. It shares no code with the historical `Sunfold/`
implementation.

---

## Requirements

- Xcode 26.x (built against the iOS 26.5 SDK)
- XcodeGen (`brew install xcodegen`)
- An iPad simulator on an iPadOS 26.x runtime — 13-inch class is the composition target

## Build and run

```bash
make generate && make build
```

`SunfoldGreenfield.xcodeproj` is generated and is not the source of truth —
`project.yml` is. Re-run `make generate` after adding or removing a source file,
or the new file will not be compiled.

## Architecture

Four rules hold this together:

1. **Simulation owns truth.** `Sources/Simulation` and `Sources/Domain` are pure
   Swift. Units, buildings, resources, queues, combat, victory, AI and map legality
   live there. They import no rendering framework.
2. **The renderer projects state.** `Sources/Rendering` turns simulation state into
   RealityKit entities and emits input intents. It decides no rules.
3. **One world coordinate system.** `WorldMap` is the single map contract. Renderer,
   pathing, minimap, AI, camera bounds, deposits, docks and selection all resolve
   position through it, so a place that looks walkable is walkable.
4. **Fixed timestep.** `SimulationClock` advances the game in equal 20 Hz slices and
   discards backlog rather than fast-forwarding. Frame rate never changes outcomes.

Supporting rules: every entity carries a durable `EntityID` (never an array index);
all tuning lives in `SkirmishTuning`; missing art falls back to a readable primitive (debug fallback only)
plus a visible `DebugLog` warning rather than a crash or an invisible entity.

```
Sources/
  App/            SwiftUI entry point and shell
  Domain/         Factions, resources, tuning, the world map contract
  Simulation/     Seeded RNG, fixed-step clock, game state
  Rendering/      RealityKit scene, camera rig, meshes, palette
  Input/          UIKit gesture recognizers for camera control
  HUD/            Tactical HUD (G2+)
  Audio/          Soundscape and cues (G4+)
  Accessibility/  VoiceOver, Reduced Motion, captions (G7)
  Debug/          Debug overlay and fail-closed logging
```

## Determinism

The match replays from a single seed, locked at `20260726` for the first playable
map. Nothing in the simulation touches `SystemRandomNumberGenerator` or
`Double.random`; all randomness comes from `DeterministicRandom`, and each
subsystem draws from its own tagged stream so adding a call in one place cannot
shift another system's numbers.

## Concept references

`Docs/Concepts/` holds the five approved gameplay concepts plus the visual bible
and per-screen notes, copied in read-only. They are **visual targets, not sprite
sheets** — no gameplay art is cropped from them.

## Evidence

`Docs/QA/` holds per-gate screenshots and build logs. A gate is not complete on a
green build: it is complete when the behaviour was observed in the rendered app on
an iPad simulator. Telemetry that could not be captured is labelled **Proof Pending**
rather than estimated.
