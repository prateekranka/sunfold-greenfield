# Review 01 — content design specification

Fresh critic. Reviewed `00-CONTENT-SPEC.md`, `01-UNIT-ROSTER.md`, `02-BUILDING-ROSTER.md`,
`03-COMBAT-MODEL.md`, `04-IMPLEMENTATION-ORDER.md` against the code at
`Sources/Domain`, `Sources/Simulation`, and `ROADMAP.md`. No plan, summary or rationale
about the spec was read.

Every number below was computed, not estimated. Two throwaway harnesses were compiled
against the real `Sources/Domain` + `Sources/Simulation` (nothing in the repo was modified):

- an **economy probe** that runs the real `SkirmishSimulation` at 20 Hz and measures
  delivered resources per citizen per node on `riverlands`, seed `20260726`;
- a **combat probe** that implements `03-COMBAT-MODEL.md` §1–§4 exactly — 20 Hz, integer-tick
  cooldowns, `max(1, (base + bonus) − armour)`, no variance, ascending-`EntityID` iteration,
  deaths applied at end of tick, nearest-hostile targeting with a lower-`EntityID` tiebreak —
  and runs the roster against itself.

---

## 1. VERDICT

**REVISE.**

Not `REJECT`: the skeleton is sound and several of its structural decisions are better than
what a typical spec at this stage produces (§5). Not `ACCEPT_WITH_FIXES`: the defects are not
at the margins. The combat model cannot express its own bonus table, two files disagree about
the armour class of four of nine units in a way that flips five matchups, the home fragment
cannot pay for the building list, one third of the counter ring is a 1-HP coin flip, the T2
mounted line is deleted at equal population by a cheaper T1 unit, and both victory paths
require a traversal rule that appears in none of the five files. These require another
authoring pass, not patches during implementation.

---

## 2. THE SINGLE LARGEST GAP

**Nothing in the game can leave the region it spawned in, and the specification never
notices.** Every promise in all five files — Conquest, Dominion, the Aether age gate, the
adversary's attack waves, "arriving with Ironsworn and siege into a base that cannot stop
them" — requires a unit to cross a region boundary. No file states how that happens.

The evidence, from the real simulation:

```
=== CROSS-REGION LAND MOVEMENT TEST ===
  citizen #2 starts at (-43.0, 3.2) in sunwovenHome
  ordering it to the Dominion centre (0.0, 0.0)
  after 240 s: (-21.3, 1.6) region sunwovenHome  distance to Dominion centre 21.4 m
  distance travelled: 21.7 m (a citizen at 3.4 m/s could cover 816 m in 240 s)

=== IS THE LAND BETWEEN sunwovenHome AND dominion CONTINUOUS? ===
    t=0.00  ( -43.6,  -6.1)  land=yes  region=sunwovenHome
    t=0.55  ( -19.6,  -2.8)  land=yes  region=dominion
```

The unit stopped dead at the region boundary after 21.7 m of an 816 m budget. There is no
water in the way — the land is continuous across that seam. The blocker is `MovementSystem`:

```62:68:SunfoldGreenfield/Sources/Simulation/MovementSystem.swift
        guard let region = unit.region else { return proposed }
        return map.clampToLand(
            proposed,
            from: current,
            in: region,
            margin: unit.kind.footprintRadius
        )
```

`clampToLand(in:)` calls `isStandable` → `contains(point, in: region)` → `region(at:) == id`.
Nothing in the codebase ever updates `Unit.region` during movement. `Causeway` exists in
`WorldMap` but is consumed only by `WorldScene`, `TerrainDressing` and `Minimap` — it is
scenery. `orderBoard` rejects every non-citizen (`unit.kind.canGather`), so military units
cannot be ferried either, and `BoardingSystem` has an `embark` and **no disembark** —
`unit.region = nil` on boarding and is never restored.

So today: no army can reach the enemy Core, no unit can stand at the Dominion, and no citizen
can reach Aether. Conquest, Dominion and Voyager are all unreachable for the same reason.

**Why this and not the damage-formula bug or the resource shortfall.** Those two are worse
*numerically*, but both are contained and both are self-announcing. A builder implementing
CP-G3a hits the bonus-keying problem on the checkpoint's own bar ("the citizen dies at the
tick the model predicts") and stops. A builder implementing CP-G3h hits the Lumen shortfall
against the bar "never stalls on a resource the player was actively gathering" and stops.
Each is one edit to one table.

Traversal is different in kind, because it is *absent* rather than wrong, so no checkpoint
owns it, and because it is the decision every other number leans on. Whether crossing is by
causeway, by transport, or by removing the region clamp determines whether the Dominion neck
is a chokepoint, whether the Light Transport is logistics or decoration, whether "Gravemark
defensive rings" have anything to ring, how far a raid has to walk (which is most of the
Pathfinder's and Lancer's value), and what the adversary's wave schedule can even mean.
`04-IMPLEMENTATION-ORDER.md` makes checkpoints 1–4 strictly serial and says to stop and report
to the human after checkpoint 4, "because that is the first point at which there is a *game*
to look at". On the current spec, that report would be delivered on a build where the two
players cannot touch each other — after three checkpoints of serial work, all of which pass
their own stated bars. That is the most expensive place to discover a missing design decision.

The fix is a paragraph, not a rewrite: state the crossing rule (my recommendation: land units
may cross a boundary wherever `landField > 0` on both sides, i.e. delete the region clamp and
keep `Unit.region` as a derived label; keep the transport for water only), state that military
units may board, and state disembark. Then schedule it *before* CP-G3c, because the adversary
cannot be specified without it.

---

## 3. BLOCKING DEFECTS

### B1 — `03-COMBAT-MODEL.md` §1/§2: the damage formula cannot express the roster's bonus table, and the literal reading gives archers `+45 vs building`

§1 defines the formula as

```
effective = max(1, (base + bonus(attacker.damageType, target.armorClass)) - armor(target, attacker.damageType))
```

and §2 confirms it: "Bonus damage is a lookup on `(damageType, armorClass)` … The full table
lives in `01-UNIT-ROSTER.md` §3; it is data, not code."

