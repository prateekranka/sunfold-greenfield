# CP-C3 — Adversary v0 · and the close of CP-C2 · 2026-07-31

**There is now somebody on the other side of the map, and combat has been seen to
happen.** Both claims are evidenced below; neither is taken from a green build.

Spec: `Docs/Design/04-IMPLEMENTATION-ORDER.md` §4 (CP-G3d), overridden where they
disagree by `Docs/Design/05-RESOLUTIONS-R1.md` §5 (B11).

---

## The bars

| Bar | Result |
|---|---|
| Two no-input runs from seed `20260726` produce one world hash at tick 12000 | **PASS** — `a9ee7bc2faeea255` both runs, and the two event logs are identical line for line |
| First wave arrives between 3:30 and 4:30 | **PASS** — arrives **4:27** (tick 5340), 3 s inside the bar |
| The wave is beatable by a player with ~five Vanguard | **Not measured** — see "What is not proven" |
| Combat observed in play (CP-C2′) | **PASS** — first blood 4:30, first kill 4:33, Core destroyed 5:59, all with **no player input** |

`swift test` → **49 tests, 0 failures**, up from 39. Ten are new.

---

## What the adversary does

A schedule, not a planner. Every decision is a pure function of the tick count and
the world state; there are **no random draws at all**, so the tagged `adversary`
stream is reserved and deliberately unused — R1 §5 fixed the schedule with no
jitter, and borrowing that stream later would shift every number here.

The measured match, seed `20260726`, map `riverlands`, nobody touching the player:

```
[0:28] Dwelling committed (population 8/10)
[2:00] Formation Yard 1 committed
[4:00] Formation Yard 2 committed
[4:00] Wave 1 dispatched: 3 Vanguard → Sunwoven Civilization Core #1
[4:00] Dwelling committed (population 16/18)
[4:27] Wave 1 ARRIVED on Sunwoven home ground
[4:30] First blood — a unit is below full life
[4:33] Sunwoven unit killed (5 → 4)
[4:36] Sunwoven unit killed (4 → 3)
[4:37] Sunwoven Core under attack
[5:30] Wave 2 dispatched: 2 Ranged, 4 Vanguard → Sunwoven Civilization Core #1
[5:30] Dwelling committed (population 24/26)
[5:54] Wave 2 ARRIVED on Sunwoven home ground
[5:59] Sunwoven Core DESTROYED
[6:01] Sunwoven unit killed (3 → 2)
[6:04] Sunwoven unit killed (2 → 1)
[7:00] Wave 3 dispatched: 3 Ranged, 4 Vanguard → no target
[7:00] Dwelling committed (population 32/34)
[8:30] Wave 4 dispatched: 4 Ranged, 5 Vanguard → no target
[10:00] Wave 5 dispatched: 5 Vanguard → no target
```

Full run, including the closing economy state:
[`adversary-test-run.txt`](adversary-test-run.txt).

**Waves 1 to 4 field exactly what R1 §5's table asks for**, for every unit this
roster has. That is asserted, not eyeballed —
`testWavesLeaveOnScheduleAndFieldWhatTheTableAsksFor` compares the dispatched
roster against `Adversary.composition(ofWave:)` cell by cell and also asserts the
sizes never shrink.

---

## Rows of the spec this build cannot honour yet

Named rather than fudged. Nothing was substituted for a unit that does not exist:
the cells are **dropped**, so the wave that finally fields a Lancer will be a
visible change rather than a silent one.

| Spec row | Why it is not here | Owed to |
|---|---|---|
| Wave 3 · 2 Lancer | `UnitKind` has no `.lancer` case | CP-C5 |
| Wave 4 · 2 Lancer, 1 Bastion Walker | no `.lancer`; nothing trains `.bastionWalker` (no cost, no build time) | CP-C5 |
| tick 4800 · Lumen Spire | `BuildingKind` has no `.lumenSpire` case | CP-C5 |
| tick 7200 · Dawn Loom, then Voyager | the building exists, the research does not — committing 130 Matter to it would only starve the waves | CP-C6 |
| tick 9600 · Stride Yard | `BuildingKind` has no `.strideYard` case | CP-C7 |

Directive 3 forbids inventing any of them in Swift, and none was invented.

**Two schedule decisions the spec did not make**, both forced by measurement and
both recorded here so they are reviewable:

1. **A second Formation Yard at tick 4800**, standing in for R1's Lumen Spire row.
   That row exists to open a second production line. With one Yard, wave 5 came
   out *smaller* than wave 4 — one building produces about seven units in the
   90 s between waves, and the table stopped rising. The Spire cannot be built;
   the slot is spent on the production building that can.
2. **Dwellings on a population rule.** R1's economy schedule never mentions
   housing, and a cap of 10 cannot hold twelve citizens, let alone twelve and an
   army. Four Dwellings, committed when headroom drops to two. Four is measured,
   not chosen: at three the adversary jammed at 34/34 population and dispatched
   wave 5 empty with 340 Matter still in the bank.

---

## The economy limit, and where it comes from

By 10:00 the Gravemark home fragment is **dug out** — 0 Matter and 0 Lumen left in
the ground. That is why wave 4 fields four Quarrels rather than the table's four
plus two Lancers' worth of pressure, and why wave 5 is Vanguard-only.

