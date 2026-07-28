# G2 — The economy loop and the tactical HUD

Gate G2 is the first slice where the game is *played* rather than looked at: a
citizen can be put to work, resources climb because of that decision, and the
player can read what is happening without the debug overlay.

Everything below was captured from the rendered build on
**Sunfold Cycle 1 iPad Air 13, iPadOS 26.5**, at **60 fps**, seed `20260726`.
Nothing here is a mock-up and nothing is inferred from source.

Frames are stored rotated into landscape. The simulator's capture buffer is
portrait (2048 × 2732) regardless of the app's landscape orientation, so a raw
capture is the game turned 90°. Reading a raw frame as if it were upright is how
one review pass in this gate briefly recorded the citizens as "flat crumpled
shapes lying on the ground" — see *Corrections* below.

---

## What was proven in play

| # | Evidence | What it shows |
|---|---|---|
| 00 | `g2-00-hud-first-frame.png` | Opening frame with the resource rail. Provisions 180 · Matter 160 · Lumen 40 · Aether 0, `POP 4/8`, `FOUNDATION`. 60 fps. |
| 01 | `g2-01-gathering-cargo-meter.png` | Selection panel mid-loop: *Citizen · Gathering Matter · 6 / 10* with the load meter at 60%. |
| 02 | `g2-02-delivery-step-in-rail.png` | Three rails ~6 s apart: Matter 314 → 315 → **326**. The +10 step is one delivery; Provisions moves 222 → 224 → 225 across the same span, which is the Core trickle alone. |
| 03 | `g2-03-lasso-live-with-count.png` | Lasso mid-drag with the live hit-count badge. Camera state unchanged (`focus −70, 22`, `zoom 58m`) — the lasso suppresses the pan. |
| 04 | `g2-04-lasso-committed-four.png` | Release: four citizens ringed, panel reads *4 Selected*. |
| 05 | `g2-05-group-card-carrying.png` | Group card aggregating the loop: *4 Citizens · Carrying 21 Matter*. |
| 06 | `g2-06-deposit-inspection.png` | Tapping a node with nothing selected inspects it: *Matter · Node · 420 remaining · No one working it*. |
| 07 | `g2-07-gatherer-stations.png` | Four citizens on one node standing at separate stations, plus one walking a load back with a visible pack. |

`g2-build-42-succeeded.log` is the build these frames came from.

---

## The gather loop

`GatheringSystem` runs the whole cycle with **no phase field**. Which leg a
citizen is on is derived from whether it is carrying a full load, so there is no
stored phase that can fall out of step with the cargo it claims to describe. The
one persistent decision — *which node is mine* — lives on the unit as
`assignment`, and that is what makes gathering a loop rather than an errand the
player has to re-issue after every delivery.

A move order clears `assignment`. Without that, a citizen told to go somewhere
walks there and immediately turns around, which reads as the game ignoring the
player.

### Work stations

Each citizen has a fixed standing position on its node, a pure function of the
node and the unit's durable `EntityID`: six stations on a 2.28 m ring, 2.4 m
apart, just clear of a citizen's 1.15 m footprint.

This replaced a stand-off point computed from each unit's *own* position, which
meant four citizens sent from the same place all walked to the same place and
stood inside one another. Because a station never moves, a citizen returning
from a delivery walks back to the spot it left — it reads as its own working
position rather than a scramble for the nearest gap.

---

## The HUD

Two surfaces, both new, both anchored away from the centre of a landscape iPad:

- **Resource rail**, flush to the top edge with only its lower corners cut, so
  it hangs from the bezel instead of floating over the diorama.
- **Selection panel**, lower-left, absent entirely when nothing is selected.

Panels are chamfered rather than rounded. The Civilization Core is an octagon and
the whole world is flat-shaded facets; a rounded rectangle would read as generic
app chrome laid on top of it.

Each resource has a distinct **silhouette**, not just a tint — a leaf, a faceted
block, a spiked star, a concave star. Four warm-ish colours on a dark panel are
not enough separation for a glance, and are no separation at all for a
colour-blind player.

The rail pulses only on a jump of **two or more**. The Core trickles a fraction
of a unit per second; flashing on every change would make the rail twitch
permanently and point at nothing.

