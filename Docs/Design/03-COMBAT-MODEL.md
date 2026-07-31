# Combat model

Part of the content design specification. Read `00-CONTENT-SPEC.md` first.

This document is the implementable contract for how one entity damages another. It is
written to be read by someone who has to make `Sources/Simulation/CombatSystem.swift`
produce bit-identical results from the same seed on every run.

---

## 1. The damage formula

```
effective = max(1, (base + bonus(attacker.damageType, target.armorClass)) - armor(target, attacker.damageType))
```

- `armor(target, .melee)`   → `target.meleeArmor`
- `armor(target, .ranged)`  → `target.rangedArmor`
- `armor(target, .siege)`   → `target.meleeArmor`  *(siege is resolved against melee armour;
  siege units are close-range machines, not archers)*

**The floor of 1 is load-bearing.** Without it, a Quarrel shooting a Warding Post does 6 − 6
= 0 and the game silently teaches the player that their army is broken. With it, the answer
is "1 damage a shot, 280 shots — go get siege", which is the same lesson delivered legibly.

**There is no damage variance and there is no miss chance.** Two reasons, in order of
importance. First, determinism: every source of randomness is a stream that has to be
tagged, ordered and never perturbed by an unrelated subsystem, and combat is the highest-
frequency event in the game. Second, readability: in an eight-minute match a player has to
be able to look at nine Vanguard versus six Quarrel and know who wins. Variance makes that
a distribution instead of an answer.

---

## 2. Armour classes and damage types

Three damage types, four armour classes.

| Damage type | Who deals it |
|---|---|
| `melee` | Vanguard, Lancer, Sunlance, Ironsworn, Citizen |
| `ranged` | Quarrel, Pathfinder, Warding Post |
| `siege` | Bastion Walker |

| Armour class | Who has it |
|---|---|
| `infantry` | Vanguard, Ironsworn, Citizen, Pathfinder |
| `mounted` | Lancer, Sunlance |
| `light` | Quarrel, Light Transport |
| `building` | every building, and the Bastion Walker |

**The Bastion Walker carrying `building` armour class is the pivot of the whole roster.** It
is what makes the anti-building Vanguard bonus (`+3 vs building`) double as the anti-siege
answer, so the counter graph closes without a fifth unit. It is also why the Warding Post
needs `+6 vs siege` written against the *damage type* rather than the armour class — the
tower has to beat the walker specifically, not everything with thick plating.

Bonus damage is a lookup on `(damageType, armorClass)`, applied **before** armour
subtraction. The full table lives in `01-UNIT-ROSTER.md` §3; it is data, not code.

---

## 3. Resolution on the 20 Hz tick

`CombatSystem.step(context:)` runs once per simulation tick, at a fixed 50 ms. It runs
**after** movement and **before** production, so a unit that moved into range this tick can
fire this tick, and a unit that died this tick cannot be paid for.

Per tick, for each armed entity **in ascending `EntityID` order**:

1. **Cooldown.** `cooldownRemaining -= 1`. If still positive, stop.
2. **Validate target.** If the current target is dead, out of sight range, or has boarded a
   transport, clear it.
3. **Acquire.** If there is no target, choose one (§4).
4. **Range.** If a target exists but is beyond `range`, and the stance permits it, issue a
   move toward the target and stop.
5. **Fire.** Apply `effective` damage immediately. Set `cooldownRemaining = cooldownTicks`.
6. **Death.** If the target's HP reached 0, mark it dead and append it to the tick's death
   list.

Deaths are **applied at the end of the tick**, not inside the loop, so that two units that
kill the same target on the same tick both resolve and neither observes a half-mutated
world. This is the standard fix for order-dependence and it is why step 1 iterates in
`EntityID` order: the iteration order of a Swift `Dictionary` is not stable across runs and
using it directly would break determinism for exactly the reason the mandate warns about.

