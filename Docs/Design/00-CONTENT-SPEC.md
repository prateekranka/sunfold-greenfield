# Sunfold Greenfield — content design specification

**Status:** authored 2026-07-31 by the director, under human Directives 1 and 3.
**Authority:** this is the single source of truth for game content. A builder may not invent
a unit, a building, a cost, a counter relationship or a victory rule that is not in these
files. If the specification is wrong, the fix is a specification change reviewed by a fresh
critic — never an improvisation in Swift.

**Read in this order.**

| File | Holds |
|---|---|
| `00-CONTENT-SPEC.md` (this file) | Design principles, tier progression, faction differentiation, victory and defeat |
| `01-UNIT-ROSTER.md` | Every unit: role, counters, cost, build time, population, HP, damage, armour, speed, range, sight, trainer, tier |
| `02-BUILDING-ROSTER.md` | Every building: cost, build time, footprint, HP, what it unlocks, what it trains, tier |
| `03-COMBAT-MODEL.md` | Damage and armour classes, deterministic resolution on the 20 Hz step, targeting, aggro |
| `04-IMPLEMENTATION-ORDER.md` | The checkpoint sequence that builds this, ordered by player-visible impact |

---

## 1. What this specification is answering

The game today has a complete verb set of **select, move, gather, build**. It has six unit
kinds (four of which nothing can produce), seven building kinds, no production, no combat,
no opponent behaviour and no way to win or lose. The human's Directive 3 is explicit:
*more units, more buildings*, and the play-feel bar has moved from Age of Empires IV to
**Age of Empires II: The Rise of Rome, in space** (bar change BC-01 in
`Docs/Gauntlet/00-PLAN.md`).

Everything here is designed backwards from six properties of that grammar:

1. **A broad roster of cheap, readable units with a clear counter structure.**
2. **A broad roster of buildings, each of which unlocks something concrete.**
3. **Tier progression that visibly changes what you can build.**
4. **Villager-driven economy with distinct resource types and drop-off buildings.**
5. **Fast, legible, high-contrast readability** — you can tell at a glance what every unit
   is and what it is doing.
6. **Short build times, a tight loop, and a match that resolves** in 8–10 minutes.

## 2. Design principles this specification commits to

**P1 — The counter triangle is the product, not a stat table.** A roster without counters is
a list. Three roles beat each other in a ring (`01-UNIT-ROSTER.md` §2), and two more sit
off the ring doing jobs the ring cannot. Every number below exists to make that ring
readable inside one five-second engagement.

**P2 — Cheap and many, not expensive and few.** No military unit costs more than ~90
resources or takes more than 26 seconds. A player should be losing units without it being a
disaster, because that is what makes a counter mistake teachable rather than fatal.

**P3 — No damage variance, anywhere.** Every attack does exactly its computed damage. This
is a deliberate determinism choice, not an omission: it removes a whole class of replay
divergence, and it is also what makes a counter legible — "my spears beat their riders" is
either true or it is not, and the player can see it.

**P4 — No research nodes.** There is exactly one researched thing in the whole game: the age
advance. Everything else is unlocked by *constructing a building*, which is visible on the
map and costs the same resources the player is already reading. `ROADMAP.md` forbids
tech-tree sprawl, and this is how that constraint is honoured while still delivering
progression: **the tech tree is the base you can see.**

**P5 — Two tiers, not three.** Considered and rejected: a third age. `ROADMAP.md`
§"Explicitly out of scope" names *the Ascension age* as a no-go, and a third tier would also
double the balance surface for a nine-minute match. Progression breadth comes from building
prerequisites instead (P4), which is the same lever Age of Empires II uses for its
Blacksmith and Castle. **If the human wants a third tier, that is a bar change and it needs
them.**

**P6 — 60% shared grammar, 40% differentiated.** Both civilizations build the same fourteen
buildings and train the same seven shared units. The 40% is one unique unit each, one
unique building skin and behaviour each, and a small set of stat modifiers that follow from
the fiction already locked in the mandate. Differentiation is never a unit the other side
cannot answer.