But `01-UNIT-ROSTER.md` §3's bonus column is keyed **per unit**, not per damage type. There are
only three damage types and nine units, so the lookup collapses whole groups into one row.
Under 01 §3's own damage types, `ranged` = {Quarrel, Bastion Walker, Sunlance}, so the
`(ranged, building)` cell must hold the Walker's `+45`. Therefore:

| | |
|---|---|
| Quarrel → Civilization Core, as the spec intends | `max(1, 6 − 6)` = **1** damage, 838 s |
| Quarrel → Civilization Core, under the formula as written | `(6 + 45) − 6` = **45** damage, **19 s** |

`02-BUILDING-ROSTER.md` §2's central claim — "**massed archers cannot take a building**" — is
false under the model that is supposed to produce it. The same collapse gives every melee unit
the Vanguard's `+12 vs mounted`: a Citizen would do `3 + 12 − 2 = 13` to a Lancer and six
Citizens would kill one in 1.9 s.

**Fix.** Key the bonus on `(attacker.kind, target.armorClass)` — or introduce an explicit
`attackProfile` per kind — and say so in §1. Every other number in the spec already assumes
this; only the formula does not.

### B2 — `01-UNIT-ROSTER.md` §3 vs `03-COMBAT-MODEL.md` §2: armour classes and damage types contradict for four of nine units, and five matchups invert

| Unit | 01 §3 says | 03 §2 says |
|---|---|---|
| Citizen | armour class `worker` | armour class `infantry` |
| Quarrel | armour class `infantry` | armour class `light` |
| Bastion Walker | armour class `siege`, damage type `ranged` | armour class `building`, damage type `siege` |
| Light Transport | armour class `hull` | armour class `light` |
| Pathfinder | damage type `melee`, range 0.9 m | damage type `ranged` |
| Sunlance | damage type `ranged`, range 6.0 m | damage type `melee` |

01 §3 uses the classes `worker`, `hull`, `siege`; 03 §2 declares there are exactly four
classes and lists none of them, adding `light` instead. So `Pathfinder +5 vs worker` and
`Lancer +6 vs worker` have no target under 03, and `Lancer +8 vs siege` has no target under 03.
Meanwhile 03 §2 rests its own argument on its version: "The Bastion Walker carrying `building`
armour class is the pivot of the whole roster … it is what makes the anti-building Vanguard
bonus double as the anti-siege answer, so the counter graph closes without a fifth unit."
Under 01 §3 the Walker is `siege`, the Vanguard has no bonus against it, and the graph does
not close.

This is not cosmetic. Running the same engine over both readings:

| Matchup (equal population) | Reading A (01 §3) | Reading B (03 §2) |
|---|---|---|
| 3 Lancer vs 2 Walker | **Lancer win, 12.5 s** | **Walker win, 33.1 s** |
| 3 Ironsworn vs 2 Walker | **Walker win, 39.1 s** | **Ironsworn win, 24.0 s** |
| 8 Quarrel vs 4 Sunlance | **Sunlance win, 13.6 s** | **Quarrel win, 14.1 s** |
| 1 Ironsworn vs 1 Sunlance | **Sunlance win, 12.1 s** | **Ironsworn win, 13.9 s** |
| 3 Vanguard vs 1 Walker | Vanguard win, 32.7 s | Vanguard win, 14.7 s |
| Pathfinder → Citizen per hit | 9 | 4 |

Five outcome reversals, including the designated counter to siege. An implementer picking the
wrong file builds a different game.

**Fix.** One authoritative class list in `03-COMBAT-MODEL.md` §2, with `01-UNIT-ROSTER.md` §3
reduced to a reference. Decide `worker` vs `infantry` for the Citizen (it changes whether the
scout has a job), and decide `siege` vs `building` for the Walker (it changes whether the
Lancer has one).

### B3 — `03-COMBAT-MODEL.md` §1 + `02-BUILDING-ROSTER.md` §3: the Warding Post's `+6 vs siege` is both unimplementable and irrelevant

Two independent failures in one line.

*Unimplementable.* 03 §2 states the bonus "needs `+6 vs siege` written against the *damage
type* rather than the armour class — the tower has to beat the walker specifically". The
formula's lookup is `bonus(attacker.damageType, target.armorClass)`. There is no slot for a
bonus keyed on the **target's** damage type. The implementer must invent a second bonus
mechanism.

*Irrelevant.* Even granting the bonus, a damage bonus cannot answer a range deficit. Warding
Post range 8.5 m (02 §3); Bastion Walker range 9.0 m (01 §3). Measured:

```
1× WardingPost (0P/100M/25L)  vs 1× Walker -> 1× Walker WINS in 12.05 s  survivor HP 190
3× WardingPost (0P/300M/75L)  vs 1× Walker -> 1× Walker WINS in 42.05 s  survivor HP 190
```

Survivor HP 190 of 190: three towers, 300 Matter and 75 Lumen, and the Walker is untouched.
02 §3's own justification — "without it a Bastion Walker out-ranges every tower in the game at
9.0 m and static defence becomes pointless" — correctly identifies the problem and then
prescribes a remedy that does not address it.

Static defence is also a losing trade against the cheap unit. A Warding Post (280 HP, 12
damage, 1.5 s) versus Vanguards (6 damage each after armour, 1.2 s): six Vanguards deal 30
damage/s and kill it in 9.3 s, while it deals 8 damage/s and kills 0.99 Vanguards. 100 Matter
and 25 Lumen buys one dead Vanguard. A Gravemark post at 455 HP buys 1.6.

**Fix.** Warding Post range must exceed 9.0 m — 10.5 m is the smallest number that keeps a
Walker inside a tower's reach with margin. Then re-derive `+6 vs siege` as an armour-class
bonus once B2 fixes the Walker's class, or delete it.

### B4 — `02-BUILDING-ROSTER.md` §1 + `01-UNIT-ROSTER.md` §3: the costs were set against a gather rate that is 1.7–2.6× the real income

