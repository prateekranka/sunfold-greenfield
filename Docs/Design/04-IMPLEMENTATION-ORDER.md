# Implementation order

Part of the content design specification. Read `00-CONTENT-SPEC.md` first.

Nine checkpoints, ordered by **player-visible impact**, not by dependency convenience. Each
one is a separate cycle of the Gauntlet Loop with its own builder, its own fresh critic, and
its own installed-build capture.

**The single most important fact on this page**, established by playing the build on device
on 2026-07-31 and then confirming it by search rather than assuming it:

- There is **no production system.** `SkirmishSimulation` contains no `enqueue`, no queue, no
  `train`. `BuildingKind.trains` exists and declares what each building makes; **nothing
  reads it.** You cannot train a single unit. Population is frozen at 4/8 for the whole match.
- There is **no combat.** No `CombatSystem`, no HP on units in any fighting sense.
- There is **no opponent.** No AI type of any kind exists in `Sources/`.
- There is **no victory or defeat.** No match can end.

So the honest answer to "can a match be won or lost" is **no, and it cannot be until CP-G3e
closes.** The verb set the player actually has today is *select, move, gather, build three of
the seven buildings*. Everything before CP-G3e on this list is a prerequisite for a game
existing at all; everything after is breadth.

---

## The order

| # | Checkpoint | Why it is here | Closes when |
|---|---|---|---|
| 1 | **CP-G3a — Production** | You cannot make a unit. More basic than combat, and it unfreezes the entire economy | A Citizen is trained from the Core and population moves |
| 2 | **CP-G3b — Combat core** | Units that cannot fight are scenery | Two units fight, one dies, on camera |
| 3 | **CP-G3c — Tier-1 military roster** | An army needs more than one kind of soldier | Vanguard, Pathfinder, Quarrel trainable and countering |
| 4 | **CP-G3d — Adversary v0** | Without an opponent there is no match, only a diorama | The enemy gathers, builds, trains and attacks |
| 5 | **CP-G3e — Victory & defeat** | The locked promise is a match that resolves | A match ends, both ways, with a screen |
| 6 | **CP-G3f — Age progression** | Tier is what makes a roster feel like a tree | Voyager advances and visibly unlocks T2 |
| 7 | **CP-G3g — Tier-2 military** | Breadth: the counter graph is incomplete without Lancer and Walker | Lancer, Bastion Walker, Warding Post live |
| 8 | **CP-G3h — Uniques & faction identity** | The 40% differentiation | Sunlance and Ironsworn field, modifiers applied |
| 9 | **CP-G3i — Economy retune & repair** | Makes the T1 buildings mean something | Farm-as-node, Extractor aura, repair |

Wave boundaries: **1–3 = an army exists**, **4–5 = the match resolves**, **6–8 = breadth**,
**9 = the economy catches up**. Stop and report to the human after checkpoint 5, because that
is the first point at which there is a *game* to look at rather than a build.

**Prerequisite, running alongside checkpoint 1: P14.** No test in this repository has ever
executed — `xcodebuild test` dies at the app host, and the one recorded "10/10 passed" came
from an environment where `xcodebuild test` was hook-blocked. A root `Package.swift` exposing
`Sources/Domain` + `Sources/Simulation` as a testable `SunfoldCore` module fixes it. Until it
lands, **every determinism and counter-matrix bar below is unprovable**, and no checkpoint
from CP-G3b on should be called closed on a green build alone.

---

## 1. CP-G3a — Production

**Goal.** You can make a unit.

**Scope.** New `Sources/Simulation/ProductionSystem.swift` implementing
`02-BUILDING-ROSTER.md` §4: per-building FIFO queue, cost charged on enqueue, population
refusal with a stated reason, integer-tick progress on the front item only, deterministic
ring spawn resolved through `WorldMap`, cancel with the 100%/75% refund split. Unit costs and
build times added to `SkirmishTuning` **and nowhere else**. A selection-aware command grid
that shows a building's `trains` list. Formation Yard, Expansion Outpost and Dawn Loom given
build tiles — they exist as `BuildingKind` cases today and are unreachable.

**Bar.** Train three Citizens from the Core; population moves 4 → 7; Provisions falls by 150
at enqueue, not at spawn; build a Dwelling and train past the old cap.

**Evidence.** `Docs/QA/G3/cp-g3a/` — a recording of the queue filling and draining, captures
of the population moving, and a resource-ledger check.

**Critic question.** *Enqueue five units you cannot afford and cancel them at various stages.
Does the resource ledger ever end up wrong?*

