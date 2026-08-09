# Resolutions — review 01

**Status: these decisions are authoritative and supersede the five spec files wherever they
disagree.** `REVIEW-01-content-spec.md` returned `REVISE` with one structural gap and sixteen
blocking defects. Every one is answered below with a number, not an intention.

The critic compiled two probes against the real `Sources/Domain` + `Sources/Simulation` and
measured rather than estimated. I checked its largest claim myself before acting on it and it
was correct. Where I have changed a number, the new number is re-derived here so the next
reader can check my arithmetic the same way.

---

## 0. The structural gap — traversal

**Accepted in full. This was the right call and it outranks everything else in the review.**

Verified independently: `Unit.region` is assigned at `WorldEntities.swift:62` and `:108` and
cleared to `nil` at `BoardingSystem.swift:82`, and **nowhere else in the codebase.** It is
set at spawn and never updated, while `MovementSystem.legalPosition` clamps every land unit to
`clampToLand(in: region)`. No land unit has ever been able to leave the region it spawned in.

Conquest, Dominion and the Aether age gate were all unreachable for this one reason, and three
serial checkpoints would each have passed their own bar before anyone noticed.

**The rule, as decided: land is land, water needs a boat.**

- A land unit may move to any standable position, in any region. The `from:` path test stays,
  so a unit walks around a bay and never across it.
- `Unit.region` becomes a **derived label** recomputed from position — for ownership, scoring
  and UI. It is never a movement constraint again.
- Transports are unchanged: they clamp to navigable void.
- `BoardingSystem` gains a **disembark**. A passenger lands on standable ground at the
  destination dock with a correct derived region.
- `orderBoard` widens from `unit.kind.canGather` to any non-`travelsVoid` unit, so military
  units can be ferried. A transport that can only carry villagers is decoration.

In flight now as **CP-G3a2**, scheduled **before** combat rather than before the adversary,
because it is cheap and everything downstream leans on it. Its real deliverable is two tests:
a land unit reaches the Dominion over continuous land, and still cannot cross void.

The critic flagged that `testHomeReachesExpansionOnlyByVoidUntilOutpostIsWoven` may now
legitimately fail. The builder is instructed to report it, not weaken it; that judgement is
mine.

---

## 1. Combat model corrections

### B1 — bonus damage is keyed on the attacking **kind** (accepted)

The formula could not express its own table: with the bonus keyed on `damageType`, the
`(ranged, building)` cell has to hold the Bastion Walker's `+45`, which hands every Quarrel
`+45 vs building` and kills a Core in 19 s. `02-BUILDING-ROSTER.md` §2's central claim —
massed archers cannot take a building — was false under the model meant to produce it.

**Decision.** Every `UnitKind` and armed `BuildingKind` carries an `AttackProfile`:

```
struct AttackProfile {
    let damageType: DamageType          // melee | ranged | siege
    let base: Int
    let bonuses: [ArmorClass: Int]      // keyed on the TARGET's armour class
    let range: Float
    let cooldownTicks: Int
}
```

and the formula becomes

```
effective = max(1, (profile.base + (profile.bonuses[target.armorClass] ?? 0)) - armor(target, profile.damageType))
```

`03-COMBAT-MODEL.md` §1 and §2 are corrected to this. Everything else in the spec already
assumed it.

### B2 — one authoritative class list (accepted)

Four of nine units had contradictory classes across two files, inverting five matchups.
`03-COMBAT-MODEL.md` §2 is now the **only** authority; `01-UNIT-ROSTER.md` §3 is a reference
that must be regenerated from it.

**Six armour classes.** The earlier "exactly four" was wrong and there is no virtue in the
number.

| Class | Members |
|---|---|
| `worker` | Citizen |
| `infantry` | Vanguard, Quarrel, Pathfinder, Ironsworn |
| `mounted` | Lancer, Sunlance |
| `siege` | Bastion Walker |
| `building` | every building |
| `hull` | Light Transport |

**Damage types.** `melee` — Citizen, Pathfinder, Vanguard, Lancer, Ironsworn.
`ranged` — Quarrel, Sunlance, Warding Post. `siege` — Bastion Walker.

Two contested calls, decided:

- **Citizen is `worker`, not `infantry`.** If the Citizen were `infantry` the Pathfinder's
  anti-worker bonus would also hit soldiers and the scout would stop being a scout. Keeping
  `worker` is what gives the Pathfinder and the Lancer a raiding job.