01 §3 states "Base rates 1.6 / 1.4 / 1.1 / 0.9 per second while working
(`SkirmishTuning.gatherRates`, unchanged)". That is accurate as a rate, and no file in the
spec ever converts it into income. Citizens walk. Measured on the real gathering and movement
systems, `riverlands`, seed `20260726`, Sunwoven home:

| Node | Distance to Core | Citizens | Delivered per citizen | Fraction of book rate |
|---|---|---|---|---|
| provisions #14 | 16.6 m | 1 | 0.767/s | 48% |
| provisions #13 | 39.7 m | 1 | 0.400/s | 25% |
| matter #15 | 17.4 m | 1 | 0.733/s | 52% |
| lumen #17 | 31.7 m | 1 | 0.433/s | 39% |
| provisions #14 | 16.6 m | 4 | 0.938/s | **59% (best in game)** |
| matter #15 | 17.4 m | 4 | 0.542/s | 39% |
| lumen #17 | 31.7 m | 4 | 0.437/s | 40% |

Real income is 39–59% of the number the costs were priced against. Every "how long until I can
afford X" judgement in the spec is off by roughly a factor of two.

**Fix.** Either restate the rates in 01 §3 as *effective* income with the measured walk penalty
shown, and reprice, or shorten the walk (see §5 — the Farm-as-node change already does exactly
this and should be dated earlier than CP-G3h).

### B5 — `02-BUILDING-ROSTER.md` §1: the home fragment cannot pay for the specified building list. Lumen misses by 26; Matter by 342

Deposit accounting only — no rate assumptions. `WorldPopulator.depositPlan` gives each home
`[provisions, provisions, matter, matter, lumen]`, with `startingYield` = ∞ / 420 / 300 / 180.

```
Building bill from 02 §1 (4× Dwelling, Formation Yard, Lumen Spire, Warding Post,
Expansion Outpost, Dawn Loom, Voyager research, Stride Yard, Siege Foundry, Ember Hall):
                         220 P   1450 M   420 L    80 Ae

home Matter ceiling = deposits 840 + start 160 + 9-min trickle 108 = 1108   SHORTFALL 342
home Lumen  ceiling = deposits 300 + start  40 + 9-min trickle  54 =  394   SHORTFALL  26
```

The **Lumen Spire and everything it trains are unaffordable from the home fragment**, because
the mandatory age-up path alone (Formation Yard 20 + Expansion Outpost 30 + Dawn Loom 50 +
Voyager 100 = 200 L) plus the Spire (45), the Warding Post (25), the Siege Foundry (60) and
the Ember Hall (90) exceeds the 394 L that exists there, before a single 30 L Quarrel.

And the supply drains fast. With only four citizens working it:

```
home Matter (840) exhausted at t = 360 s (6.0 min)
home Lumen  (300) exhausted at t = 180 s (3.0 min)
```

Taking the expansion (420 M, 300 L) and one outcrop (420 M) raises the ceilings to 1948 M and
694 L, leaving **498 Matter and 274 Lumen for the entire army** — 4 Bastion Walkers' worth of
Matter, or 9 Quarrel / 5 Sunlance of Lumen. On a citizen-second budget using the measured
rates, a 9-minute match that reaches ~40 population with the full building list needs 5316
citizen-seconds of gathering against 5692 available (4 starting citizens plus 8 trained at
14 s intervals, minus 236 builder-seconds): **7% slack, with zero idle time, zero losses, and
three fragments occupied.**

This is not a rounding problem and it interacts badly with the faction fiction. Gravemark is
specified as "slow to expand … turtle on a Matter economy", and Matter is the resource whose
home supply falls 342 short of the buildings they are told to build. Their +25% Matter *rate*
does not add yield; it exhausts the finite 840 sooner.

**Fix.** Choose one: raise home yields (Matter 420 → ~700 each, Lumen 300 → ~550), or cut the
Matter/Lumen content of the building list by ~30%, or state explicitly that the T2 building set
requires two fragments and make that a stated pacing goal rather than an accident. Whichever is
chosen, print the bill-versus-supply table in the spec so the next change is checked against it.

### B6 — `01-UNIT-ROSTER.md` §2: the Lancer, and therefore the whole Stride Yard line, is deleted at equal population by the cheaper T1 unit

The spec's "Vanguard beats Lancer" leg is not a counter, it is an erasure. Measured with the
spec's own numbers, at equal population:

```
 2× Vanguard (pop 2, 90P/40M)   vs 1× Lancer (pop 2, 55P/35M)  -> Vanguard WINS in  2.45 s, survivors 51,75
 6× Vanguard (pop 6, 270P/120M) vs 3× Lancer (pop 6, 165P/105M) -> Vanguard WINS in  2.45 s, survivors 35,75,75,75,75,75
12× Vanguard (pop 12)           vs 6× Lancer (pop 12)           -> Vanguard WINS in  3.65 s, 11 of 12 at full HP
```

The Lancer is 2 population against the Vanguard's 1, so per population it fields 50 HP and
3.6 damage/s against the Vanguard's 75 HP and 5.8 damage/s — and then eats `+12 vs mounted`
on top. It requires a Stride Yard (40 P + 140 M, 22 s) that only exists after the age-up. A
player who has understood the numbers never builds one, which removes CP-G3f's headline unit,
the Sunlance's only real answer (B7), and the Walker's designated counter under Reading A.

**Fix.** Lancer at 1 population, or Vanguard's mounted bonus reduced to +6 with the Lancer's
HP raised to ~130. The invariant to hold: a 2-pop unit must beat two 1-pop units of the class
it is supposed to lose to *less* badly than 2.45 seconds.

### B7 — `00-CONTENT-SPEC.md` §4 + `01-UNIT-ROSTER.md` §3: the Sunlance has no answer anywhere in Gravemark's roster

01 §2 claims "Sunlance is mounted (so Vanguard's `+12` still answers it)". That holds only if a
Vanguard can reach it. Sunlance: 4.8 m/s, 6.0 m range. Gravemark's `−8% speed` modifier applies
to every land unit:

| Gravemark unit | Speed | Speed edge the Sunlance keeps | Time to close from 6.0 m to weapon range |
|---|---|---|---|
| Vanguard | 2.76 m/s | +2.04 m/s | never — the gap grows |
| Ironsworn | 2.48 m/s | +2.32 m/s | never — the gap grows |
| Lancer | 4.97 m/s | +0.17 m/s | **29.8 s** |
| Quarrel | 2.94 m/s (7.5 m range) | outranged by 1.5 m, but loses the DPS race 3.6 vs 10.8 | — |

A Sunlance firing every 1.2 s for 11 damage (Lancer ranged armour 2) lands **24 shots = 264
damage** during the 29.8 s a Gravemark Lancer needs to close 5 m on a 100 HP body. It kills
Vanguards and Ironsworn without ever being touched. The `Guard` stance's 6 m leash means the
simulation will not kite for the AI, but a human will, and `00-CONTENT-SPEC.md` §6 states the
opponent is the Gravemark AI — so this is the actual matchup.

The one answer that works under Reading B (massed Quarrel; 8 Quarrel beat 4 Sunlance in 14.1 s)
does not work under Reading A (4 Sunlance beat 8 Quarrel in 13.6 s), so B2 has to be resolved
before this can even be assessed. And Gravemark's Lumen ceiling (B5) will not fund massed
Quarrel regardless.

**Fix.** Sunlance range 6.0 → 4.0 m so a 2.76 m/s Vanguard closes it in a bounded window, or
speed 4.8 → 3.6 m/s, or exempt mounted units from Gravemark's speed penalty. The invariant:
no unit may hold a positive speed edge over *every* unit that has a bonus against it.

### B8 — `01-UNIT-ROSTER.md` §2: the Quarrel↔Vanguard leg of the ring is decided by ≤5 HP and inverts on starting distance

The spec's claim: "The Vanguard spends the entire approach being shot and arrives having lost
most of its health." Measured: the approach is 6.6 m at 3.0 m/s = 2.20 s, which at a 1.4 s
cooldown is exactly **2 free shots = 20 of 75 HP (27%)**. Then:

```
engagement opens at 7.5 m:  Quarrel WINS  in 9.85 s, survivor HP 1
engagement opens at 6.0 m:  Quarrel WINS  in 9.85 s, survivor HP 1
engagement opens at 5.0 m:  Vanguard WINS in 9.80 s, survivor HP 5
engagement opens at 3.0 m:  Vanguard WINS in 9.10 s, survivor HP 5
5v5 at 6.0 m: Quarrel WINS (29,50)     5v5 at 3.0 m: Vanguard WINS (5)
```

One hit point at maximum range; the result flips at 5.0 m and flips again for groups at 3.0 m.
The winner is decided by where the camera happened to be when the order was issued, not by
composition. Nor can the player fix it with skill: the Quarrel's speed edge over the Vanguard
is **0.20 m/s**, so re-opening the 6.6 m it needs takes **33.0 s**. The counter is two free
shots and nothing else, permanently.

**Fix.** Quarrel range 7.5 → 9.0 m (three free shots, and it survives at 11 HP instead of 1),
or Quarrel speed 3.2 → 3.8 m/s so kiting exists. Range is the cheaper lever because it does not
also change the Lancer matchup.

### B9 — `01-UNIT-ROSTER.md` §3 + `02-BUILDING-ROSTER.md` §2: massed T1 Vanguard is a dominant strategy that makes Voyager and the whole T2 roster optional

Vanguard: 1 population, 45 P + 20 M, 13 s, 75 HP, 7 damage, `+12 vs mounted`, `+3 vs building`,
trainable at T1 from a 110 M + 20 L building. It beats the Lancer (B6), trades at ±5 HP with the
Quarrel (B8), and is second only to the Walker at killing structures. Measured:

```
10× Vanguard (pop 10, 450P/200M)  vs Core (600) -> Core dead in 10.85 s, zero Vanguards lost
 3× Walker   (pop  9, 120P/330M)  vs Core (600) -> Core dead in  9.05 s
 6× Vanguard (pop  6, 270P/120M)  vs Formation Yard (260) -> dead in 8.45 s, zero lost
```

01 §3 concludes from its own table: "Siege is required for a fast Conquest and optional for a
slow one." It is not. Ten Vanguards (10 pop, one T1 building, 450 P + 200 M) kill a Core in
10.85 s; three Walkers (9 pop) take 9.05 s but require Voyager, a 180 M + 60 L Siege Foundry
and 78 s of serial training. Working the timeline with the measured rates — Formation Yard by
~t=90 s, ten Vanguards by ~t=240 s, 88–110 m of walking at 3.0 m/s — the rush lands at roughly
**4:50**, while the earliest Voyager on the same economy is 5–6 minutes. The dominant line ends
the match before the tier that contains four of the nine units exists.

This is the pacing consequence of B3, B5 and B6 compounding: static defence cannot stop it
(B3), the defender's archers are unaffordable (B5), and the T2 answer is a unit that loses to
the thing it should counter (B6).

**Fix.** Remove `+3 vs building` from the Vanguard (it is also what makes it the anti-siege
answer under Reading B, so resolve B2 first), raise Core melee armour so infantry needs numbers
the pop cap forbids, or accept the rush and re-scope T2 as a comeback tier rather than the
place half the content lives.

### B10 — `00-CONTENT-SPEC.md` §5 vs `04-IMPLEMENTATION-ORDER.md` §4: the Dominion victory is specified twice with numbers 4× apart, its objective does not exist, and mutual occupation deadlocks

| | `00-CONTENT-SPEC.md` §5 | `04-IMPLEMENTATION-ORDER.md` §4 |
|---|---|---|
| Hold requirement | 45 s | **180 s** |
| Escalation | 30 s at 7:00, 20 s at 9:00 | **120 s at 8:00, 60 s at 10:00** |

00 §5 matches the code (`dominionHoldDuration = 45`, `dominionMilestones = [15, 30]`) and is
annotated "unchanged", so 04 is the wrong one — but 04 is the file the builder executes, and its
version cannot fit an 8–10 minute match at all (a 180 s uncontested hold that only shortens at
8:00).

Three further holes in the same rule:

1. **There is no Dominion Spire.** 00 §5 says the fragment "carries a neutral **Dominion
   Spire**". It is not a `BuildingKind`, it is not in 02's fourteen-building roster, and no
   checkpoint in 04 creates it. Position, HP, footprint, destructibility and ownership are all
   unstated.
2. **"Military unit" is undefined.** `UnitKind.isMilitary` today is `{vanguard, ranged,
   bastionWalker}` — the Pathfinder is **not** military. Can a scout capture the Dominion? Can a
   Citizen contest it? The spec never says, and it never updates `isMilitary` for Lancer,
   Sunlance or Ironsworn.
3. **Mutual occupation never resolves.** Capture requires "no enemy military unit inside 12 m";
   an enemy in the ring "**pauses** the timer; it does not reset it". If both sides keep a unit
   in the ring, both timers pause forever. 00 §5 also promises "**No hard match timer, no draw
   state**". The escalation table shortens a requirement that is not advancing, so the claim that
   it "converts a stalemate into a forced fight … rather than into a timeout" does not hold. Nor
   is it stated whether the timer is per-faction or a single tug-of-war.

**Fix.** Delete 04's version and cite 00 §5. Add the Spire to 02's roster with a position, HP
and armour. Define the capture predicate over an explicit unit-kind set. Replace "pause" with
decay (e.g. contested drains at half rate) so the objective cannot deadlock.

### B11 — `04-IMPLEMENTATION-ORDER.md` §3: the adversary — the thing that makes it a match — is specified as "a schedule, not a planner", with no schedule

CP-G3c gives: gather with starting citizens, train citizens to 12, Formation Yard "around tick
2400", Lumen Spire "around tick 4800", and "attack waves at rising size on a fixed cadence".
Absent: the cadence, the wave sizes, the wave composition, what "around" means (any jitter is a
random draw and the spec says which stream but not how many draws or when), the target selection
rule, whether waves retreat, and what happens when the first wave dies. The bar — "beatable by a
player who built five Vanguard" — is not a specification of anything.

`00-CONTENT-SPEC.md` §6 also states "**No AI opponent behaviour is specified here.** The
Gravemark AI is a separate document and a separate checkpoint", which contradicts 04 specifying
it inline. And nothing says what happens when the player chooses Gravemark, which 00 §4 and
`Docs/Concepts/05-gravemark-player-perspective.png` both imply is possible.

**Fix.** Either write the wave table (time, size, composition, target, retreat rule) into 04, or
make CP-G3c depend on a named adversary document and remove the half-schedule from 04 so an
implementer is not tempted to fill in the gaps.

### B12 — `02-BUILDING-ROSTER.md` §4: the population rule as written lets the cap be overshot, and the spec forbids the only remedy it leaves

The rule: "An enqueue is **refused** when `used + populationCost > cap`." `used` is computed
from live units:

```78:86:SunfoldGreenfield/Sources/Simulation/SkirmishSimulation.swift
    func population(for faction: Faction) -> (used: Int, cap: Int) {
        let used = units.values
            .filter { $0.faction == faction }
            .reduce(0) { $0 + $1.kind.populationCost }
```

Queued items reserve nothing. At `used = 8, cap = 10`, a player enqueues a Bastion Walker at the
Siege Foundry (8 + 3 ≤ 10 ✓) and two Citizens at the Core (8 + 1 ≤ 10 ✓ each): five population
of production is committed against two slots. `03-COMBAT-MODEL.md` §7 then forbids the only
escape — "Retroactive unit deletion is never acceptable" — and 02 §4 promises the refusal "is
never silently dropped". Three rules, no consistent outcome.

**Fix.** Count queued population in `used`, and state that the check is re-evaluated at spawn
with the item held (not cancelled) at the front of the queue when the cap is full, with a HUD
reason. Also state whether a Dwelling lost mid-queue holds or refunds.

### B13 — `04-IMPLEMENTATION-ORDER.md`: five of its scope items already exist in the code, the required rename is never stated, and one "unchanged" file must be rewritten

04 is the executable document, and its scope lists do not match the repository:

| 04 says | Reality |
|---|---|
| CP-G3a: "Add `.vanguard` to `UnitKind`" | `UnitKind.vanguard` exists |
| CP-G3a: "Add `UnitActivity.attacking`" | `UnitActivity.attacking(targetID:)` exists |
| CP-G3a: "Extend `Unit` with `hp`, `maxHP`" | `Unit.life` and `UnitKind.maxLife` exist — following 04 literally creates two sources of truth for HP |
| CP-G3b: "`.formationYard` … `BuildingKind` cases" | `BuildingKind.formationYard` exists |
| CP-G3b: "`.pathfinder` and `.quarrel` `UnitKind` cases" | `.pathfinder` exists; **`.quarrel` does not — `.ranged` does** |
| CP-G3e: "`.dawnLoom` building" | `BuildingKind.dawnLoom` exists (zero cost, zero build time in `SkirmishTuning`) |

The `.ranged` → Quarrel change is a **rename**, not an addition, and no file says so. `UnitKind.ranged`
is referenced by `SkirmishTuning.rangedCost`/`rangedBuildTime`/`rangedPopulation`,
`BuildingKind.trains`, `isMilitary`, `SelectionPanel`, `UnitMeshes` and `SunfoldPalette`. An
implementer reading 04 literally ships a roster with both a "Ranged" and a "Quarrel".

Separately, `02-BUILDING-ROSTER.md` §5 opens "Unchanged from
`Sources/Simulation/ConstructionPlacement.swift` and extended". That file hardcodes one faction
and three kinds:

```25:25:SunfoldGreenfield/Sources/Simulation/ConstructionPlacement.swift
    static var placeableKinds: [BuildingKind] { [.farm, .matterExtractor, .dwelling] }
```

```61:61:SunfoldGreenfield/Sources/Simulation/ConstructionPlacement.swift
            guard map.region(at: sample) == .sunwovenHome else { return false }
```

Under this rule an Expansion Outpost — which 02 §5 requires to be in a non-home region — can
never be placed anywhere, and Gravemark can build nothing. "Unchanged and extended" will
mislead whoever costs the work.