**P7 — Nothing renders that the simulation does not own.** Every number here belongs in
`Sources/Domain` (pure Swift). The renderer reads it. This is not negotiable and it is what
makes the roster testable.

---

## 3. Tier progression

Two tiers. They are the existing `Age` enum — `foundation` and `voyager` — and no third
case is added.

### Foundation (T1) — the opening, minutes 0–3

Where every match starts. Everything needed to run an economy, scout, and field the base
counter triangle.

**Unlocked at T1:** Citizen · Pathfinder · Vanguard · Quarrel · Light Transport.
**Buildable at T1:** Civilization Core (pre-placed) · Dwelling · Farm · Matter Extractor ·
Waystation · Dock · Formation Yard · Lumen Spire · Warding Post · Dawn Loom ·
Expansion Outpost.

### Voyager (T2) — the contest, minutes 3–10

**How you advance.** Build a **Dawn Loom** (T1 building, 130 Matter · 50 Lumen, 26 s), then
research the Voyager channel at it.

**What advancing costs.**

| | |
|---|---|
| Resources | 180 Provisions · 180 Matter · 100 Lumen · 80 Aether |
| Channel | 20 seconds, visible in the world and in the HUD, cancellable for a 75% refund |
| Prerequisite | A completed Dawn Loom |

**Aether is the gate, and it is a map gate, not a wallet gate.** Aether does not exist on
either home fragment — `WorldPopulator.depositPlan` places it only on the expansions, the
Dominion and the two neutral outcrops. **You cannot reach Voyager without leaving home.**
That is the whole reason the tier exists: it converts "age up" from a menu click into a map
decision, and it makes the Light Transport and the Expansion Outpost load-bearing instead of
decorative. Keep this property; it is the single best structural idea in the progression.

**What Voyager visibly unlocks.**

| Unlocked | Kind |
|---|---|
| **Stride Yard** | Building — trains the mounted line |
| **Siege Foundry** | Building — trains the siege line |
| **Ember Hall** (Sun Hall / Grave Bastion) | Building — trains your unique unit |
| **Lancer** | Unit — mounted, from the Stride Yard |
| **Bastion Walker** | Unit — siege, from the Siege Foundry |
| **Sunlance** / **Ironsworn** | Unit — your civilization's unique, from the Ember Hall |
| Core, Formation Yard, Lumen Spire, Warding Post | **+30% max HP**, applied on advance |

The +30% structure HP is what makes the age change *felt* rather than read: the moment you
advance, your base stops folding to the units that were beating it a minute ago.

---

## 4. Faction differentiation

Both civilizations share all fourteen buildings and all seven shared units. What differs:

### Sunwoven — mobile, luminous, far-seeing; light on static defence

Warm ivory, saffron, woven gold, restrained turquoise.

| Difference | Value |
|---|---|
| **Unique unit** | **Sunlance** — fast mounted skirmisher that attacks at range |
| Lumen gathering | **+25%** rate |
| Pathfinder | **−20% cost**, **+4 sight**, **+10% speed** |
| Light Transport | **+1 capacity** (5 not 4), **+15% speed** |
| All buildings | **−15% max HP** |
| Warding Post | **−20% HP**, **+1.5 range** |
| Expansion Outpost | **−15% cost** |

### Gravemark — heavy, deliberate, territorial; strong at Matter; slow to expand

Charcoal, slate, mineral blue, oxidised copper.

| Difference | Value |
|---|---|
| **Unique unit** | **Ironsworn** — heavy armoured infantry that holds a line |
| Matter gathering | **+25%** rate |
| All buildings | **+25% max HP** |
| Warding Post | **+30% HP**, **+25% damage** |
| All land units | **−8% speed** |
| Expansion Outpost | **+20% cost** |
| Matter Extractor | **+20%** drop-off bonus radius |

### Why this is 40% and not 10%

