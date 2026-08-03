# Unit roster

Part of the content design specification. Read `00-CONTENT-SPEC.md` first.

**Nine unit kinds: seven shared, one unique per civilization.** Six of the seven shared
kinds already exist as `UnitKind` cases; the numbers below replace the current placeholder
values, which were never balanced against each other because nothing could fight.

---

## 1. The roster at a glance

| Unit | Role | Tier | Trained at | Pop | Prov | Matter | Lumen | Build |
|---|---|---|---|---|---|---|---|---|
| **Citizen** | Economy | T1 | Civilization Core | 1 | 50 | — | — | 14 s |
| **Pathfinder** | Scout | T1 | Formation Yard | 1 | 35 | — | 10 | 11 s |
| **Vanguard** | Infantry | T1 | Formation Yard | 1 | 45 | 20 | — | 13 s |
| **Quarrel** | Ranged | T1 | Lumen Spire | 1 | 35 | — | 30 | 15 s |
| **Light Transport** | Logistics | T1 | Dock | 0 | — | 60 | — | 20 s |
| **Lancer** | Mounted | **T2** | Stride Yard | 2 | 55 | 35 | — | 18 s |
| **Bastion Walker** | Siege | **T2** | Siege Foundry | 3 | 40 | 110 | — | 26 s |
| **Sunlance** *(Sunwoven only)* | Unique — mounted ranged | **T2** | Sun Hall | 2 | 60 | 20 | 55 | 20 s |
| **Ironsworn** *(Gravemark only)* | Unique — heavy infantry | **T2** | Grave Bastion | 2 | 60 | 70 | — | 20 s |

Nothing costs more than 90 resources or 26 seconds. That is principle P2 and it is the whole
reason a counter mistake is survivable.

---

## 2. The counter structure

This is the part that makes the roster a game rather than a list. Read it before any table.

```
                 Vanguard  (infantry)
                    ▲            ▲
        beats  ╱                    ╲  beaten by
              ╱                        ╲
        Lancer  ◄─── beaten by ────  Quarrel
      (mounted)  ──── beats ────►    (ranged)
```

- **Vanguard beats Lancer.** Vanguard carries **+12 bonus damage vs `mounted`**. A Lancer
  that charges a spear line dies in about 7 seconds; the same Lancer kills a Quarrel in 6.
- **Lancer beats Quarrel.** The Lancer is 68% faster (5.4 m/s against 3.2) and takes almost
  nothing on the way in — Quarrel's `+4 vs infantry` bonus does not apply to a `mounted`
  target, so the Lancer closes on 4 damage a shot and then hits for 9.
- **Quarrel beats Vanguard.** `+4 bonus vs infantry` and a 7.5 m range against Vanguard's
  0.9 m. The Vanguard spends the entire approach being shot and arrives having lost most of
  its health.

**Off the ring, doing jobs the ring cannot:**

- **Bastion Walker (siege)** is the only unit that can meaningfully hurt a building
  (`+45 vs building`). It is slow (2.6 m/s), fragile to anything mobile, and costs 3
  population. It exists so that a turtled base is a target rather than a wall.
- **Pathfinder (scout)** beats nothing. It is 4.6 m/s with 20 m of sight — double anything
  else — and `+5 vs worker`. It exists so that *knowing* is a thing you spend resources on,
  and so an unguarded citizen line is punishable.

**The unique units bend the ring without breaking it:**