---

## 2. CP-G3b — Combat core

**Goal.** Two units can fight and one can die.

**Scope.** New `Sources/Simulation/CombatSystem.swift` implementing `03-COMBAT-MODEL.md`
§1–§4 and §7. Extend `Unit` with `hp`, `maxHP`, `cooldownRemaining`, `currentTarget`,
`damageType`, `armorClass`, `meleeArmor`, `rangedArmor`. Add `UnitActivity.attacking`. Add
`.vanguard` to `UnitKind`. Attack-move and attack orders in `SelectionModel`. HP bars and a
hit flash in the renderer.

**Explicitly out.** Stances, ranged units, siege, buildings shooting, repair.

**Bar.** Order a Vanguard onto an enemy Citizen; it closes, strikes on a 1.1 s cadence, the
citizen dies at the tick the model predicts, population frees. Determinism test: identical
tick-by-tick HP trace over two runs from seed `20260726`.

**Evidence.** `Docs/QA/G3/cp-g3b/` — landscape capture mid-fight, capture post-death, test
output, and an HP trace diff.

**Critic question.** *Does the fight read? Can you tell, from the capture alone and without
the HUD, which unit is attacking, which is being hit, and how hurt each one is?*

---

## 3. CP-G3c — Tier-1 military roster

**Goal.** You can build an army.

**Scope.** `.formationYard` and `.lumenSpire` `BuildingKind` cases with the costs in
`02-BUILDING-ROSTER.md` §1. `.pathfinder` and `.quarrel` `UnitKind` cases. Ranged attack
(the `range` branch of §3 step 4). Prerequisite gating with a named reason on the dimmed
tile. The two-page command grid from §6. Rally points. Cost-on-enqueue.

**Bar.** From a fresh start: build a Formation Yard, train two Vanguard and a Pathfinder,
build a Lumen Spire, train three Quarrel, and walk all six across the map as a group. No
resource desync, no phantom queue, no unit spawning inside terrain.

**Evidence.** `Docs/QA/G3/cp-g3c/` — a screen recording of that whole sequence, plus a
resource-ledger assertion test.

**Critic question.** *Is a player who has never seen this game told, at every point, why a
building they cannot build is unavailable?*

---

## 4. CP-G3d — Adversary v0

**Goal.** There is somebody on the other side of the map.

**Scope.** New `Sources/Simulation/Adversary.swift`. Fully deterministic, driven only by
tick count and world state, drawing from a **new tagged `adversary` random stream**. A
schedule, not a planner: gather with its starting citizens, train citizens to 12, place a
Formation Yard around tick 2400 (2:00), a Lumen Spire around tick 4800, and send attack
waves at rising size on a fixed cadence. It plays the same opening every time, which is
correct for v0 — a legible opponent that a player can learn to beat is worth more than a
clever one they cannot read.

**Explicitly out.** Difficulty levels, adaptation, expansion, transports, siege.

**Bar.** Two full runs from seed `20260726` with no player input produce an identical world
hash at tick 12000. The first wave arrives between 3:30 and 4:30 and is beatable by a
player who built five Vanguard.

**Evidence.** `Docs/QA/G3/cp-g3d/` — world-hash test output for both runs, a capture of the
first wave arriving, and a wave-timing log.

**Critic question.** *Play against it. Is losing to it ever confusing — that is, does it
ever kill you with something you had no way to see coming?*

---

## 5. CP-G3e — Victory & defeat

**Goal.** The match ends. **This is the checkpoint that makes this a game.**

**Scope.** New `Sources/Simulation/VictorySystem.swift` implementing `00-CONTENT-SPEC.md`
§6: Conquest (Core destroyed) and Dominion (hold the central Spire 180 s, contested pauses,
escalating to 120 s at 8:00 and 60 s at 10:00). A match clock. A Dominion progress readout
in the HUD, visible from the first second so the second win path is discoverable. An
end-of-match overlay naming which condition fired, with a restart.

**Bar.** Win by Conquest. Win by Dominion. Lose by Conquest. All three end cleanly, with
the correct condition named and no simulation running behind the overlay.

**Evidence.** `Docs/QA/G3/cp-g3e/` — three captures, one per outcome, plus victory-condition
unit tests including the contested-pause and escalation cases.

**Critic question.** *At 6:00 into a match, can the player tell how they are doing and what
they should do about it?*

---

## 6. CP-G3f — Age progression

**Goal.** Advancing to Voyager visibly changes the game.