- **The Bastion Walker is `siege`, not `building`.** Making it `building` was a clever trick to
  close the counter graph without a fifth unit, and it is rejected: it made the Warding Post's
  anti-siege bonus unimplementable (B3) and it meant an anti-building bonus doubled as an
  anti-siege bonus, which no player would ever infer. The Vanguard instead gets an explicit
  **`+8 vs siege`**, which is legible and says what it means.

### B3 — the Warding Post can actually reach a Bastion Walker (accepted)

Three towers, 300 Matter and 75 Lumen left a Walker at **190 of 190 HP**. A damage bonus
cannot answer a range deficit.

| | Was | Now |
|---|---|---|
| Range | 8.5 m | **10.5 m** |
| HP | 280 | **350** |
| Base damage | 12 | **14** |
| `+6 vs siege` | keyed on the target's *damage type* — unimplementable | keyed on armour class `siege`, which B2 now gives the Walker |

10.5 m is the smallest range that keeps a 9.0 m Walker inside the tower's reach with margin.

A tower still loses to six Vanguards, and that is intended — towers buy time, they do not win
fights. With the Vanguard's anti-building bonus removed (B9) the trade improves from "100
Matter buys one dead Vanguard" to roughly 1.5, which is the right order for a structure that
also holds ground and gives vision.

### B6 — the Lancer is 1 population (accepted)

At 2 population against the Vanguard's 1, the Lancer fielded 50 HP and 3.6 damage/s per
population against 75 HP and 5.8 — and then ate `+12 vs mounted`. Six Vanguards beat three
Lancers in 2.45 s with five of six at full health. Nobody would ever build one.

| | Was | Now |
|---|---|---|
| Lancer population | 2 | **1** |
| Lancer HP | 100 | **110** |
| Vanguard `vs mounted` | +12 | **+10** |

Re-derived at equal population:

- Vanguard → Lancer: `(7 + 10) − 2 = 15` per 1.2 s = 12.5 damage/s → **8.8 s**
- Lancer → Vanguard: `9 − 1 = 8` per 1.1 s = 7.3 damage/s → **10.3 s**

The Vanguard wins by ~15%, which is a counter rather than an erasure, and the Lancer is still
worth building because it costs more for speed (5.4 m/s) and `+6 vs worker`. The invariant
going forward: **a counter should win by 15–40%, never by 4×.**

### B7 — the Sunlance can be caught (accepted)

At 4.8 m/s and 6.0 m range against a Gravemark roster slowed 8%, the Sunlance held a positive
speed edge over **every** unit with a bonus against it and killed Vanguards and Ironsworn
without ever being touched.

| | Was | Now |
|---|---|---|
| Sunlance speed | 4.8 m/s | **3.6 m/s** |
| Sunlance range | 6.0 m | **5.0 m** |

A Gravemark Lancer at 5.4 × 0.92 = 4.97 m/s now holds a **+1.37 m/s** edge and closes the 4.1 m
gap in 3.0 s instead of never. The answer to the Sunwoven unique is the Gravemark Lancer —
affordable, tier-appropriate, and now 1 population.

**Standing invariant:** no unit may hold a positive speed edge over every unit that has a bonus
against it.

### B8 — the Quarrel leg stops being a 1 HP coin flip (accepted)

Measured, the Quarrel won at 7.5 m with **1 HP** and lost at 5.0 m — the winner was decided by
where the camera happened to be.

**Quarrel range 7.5 → 9.0 m.** Approach becomes 8.1 m at 3.0 m/s = 2.7 s = **three** free
shots (30 damage) instead of two. The Vanguard arrives at 45 of 75 HP; the Quarrel then needs
6.3 s to finish it against the Vanguard's 8.6 s. The Quarrel wins with a real margin.

Range is the right lever because it does not disturb the Lancer matchup: the Lancer still
closes and still wins 6.1 s to 38 s.

### B9 — the Vanguard loses `+3 vs building` (accepted)

Ten Vanguards — one T1 building, 450 Provisions and 200 Matter — killed a Core in 10.85 s
without a casualty, landing around 4:50 while the earliest Voyager is 5–6 minutes. The
dominant line ended the match before the tier holding four of nine units existed.

