# Roadmap

Gates run in order. A gate is complete only when its behaviour was observed in the
rendered app on an iPad simulator — a green build is never sufficient.

---

### G0 — Clean native foundation ✅ complete

Generate the project; boot a SwiftUI shell hosting a RealityKit world on an
iPadOS 26.x 13-inch iPad simulator; lock landscape, the orthographic camera, app
identity, the deterministic seed and the debug overlay.

Delivered: 7-fragment authored map, void card with sparse stars and one distant
body, gravity causeways, 20 Hz fixed-step clock, Core trickle, seeded RNG with
per-subsystem streams, camera rig with pan/pinch/yaw/return-north, debug overlay.
Evidence in `Docs/QA/G0/`.

### G1 — Camera, selection, and one moving citizen — 🔶 in progress

Render the home fragment's Civilization Core, four citizens, resource deposits and
the light transport. Tap to select, tap ground to move, with destination feedback.
Prove camera-relative motion and that selection never fights with camera pan.
Stop and compare the rendered frame against concept 01.

### G2 — First Hearth economy — 🔶 in progress

Gather Provisions and Matter. Build Farm, Matter Extractor and Dwelling. Train a
Citizen or Pathfinder. Add the objective rail and the 30/60/90-second hint ladder.
Time a first-time pass from boot to completed building.

Done and observed in play (`Docs/QA/G2/`): the gather → carry → deliver → return
loop with per-node work stations; the tactical HUD (resource rail, selection
panel, load meter, deposit inspection); selection lasso and double-tap
select-all-of-kind.

Also done 2026-07-31: **construction** (place, pay, build, cancel with refund —
CP-G2a, `Docs/QA/G2/cp-g2a/r3-resolution.md`) and **production** (per-building
queue, cost on enqueue, cancel refund, population reservation — CP-C1,
`Docs/QA/G3/cp-c1/`). Camera navigation is real: minimap tap and drag, Go to
Core, Face north (CP-G2b-NAV). Land units can finally leave the region they
spawned in (CP-G3a2) — until that fix no unit had ever crossed a region
boundary, which quietly made G3, Conquest and Dominion all unreachable.

Still open in this gate:
- Objective rail and the 30 / 60 / 90-second hint ladder.
- A timed first-time pass from boot to a completed building.
- A deposit selection ring in the world; inspection currently updates the panel
  with nothing on the node confirming the tap landed.
- Selection rings overlap when citizens stand on adjacent stations (rings are
  1.5 m radius, stations 2.4 m apart). Units no longer interpenetrate; the rings
  still do.
- The group card reports composition and carried load but no activity, so a
  player who selects four citizens cannot tell whether they are working or idle.
  The single-unit card does report it.

### G3 — Logistics and expansion

Board citizens from a land-side staging point, sail a legal void lane, unload at
the expansion and establish an Outpost — which weaves the home causeway. Prove no
void chasing, no cusp stall, no duplicate cargo, no unreachable dock. Compare
against concept 02.

### G4 — Voyager and readable rival pressure

Gather Lumen and Aether, complete the 20-second Voyager channel, spawn the Dawn
Loom. Run the Gravemark defend → expand → contest telegraph. Produce Pathfinder
and Vanguard, and show stable formation motion.

### G5 — Two complete win paths

Dominion control with contest pause and 15/30/45-second milestones, ending in an
in-world transformation before the overlay. Conquest with Core damage thresholds
at 75/50/25% and a structural calamity before the overlay. Restart and Play Again
reset every deterministic system. Compare against concepts 03 and 04.

### G6 — Natural 8–10 minute calibration

At least three uninterrupted first-time-style playthroughs with no debug shortcuts.
Record beat times for first gather, first building, boarding, expansion, Voyager,
first AI contact and victory. Tune only the few variables driving the largest
pacing mismatch. A pass requires a natural 8–10 minute completion.

### G7 — Player-signable proof

Full landscape iPadOS 26.x run covering touch, audio, Reduced Motion, VoiceOver on
critical HUD actions, restart and both win paths. Narrow deterministic tests for
economy conservation, map connectivity, cargo integrity, age transition, Dominion
ownership, Core defeat and AI no-cheat accounting. Screenshots, video and an
evidence index under `Docs/QA/`.

---

## Explicitly out of scope

Mission 1 rescue; the Caravan → Waycamp → Haven narrative tracer; the Ascension age
and Ascension victory; multiplayer; campaign framework; broad progression; tech-tree
sprawl; diplomacy; fleets; meta economy; monetisation of any kind; paid assets or
services; analytics; accounts; 80-unit spectacle before the loop is proven.
