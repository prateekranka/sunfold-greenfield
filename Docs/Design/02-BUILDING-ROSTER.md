# Building roster

Part of the content design specification. Read `00-CONTENT-SPEC.md` first.

**Fourteen building kinds, shared by both civilizations.** Seven already exist as
`BuildingKind` cases. **Every one of them unlocks something concrete** — that is principle
P4, and it is how this game gets tier progression without the tech-tree sprawl `ROADMAP.md`
forbids: *the tech tree is the base you can see.*

---

## 1. The roster at a glance

| Building | Tier | Prereq | Prov | Matter | Lumen | Build | Footprint r | HP | Unlocks / trains | Drop-off |
|---|---|---|---|---|---|---|---|---|---|---|
| **Civilization Core** | T1 | pre-placed | — | — | — | — | 5.0 | 600 | Trains **Citizen** | all four |
| **Dwelling** | T1 | — | — | 55 | — | 14 s | 2.6 | 180 | **+8 population** | — |
| **Farm** | T1 | — | — | 70 | — | 12 s | 3.6 | 120 | A placeable **Provisions node** | Provisions |
| **Matter Extractor** | T1 | — | — | 60 | — | 14 s | 2.6 | 160 | **+20% Matter rate** within 14 m | Matter |
| **Waystation** | T1 | — | — | 45 | — | 11 s | 2.2 | 140 | Forward **drop-off** | all four |
| **Dock** | T1 | coastal | — | 80 | — | 18 s | 3.4 | 200 | Trains **Light Transport** | all four |
| **Formation Yard** | T1 | — | — | 110 | 20 | 18 s | 4.0 | 260 | Trains **Vanguard**, **Pathfinder** | — |
| **Lumen Spire** | T1 | Formation Yard | — | 90 | 45 | 18 s | 3.0 | 210 | Trains **Quarrel** | Lumen |
| **Warding Post** | T1 | Formation Yard | — | 100 | 25 | 16 s | 2.0 | 280 | **Attacks** enemies in 8.5 m | — |
| **Dawn Loom** | T1 | — | — | 130 | 50 | 26 s | 4.4 | 320 | Researches the **Voyager age** | — |
| **Expansion Outpost** | T1 | off-home region | — | 100 | 30 | 20 s | 3.0 | 240 | **Claims a fragment**, +2 pop, weaves the causeway | all four |
| **Stride Yard** | **T2** | — | 40 | 140 | — | 22 s | 4.0 | 300 | Trains **Lancer** | — |
| **Siege Foundry** | **T2** | Formation Yard | — | 180 | 60 | 26 s | 4.2 | 340 | Trains **Bastion Walker** | — |
| **Ember Hall** | **T2** | Dawn Loom | — | 200 | 90 | 34 s | 4.8 | 480 | Trains your **unique unit** | — |

**Ember Hall is one `BuildingKind` with two faces.** Sunwoven build the **Sun Hall** and
train the Sunlance; Gravemark build the **Grave Bastion** and train the Ironsworn. Same
cost, same footprint, same slot in the tree — different mesh, different livery, different
unit. That is the Castle analogue and it is where most of the 40% differentiation lands.

**Faction HP modifiers apply on top of every row:** Sunwoven **−15%**, Gravemark **+25%**.
A Gravemark Warding Post is 280 × 1.25 × 1.30 = 455 HP; a Sunwoven one is 280 × 0.85 × 0.80
= 190 HP with 10 m of reach. That single row is most of "territorial" versus "mobile".

---

## 2. Structural armour

Every building carries armour class `building`, **melee armour 4, ranged armour 6**, except:

| Building | Melee | Ranged | Why |
|---|---|---|---|
| Civilization Core | 4 | 6 | Standard; its 600 HP is what makes it hard |
| Ember Hall | 6 | 8 | The one structure a raid should not be able to chew through |
| Farm | 0 | 0 | A field. It is meant to be raidable — burning a Farm is a real play |

The consequence, already tabulated in `01-UNIT-ROSTER.md` §3: **massed archers cannot take a
building** (max(1, 6−6) = 1 damage a shot), **infantry can but slowly**, and **siege is the
answer**. Farms are the exception on purpose, so that harassment has a target that does not
require a Bastion Walker.

---

## 3. What each building is actually for

Short, because a building whose purpose needs a paragraph is a building that will not read
on screen.

**Civilization Core.** The one pre-placed building. Trains Citizens, accepts every resource,
and is the Conquest target. Cannot be rebuilt: losing it is losing.

**Dwelling.** The population building. Starting cap is **10**; each Dwelling adds **8**, to
a hard ceiling of 200. Four Dwellings gets a player to 42, which is the intended peak army
for a nine-minute match. *(Current tuning is cap 8 / +4 per Dwelling / 80 Matter; those three
numbers change to 10 / +8 / 55, because eight Dwellings for one army is clicking, not
strategy.)*

**Farm.** Placing a Farm **creates a Provisions deposit at its own position** with a finite
yield of **400**, and accepts Provisions drop-off at zero walking distance. That is exactly
the Age of Empires II farm: a renewable-feeling but finite food source you choose the
location of, that has to be re-laid when it runs out. It reuses the deposit and gathering
systems that already work, and it gives "where do I put this" an answer.