The two civilizations play a different *map*. Sunwoven expand early, scout constantly, take
the Aether outcrops first, and age up sooner — and then have to hold ground with units
because their buildings will not do it. Gravemark turtle on a Matter economy behind
buildings that genuinely resist damage, reach Voyager later, and win by arriving with
Ironsworn and siege into a base that cannot stop them. Neither is stronger; they are on
different clocks. That asymmetry is what the mandate's "unequal temperament" means, and it
is expressed entirely through this table plus one unit each.

---

## 5. Victory and defeat

The simulation currently has neither. This is the locked promise: **two win paths, resolving
in 8–10 minutes.**

### Win path 1 — Conquest

**Destroy the enemy Civilization Core.**

| | |
|---|---|
| Core HP | 600 (`SkirmishTuning.enemyCoreLife`, unchanged) |
| Telegraph | Structural calamity beats at **75% / 50% / 25%** remaining (`corePressureThresholds`, unchanged) — the Core visibly damages, an alert fires, and the minimap pulses |
| Trigger | The Core reaches 0 HP |
| Defeat mirror | Your own Core reaches 0 HP |

A Core cannot be repaired below 25% in this slice. Losing it is meant to be recoverable
right up until it is not.

### Win path 2 — Dominion

**Hold the Dominion Spire for a continuous period.**

The Dominion fragment sits equidistant from both Cores (a locked map property — only Core
centres need equal distance from the Dominion). It carries a neutral **Dominion Spire**.

| | |
|---|---|
| Capture | Stand any military unit inside 12 m of the Spire with no enemy military unit inside 12 m |
| Hold requirement | **45 s** continuous (`dominionHoldDuration`, unchanged) |
| Milestones | Alert + world beat at **15 s** and **30 s** held (`dominionMilestones`, unchanged) |
| Contest | An enemy military unit entering the ring **pauses** the timer; it does not reset it. Clearing them resumes it |
| Reset | The timer resets to zero only if the holder has **no** military unit in the ring for 8 continuous seconds |
| Trigger | The hold timer reaches the requirement |
| Defeat mirror | The opponent completes their hold |

### The escalation that guarantees the match resolves

An 8–10 minute promise cannot rest on both players choosing to attack. The Dominion hold
requirement **shortens as the match runs long**:

| Match time | Hold required |
|---|---|
| 0:00 – 7:00 | 45 s |
| 7:00 – 9:00 | 30 s |
| 9:00 onward | 20 s |

This is deterministic (it is a function of `clock.elapsed` only), it is visible in the HUD
objective rail, and it converts a stalemate into a forced fight over one piece of ground
rather than into a timeout. **No hard match timer, no draw state.**

### Resign and the match-over state

- The player may resign from the pause menu. Resigning is a defeat.
- On victory or defeat the simulation enters a terminal `MatchOutcome` state, stops
  stepping, and the HUD shows an outcome overlay with the win path, the elapsed time and a
  **Play Again** that resets every deterministic system from the same seed.
- `MatchOutcome` is owned by `SkirmishSimulation`, not by the renderer.

---

## 6. What this specification deliberately does not contain

Recorded so a later agent does not read an omission as an oversight.

- **No walls.** A wall system needs pathfinding that respects obstacles; `MovementSystem`
  currently walks straight lines with land clamping. Defensive play is served by the Warding
  Post and by Gravemark's building HP. Walls are a separate, larger decision.
- **No upgrades or research** beyond the single age advance (principle P4).
- **No naval combat.** The Light Transport is logistics; it does not fight.
- **No air units.**
- **No third age** (principle P5).
- **No hero units, no formations, no stances beyond the aggro rule in `03-COMBAT-MODEL.md`.**
- **No AI opponent behaviour is specified here.** The Gravemark AI is a separate document
  and a separate checkpoint; this file specifies only what both sides *can* do. Until that
  AI exists, Conquest is winnable against a passive opponent and Dominion is winnable
  uncontested — which is enough to prove both paths end a match.
