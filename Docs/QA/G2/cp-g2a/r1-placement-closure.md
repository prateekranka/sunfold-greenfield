# CP-G2a-R1 — placement closure proof

**Branch:** `cursor/cp-g2a-r1-placement-closure-13bb`  
**Base:** `visual/aaa-uplift-cp02` @ `fd34833`  
**Build:** `./scripts/agent-build.sh cp-g2a-r1`  
**Device:** iPad Air 13 (M3), iPadOS 26.5, UDID `A59055F8-1354-4936-97B8-7033DF90B0BB`

## Fix (R1 only)

Successful `endBuildGhostDrag()` now clears `buildGhost` instead of keeping the session alive for a gold flash. `CameraGestureLayer.handleGhostPan` refreshes gesture gates after drag-release so camera pan / tap / lasso resume immediately.

## Simulator proof (LandscapeLeft, scale 1.0)

| Frame | Scenario | Pass criteria |
|---|---|---|
| `r1-proof/20-ready-landscape.png` | Opening ready | Command grid visible, no placement panel |
| `r1-proof/21-post-success-farm-selected.png` | A) Legal Farm drag-release | No ghost / no BLOCKED panel; Farm selected with construction card; Matter charged once (70) |
| `r1-proof/22-deny-blocked-still-placing.png` | B) Illegal Dwelling release on Core | Placement panel BLOCKED; ghost remains; Matter unchanged (no −80) |
| `r1-proof/23-cancel-exit-no-charge.png` | C) Cancel placement | Panel dismissed; Farm selection retained; no charge |
| (live) | D) Legal Extractor | Extractor selected, constructing; placement mode exited |

## Out of scope

Does not close broader CP-G2a review gaps (audio matrix, boarding builders, fractional refunds, repeat-placement mode).