**`+3 vs building` is deleted.** A Vanguard now does `7 − 4 = 3` to a Core: ten of them take
**24 s** instead of 10.85, which is long enough for towers and defenders to matter, and it
restores the sentence `01-UNIT-ROSTER.md` §3 wanted to be able to write — **siege is required
for a fast Conquest.**

Removing it also fixes the anti-tower trade in B3, which is why these two were decided
together.

### B16 — repair is linear (accepted)

`03-COMBAT-MODEL.md` §8 cited "the same diminishing-returns curve construction uses".
`ConstructionSystem` is explicitly **linear** and says so in its own header comment. There is
no curve; an implementer would have invented one.

**Repair is linear, capped at `maxBuildersPerSite` (4), at 8 HP/s each, costing 0.5 Matter per
HP.** Four citizens repair 32 HP/s and drain **16 Matter/s** against a measured income near
0.55 Matter/s per citizen — so repair is a burst tool, not a wall, and the spec says that
explicitly. Construction's diminishing-returns language is likewise corrected to linear.

---

## 2. Economy

### B4 + B5 — the costs were priced against income that does not exist (accepted)

Two separate findings, one fix.

**B4:** book gather rates are 1.6/1.4/1.1/0.9 per second *while working*. Citizens walk.
Measured delivered income is **39–59% of book** — best case 0.938/s with four citizens on a
16.6 m node. Every affordability judgement in the spec was off by roughly 2×.

**B5:** on deposit accounting alone, the home fragment is **342 Matter and 26 Lumen short** of
the specified building list, and home Lumen exhausts at **3:00**. The Lumen Spire and
everything it trains were unaffordable from home.

**Decisions:**

1. **Home yields rise.** Matter 420 → **700** each, Lumen 300 → **550**. New home ceilings:
   1668 Matter, 644 Lumen against a 1450/420 bill. That leaves headroom rather than a 7% slack
   with zero idle time.
2. **`01-UNIT-ROSTER.md` §3 restates rates as *effective*,** with the measured walk penalty
   shown, and every cost is read against effective income. Book rates are a footnote.
3. **Farm-as-node moves from the last checkpoint to CP-G3a.** The critic verified it is worth
   1.7× income — a Farm's deposit sits inside its own footprint, so the citizen never leaves
   delivery range and earns the full 1.60/s against 0.94/s best case from a natural node. It is
   the cheapest available answer to B4 and it was scheduled eighth.
4. **The bill-versus-supply table is printed in the spec** so the next change is checked
   against it instead of re-derived.

Gravemark's `+25% Matter rate` correctly does not add yield — it exhausts a finite supply
sooner. With home Matter at 1400 that is now a real advantage rather than a trap.

### Provisions renewability (accepted, non-blocking)

`ResourceKind.provisions.isRenewable == true` and `startingYield == .infinity`, while a Farm is
a **finite 400**. Any HUD text keyed on `isRenewable` will tell the player a Farm never runs
dry. The Farm's node carries an explicit finite flag and the inspection text reads from the
deposit, not the kind.

---

## 3. Victory

### B10 — one Dominion rule (accepted)

`04` said 180 s with escalation at 8:00/10:00; `00` said 45 s with milestones at 15/30 and
matches the code (`dominionHoldDuration = 45`, `dominionMilestones = [15, 30]`). **`04`'s
version is deleted.** 180 s uncontested cannot fit an 8–10 minute match.

Three further holes, closed:

1. **The Dominion Spire now exists** as a `BuildingKind`: neutral, pre-placed at the Dominion
   centre, **1200 HP**, footprint radius 4.0, melee armour 6 / ranged armour 8,
   **indestructible** (it is an objective, not a target — damage does not apply to it). It is
   the fifteenth building and the only one no player builds.
2. **The capture set is explicit**, not `isMilitary` — which today excludes the Pathfinder and
   would silently exclude Lancer, Sunlance and Ironsworn. Capturing and contesting units are
   **Vanguard, Quarrel, Lancer, Bastion Walker, Sunlance, Ironsworn**. A Pathfinder can *see*
   the Dominion and cannot *hold* it, which is the right shape for a scout. Citizens neither
   capture nor contest.
3. **Contested decays, it does not pause.** An enemy in the ring drains the holder's timer at
   **half the rate it fills**. Mutual occupation therefore always resolves — whoever brought
   more, wins ground — and the promise of "no draw state, no hard timer" survives. A pause rule
   deadlocks forever if both sides keep one unit in the ring, which is exactly what two AIs
   would do.

