# First-Impression Phase B — status after the combined product review

Reviewed on the project iPad simulator against an installed build, as both Sunwoven and
Gravemark. Verdicts below come from the running product, not from tests or builder reports.

Branch `visual/aaa-uplift-cp02`, from baseline `ca10825`.

## Verdicts

| Ticket | Verdict | Commit |
| --- | --- | --- |
| FI-03 grounded single-unit obstacle navigation | Accepted | `e064b7d` |
| FI-05 full-footprint placement clearance | Accepted | `761960f` |
| FI-10 minimap camera navigation and accessibility | Accepted | `1b9de63` |
| FI-02 legal Light Transport voyage | **Not accepted** | `e064b7d` (inseparable, see below) |

## What was proved on device

**FI-03.** Both civilizations. A Citizen ordered straight across its own Core arrived on the far
side, clear of the Core, visually grounded, status Idle. An unreachable order into the void placed
the marker at a legal coastline point; the Citizen walked there and stopped Idle with no
oscillation and no permanent sticking. Re-verified after the FI-02 correction rebuild.

**FI-05.** Both civilizations. The Farm ghost turned red and read `BLOCKED — Move onto clear home
ground` while a visible gap still remained between the ghost edge and the Core mesh. Releasing
while blocked founded nothing and spent nothing. Legal placement immediately outside the boundary
succeeded, deducted 70 Matter, created the foundation and completed the Farm.

**FI-10.** Both civilizations. The minimap is exposed as one adjustable accessibility element with
a stable `minimap` identifier, a faction-aware label and a live camera value. Tap re-centred the
camera, a continuous drag panned it, the viewport indicator tracked and clamped at the map edge,
and the value updated truthfully. Minimap interaction issued no world orders and revealed no fog.

**Restart.** Proven from a real terminal result: a Gravemark match ended `DEFEAT by CONQUEST` at
5:44 and `Play again` produced a fresh, visible, interactive match at 0:01 with Cores 100/100 and
reset resources. Restart after a **victory** remains unproven — the adversary won both matches
played.

**Phase A.** The New Game screen and faction perspective survived every restart.

## Why FI-02 is not accepted

On the installed build the opening Light Transport renders beached on dry sand, far from any drawn
water, for both civilizations. After one correction round:

- Sunwoven rejects every move order tried, to drawn water and to drawn land alike, so it can make
  no voyage at all.
- Gravemark still accepts an order into the drawn void channel, travels across dry land and stops
  Idle on sand.

`WorldPopulator` spawns the Transport at `WorldMap.dockPoint`, which now searches the whole local
theatre in deterministic rings and traps rather than silently returning a land point. The app does
not trap. So the simulation believes the berth is deep navigable void while the renderer draws dry
sand: **the signed land field and the drawn terrain disagree.**

`landField` is also strongly negative outside the continent, where `VoidWaterMeshFactory` draws no
water at all — so "legal void" and "drawn water" are not the same set of points.

Repairing that belongs to FI-01 void-water world repair and to the terrain mesh in
`Sources/Rendering`, outside this ticket's ownership.

Two further items are open in the FI-02 work that shipped in `e064b7d`:

1. A rejected order draws the same `OrderMarker` as an accepted one, so denial is visible but
   indistinguishable from acceptance.
2. `WorldMap.dockPoint` now ends in `preconditionFailure`. That is deliberate loud failure, but it
   turns a cosmetic berth problem into a hard crash on any map that cannot supply a legal berth.

## Checks run

- `swift test` — 111 tests, 2 skipped, 0 failures, 131.8 s, exit 0.
- `./scripts/agent-build.sh` — BUILD SUCCEEDED, warnings only.

## Not proved

- Restart after a victory.
- Audible feedback. The device review was visual; no cue was confirmed by ear.
- Any behaviour of the gated tickets FI-04, FI-06, FI-06A, FI-07, FI-08, FI-09, FI-11, FI-12, FI-13.

Run material: `.codex-orchestrator/runs/run-20260801-04/` (git-excluded locally).
