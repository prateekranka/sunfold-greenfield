# CP-C4 — Victory and defeat · 2026-08-01

**A match can now be won and lost, and both were watched happening on the iPad.**
Two win paths, a terminal state that genuinely stops the world, and a Play Again
that rewinds it. Every claim below is evidenced; none is taken from a green build.

Spec: `Docs/Design/00-CONTENT-SPEC.md` §5, overridden where they disagree by
`Docs/Design/05-RESOLUTIONS-R1.md` §3 (B10).

---

## The bars

| Bar | Result |
|---|---|
| Conquest ends the match, both directions | **PASS** — `01-defeat-by-conquest.png` (5:59) and `03-victory-by-conquest.png` (15:55) |
| Dominion ends the match on a 45 s hold | **PASS** — `02-victory-by-dominion.png`, overlay at **45s / 45s**, match time 3:55 |
| Contested **decays at half the fill rate**, per B10.3 | **PASS (test only)** — `testContestedProgressDecaysAtHalfTheFillRateRatherThanPausing`, `testMutualOccupationDrainsBothSidesAndCannotDeadlock`. Never observed in play — see *What is not proven* |
| The Spire is neutral and indestructible | **PASS** — `testTheSpireCannotBeDamagedEvenWhenOrderedAttackedPointBlank`, `testNothingEverAcquiresTheSpireAsATarget` |
| The hold requirement shortens with match time | **PASS** — asserted in test, and visible on device: `03-…png` reads **`0s / 20s`** at 15:55 |
| A finished match stops stepping | **PASS** — `testAFinishedMatchStopsSteppingEntirely`, and on device the accessibility tree was polled at 1 Hz for **12.0 s** with the overlay up and the match clock read `Match time 5:59` on every poll |
| Resignation is named honestly, not reported as a Conquest | **PASS** — `04-defeat-by-resignation.png` reads *DEFEAT · RESIGNATION · Sunwoven resigned.* |
| Play Again rewinds to the opening state | **PASS** — `06-play-again-restarted.png`: clock **0:01**, POP **4/10**, stock back to 180 / 160 / 40, no stale entities |
| Determinism survives the new system | **PASS** — two no-input runs stop on the same tick with the same outcome and the same fingerprint |

`swift test` → **72 tests, 0 failures**, up from 49 at CP-C3.
`./scripts/agent-build.sh cp-c4-close` → `** BUILD SUCCEEDED **`.

| Suite | Tests |
|---|---|
| VictoryTests (new) | 20 |
| AdversaryTests | 11 (was 10) |
| ConstructionIntegrityTests | 12 (was 10) |
| DeterminismTests | 21 |
| CombatTests | 8 |

---

## The determinism fingerprint changed, and why

CP-C3's bar was *"one world hash at tick 12000: `a9ee7bc2faeea255`"*. **Both halves of
that sentence are now obsolete**, and the change is expected rather than a regression:

- **Tick 12000 is unreachable.** The adversary destroys the untouched player's Core at
  **tick 7192 (5:59)**, and a finished simulation refuses to step. The bar is now
  measured over the whole match — both runs must stop on the *same tick* with the
  *same outcome* and the *same hash*.
- **The hash moved to `4645f2d24d31018c`** because the world itself changed: the
  Dominion Spire is now a building folded into `WorldHash`, and the Dominion
  fragment's deposits were pushed outside the Spire footprint so a Matter node
  cannot sit inside the objective.

`testTwoNoInputRunsShareOneWorldHashForTheWholeMatch` asserts the new form.

**Two stale captions were fixed in the same pass.** The diagnostic printed
`=== Gravemark at 10:00 ===` and `=== world hash at tick 12000 ===` while the run
now stops at 5:59. That output gets pasted into STATUS docs as evidence, so both
captions are now computed from the clock. They read `Gravemark at 5:59` and
`world hash at tick 7192`.

---

## The defect this checkpoint found on the way

**Three of the six buildings could not be placed at all.** CP-C1 gave the Formation
Yard, Expansion Outpost and Dawn Loom command tiles — lit, priced, tappable — while
`ConstructionPlacement.placeableKinds` still listed only the three CP-G2a kinds.
`beginBuildGhost` bounced off that list silently, so all three tiles did nothing.

This is in CP-C4's scope rather than a separate ticket because **the Formation Yard
is the only building that trains a military unit**. Without it the player can field
no Vanguard, and with no Vanguard there is no Conquest *and* no Dominion — neither
win path was reachable by a player. Found on device while trying to build the Yard
that trains the unit that captures the Spire.