The timer is **per faction**, not a shared tug-of-war.

### B15 — the Core is exempt from faction HP modifiers (accepted)

A Gravemark Core at 750 against a Sunwoven Core at 510 is **47% tougher on the win condition
the spec names first**, with nothing compensating. `00 §4` asserts "neither is stronger"; on
those numbers it was not established.

**Both Cores are 600, flat.** The faction HP modifier applies to every building except the
Civilization Core and the Dominion Spire. Voyager's `+30%` applies to both Cores equally.

---

## 4. Production

### B12 — queued population is reserved (accepted)

`population(for:)` counts live units only, so at 8/10 a player could enqueue a Walker (3) and
two Citizens (1 each) — five population against two slots — and then `03 §7` forbids the only
escape by prohibiting retroactive deletion.

**Decisions.** Queued items count toward `used`. The check is re-evaluated at spawn; if the cap
is full the item **holds at the front of the queue** with a HUD reason and is never cancelled.
A Dwelling destroyed mid-queue **holds** the affected items rather than refunding them, so
rebuilding resumes production.

---

## 5. The adversary

### B11 — the wave table (accepted)

"A schedule, not a planner" with no schedule is not a specification. Here it is. All times are
simulated, all values are exact, and the whole thing is a pure function of tick count and world
state.

| Wave | Time | Composition | Target |
|---|---|---|---|
| 1 | 4:00 | 3 Vanguard | Nearest player building to the Gravemark Core |
| 2 | 5:30 | 4 Vanguard, 2 Quarrel | Nearest player building |
| 3 | 7:00 | 4 Vanguard, 3 Quarrel, 2 Lancer | Player's newest Expansion Outpost, else nearest building |
| 4 | 8:30 | 5 Vanguard, 4 Quarrel, 2 Lancer, 1 Bastion Walker | Player's Civilization Core |
| 5+ | every 90 s | previous wave + 1 Vanguard + 1 Quarrel | Player's Civilization Core |

Economy schedule: gather with the four starting citizens from tick 0; train Citizens
continuously to 12; Formation Yard at **tick 2400** exactly (2:00); Lumen Spire at tick 4800;
Dawn Loom at tick 7200; Voyager advance when affordable; Stride Yard at tick 9600.

Rules: **no jitter, therefore no random draws at all** — the `adversary` stream is reserved and
tagged but unused in v0, which is stated so nobody assumes it is free to borrow. Waves never
retreat. A wave that loses every unit is simply gone; the schedule does not react. If a target
dies mid-approach the wave retargets by the same rule, evaluated once on target death.

**Also decided:** the player may choose Gravemark, in which case the adversary plays Sunwoven
with the same schedule and its own roster. The adversary is a separate document,
`06-ADVERSARY.md`, and `04`'s inline half-schedule is deleted — as `00 §6` already said it
should be.

---

## 6. The thirteen missing decisions (B14)

Answered in order, each to be written into the section where an implementer will look.

1. **Range is measured between footprints**, edge to edge — `distance(a, b) − aRadius − bRadius`.
   Centre-to-centre would make a Core's 5.0 m radius eat most of a Quarrel's range.
2. **A unit that reached 0 HP earlier in the same tick does not act.** Deaths apply at end of
   tick for *observation*; a dead flag is set immediately and checked at step 1.
3. **"Damaged me most recently" is resolved by the lowest `EntityID` among attackers in the
   same tick.** Same rule as every tiebreak in the model.
4. **Spawn slot is `unit.id.raw % ringSlotCount`**, matching `GatheringSystem.workStation`'s
   existing derivation. "First free slot" over a dictionary is a determinism break.
5. **A Dock-trained Light Transport spawns on its dock's void point**, never a land ring
   position. A hull spawned on land is permanently stuck, because `clampToVoid` holds still
   rather than inventing a berth.
6. **Voyager's `+30% max HP` adds the delta to current HP as well as maximum**, so an advance
   never leaves a building at 77% health. It is a reward, not a dilution.
7. **"A Core cannot be repaired below 25%" is deleted.** It conflicted with the general repair
   rule and bought nothing. Any friendly building repairs at 8 HP/s at any health.
8. **Repair draws Matter in ascending `EntityID` order** when the pool cannot pay everyone.
9. **Drop-off becomes per resource.** `BuildingKind.acceptsDropOff: Bool` becomes
   `acceptedDropOffs: Set<ResourceKind>`, and `GatheringSystem.nearestDropOff` filters on cargo
   kind. Scheduled in CP-G3a, not unscheduled.