**Combat consumes no randomness whatsoever.** There is no `combat` stream to tag. If a
future feature needs one — scatter for area damage, say — it gets its own tagged stream per
architecture rule 5, and it must not be drawn from inside the per-entity loop above.

---

## 4. Target acquisition

Deterministic, in this priority order:

1. The player's **explicitly commanded** target, if alive and reachable. An explicit order
   never re-targets on its own.
2. The **entity that damaged me most recently**, if within sight.
3. The **nearest hostile within sight range**, breaking ties by **lower `EntityID`**.

Citizens are the exception: they never auto-acquire. A citizen fights only when explicitly
ordered to, and returns to its previous job when the target dies. Losing your economy
because your villagers walked into a raid is a Warcraft behaviour, not an Age one.

Sight range is a per-kind value (`01-UNIT-ROSTER.md` §3) and is always **greater than**
weapons range, so a unit always sees what shoots it. The Quarrel's 7.0 range against 13.0
sight is the largest gap in the roster and is what makes archers feel like archers.

---

## 5. Stances

Three, on a single cycling control, defaulting to **Guard**.

| Stance | Auto-acquires | Chases |
|---|---|---|
| **Aggressive** | Yes | Yes, without limit |
| **Guard** (default) | Yes | Up to **6 m** from the position it held when it acquired, then returns |
| **Hold** | Yes | Never — fires only at what enters range |

Guard as the default is deliberate. Aggressive as a default produces the single most
frustrating RTS moment there is: an army that dissolves because it chased one scout across
the map. Guard's 6 m leash means a line holds where you put it while still punishing anyone
who walks into it.

---

## 6. Projectiles

**The simulation applies damage instantly on fire. Projectiles are cosmetic.**

The renderer spawns a tracer from the attacker to the target's position at the moment of
fire and animates it over ~180 ms. If the target dies before the tracer lands, the tracer
still lands — on the corpse, or on the last known position.

The alternative, an in-flight projectile entity that resolves on arrival, is more physically
honest and it is what Age of Empires II actually does. It is rejected here because it puts a
second mutable entity collection inside the deterministic core for something the player
cannot perceive at 20 Hz over a 7 m range, and because "my arrows were in the air when he
died" is a source of desync bugs out of all proportion to its value. If a design need later
demands real ballistics — a mortar arcing over a wall — this decision gets revisited then,
with a tagged stream if it needs one.

---

## 7. Death and cleanup

- A dead unit is removed from the simulation at end of tick and its population is freed.
- A dead building is removed and **anything it was training is refunded at `cancelRefundFraction`** (75%).
- Losing a Dwelling **reduces the population cap immediately**. If that puts the player over
  cap, nothing dies — they simply cannot train until they are back under. Retroactive unit
  deletion is never acceptable.
- The renderer plays a death effect and holds a corpse decal for ~4 s. The corpse is
  presentation only; it has no simulation presence and cannot be targeted.
- A destroyed **Civilization Core** triggers the Conquest check in `VictorySystem`.

---

## 8. Repair

A Citizen ordered onto a damaged friendly building repairs it at **8 HP/s**, costing
**0.5 Matter per HP** drawn continuously from the pool. Repair stops at full HP, when the
pool empties, or on any new order. Up to `maxBuildersPerSite` citizens may repair one
building, with the same diminishing-returns curve construction uses.

Repair reuses the construction assignment path wholesale, which is why it is specified here
rather than deferred: it is a handful of lines on top of CP-G2a's work and it is what makes
the Warding Post and the Gravemark identity mean anything. A defensive faction whose
buildings cannot be healed is not a defensive faction.

---

## 9. What combat must never do

A checkpoint that does any of these fails outright.

- Read wall-clock time, frame time, or `Date()` inside `CombatSystem`.
- Iterate an unordered collection to decide who fires first.
- Call `Double.random`, `Int.random`, `shuffled()`, or `SystemRandomNumberGenerator`.
- Apply damage from the renderer, or let the renderer decide whether a shot connects.
- Scale damage, cooldown or movement by anything derived from the display refresh rate.