**Scope.** `.dawnLoom` building. The Voyager research (20 s channel, cost and refund per
`00-CONTENT-SPEC.md` §4). `Age` gating enforced on every command tile. Aether gathering
verified end-to-end from an Expansion Outpost. A civilization-wide visual and audio beat on
advance — this is the moment the player has been working toward and it must land.

**Bar.** From a fresh start: expand, gather Aether, build a Dawn Loom, advance, and watch
three T2 tiles undim. Under nine minutes.

**Evidence.** `Docs/QA/G3/cp-g3f/` — before/after command-grid captures, the advance moment
recorded, a timed run log.

**Critic question.** *Does advancing feel like an achievement or like a menu action?*

---

## 7. CP-G3g — Tier-2 military

**Goal.** The counter graph closes.

**Scope.** `.strideYard` + `.lancer`. `.siegeFoundry` + `.bastionWalker` (with `building`
armour class and the `+45 vs building` bonus). `.wardingPost` with the tower attack and
`+6 vs siege`. Stances from `03-COMBAT-MODEL.md` §5. The full bonus-damage table live.

**Bar.** Every counter in `01-UNIT-ROSTER.md` §2 demonstrated in a unit test at the
predicted time-to-kill, ±1 tick. A Bastion Walker takes a Warding Post; three Warding Posts
take a Bastion Walker first.

**Evidence.** `Docs/QA/G3/cp-g3g/` — the counter-matrix test output as a table, plus a
capture of a mixed-arms engagement.

**Critic question.** *Can you tell the five unit kinds apart at normal camera height, in
motion, without selecting anything?*

---

## 8. CP-G3h — Uniques & faction identity

**Goal.** The two civilizations play differently.

**Scope.** `.emberHall` with its two faces. `.sunlance` and `.ironsworn`. Every faction
modifier from `00-CONTENT-SPEC.md` §5 applied in one place, as data, not scattered
conditionals. Livery enforced per `Docs/Concepts/00-visual-bible.md`.

**Bar.** A blind A/B: two captures of comparable armies, one per faction. A viewer who has
not read the spec names which is Sunwoven. Run through `Docs/Gauntlet/tools/framestat.py pair`.

**Evidence.** `Docs/QA/G3/cp-g3h/` — the sealed pair, `answer.txt` opened after the verdict.

**Critic question.** *Is the difference a stat sheet or something you can see?*

---

## 9. CP-G3i — Economy retune & repair

**Goal.** The tier-1 buildings earn their cost.

**Scope.** Farm becomes a placeable Provisions node (`02-BUILDING-ROSTER.md` §3). Matter
Extractor gets the 14 m / +20% aura with a visible radius while placing. `.waystation`.
Dwelling retuned to cap 10 / +8 / 55 Matter. Repair per `03-COMBAT-MODEL.md` §8. Gather
rates and costs reconciled against `00-CONTENT-SPEC.md` §3 in one pass.

**Bar.** A nine-minute match reaches roughly 40 population with four Dwellings and never
stalls on a resource the player was actively gathering.

**Evidence.** `Docs/QA/G3/cp-g3i/` — a resource-over-time plot from a scripted run, plus a
repair capture.

**Critic question.** *Is there a moment in the first three minutes where the player has
nothing useful to do?*

---

## Parallelisation

Checkpoints 1–5 are **strictly serial**: each depends on the one before, and all five touch
`SkirmishSimulation`.

Checkpoints 6–9 have largely disjoint file sets and can overlap two at a time, subject to the
two standing constraints: the **simulator lease** in
`Docs/Gauntlet/workbench-data.json → simLease` is held by one agent at a time, and **no two
builders hold the same file**. The safe pairing is **7 with 9** — 7 lives in combat and
military `BuildingKind`s, 9 lives in gathering and economic ones. 6 and 8 both touch `Age`
and the command grid and must not run together.

**P14 (the SwiftPM test harness) and CP-G2b-NAV (camera navigation) are disjoint from all of
the above** and are running in parallel with checkpoint 1 right now.

## Content that is specified and deliberately not scheduled

Named here so no one mistakes absence for oversight: **walls and gates**, a **market or
resource trading**, **unit upgrades** (veterancy or +1 armour lines), **more than two
ages**, **naval combat**, and **formations**. Each is a legitimate Age of Empires idea. Each
is also a tech-tree-sprawl risk that `ROADMAP.md` forbids, and none of them is worth
anything until a match can be won and lost. Revisit after checkpoint 8, not before.