10. **`BuildingKind.trains` becomes `trains(for: Faction)`.** The Ember Hall is the only kind
    whose list varies, and a faction-blind static property cannot express it.
11. **Passengers die with their transport.** A transport in the void is targetable only by
    `ranged` and `siege` attackers whose range reaches it; melee units cannot attack a hull.
12. **A Farm's own node is exempt** from the deposit-clearance rule in
    `ConstructionPlacement.isLegal`, and other buildings still respect the clearance around it —
    so a Waystation cannot be placed on top of a Farm.
13. **The world hash** is FNV-1a over, in order: tick; then for each faction in declaration
    order its four resource amounts as centi-units; then every unit in ascending `EntityID` as
    (id, kind, faction, x and z quantised to 1 mm, life in centi-units, activity tag); then
    every building the same way. Defined once, in `SunfoldCore`, used by every determinism test.

---

## 7. Corrections accepted without argument

The arithmetic slips and cross-reference rot are all real. Fixed in place: Vanguard → Ironsworn
is 144 s not 180; the Walker→Core row resolves against melee armour; the Quarrel's range is 9.0
(not 7.0 or 7.5) and the Sunlance holds the largest sight-to-range gap; the Vanguard's cadence
is 1.2 s; `01 §1`'s "nothing costs more than 90 or 26 s" is corrected to name the Bastion
Walker's 110 Matter as the deliberate exception; the Sunlance is not the largest Lumen sink.
`04`'s three wrong section citations are repointed.

**B13 — `04` is rewritten against the real `EntityKinds.swift`.** `.vanguard`,
`UnitActivity.attacking(targetID:)`, `.formationYard`, `.pathfinder` and `.dawnLoom` all already
exist. **HP lives on `Unit.life` and `UnitKind.maxLife`** — adding `hp`/`maxHP` would create two
sources of truth. And **`.ranged` → `.quarrel` is a rename, not an addition**, with call sites
in `SkirmishTuning.rangedCost`/`rangedBuildTime`/`rangedPopulation`, `BuildingKind.trains`,
`isMilitary`, `SelectionPanel`, `UnitMeshes` and `SunfoldPalette`. Following `04` literally
would have shipped a roster containing both a "Ranged" and a "Quarrel".

**`02 §5`'s "unchanged and extended"** is rewritten. `ConstructionPlacement.placeableKinds` is
hardcoded to three kinds and `region(at:) == .sunwovenHome` is hardcoded to one faction, so
today Gravemark can build nothing and an Expansion Outpost can never be placed. The predicate
becomes faction- and region-parameterised, and that is real work, not a footnote.

**Checkpoint naming.** `ROADMAP.md` gate G3 is "Logistics and expansion" and the spec's
`CP-G3a…i` collide with it. The content checkpoints are renamed **`CP-C1…C9`**. Traversal,
being logistics, keeps a G3 name: **`CP-G3a2`**.

**`CONTEXT.md` still names the AoE IV bar** and must be repointed at BC-01, or the next critic
judges against a superseded reference.

---

## 8. What I did not accept

**Nothing was rejected outright.** Two were reframed rather than taken as written:

- The critic offered three options for B9 and I took the first (delete `+3 vs building`) rather
  than accepting the rush and re-scoping T2 as a comeback tier. Re-scoping T2 would have made
  the age-up optional, and a visible tier change is the part of the AoE grammar Directive 1
  names explicitly.
- For B7 the critic offered range, speed, or exempting mounted units from Gravemark's speed
  penalty. I took **both** range and speed, because the invariant it derived — no unit may
  outrun everything that counters it — is not satisfied by the range change alone.

---

## 9. What happens now

1. **CP-G3a2 traversal** — in flight.
2. **CP-C1 production** — in flight, unaffected by these decisions; it implements the queue
   mechanism, and every number lives in `SkirmishTuning` precisely so this retune is one file.
3. **Re-author the five spec files** against this document, then a **second critic round on a
   fresh reviewer** before any roster content is built. The counter matrix must be
   re-derived from the fixed model, not patched — B2 alone inverts five matchups, and a
   patched table would carry the old numbers forward.
4. The building-bill-versus-supply table and the corrected time-to-kill table are the two
   artifacts that must appear in the re-authored spec. They are what made this review possible.