Two rules now hold the line, in `ConstructionIntegrityTests`:

- `testEveryBuildingWithAPriceCanActuallyBePlaced` — if it has a cost, a citizen can
  put it down.
- `testNothingFreeIsPlaceable` — the mirror, so a stray addition cannot hand the
  player a free Civilization Core or the objective itself.

---

## Decisions the spec did not make

Named rather than buried.

1. **`canCaptureDominion` is its own list, not `isMilitary`.** R1 §3 (B10.2) asks for
   an explicit capture set. The two lists are identical today, which is exactly the
   trap: `isMilitary` answers a *combat* question, and reusing it would silently
   answer a *victory* question every time a unit is added. The spec's set is
   Vanguard, Quarrel, Lancer, Bastion Walker, Sunlance and Ironsworn; the last four
   do not exist yet, so this list grows with the roster at CP-C5.
2. **`Building.faction` became `Faction?` rather than gaining a `.neutral` case.** A
   third faction case would flow into every `for faction in Faction.allCases` loop in
   the project — resource stocks, population, the Core trickle — and give the Spire a
   treasury. `nil` makes the compiler ask the ownership question at each site.
3. **Resign lives on the objective rail, not in a pause menu.** §5 puts it in a pause
   menu; there is no pause menu. Leaving `resign()` unreachable would have made it
   dead code, and an unproven end state is the exact thing this project keeps
   getting wrong. It is two taps (RESIGN → CONFIRM) because a one-tap resign beside
   a live HUD is a trap.
4. **`AlertStrip` was deleted, not extended.** It printed the same seeded sentence —
   *"Light transport docked at home rim"* — for an entire match whatever happened.
   `ObjectiveRail` replaces it with the match clock, both Dominion timers, both Core
   meters and a live alert line.
5. **The Spire's 1200 HP is authored and inert.** It is indestructible by rule, so
   nothing ever reads that number down. Kept at R1's value rather than dropped, so
   the day it becomes destructible the number is already right.

---

## Device evidence

Installed and played on `75898CE1-…` (Sunfold Cycle 1 iPad Air 13, iPadOS 26.5),
landscape.

| Frame | Shows |
|---|---|
| `00-objective-rail-opening.png` | Opening at 0:30: the neutral Spire standing on the Dominion fragment inside its capture ring, rail reading `DOMINION 0s / 45s` and both Core meters full |
| `01-defeat-by-conquest.png` | **DEFEAT · CONQUEST** at **5:59** — *"Sunwoven's Civilization Core was destroyed."* The no-input match CP-C3 could only watch run over the corpse |
| `02-victory-by-dominion.png` | **VICTORY · DOMINION** at **3:55**, rail reading **`45s / 45s`** — *"Sunwoven held the Dominion Spire."* |
| `03-victory-by-conquest.png` | **VICTORY · CONQUEST** at **15:55** — *"Gravemark's Civilization Core was destroyed."* Rail reads **`0s / 20s`**: the escalation ladder, visible |
| `04-defeat-by-resignation.png` | **DEFEAT · RESIGNATION** — *"Sunwoven resigned."* Not reported as a Conquest that never happened |
| `05-defeat-under-live-adversary.png` | The same ending arriving under a live opponent rather than a forced one |
| `06-play-again-restarted.png` | **After tapping PLAY AGAIN**: clock **0:01**, POP **4/10**, stock back to 180 Provisions / 160 Matter / 40 Lumen, the Spire back, nothing left over from the finished match |

**The world really stops.** With a Conquest defeat overlay up, the accessibility
tree was polled once a second for **12.0 s**. `Match time 5:59` on every one of the
thirteen reads, in both the objective rail and the overlay. The overlay is not a
panel over a running world.

**Restart replays the seed, and that was observed rather than assumed.** The match
restarted by `06-play-again-restarted.png` was left running untouched and resolved
on its own to **DEFEAT · CONQUEST at 5:59** — the same outcome, at the same match
time, as the first run and as `testAnUntouchedMatchAgainstTheAdversaryNowResolves`
(tick 7192). Play Again is a genuine rewind, not a partial reset.

