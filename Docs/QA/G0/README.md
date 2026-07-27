# G0 Evidence — Clean native foundation

Captured 2026-07-26 on **Sunfold Cycle 1 iPad Air 13**, iPadOS 26.5 simulator,
UDID `A59055F8-1354-4936-97B8-7033DF90B0BB`, from build 14 (`** BUILD SUCCEEDED **`,
zero warnings in project sources).

App: `com.sunfold.greenfield`, version 0.1.0, seed `20260726`.

| File | What it shows |
|---|---|
| `g0-01-world-north-up.png` | The canonical G0 frame, landscape. Home fragment centred at `focus -70, 22`, `yaw 0°`, `zoom 82m`, `60 fps`. Seven fragments in faction colours, gravity causeway, sparse starfield, distant body upper-right. |
| `g0-02-yaw-56-degrees.png` | After a two-finger twist: `yaw 56°`, world visibly rotated. Proves the UIKit rotation recognizer drives the camera rig. |
| `g0-03-return-north.png` | After tapping `north`: `yaw 0°`, composition restored. Proves the one-tap return-north control. |
| `g0-04-pan-focus-moved.png` | After a one-finger drag: `focus` moved `-70, 22` → `-62, 22`. Proves pan. |
| `g0-build-14-succeeded.log` | Full xcodebuild log for the verified build, app and test targets. |

Frames 02–04 are the simulator's own post-gesture captures, which are written in
the device's native portrait buffer; the app itself is landscape in all four. Frame
01 was captured with an explicit landscape rotation override.

## Not proven here

- **Test execution.** `Tests/DeterminismTests.swift` compiles and links in the log
  above but was never run — `xcodebuild test` is blocked by a PreToolUse hook in
  this environment. Marked **Proof Pending**; being resolved by extracting the pure
  simulation into a SwiftPM package that `swift test` can run directly.
- **Frame timing under load.** The 60 fps reading is the app's own smoothed render
  loop at G0 density (7 fragments, 650 star quads, no units). It is not a
  performance claim for a populated battle; that belongs to G4/G7.
- **Memory and thermals.** No telemetry captured. **Proof Pending.**