This traces to a decision that is already made and not yet implemented: **R1 §2
(B4/B5) raised home yields to 700 Matter and 550 Lumen** precisely because the
building bill does not fit inside 420 and 300. `WorldPopulator.startingYield` is
still at the old numbers. Raising it changes the player's economy too and belongs
to **CP-C9 — economy retune**, not here. Until then the adversary's ceiling is the
fragment's, which is honest but is a known limit rather than a design.

---

## The adversary is granted nothing

Two independent guarantees, because "the AI must never receive hidden income" is
the oldest claim in this project's test suite and it has to survive an AI existing.

1. **Structural.** `Adversary.plan` receives `stock` **by value**. It cannot write
   to a resource pool. Every unit it trains and every building it places is
   charged by `SkirmishSimulation` through `enqueueUnit` / `placeBuilding` — the
   same methods a player's tap reaches.
2. **Measured.** `testTheAdversaryMatterLedgerCloses` reconstructs Gravemark's
   Matter balance from first principles at tick 4000 — starting stock, plus the
   shared Core trickle, plus exactly what came out of its own deposits, minus
   cargo still on a citizen's back, minus the cost of every building standing and
   every unit alive or queued — and asserts the books close to 0.5 units.

`DeterminismTests.testBothFactionsReceiveTheIdenticalCoreTrickle` now runs with
the adversary **frozen** (`adversaryEnabled: false`). That is not a weakened test:
Gravemark now spends from the first seconds, so a running adversary makes the two
balances differ for a reason that has nothing to do with income, and the claim
under test is the grant. The comment in that test says so, and points at the
ledger test above for the other half.

---

## Device evidence — and the close of CP-C2

Installed and played on `75898CE1-…` (Sunfold Cycle 1 iPad Air 13, iPadOS 26.5),
landscape, **no player input at any point** beyond the speed control and one tap
to select the Core and read its life.

| Frame | Shows |
|---|---|
| `01-opening-no-input.png` | Fresh match: Sunwoven Core, four citizens, POP 4/10 |
| `02-wave-1-engaging.png` | Paused at **4:32**, POP **3/10** — one citizen already dead, a Gravemark Vanguard in the settlement |
| `03-fight-crop.png` | Native-resolution crop of that frame: the Vanguard standing over a Sunwoven citizen whose **health bar is visibly part-drained** |
| `04-core-under-attack.png` | Paused at **5:16**, the Vanguard striking the Core |
| `05-core-life-readout.png` | Crop of the selection panel: **Civilization Core · SUNWOVEN · 303 / 600**, meter half gone |
| `06-gravemark-base-built.png` | The adversary's own base: Core, **two** Formation Yards, Dwellings and a standing army it built and paid for |
| `07-player-wiped-pop-zero.png` | POP **0/10**, the Core gone — every Sunwoven citizen dead and the settlement taken |

**This closes CP-C2 as CP-C2′.** The thing CP-C2 refused to claim was that combat
had ever been *seen* to happen. `05-core-life-readout.png` is a number falling on
a real device in a real match, and `03-fight-crop.png` is a unit's health bar
draining next to the thing draining it. Neither is a test result.

**A capture technique worth keeping.** At 3× speed every tool round-trip costs
roughly ten seconds of match time, which is how the first two attempts sailed past
the fight and photographed the aftermath. What works is one `run-sequence` that
waits on a *state change* and then pauses in the same call — here,
`await-ui-element` on the population label going from "Population 4 of 10" to
anything else, immediately followed by a tap on Pause. That froze the match on the
tick of the first kill with no timing luck involved, and everything after it was
captured at leisure against a stopped clock.

---

## What is **not** proven

Recorded so it is a known gap, not a surprise.

- **"Beatable by a player with five Vanguard" is unmeasured.** It needs a played
  defence, and the player cannot yet train a Vanguard without first building a
  Formation Yard — which is a CP-C5 flow, not a CP-C3 one. What *is* measured is
  the other half of the same question: three Vanguards take 82 s to bring down an
  undefended 600 HP Core, which is long enough for a defence to exist.
- **The critic question is unanswered.** *"Play against it. Is losing to it ever
  confusing — does it kill you with something you had no way to see coming?"*
  There is no fog of war, no attack alert and no minimap warning, so the honest
  answer today is that the wave is visible on the minimap the whole way and
  nothing arrives unannounced — but nobody has played a defended match yet.
- **An unexplained camera jump.** During the second device run the camera moved
  from the player's settlement to the Gravemark base on its own, at roughly the
  moment the Sunwoven Core was destroyed. `Minimap.goToCore` is not the cause — it
  guards on the viewer's own faction and returns silently when that Core is gone,
  which is exactly what a later tap did. Not reproduced on the third run. Logged
  here rather than guessed at; worth one look during CP-C4, which is the
  checkpoint that has to decide what the camera does when a Core dies.
- **No `-sunfoldPerf` smoke was taken.** The session brief says not to touch
  performance. BC-02's checkpoint-close smoke is therefore skipped deliberately,
  not forgotten.