**Fix.** Rewrite 04's scope lists against the actual `EntityKinds.swift`; state the `.ranged` →
`.quarrel` rename with its call sites; state that HP lives on `Unit.life` / `kind.maxLife`, not a
new field; and rewrite 02 §5's opening to say the placement predicate becomes faction- and
region-parameterised.

### B14 — Missing decisions: places an implementer must stop and invent

The spec's stated purpose is to be implementable without further design decisions. These are the
points where it is not. Each is named by file and section.

1. **`03-COMBAT-MODEL.md` §3 — is `range` measured centre-to-centre or between footprints?**
   Never stated. It changes every time-to-kill involving a building (Core footprint radius 5.0,
   Ember Hall 4.8, Farm 3.6) and it is what decides the Walker/Warding Post stand-off in B3.
2. **`03-COMBAT-MODEL.md` §3 step 6 — may an entity that died earlier in the same tick still
   act?** Deaths are "applied at the end of the tick", so a unit at 0 HP is still in the
   collection when a higher-`EntityID` sibling iterates. Both answers are deterministic; they
   give different results.
3. **`03-COMBAT-MODEL.md` §4 priority 2 — "the entity that damaged me most recently" is
   ambiguous within a tick.** Two attackers in the same tick leave the retaliation target
   dependent on iteration order, which is unstated. This also creates a hazard: adding the
   Warding Post as a damage source in CP-G3f changes existing retaliation outcomes.
4. **`02-BUILDING-ROSTER.md` §4 — "a ring position beside the building resolved through
   `WorldMap`" does not say which position.** `GatheringSystem.workStation` derives its slot from
   `unit.id.raw % stationCount`; the spec should mandate the same derivation, because "first free
   slot" over a dictionary is a determinism break.
5. **`02-BUILDING-ROSTER.md` §1 — where does a Dock-trained Light Transport spawn?** A transport
   is a void unit; a ring position beside a Dock is land. `MovementSystem.resolveDestination`
   →`clampToVoid` "holds still rather than invent a berth" when the current position is illegal,
   so a hull spawned on land is permanently stuck.
6. **`00-CONTENT-SPEC.md` §3 — does the Voyager `+30% max HP` scale current HP?** A damaged
   Formation Yard either heals proportionally, gains the delta, or sits at 77% health after the
   advance. Unstated.
7. **`00-CONTENT-SPEC.md` §5 vs `03-COMBAT-MODEL.md` §8 — "A Core cannot be repaired below 25%"
   has no counterpart in the repair rule**, which allows any citizen to repair any damaged
   friendly building at 8 HP/s. Which wins, and does "below 25%" mean "while below" or "back up
   from below"?
8. **`03-COMBAT-MODEL.md` §8 — repair draw order when the Matter pool empties.** Several citizens
   repairing several buildings drain one pool; the order decides who gets the last Matter. Not
   stated (ascending `EntityID` would match every other system).
9. **`02-BUILDING-ROSTER.md` §1 — the drop-off column is per resource** (Farm → Provisions, Lumen
   Spire → Lumen, Waystation → all four) while `BuildingKind.acceptsDropOff` is a `Bool` and
   `GatheringSystem.nearestDropOff` ignores cargo kind. The change is scheduled in no checkpoint.
10. **`02-BUILDING-ROSTER.md` §1 — the Ember Hall "trains your unique unit"**, but
    `BuildingKind.trains` is a faction-blind static property. No mechanism is given for a
    faction-dependent production list.
11. **`03-COMBAT-MODEL.md` §7 — what happens to passengers when a Light Transport dies?** §4
    mentions clearing a target that "has boarded a transport"; §7's death rules never mention
    carried units, nor whether a transport in the void is targetable by land units at all.
12. **`02-BUILDING-ROSTER.md` §3 — a Farm creates a deposit at its own position**, but
    `ConstructionPlacement.isLegal` rejects any footprint within `Deposit.workRadius + radius +
    clearance` of a deposit. Whether a Farm's own node is exempt, and whether a Waystation can
    then be placed beside a Farm, is undecided.
13. **`04-IMPLEMENTATION-ORDER.md` §3 — the world hash.** The determinism bar is "an identical
    world hash at tick 12000". No hash function exists and the spec does not define what is
    hashed or in what order.

### B15 — `00-CONTENT-SPEC.md` §5 vs §3 and `02-BUILDING-ROSTER.md` §1: Core HP is specified three ways, and the resulting asymmetry favours Gravemark by 47% on the primary win condition

00 §5: "Core HP 600 (`SkirmishTuning.enemyCoreLife`, unchanged)." 02 §1: "Faction HP modifiers
apply on top of **every row**" (Sunwoven −15%, Gravemark +25%). 00 §3: Voyager grants the Core
"+30% max HP".

| | Foundation | Voyager |
|---|---|---|
| Sunwoven Core | 600 × 0.85 = 510 | 663 |
| Gravemark Core | 600 × 1.25 = 750 | 975 |

A Gravemark Core is 47% tougher than a Sunwoven one at the same age, on the win condition the
spec names first, with no compensating advantage anywhere in §4's table. Against the ten-Vanguard
rush of B9 (50 damage/s) that is 10.2 s versus 15.0 s. 00 §4 asserts "Neither is stronger"; on
these numbers that is not established.

**Fix.** Exempt the Core from the faction HP modifier and keep `enemyCoreLife = 600` for both, or
state the compensating asymmetry and show the arithmetic.

### B16 — `01-UNIT-ROSTER.md` §3 vs `03-COMBAT-MODEL.md` §8: construction is linear in builders; repair cites a diminishing-returns curve that does not exist

01 §3: "Constructs — Yes — up to 4 per foundation, **linear** progress." The code agrees:

```5:7:SunfoldGreenfield/Sources/Simulation/ConstructionSystem.swift
/// Progress is linear in builder count (#5): two citizens finish in half the
/// time of one. Pure and deterministic — same state + step → same result.
```

