# Phase A — final product review on the installed iPad build

Reviewer: Opus, orchestrating. Builders did not grade their own work.

Device: `Sunfold Cycle 1 iPad Air 13` (`75898CE1-A691-4973-817A-973D4249A38F`), iPadOS 26.5.
Build: `./scripts/agent-build.sh opus-integration` — **BUILD SUCCEEDED**.
Install / launch / interaction: argent MCP, per `AGENTS.md`.

## Verdict

Phase A's three requirements are met on the running product.

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Riverlands internal channels visibly reach the surrounding void | pass | `05-topology-both-channels-reach-outer-void.png` |
| 2 | Topology invariant confirms one intended navigable network | pass | `opus-independent-topology-probe-output.txt` |
| 3 | Rendering, navigation and minimap agree | pass | `04`, `05`, `07` |
| 4 | New Game starts as Sunwoven with no black screen | pass | `02`, `03` |
| 5 | Sunwoven can select, move, gather, build, take match pressure | pass | `03`, and the in-session Farm founding |
| 6 | New Game then starts as Gravemark with no black screen | pass | `06` |
| 7 | Gravemark can select, move, gather, build, take match pressure | pass | `06`, `07` |
| 8 | Each choice assigns the opposite faction as adversary | pass | `05` vs `07` |
| 9 | Restart after an outcome gives a visible, interactive scene | pass (defeat path) | `08`, `09`, `10` |

## Independent topology verification

The orchestrator did **not** reuse Luna A's test code. `opus-independent-topology-probe.swift`
re-derives the flood fill from `WorldMap.isNavigableVoid` and compiles directly against
`Sources/Domain` with `swiftc`. It runs three maps at three seeds:

```
riverlands seed=20260726: raster=4 edgeTouching=4 interior=[] exteriorJoined=1
riverlands seed=1:        raster=4 edgeTouching=4 interior=[] exteriorJoined=1
riverlands seed=99999:    raster=4 edgeTouching=4 interior=[] exteriorJoined=1
determinism same-seed identical field: true
```

Riverlands has **zero interior components** at every seed tested, so the fix is seed-robust
rather than tuned to one map. Determinism holds.

The same probe shows `basin` and `fjords` still carry isolated interior basins. Those maps were
out of Phase A scope, and lake country having lakes is arguably intended. Recorded as a finding,
not a defect.

## What the minimap shows

`05` (playing Sunwoven) and `07` (playing Gravemark) both show the same two channels: one entering
from the upper-left coastline notch and running down into the interior, one entering from the
lower-right and hooking up and inward. Both are continuous with the black surrounding void. No
isolated black pocket appears anywhere inside the landmass. The hook on the lower-right channel is
the pool basin joined by its new outlet. Coastlines stay scalloped and organic — no ruler-straight
cut and no visible surgical notch at either mouth.

## What the faction switch actually changes

`05` and `07` are the same map at the same zoom, one match apart:

- As Sunwoven, the camera viewport sits over the northern home, own units are teal, and the blue
  Gravemark adversary holds the south.
- As Gravemark, the viewport sits over the southern home, own units are blue, and the teal Sunwoven
  adversary holds the north — visibly expanded, which is live match pressure.

The HUD emblem reads `Sunwoven` in one match and `Gravemark` in the other. The selection panel
labels the selected Citizen with the matching faction. Resigning as Gravemark produces
`DEFEAT / Gravemark resigned.` with `Sunwoven wins by Resignation.` on the rail. This is a
perspective change, not a recolour.

## Not proven

- **Restart after a victory.** Only the defeat path was exercised, by resignation. Victory and
  defeat share one `MatchOverlay` and one restart path, so the risk is low, but this is stated as
  unproven rather than assumed.
- **The focused XCTests do not run.** `Tests/TopologyTests.swift` and
  `Tests/LifecycleFactionTests.swift` were written but the whole test target fails to build:
  all ten test files use `@testable import SunfoldCore` while the app module is
  `SunfoldGreenfield`, and `project.yml` sets no `PRODUCT_MODULE_NAME`. This is pre-existing and
  repo-wide, not introduced by Phase A. The topology invariant is therefore proven by the
  independent headless probe above, and the lifecycle/faction behaviour by the device pass.
- **Live Transport traversal of the new channel** — deferred to FI-02, which was out of scope.