> **Correction to commit `3f63da9`.** That message says the clock "held at 0:21
> across two accessibility reads seven seconds apart". The two 0:21 observations
> were in fact one screenshot and one accessibility read, 7.4 s apart — the
> conclusion held, the method description did not. The 12.0 s / 1 Hz measurement
> above was taken afterwards to replace it and is the number to cite.

---

## What is **not** proven

Recorded so it is a known gap, not a surprise.

- **The 8–10 minute promise is not met by either observed match.** The no-input match
  resolves at **5:59** and the played Conquest took **15:55**. The escalation ladder
  exists and was seen working (`0s / 20s` at 15:55), but no measured match has landed
  in the promised window. The ladder shortens the *Dominion* requirement; it does
  nothing to the time it takes to walk an army across the map and chew through a
  600 HP Core, which is what 15:55 was mostly spent on. This is a pacing question for
  CP-C5/CP-C9, not a victory-rules question.
- **The contest rule has never been seen in play.** Decay-at-half-rate and the
  no-deadlock property are test-proven only. A *contest* needs both sides in the
  ring at once, and that has never happened on a device: the player has never had
  a unit there while Gravemark did. This is the single largest untested surface in
  CP-C4.
- **The adversary banks Dominion progress by accident, and nobody designed that.**
  Measured on device at the end of the observed no-input match: the rail read
  *"Dominion: you 0 of 45 seconds, **enemy 11**"*. CP-C3 routes every wave via the
  Dominion centre because there is no pathfinder, so waves walk through the capture
  ring on their way to the player's Core and fill the Gravemark timer while they
  pass. Eleven seconds of forty-five is a long way from a win, and this run ended by
  Conquest first — but the number is not zero, it was never intended, and nothing
  caps it. A slower Conquest or a wave that stalls on the objective could hand
  Gravemark a Dominion victory that no schedule ever asked for. **Worth a decision
  before CP-C5**, and it is a live example of exactly the failure the checkpoint
  question asks about: losing to something the player could not see coming.
- **Play Again does not reset `timeScale`.** Restarting after a match played at 3×
  starts the new match at 3×. Deliberate-looking rather than deliberate — nobody
  decided it. The device capture was taken at 1×, so the interaction is unobserved.
- **The CP-C3 camera jump is unexplained, and CP-C4 did not explain it.** CP-C3 logged
  the camera moving to the Gravemark base on its own around the moment the Sunwoven
  Core died, and suggested CP-C4 would settle what the camera does when a Core dies.
  It does not: the only new `setFocus` is on **restart**, which puts the camera back
  on the player's Core. Nothing in CP-C4 moves the camera on a Core's death. Not
  reproduced this session; still open.
- **A clean checkout still does not build.** Committed call sites reach untracked
  definitions under `Sources/Diagnostics/` and `Sources/Simulation/BoardingSystem.swift`.
  CP-C4 deliberately did **not** deepen this: the perf-overlay hunks in `RootView.swift`
  and the frame-pacing hook in `SunfoldRealityView.swift` were left out of the commit
  even though they sit in files CP-C4 otherwise touched. See *Commit boundary* below.
- **No `-sunfoldPerf` smoke was taken.** BC-02 allows a cheap smoke at checkpoint
  close; the session brief says not to touch performance, and the perf harness is
  another agent's uncommitted work. Skipped deliberately, as at CP-C3 — not forgotten.
- **Nobody has played a full defended match to a Dominion win against a live
  adversary.** `02-victory-by-dominion.png` was won at 3:55, before the first wave
  arrives at 4:27. The Dominion path has not been tested under pressure.

---

## Commit boundary

Committed narrowly by explicit path. `RootView.swift` carries both CP-C4 work and
another agent's perf overlay, so the **index was staged surgically**: the committed
version has `MatchOverlay`, `ObjectiveRail` and the outcome animation, and does not
have `PerfOverlay` / `PerfLaunchFlags` / the `perfDensity` pass-through. The working
tree is untouched and still builds with the perf overlay present.

Left uncommitted and unmodified: `Sources/Diagnostics/`, `Sources/Rendering/FramePacing.swift`,
`Sources/Simulation/BoardingSystem.swift`, `Sources/App/SunfoldGreenfieldApp.swift`,
`Sources/App/Info.plist`, `project.yml`, `scripts/`, the app-icon assets,
`Resources/PrivacyInfo.xcprivacy`, `Docs/QA/Perf/`, `Docs/QA/Launch/`, `Docs/Method/`,
`Docs/agents/`, `Docs/research/` and `CONTEXT.md`.