03 §8: "Up to `maxBuildersPerSite` citizens may repair one building, with **the same
diminishing-returns curve construction uses**." There is no such curve. An implementer told to
reuse a curve that does not exist will invent one, and repair throughput is load-bearing: four
citizens at 8 HP/s each is 32 HP/s against a Bastion Walker's 20.3 damage/s, so whether the
fourth builder contributes 8 HP/s or 2 decides whether a defended Core can be sieged at all.

**Fix.** Say "linear, capped at `maxBuildersPerSite`", matching construction, and state the
Matter drain per builder (4 Matter/s each at 0.5 M/HP — four citizens cost 16 Matter/s against a
measured income of ~0.55 M/s per citizen, which is worth stating explicitly because it is what
stops repair from being an infinite wall).

---

## 4. NON-BLOCKING OBSERVATIONS

**Arithmetic slips in the spec's own tables.**

- 01 §3, TTK table, "Vanguard → Ironsworn": 1 damage on a 1.2 s cooldown is 0.83 damage/s and
  **144 s**, not "0.7 / 180". 0.7 is the Quarrel's cooldown, not the Vanguard's.
- 01 §3, "Bastion Walker → Civilization Core": the row computes `(20 − 6) + 45 = 59` using
  *ranged* armour, while 03 §1 resolves siege against melee armour and 03 §2 makes the Walker a
  `siege` type — which gives 61 and 29.5 s, not 59 and 30.5 s. The row is evidence the table was
  written before the model.
- 03 §4: "The Quarrel's 7.0 range against 13.0 sight" — the roster says **7.5**. And it is not
  "the largest gap in the roster": the Sunlance's is 15.0 − 6.0 = 9.0 against the Quarrel's 5.5.
- 04 CP-G3a: "strikes on a **1.1 s** cadence" — the Vanguard's cooldown is 24 ticks = **1.2 s**.
  1.1 s is the Lancer's.
- 01 §1 asserts "Nothing costs more than 90 resources or 26 seconds" directly beneath a table
  showing the Bastion Walker at 40 P + 110 M (150 total, 110 in one line). Principle P2 states the
  same ceiling. Either the principle or the Walker has to move.
- 01 §2 calls the Sunlance "the most expensive Lumen sink in the game" at 55 L; the Ember Hall is
  90 L and the Voyager advance is 100 L.

**Cross-reference rot in 04.** Three of its citations point at the wrong section of 00: CP-G3d
cites "§6" for victory (it is §5; §6 is the out-of-scope list), CP-G3e cites "§4" for the Voyager
cost (it is §3), CP-G3g cites "§5" for faction modifiers (it is §4). Combined with B10's 45 s/180 s
split, 04 reads as though it was written against an earlier draft of 00.

**Checkpoint naming collides with the roadmap.** The spec's checkpoints are CP-G3a…h, while
`ROADMAP.md` gate **G3 is "Logistics and expansion"** — boarding, sailing, unloading, establishing
the Outpost — which is the unfinished prerequisite for the Aether gate that CP-G3e depends on. Two
different things called G3, one of which blocks the other.

**`CONTEXT.md` still names the old bar.** It says "**AoE IV play-feel bar**. The Gauntlet critic
judges … against Age of Empires IV play". The spec asserts the bar moved to Age of Empires II. One
of the two needs updating or the next critic judges against the wrong reference.

**Provisions are now two contradictory things.** `ResourceKind.provisions.isRenewable == true` and
`WorldPopulator.startingYield(.provisions) == .infinity`, while 02 §3 gives a Farm a **finite 400**
Provisions node. The gathering code will deplete it correctly, but any HUD or deposit-inspection
text keyed on `isRenewable` will tell the player a Farm never runs dry.

**Citizen combat is stronger than the anti-worker bonuses.** With citizens ordered to fight,
4 citizens beat a Pathfinder in 4.55 s and 6 citizens beat a Vanguard in 9.05 s. 03 §4's rule
that citizens never auto-acquire is what makes raiding work at all, so this is a micro-skill
cliff rather than a balance break — but "an unguarded citizen line is punishable" (01 §2) is only
true while it is unguarded *and* the defender does nothing.

**The home→expansion water is one metre wide.** At the dock bearing on `riverlands`, the two dock
points are 0.4 m apart (`dock (home) (-25.1, 20.9)`, `dock (far) (-25.3, 20.6)`), so the crossing
that justifies the Light Transport is a puddle; the barrier is the region clamp of §2, not the
river. If the transport is meant to feel load-bearing, the map needs a wider channel on that seam.

**`SimulationClock` drops backlog under load.** `advance(by:)` sets `accumulator = 0` when it
falls more than `maxStepsPerFrame` behind, so simulated `elapsed` drifts below wall-clock time on
a stuttering device. This does not break determinism — `elapsed` is `ticks × stepDuration`, and
the Dominion escalation being a function of it is therefore correct and frame-rate independent —
but the 8–10 minute promise is 8–10 minutes of *simulated* time, which is worth saying once.

**Determinism, overall.** I found **no randomness holes**. 03 §3's ascending-`EntityID` iteration,
end-of-tick death application, integer-tick cooldowns and §9's prohibition list are the right
artifacts, the stated reason (Swift `Dictionary` order is not stable) is correct, and every
existing system already follows the same discipline (`GatheringSystem`, `MovementSystem`,
`ConstructionSystem` and `BoardingSystem` all iterate `units.keys.sorted`). CP-G3c correctly
demands a new tagged `adversary` stream, which matches `DeterministicRandom.stream(seed:tag:)`.
What is missing is **order specification**, not RNG discipline: items 2, 3, 4 and 8 of B14.