**Matter Extractor.** Raises the gather rate of any citizen working a Matter deposit within
**14 m** by **20%**, and accepts Matter. Placement matters: next to a Matter node it is a
real economic decision, in the middle of your base it is 60 wasted Matter.

**Waystation.** The cheapest building in the game and the one a good player builds most. No
bonus, no unlock — just a drop-off for all four resources, 45 Matter, 11 seconds. It exists
so that "my citizens walk too far" has a cheap answer that costs a decision rather than a
research.

**Dock.** Trains the Light Transport and accepts all four resources. Must be placed on a
coastal cell (the void-adjacency test `WorldMap.dockPoint` already computes).

**Formation Yard.** The barracks. Trains Vanguard and Pathfinder, and gates the Lumen Spire,
the Warding Post and the Siege Foundry. It is the first military building every match.

**Lumen Spire.** The archery range. Trains Quarrel and accepts Lumen. Requiring a Formation
Yard first means the opening is always infantry-then-archers, which is a legible ramp rather
than a menu.

**Warding Post.** The tower. Ranged attack, **base 12 damage, +6 vs `siege`**, range 8.5 m,
cooldown 30 ticks (1.5 s), 16 m sight. The `+6 vs siege` is deliberate: without it a Bastion
Walker out-ranges every tower in the game at 9.0 m and static defence becomes pointless.

**Dawn Loom.** The age building. Does nothing except research the Voyager advance — 20 s
channel, 180 Prov / 180 Matter / 100 Lumen / 80 Aether, cancellable for 75%. It costs 130
Matter and 50 Lumen and 26 seconds to build, so committing to age up is itself a decision.

**Expansion Outpost.** Claims a non-home fragment, grants +2 population, accepts all four
resources, and weaves the home causeway (the existing G3 behaviour). **This is how you reach
Aether**, and therefore how you reach Voyager.

**Stride Yard.** The stable. Trains the Lancer. First T2 military building, and the cheapest
of the three, so the age-up has an immediate visible payoff.

**Siege Foundry.** Trains the Bastion Walker. The most expensive non-unique building because
siege ends games.

**Ember Hall.** Trains the unique unit. 34 seconds and 200 Matter / 90 Lumen — a player who
builds one is choosing it over roughly four Dwellings' worth of army.

---

## 4. Production

One shared production model for every building that trains anything.

| Rule | Value |
|---|---|
| Queue length | **10** per building (`SkirmishTuning.maxQueueLength`, unchanged) |
| Cost timing | **Charged on enqueue**, not on spawn — so a queue cannot be used as free storage |
| Cancel | Refunds **100%** if the item has not started; **`cancelRefundFraction` (75%)** if it is in progress |
| Population | An enqueue is **refused** when `used + populationCost > cap`. The tile dims and the HUD says why. It is never silently dropped |
| Progress | Linear, driven by the fixed 20 Hz step. Only the **front** item progresses |
| Spawn | At the building's rally point, defaulting to a ring position beside the building resolved through `WorldMap` |
| Rally | Settable per building by tapping the ground with the building selected. The command grid's existing "Set rally point" tile becomes live |
| Determinism | Build times are integer tick counts. Nothing in production consumes randomness |

**Why cost-on-enqueue.** The alternative — charging on spawn — lets a player queue ten units
they cannot afford and have the queue drain their income invisibly. Charging up front makes
the resource bar tell the truth, which matters more here than it would in a longer game.

---

## 5. Placement rules

Unchanged from `Sources/Simulation/ConstructionPlacement.swift` and extended:

- Full-footprint legality against terrain, the rim, other buildings and deposits.
- **Explored cells only** (per `CONTEXT.md`). Until fog exists, explored is treated as all
  home-and-claimed land.
- Land only. No building may be placed in void.
- **Dock** additionally requires a coastal cell.
- **Expansion Outpost** additionally requires a non-home region.
- **Lumen Spire, Warding Post, Siege Foundry** additionally require a *completed* Formation
  Yard of the same faction. **Ember Hall** requires a completed Dawn Loom.
  A missing prerequisite dims the command tile and states the prerequisite by name — it
  never lets the player enter placement mode and then deny them at commit.

---

## 6. Command grid layout

The grid is a fixed 3×3 and a command that does not apply dims **in place** (mandate:
muscle memory for a command's *position* is most of what makes an RTS fast). Fourteen
buildings do not fit in nine tiles, so buildings are paged.

**With a Citizen selected — page 1 (Economy):**

| | | |
|---|---|---|
| Farm | Matter Extractor | Waystation |
| Dwelling | Dock | Expansion Outpost |
| Stop | Guard | **▸ Military** |

**With a Citizen selected — page 2 (Military):**

| | | |
|---|---|---|
| Formation Yard | Lumen Spire | Warding Post |
| Stride Yard | Siege Foundry | Ember Hall |
| Dawn Loom | Guard | **◂ Economy** |

**With a production building selected:** its trainable units in the top row, the age
advance where applicable, then Set Rally · Stop · Cancel.

Two pages, not a scroll and not a reflow. The page toggle sits in the same corner on both
pages so it is one muscle-memory position, and the economy page is always the default —
which is the page a player needs in the first ninety seconds.
