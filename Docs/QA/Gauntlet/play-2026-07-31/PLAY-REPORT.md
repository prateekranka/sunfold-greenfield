# Play report — 2026-07-31, director session

**Build.** Working tree at `fd34833` + 16 modified tracked files + untracked in-flight work
from concurrent agents. Compiled as `build-agents/director-play`, `** BUILD SUCCEEDED **`.

**Device.** `75898CE1-A691-4973-817A-973D4249A38F` — "Sunfold Cycle 1 iPad Air 13",
iPad Air 13-inch (M2), iPadOS 26.5. Verified present and booted before use. The UDID in
`AGENTS.md` (`A59055F8-…`) does not exist on this machine.

**Method.** Installed, launched, rotated Portrait → LandscapeLeft, waited, captured, then
played: selected a citizen, issued a move order, opened the Farm placement ghost, dragged
it to open ground and released it, and inspected the resulting state.

This is a play report, not a code review. Everything below was observed in the running app.

---

## Ranked by player impact

### 1 — There is no game to win or lose. *(highest impact, and it is not close)*

The match never ends. There is no victory condition, no defeat condition, no combat, no
production, and no opponent behaviour. Gravemark exists on the map as four citizens and a
Core that stand still for the entire session. After ten minutes of play the only thing that
has changed is four numbers in the top bar.

The complete verb set the player actually has is **select, move, gather, build (three
buildings)**. Everything an RTS is *for* — making an army, meeting an opponent, resolving a
fight, winning — is absent. This is the correct top item under the human's Directive 2.

Evidence: whole session. `Sources/Simulation/` contains no combat, production, or victory
system; `Sources/AI/` does not exist.

### 2 — A successful build ends in a red error state, and takes the camera with it.

Selected a citizen, tapped the Farm tile, dragged the ghost to open ground, released.
The Farm **was** founded correctly: 70 Matter was deducted, the selection panel switched to
"Farm · Constructing 7% · 2 citizens building", and two citizens walked over and started
work. All good.

But the placement session stayed alive, sitting on the foundation it had just created. The
new building makes that footprint illegal, so the ghost turned **red** and the placement
panel read **BLOCKED — "Move onto clear home ground"**. The player's successful action
terminates in what looks like a failure.

Worse, and not in the original review: because `endBuildGhostDrag()` leaves `buildGhost`
non-nil, the gesture gates never flip back. Pan, tap and lasso stay disabled and the ghost
recognizers stay enabled — **the player loses camera control and normal selection until
they tap to cancel a ghost they did not know was still active.**

Evidence: `02-cp-g2a-defect-ghost-blocked-after-place.png`. This is the CP-G2a defect from
`Docs/QA/G2/cp-g2a/read-only-kimi-review.md`, still present, reproduced first try.

### 3 — You cannot see what you have selected.

Tapping a citizen brings up the selection panel — portrait, name, "Idle", a 40/40 life
meter. In the **world**, nothing changes. No ring, no highlight, no colour shift, no life
bar over the unit. With four citizens standing in a clump beside the Core, there is no way
to tell which one you are commanding.

Concept 01 draws a teal selection ellipse and a green life bar under every unit. The game
draws neither. For a game whose entire loop is *pick that one, send it there*, this is the
largest readability failure in the frame.

Evidence: `03-zoomed-core-no-selection-ring.png` — a citizen is selected (panel bottom-left
reads "Citizen · Idle · 40/40") and is visually identical to its neighbours.

### 4 — Six of the nine command tiles are permanently dead chrome.