**Things I could not verify.** Whether a fight *reads* on screen (I did not build or run the app,
and readability is 04's own critic question for CP-G3a). Whether `Docs/Gauntlet/tools/framestat.py`
supports the `pair` invocation CP-G3g assumes — the file exists and `pair` is referenced elsewhere
in the repo, but I did not run it. The effective Aether gather rate — no reachable drop-off exists
today, so the 0.65/s used in B5's citizen-second budget is an assumption, not a measurement; at the
full book 0.9/s the budget improves by only 34 citizen-seconds, so the conclusion is insensitive to
it. The bar-change authority the spec cites (`Docs/Gauntlet/00-PLAN.md` BC-01) — deliberately not
read, per the brief.

---

## 5. WHAT THE SPECIFICATION GETS RIGHT

This is not a document written carelessly, and several of its decisions are ones I would defend
against a redesign.

**Its claims about the current codebase are accurate almost everywhere I checked.** Every
"unchanged" annotation verified exactly: `gatherRates` 1.6/1.4/1.1/0.9, `carryCapacity` 10,
`maxQueueLength` 10, `cancelRefundFraction` 0.75, `dominionHoldDuration` 45,
`dominionMilestones` [15, 30], `enemyCoreLife` 600, `corePressureThresholds` [0.75, 0.50, 0.25].
So did "six of the seven shared kinds already exist", "seven already exist as `BuildingKind`
cases", "`Sources/Simulation` contains no `CombatSystem` and no AI of any kind — verified by
search, not assumed", "sight radius currently does nothing because there is no fog of war", and
"`MovementSystem` currently walks straight lines with land clamping". A spec that is honest about
the ground it stands on is rarer than it should be. The failures in this review are arithmetic and
omission, not fabrication.

**The Aether gate is a genuinely good structural idea and the claim behind it is true.**
`WorldPopulator.depositPlan` places Aether only on the expansions, the Dominion and the two
outcrops — never on either home. Converting "age up" from a menu click into a map decision, and
thereby giving the transport and the Outpost a reason to exist, is the strongest single idea in the
progression. 00 §3 says so and it is right. (It just needs §2's traversal rule to be reachable.)

**"The tech tree is the base you can see" is the correct answer to the constraint.** `ROADMAP.md`
forbids tech-tree sprawl. Fourteen buildings, each unlocking exactly one concrete thing, with
exactly one researched item in the game, honours that constraint while still delivering
progression breadth — and it does so *visibly*, on the map, in resources the player is already
reading. I checked this specifically as a possible violation of the hard constraints and it is
not one: there are no research nodes, no upgrade lines, no veterancy, and P5's rejection of a
third age cites the roadmap correctly. **No hard constraint in the brief is violated** — the
content lives in `Sources/Domain` as pure data, cooldowns are integer ticks at 20 Hz, randomness
is untouched, and the two civilizations are the locked pair.

**No damage variance is the right call, for the right reasons, stated in the right order.** P3 and
03 §1 argue it from determinism first and readability second. Both are correct, and the floor of 1
with its "1 damage a shot, 280 shots — go get siege" justification is exactly the kind of
reasoning that survives contact with a builder.

**End-of-tick death application is the correct fix for order dependence**, and 03 §3 explains
*why* rather than asserting it. §9's five-item list of what combat must never do is the single
most useful paragraph in the five files: it is short, it names the specific APIs
(`Double.random`, `shuffled()`, `SystemRandomNumberGenerator`), and it is checkable in review.

**Farm-as-node is a real fix for a real measured problem.** A Farm's own deposit sits inside its
footprint, and `footprintRadius 3.6 + Deposit.workRadius 2.4 = 6.0 m` of delivery reach against a
work station 2.28 m out — so the citizen never leaves delivery range and earns the full book
1.60/s, against the 0.94/s best case from a natural node. That is a 1.7× income improvement bought
with a placement decision, which is precisely the AoE II farm. Its 0/0 armour makes it die to one
Vanguard in 13.2 s, so "burning a Farm is a real play" is also true. This change deserves to be
earlier than checkpoint 8, because it partly answers B4.

**The Ironsworn is correctly designed, and it is the one unit whose whole claim survives
verification.** A Vanguard does `max(1, 7 − 6) = 1` to it (144 s to kill), and at equal population
Quarrel beat it decisively (10 Quarrel vs 5 Ironsworn: Quarrel win in 11.25 s with 8 of 10 alive).
"Functionally immune to melee and dies to massed ranged" is exactly what the numbers do. 01 §2's
description of it is the model the rest of the roster should have been held to.

**Sound smaller decisions.** Guard as the default stance with a 6 m leash, argued from the failure
mode it prevents. Cost-on-enqueue, argued from what the resource bar has to be able to tell the
player. Cosmetic projectiles with the in-flight alternative named and rejected on desync grounds.
The Dominion escalation as a pure function of elapsed time with no draw state. The silhouette
contract in 01 §5 — specifying that the Vanguard reads vertical and the Quarrel horizontal because
they are the same height and the player has ten pixels — is the kind of thing that normally gets
left to a mesh author and should not be. And both 00 §6 and 04's closing section record what was
deliberately excluded, which is the cheapest possible insurance against a later agent reading an
omission as an oversight.

**The pop-cap retune is arithmetically clean.** 10 + 4 × 8 = 42, matching CP-G3h's "roughly 40
population with four Dwellings", and the current 8 / +4 / 80 Matter is correctly diagnosed as
"eight Dwellings for one army is clicking, not strategy".

---

## 6. THE SHORTEST PATH TO A BUILDABLE SPEC

In dependency order, because several of these unblock the others:

1. Write the traversal rule (§2). Nothing else in the spec can be validated without it.
2. Collapse the armour-class and damage-type lists into one authority (B2), then re-key the bonus
   lookup on the attacking kind (B1). These two together are one editing pass and they determine
   every number in step 3.
3. Re-derive the counter matrix from the fixed model and fix the four broken relationships:
   Warding Post range (B3), Lancer population or Vanguard mounted bonus (B6), Sunlance range or
   speed (B7), Quarrel range (B8). Then re-check the Vanguard's `+3 vs building` against B9.
4. Reprice against measured income, not book rates, and print the building-bill-versus-supply
   table (B4, B5).
5. Rewrite 04 against the actual `EntityKinds.swift`, fix the three section citations, delete the
   180 s Dominion numbers, and insert traversal before CP-G3c (B10, B13).
6. Resolve the thirteen missing decisions in B14 inline, in the sections where an implementer will
   look for them.

The roster's *shape* — cheap readable units, a ring plus two off-ring roles, buildings as the tech
tree, two tiers, one map-gated advance — is worth keeping. It is the numbers and the omissions that
need another pass.
