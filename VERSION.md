# Version

**0.6.3** — build 48

| Field | Value |
|---|---|
| Active development track | Helios Rift — Broken Ring reference parity |
| Latest Helios checkpoint | Cycle 09 — material-driven Broken Ring terrain · commit `816d06c` |
| Dev deployment | `dev.helios.contenthelper.in` · Worker `c4c70fa5-8a06-49d6-85cb-0f7447d3c441` |
| Gate | G0 complete · G1 in progress (not passed) · G2 in progress (not passed) · G3 opened |
| Play-feel reference | Age of Empires 2 / Rise of Rome, in space (BC-01, 2026-07-31) |
| Locked map seed | `20260726` |
| Bundle identifier | `com.sunfold.greenfield` |
| Built against | iOS 26.5 SDK (Xcode 26.6) |
| Deployment target | iOS 26.0 — runs on any installed iPadOS 26.x runtime, never iOS 27 |
| Device family | iPad only |
| Orientation | Landscape left and right only |
| Swift | 6.0 language mode, complete strict concurrency |
| Verified on | Sunfold Cycle 1 iPad Air 13, iPadOS 26.5 |

Deployment target is 26.0 rather than 26.5 so the build runs on every installed
iPadOS 26.x runtime while still compiling against the newest 26.x SDK. The plan's
hard constraint — never target iOS 27 — holds.