Gather, Move, Set rally point, Stop, Build Outpost and Guard all render as buttons. Only
Farm, Matter Extractor and Dwelling do anything (and `stop`, which is wired as a move order
to the unit's own position). A first-time player reads a nine-verb game and finds a
three-verb one.

### 5 — The frame is a beige desert. The game no longer reads as being in space.

Measured on today's capture with `Docs/Gauntlet/tools/framestat.py measure`:

| | concept 01 (the bar) | today |
|---|---|---|
| void fraction | 0.530 | **0.025** |
| black point (luma p05) | 0.001 | **0.104** |
| dynamic range | 0.515 | 0.448 |
| saturation mean | 0.484 | 0.366 |
| dominant hue share | 0.789 | **0.860** |

Four of five B1b thresholds fail. There is not one true black pixel in the rendered world.
At default zoom the frame is wall-to-wall sand with no rim, no void channel, no nebula and
no celestial body in shot. This is the known P1 regression from CP-12 → CP-14 and today's
capture confirms it has not moved.

Evidence: `01-opening-frame.png`.

### 6 — The light transport is beached on dry sand.

The vessel and its gold pier sit on open regolith with no water anywhere near them. It is
the kind of thing a stranger notices in one second.

Evidence: `01-opening-frame.png`, lower-centre-left.

### 7 — The stale alert is still there.

"Light transport docked at home rim" has been on screen in every committed capture since
CP-08 and was on screen for this entire session. An alert that never clears trains the
player to stop reading the alert strip.

### 8 — Scene build takes about 55 seconds in Debug, not 12.

`AGENTS.md` says wait ≥ 12 s after a Debug launch before judging. I did, captured, and got a
**completely black theatre with a fully drawn HUD** — which reads exactly like a renderer
regression. The world appeared between 35 s and 55 s after launch. The 12 s figure is stale;
the tree has grown a lot of procedural work since it was measured. Anyone who captures at
12 s today will file a false regression report. Recorded in `AGENTS.md`.

### 9 — The app was force-quit out from under the play session.

At 19:28:21 `CoreSimulatorBridge` sent `FBSSystemAppProxy: Sending request to terminate
application com.sunfold.greenfield` — "Termination requested by simulator host", exception
code `Force Quit (0xFBFBFBFB)`. Not a crash: no diagnostic report was written and the
process was in the foreground and healthy. A concurrent agent was driving the same
simulator while `workbench-data.json → simLease.holder` still named `perf-agent`.

Separately, `~/Library/Logs/DiagnosticReports/` holds **18 real SunfoldGreenfield crash
reports between 17:55 and 18:10 today**, all `EXC_BREAKPOINT / SIGTRAP` in
`FramePacingView.installUpdateLinkIfNeeded()` at `FramePacing.swift:66` under
`-[UIUpdateLink setRequiresContinuousUpdates:]`. That file has since been rewritten onto
`CADisplayLink` by its owning agent, so the crash appears to be fixed — but it is untracked
in-flight work that has never been proven in a play session, and it is in the render path
of every launch.

### 10 — Units are about 10 px tall at default zoom.

At the default zoom of 64 a citizen is a few pixels of teal. The visual bible's own rule —
citizen silhouette ≈ 1/4 to 1/3 of building height on screen — is not met. Combined with
item 3, a player at default zoom cannot tell how many units they have, which are theirs,
or what any of them is doing.

---

## Things that are better than expected

Recorded so the next checkpoint does not regress them.

- **The Civilization Core is genuinely good.** Ivory pavilion, gold armature, turquoise
  glazing, real cast shadow, and the brightest object in frame. It reads as a building.
- **Construction, once you get past the ghost bug, works properly.** Cost deducts on
  commit, two citizens path to the foundation and start work, progress ticks visibly, the
  selection panel reports "Constructing 7% · 2 citizens building" and offers a cancel with
  its refund. That is a real verb.
- **The HUD chrome is close to concept parity** — resource rail, emblem, speed cluster,
  alert strip, group slots, minimap with a yaw-correct camera quad, selection panel with a
  life meter, 3×3 command grid. It looks like an RTS.
- **The placement panel copy is good**: name, purpose, cost, state, and the gesture
  instruction ("Drag to place, release to found · Tap to cancel").
- Pinch-zoom, pan and the minimap reticle all behave correctly.

---

## Captures

| file | shows |
|---|---|
| `01-opening-frame.png` | Default-zoom opening frame; beached transport; stale alert; no void |
| `02-cp-g2a-defect-ghost-blocked-after-place.png` | Farm founded and building, ghost still live and red BLOCKED on top of it |
| `03-zoomed-core-no-selection-ring.png` | A selected citizen with no world-side selection marker |

---

# Second pass — same day, after the CP-G2a fix landed

**Build.** `build-agents/director-verify`, same tree plus the ported CP-G2a fixes and the P4
presenter cache. `** BUILD SUCCEEDED **`. Same device, same method.

**What I did.** Placed a Farm and watched it complete; panned to the map rim and back; tried
every camera-navigation affordance; selected the Civilization Core and read its command card.

## Item 2 above is fixed

Reproduced the original defect's success path and it is clean now: the ghost clears on
placement, the camera is immediately usable again, and the refund reads `+52.5 Matter`
instead of `53`. Full write-up and captures: `Docs/QA/G2/cp-g2a/r3-resolution.md` and
`Docs/QA/G2/cp-g2a/r3-device/`.

## New findings, ranked

### A — You cannot train a single unit. Population is frozen at 4/8 forever.

This outranks everything else I have written in this document, including the old item 1,
because it is more basic than combat: **there is no production of any kind.**

I selected the Civilization Core. The command card **did not change** — it still showed the
*citizen's* build menu (Farm, Matter Extractor, Dwelling). There is no "Train Citizen" tile
anywhere in the game.

Confirmed in source: `SkirmishSimulation.swift` contains no `enqueue`, no `queue`, no
`train`, no production of any kind. `BuildingKind.trains` exists at `EntityKinds.swift:181`
and correctly declares `civilizationCore → [.citizen]` and
`formationYard → [.pathfinder, .vanguard, .ranged]` — **nothing reads it.**
`SkirmishTuning.maxQueueLength = 10` and `cancelRefundFraction = 0.75` exist — **nothing
reads either.**

The knock-on effects are the whole economy: the Dwelling's only purpose is to raise a
population cap that nothing can ever consume, and the Formation Yard is a building that
trains three units and can never be built.

Evidence: `captures/core-selected-no-train-tile.png` — Core selected, panel reads
`Civilization Core · Heart of the Hearth · 600/600`, command card shows Farm / Matter
Extractor / Dwelling.

### B — Three buildings that exist can never be built.

`formationYard`, `expansionOutpost` and `dawnLoom` are full `BuildingKind` cases with costs,
HP, footprints, meshes and purposes. `CommandGrid.rows` hardcodes exactly three build tiles —
Farm, Matter Extractor, Dwelling — so the other three have no tile and are unreachable. The
Dawn Loom is the age-advance building, which means **the Voyager age is unreachable too.**

### C — Camera navigation is dead except drag-pan.

The map is several screens wide. I panned to the map rim, then tried to get home:

- **Minimap tap does nothing.** `Sources/HUD/Minimap.swift` has no tap or drag gesture on
  the map well at all.
- **"Go to Core" does nothing.** Tapped it from the rim; camera did not move.
- **"Face north", "Place marker", "Expand map"** — same. All four tiles at
  `Minimap.swift:94-97` are `HUDIconTile(glyph:size:name:)` with **no action closure.**

So five more controls that look interactive and are decoration. Getting back to my own base
took six drag-pans and I overshot twice. In an RTS the player navigates constantly; this is
the most *felt* defect of the session after A.

This corrects a line in the first pass above: the minimap's camera **reticle** does render
correctly and track the camera. Its **navigation** does not exist.

Evidence: `Docs/QA/G2/cp-g2a/r3-device/07-minimap-tap-no-effect.png` and
`08-go-to-core-no-effect.png`.

### D — The resource rate readout always says `+0` while the numbers climb.

Provisions went 194 → 293 over the session; the rate indicator beside it read `+0` the entire
time, as did Matter, Lumen and Aether. Either the rate is not computed or it is not bound.
A HUD that contradicts the number next to it is worse than no HUD.

### E — Untextured grey polygons float in the void near the map rim.

Panning past the coastline shows five or six flat grey chevrons suspended in empty space with
no shading and no material. They may be intended debris; they do not read as anything.

Evidence: `captures/void-rim-floating-polys.png`.

### F — Large translucent pale quads lie flat on the terrain.

Semi-transparent lavender-white rectangles with yellow stripes, sitting on the sand at
several places. If these are causeways or route markers they do not read as either.

Evidence: `captures/terrain-translucent-quads.png`.

### G — No test in this repository has ever actually run.

Not a play observation, but it governs what any of the above can be *proven* by, so it
belongs in the ranked list. `xcodebuild test` fails at the app host —
`Early unexpected exit … Test crashed with signal kill before establishing connection` —
because the host needs ~55 s to build its scene. The r1 worktree's recorded "10/10 passed"
came from an environment where `xcodebuild test` was hook-blocked, so it is not real output.
Being fixed under P14.

## Captures, second pass

| file | shows |
|---|---|
| `captures/core-selected-no-train-tile.png` | Core selected; no production tile anywhere |
| `captures/base-farm-and-core.png` | Completed Farm beside the Core — construction works end to end |
| `captures/void-rim-floating-polys.png` | Untextured grey polygons floating in the void |
| `captures/terrain-translucent-quads.png` | Translucent pale quads lying on the terrain |