---

## Touch grammar as it now stands

| Gesture | Result |
|---|---|
| Tap a unit | Select it |
| Double-tap a unit | Select every unit of that kind **currently on screen** |
| Tap a node with citizens selected | Assign them to gather |
| Tap a node with nothing selected | Inspect it |
| Tap ground with units selected | Move order |
| Hold 0.22 s, then drag | Selection lasso |
| One-finger drag | Camera pan |
| Two fingers | Pinch zoom, twist yaw |

Plain drag stays camera pan because a touch RTS moves the camera constantly and
cannot afford a mode switch to do it — the hold is what buys the lasso. Double-tap
is detected by timestamp and distance inside the single-tap handler rather than by
`require(toFail:)`, so the single tap — the verb used hundreds of times a match —
keeps zero added latency.

Double-tap is scoped to the viewport, not the map: pulling in citizens from a
fragment the player is not looking at would silently abandon whatever they were
doing there.

---

## Defects found by looking, and fixed

1. **Selection panel spanned the full screen width.** The `Spacer` in its title
   row was greedy inside an unconstrained card. Fixed to a fixed 214 pt width —
   also the right answer regardless, since a panel that resizes as its own text
   changes between *Idle*, *Walking to Matter* and *Delivering Matter* jitters at
   exactly the moment the player is reading it.

2. **Starfield showing through the HUD.** At 0.82 opacity a star square landed
   inside the Lumen glyph and read as a chip out of the icon. Raising to 0.95 was
   not enough: the pixel was measured in the rendered build at rgb(21, 23, 32)
   against a panel of rgb(11, 13, 24) — a bright star bleeds through even 5% of
   alpha. The panel is now fully opaque, and *deeper* than `voidDeep` rather than
   equal to it, so it still reads as a panel over open space instead of vanishing
   into a background it happened to match. Re-measured after the fix: both sample
   points read rgb(5, 6, 13).

3. **Gatherers stood inside each other** — see *Work stations* above.

4. **"4 Citizen".** `displayName` was being printed for a count. `pluralName` is
   now written out per kind rather than derived by appending "s", because
   "Ranged" is already plural. A single-kind group also names itself in the title
   now (*4 Citizens*) instead of repeating the breakdown underneath.

5. **A node could not be inspected at all.** Tapping one with nothing selected
   used to clear the selection. It now answers the two questions that decide
   whether to send anyone: what is in it, and who is already on it.

---

## Corrections to earlier readings in this gate

- An early review pass recorded the citizen mesh as rendering "flat, roughly 3×
  wider than tall, like a crashed paper plane". That was wrong, and the cause was
  reading the portrait capture buffer without rotating it. Rotated, the same
  frame shows an upright figure with hood, ivory robe, two gold sash stripes, a
  teal faction chip, legs, arms and a gold gather haft. No mesh change was made
  or needed.

- A 13 fps reading noted earlier in the project was the FPS smoother at tick 8,
  not a real dip.

---

## Not proven — do not read these as passed

- **Frame-time and memory telemetry: Proof Pending.** The 60 fps figure is the
  app's own smoothed render-loop counter shown in the debug overlay. It is a live
  reading, not an instrumented profile. No Instruments trace has been taken.
- **The delivery pulse animation has not been observed.** The `+10` rise on the
  rail lasts 1.0 s. Screenshot round-trip through the MCP bridge is ~1.5 s and
  timed burst capture is blocked in this environment (see below), so no frame
  captures it mid-animation. The *delivery itself* is proven numerically by
  evidence 02; the animation is not.
- **No first-time-player timing run.** Nothing here measures boot → first
  completed building.
- **The deterministic tests still do not run.** They need `SunfoldCore` extracted
  as a SwiftPM package. Proof Pending, unchanged from G1.
- **Deposits have no selection ring in the world.** Inspection updates the panel
  but nothing on the node itself confirms the tap landed.

### Capture limitation

Timed burst / video capture via `xcrun simctl io screenshot` / `recordVideo` was
not used for this gate. Flowdeck is banned and must not be used as a substitute.
All evidence here is single frames via the argent bridge.