- **Sunlance** is mounted (so Vanguard's `+12` still answers it) but attacks at 6 m, so it
  beats Quarrel *and* trades well into Vanguard — at 55 Lumen it is the most expensive
  Lumen sink in the game, and Sunwoven's `−15%` building HP means they cannot afford to
  turtle while they save for it.
- **Ironsworn** is infantry (so Quarrel's `+4` still answers it) with **melee armour 6** —
  it reduces a Vanguard's 7-damage hit to 1. It beats every melee unit in the game and
  loses to massed Quarrel, which is exactly the pressure Gravemark's slow clock invites.

---

## 3. Full statistics

Damage, armour and range semantics are defined in `03-COMBAT-MODEL.md`. Cooldowns are
**integer ticks at 20 Hz** so that combat can never depend on frame rate.

### Combat statistics

| Unit | HP | Dmg type | Base dmg | Bonus damage | Melee armour | Ranged armour | Armour classes | Range (m) | Cooldown (ticks / s) | Speed (m/s) | Sight (m) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Citizen** | 40 | melee | 3 | +3 vs `building` | 0 | 0 | `worker` | 0.8 | 30 / 1.5 | 3.4 | 9 |
| **Pathfinder** | 45 | melee | 4 | +5 vs `worker` | 0 | 0 | `infantry` | 0.9 | 26 / 1.3 | 4.6 | **20** |
| **Vanguard** | 75 | melee | 7 | **+12 vs `mounted`**, +3 vs `building` | 1 | 0 | `infantry` | 0.9 | 24 / 1.2 | 3.0 | 11 |
| **Quarrel** | 50 | **ranged** | 6 | **+4 vs `infantry`** | 0 | 0 | `infantry` | **7.5** | 28 / 1.4 | 3.2 | 13 |
| **Lancer** | 100 | melee | 9 | +6 vs `worker`, +8 vs `siege` | 2 | 2 | `mounted` | 1.0 | 22 / 1.1 | **5.4** | 14 |
| **Bastion Walker** | 190 | **ranged** | 20 | **+45 vs `building`** | 3 | 4 | `siege` | **9.0** | 60 / 3.0 | 2.6 | 10 |
| **Light Transport** | 140 | — | — | — | 2 | 2 | `hull` | — | — | 5.2 | 14 |
| **Sunlance** | 80 | **ranged** | 8 | +5 vs `infantry` | 1 | 1 | `mounted` | **6.0** | 24 / 1.2 | 4.8 | 15 |
| **Ironsworn** | 120 | melee | 10 | +4 vs `building` | **6** | 2 | `infantry` | 1.0 | 30 / 1.5 | 2.7 | 11 |

Faction modifiers from `00-CONTENT-SPEC.md` §4 apply on top: Sunwoven Pathfinders are
`+4 sight / +10% speed / −20% cost`; every Gravemark land unit is `−8% speed`.

### Time-to-kill, computed from the table above

Sanity check that engagements resolve inside a five-to-fifteen-second window. This is the
evidence that the numbers are a design and not a wish.

| Attacker → Defender | Damage per hit | DPS | Seconds to kill |
|---|---|---|---|
| Vanguard → Lancer | (7 − 2) + 12 = 17 | 14.2 | **7.0** |
| Lancer → Vanguard | 9 − 1 = 8 | 7.3 | 10.3 |
| Lancer → Quarrel | 9 − 0 = 9 | 8.2 | **6.1** |
| Quarrel → Lancer | 6 − 2 = 4 | 2.9 | 34.5 |
| Quarrel → Vanguard | (6 − 0) + 4 = 10 | 7.1 | **10.5** |
| Vanguard → Quarrel | 7 − 0 = 7 | 5.8 | 8.6 *(but only after closing 6.6 m under fire)* |
| Lancer → Citizen | (9 − 0) + 6 = 15 | 13.6 | **2.9** |
| Bastion Walker → Civilization Core | (20 − 6) + 45 = 59 | 19.7 | **30.5** |
| Vanguard → Civilization Core | (7 − 4) + 3 = 6 | 5.0 | 120 |
| Quarrel → Civilization Core | max(1, 6 − 6) = 1 | 0.7 | 840 |
| Ironsworn → Vanguard | 10 − 1 = 9 | 6.0 | 12.5 |
| Vanguard → Ironsworn | max(1, 7 − 6) = 1, +0 | 0.7 | **180** |
| Quarrel → Ironsworn | (6 − 2) + 4 = 8 | 5.7 | 21.0 |

Read the last three rows together: **Ironsworn is functionally immune to melee and dies to
massed ranged.** That is the intended shape, it is legible in play, and it is what stops
Gravemark's heavy line from being an auto-win.

Read the Core rows together: **one Bastion Walker takes 30 s on a Core; three take 10 s; ten
Vanguards take 12 s; archers cannot do it at all.** Siege is required for a fast Conquest
and optional for a slow one.

### Economy statistics

| | Citizen |
|---|---|
| Gathers | Provisions, Matter, Lumen, Aether |
| Base rates | 1.6 / 1.4 / 1.1 / 0.9 per second while working (`SkirmishTuning.gatherRates`, unchanged) |
| Carry capacity | 10 (unchanged) |
| Constructs | Yes — up to 4 per foundation, linear progress |
| Faction modifier | Sunwoven +25% Lumen · Gravemark +25% Matter |

Citizens can fight (3 damage) so that a base raid is a fight rather than an execution, and
so a losing player has something to do. They are not a military answer to anything.

---

## 4. Sight, and why the scout is a real unit

Sight radius currently does nothing because there is no fog of war. It is specified here
anyway, because the numbers must be authored *before* fog exists or the roster will need
re-tuning the day it lands. `CONTEXT.md` already defines the exploration contract
(explored = ever-revealed, permanent; visible = currently inside a revealer's sight;
revealers are mobile units plus the Core and completed buildings).

Buildings reveal: Civilization Core 18 m · Warding Post 16 m · Expansion Outpost 14 m ·
Dock 12 m · everything else 9 m.

**The Pathfinder's 20 m against a Vanguard's 11 m is the entire justification for its
existence.** If fog never ships, the Pathfinder collapses into "a fast cheap unit" and the
roster loses a role. Flag that dependency; do not quietly re-tune the scout to compensate.

---

## 5. Naming, and what each unit reads as on screen

Readability is a bar (`00-CONTENT-SPEC.md` principle 5), so silhouette is specified with the
statistics, not left to the mesh author.

| Unit | Silhouette contract |
|---|---|
| **Citizen** | Smallest humanoid. Carries a visible load. No weapon at rest. |
| **Pathfinder** | Citizen height, leaner, forward-leaning stance, a tall thin standard — reads as *fast* from directly above. |
| **Vanguard** | Broadest humanoid. A long haft held vertical — the vertical line is the read at distance. |
| **Quarrel** | Citizen height, crouched, a horizontal bow-like arc — the horizontal line against Vanguard's vertical one. |
| **Lancer** | Tallest and longest. A quadruped mount plus rider; a low horizontal mass that is unmistakable at any zoom. |
| **Bastion Walker** | Largest by area. Four legs, no rider, a heavy dorsal barrel. Reads as a machine, not a person. |
| **Sunlance** | Lancer proportions, ivory and gold, a long forward-pointing luminous spar. |
| **Ironsworn** | Vanguard proportions at 1.3× mass, slab shoulders, charcoal and copper. Reads as *armoured*. |
| **Light Transport** | Unchanged. |

**The vertical/horizontal opposition between Vanguard and Quarrel is deliberate.** They are
the two units a player must distinguish fastest and most often, they are the same height,
and at default zoom a player has about ten pixels to do it in.
