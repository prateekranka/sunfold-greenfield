# Deterministic simulation inside the Three.js runtime

Issue #22. Companion to `threejs-wkwebview.md`, which records the shell and
bridge decisions from #21.

Issue #19 moved simulation ownership into the Three.js runtime. This document
records how that ownership works, what was carried across from the Swift
implementation, and — just as importantly — what was not.

## 1. One authoritative simulation

`ThreeRuntime/src/sim/simulation.js` owns all game truth. Swift decides no rule,
holds no entity and reads no position. The renderer projects state and never
writes to it.

There is no per-frame Swift ↔ JavaScript traffic of any kind. The bridge carries
six commands in and twelve events out, all of them lifecycle, save or terminal.
A save document crosses on `saveGame` → `saveReady` and `loadGame`; that is one
message at a player-driven moment, which #19 explicitly permits.

The Swift `Sources/Simulation` and `Sources/Domain` trees remain on this branch
untouched as the native fallback and as the reference these rules were ported
from. They are not compiled into the `SunfoldThreeJS` scheme's gameplay path and
they do not run.

## 2. The 20 Hz clock

`sim/clock.js`.

- Fixed step: **20 Hz**, `stepDuration = 0.05 s`. Never derived from frame time.
- `maxStepsPerFrame = 5`. A frame that arrives after a stall runs at most five
  steps and the surplus is **dropped**, not replayed as a burst. A game resumed
  from the background must not fast-forward through the time it was away.
- `elapsed` is recomputed as `tick × stepDuration` rather than accumulated, so a
  long match cannot drift by summed floating-point error. Tick 36 000 is exactly
  1800 s on every run and on every device.
- The sub-step accumulator is presentation residue. It is not hashed and not
  saved — restoring it would make a reload depend on where inside a frame the
  save happened.

Render cadence therefore cannot change an outcome. Two runs that reach the same
tick have run the same number of identical steps, whatever the display did.

## 3. Seeded randomness

`sim/rng.js`, ported from `Sources/Simulation/DeterministicRandom.swift`.

- **SplitMix64**, implemented on pairs of 32-bit halves (`sim/int64.js`) so every
  operation is exact and allocation-free. `BigInt` would be exact but allocates
  per operation, which is not affordable inside a 20 Hz step at benchmark
  density.
- Verified against an independent Python reference implementation: the raw
  64-bit outputs, the `unitFloat` values to 17 significant digits, and the FNV-1a
  stream-tag hashes all match bit for bit.
- `unitFloat()` takes the top 24 bits and divides by 2²⁴. Both operands are
  exactly representable, so the quotient is exact on every IEEE 754 engine.
- **Tagged streams.** Each subsystem draws from `state.random.stream(tag)`, seeded
  as `seed XOR fnv1a64(tag)`. Adding a draw in one subsystem cannot shift the
  numbers another receives. Tags are registered in `RNG_STREAM_TAGS`; an
  unregistered tag raises rather than silently creating a new stream.
- There is no unseeded `Math.random()` anywhere in `sim/`. This is enforced by a
  test that greps the shipped bundle, not merely by review.

## 4. Identity, ordering and quantisation

- **Identity** is a durable integer from `EntityIDAllocator`, never an array
  index. Ids are allocated in a fixed declaration order so a replay matches.
- **Ordering.** Every rule that walks entities walks `EntityStore.ordered()` —
  ascending id. Insertion order is not a stable identity across a save/restore
  round trip, and `Map` order would make a contested resource a coin flip.
- **Ties break on ascending id.** Every "nearest", "best" or "first" selection
  that can tie says so explicitly.
- **Quantisation.** The world hash quantises positions to **1 mm** and
  resources, life and construction progress to **hundredths**. Two runs that
  agree to the millimetre are the same run; comparing raw double bit patterns
  would fail on a difference no player could observe and no bug could cause.
- Non-finite values are pinned rather than thrown, because an infinite renewable
  deposit yield exists on purpose. `NaN` is a hard error — it means a rule
  produced an undefined number.

The hash layout carries `WORLD_HASH_LAYOUT_VERSION`, so a recorded hash from an
older layout can never be silently compared against a new one.

## 5. Input scheduling — why latency cannot change an outcome

`INPUT_LATENCY_TICKS = 2`.

An order is never applied on the tick it arrives. It is stamped for
`tick + 2` and applied at that tick boundary, sorted by `(scheduledTick,
arrivalSequence)`. Delivery jitter smaller than that 100 ms window therefore
lands on the same tick and produces the same match.

This is what makes the guarantee testable rather than hopeful: the same logical
input script replays identically regardless of when the messages actually
arrived, and the test drives the same order at every wall-clock offset inside
the window.

## 6. Save schema

`sim/snapshot.js`. `SNAPSHOT_SCHEMA_VERSION = 2`; the bridge's
`SAVE_SCHEMA_VERSION` moves with it on both sides.

A snapshot stores the tick, every RNG stream's state and draw count, the
allocator, stock, age, every unit, building, deposit and production queue. Each
queued item carries its tick progress **and** its start flag, and each queue
carries its hold reason — a queue that was mid-build or held when the save was
taken must resume in exactly that state, or the restored match refunds a
different fraction than the one that was saved. It does **not** store the map —
that is a pure function of `(mapID, seed)` and regenerating it is strictly
safer than trusting a serialised copy to match the generator the next run would
use.

A snapshot from a different schema version is refused, not migrated. A save that
loads into a subtly different world is worse than a save that will not load.

Restoring preserves the pending order queue: orders in flight when a save was
taken ride the snapshot and land on their scheduled ticks after the reload.
Dropping them would make a restored match diverge from the one that was saved on
the very tick they were due, which is the exact failure the save/restore
continuation test guards against.

## 7. Animation-facing state — no new gameplay enums

`ACTIVITY_TAGS` in `sim/types.js` stays closed at the same seven gameplay
activities the Swift simulation owns: idle, moving, gathering, boarding, aboard,
constructing, attacking. Issue #22 forbids adding to it and nothing does.

Everything #20's citizen contract needs lives in `sim/animation.js` as
**controller substates** on `unit.animation`, plus the six authoritative events
in `sim/events.js`: `tool_attach`, `tool_release`, `gather_contact`,
`payload_attach`, `deposit_release`, `construct_contact`.

The substate is hashed and saved, because #20 makes it event-authoritative: a
resumed match whose citizen forgot it was holding a tool, or lost a chunk that
was airborne, is a different match — not a cosmetic difference.

### The one deliberate rule change, and why

The Swift `GatheringSystem` extracts continuously at `gatherRates[kind] × dt`
straight into `unit.cargo`. #20 requires the transfer to be event-authoritative.

The rate rule is unchanged. What changed is where the extracted amount sits
between events: it accrues into a pending accumulator, is debited from the
deposit and launched as an airborne chunk at `gather_contact`, and commits to
cargo at `payload_attach`. At every instant

```
extracted total == airborne + carried cargo + credited stock
```

so nothing is created or destroyed anywhere in the cycle. This is asserted every
tick by the conservation test rather than argued.

## 8. Migration matrix

Status meanings:
**PORTED** — the rule runs in JavaScript and a test exercises it.
**PRESERVED** — the data or constant is carried across unchanged and is
available, but no rule consumes it yet.
**DEFERRED** — deliberately not migrated in this task; the Swift source remains
the reference and a follow-up ticket owns it.
**REDUCED** — migrated in part; the omission is stated.

| Swift source | Rule | Status | Notes |
|---|---|---|---|
| `DeterministicRandom.swift` | SplitMix64, tagged streams | **PORTED** | `sim/rng.js`; cross-checked against an independent Python reference. |
| `SimulationClock.swift` | Fixed 20 Hz, backlog drop | **PORTED** | `sim/clock.js`; `elapsed` now derived from tick rather than accumulated. |
| `WorldHash.swift` | Canonical fingerprint | **PORTED**, widened | `sim/hash.js`; layout v3 adds deposits, cargo, queues (start flag and hold reason), and animation substate. |
| `CoreTypes.swift` | `EntityID`, allocator, `ResourcePool`, `Faction`, `ResourceKind`, `Age` | **PORTED** | `sim/ids.js`, `sim/types.js`. |
| `EntityKinds.swift` | Unit and building rosters | **PORTED** | `sim/kinds.js`. Combat profiles are **PRESERVED** — carried across, unused while combat is deferred. |
| `SkirmishTuning.swift` | Every cost, rate, timing, radius | **PORTED** | `sim/tuning.js`, verbatim. |
| `WorldMap.swift`, `LandShape.swift`, `LandContour.swift` | One continent cut by void water; three layouts; 75–80% land coverage; camera bounds fitted to land | **REDUCED** | `sim/world.js`. Land field, regions, bounds, coverage and standing legality are ported. Minimap contour extraction, causeway spars and the drowned-cell mesh carve are rendering concerns and are not part of simulation truth. |
| `WorldPopulator.swift` | Deterministic starting state | **PORTED** | `sim/populate.js`. |
| `MovementSystem.swift`, `Locomotion.swift`, `ObstacleNavigation.swift` | Destination resolution, obstacle routing, per-tick advance | **PORTED** | `sim/movement.js`. Presentation-side turn-rate limiting and facing deadband stay in the renderer, as they did in Swift. |
| `GatheringSystem.swift` | Assignment loop, work stations, drop-off selection, one kind at a time, hold rather than discard | **PORTED**, one change | See §7. |
| `ConstructionSystem.swift` + `SkirmishSimulation` placement/cancel | Linear-in-builders progress, kerb approach, 4-builder cap, cost on place, 75% refund, G2a carry credit | **PORTED** | `sim/construction.js`. |
| `ConstructionPlacement.swift` | Site legality | **REDUCED** | Footprint, land and region legality are ported; explored-cell restriction depends on fog, which is deferred. |
| `ProductionSystem.swift` | Charge on enqueue, queue cap 10, population cap, tick-based build, refund on cancel and on destruction | **PORTED** | `sim/production.js`. Refund parity is exact: an unstarted front returns in full, a started front returns `cost × cancelRefundFraction`, and building destruction returns only the front item under the same started rule and discards the rest. |
| `CombatSystem.swift`, `CombatTypes.swift` | Damage, armour classes, stances, retaliation, death cleanup | **DEFERRED** | Not required by any #22 acceptance criterion and not part of the #27 workload. Roster combat numbers are preserved in `sim/kinds.js` so the port has one source when it happens. |
| `Adversary.swift` | Scheduled opponent AI | **DEFERRED** | Depends on combat and production targeting. |
| `VictorySystem.swift`, `VictoryTypes.swift` | Dominion hold schedule, contest decay, core-life pressure | **DEFERRED** | The hold-requirement schedule and its constants are **PRESERVED** in `sim/tuning.js`. `battleFinished` remains a valid protocol event with no rule that currently fires it. |
| `BoardingSystem.swift` | Transport embark/disembark | **DEFERRED** | The `boarding` and `aboard` activity tags and `boardingProgress` are preserved so the port does not need a schema change. **The Swift file exists only as untracked work in the protected worktree and was not read, copied or referenced.** |
| Fog of war (#16) | Explored versus visible | **NOT YET EXERCISED** | No implementation exists on this branch in either language. Recorded so the gap is visible rather than assumed done. |

### What "deferred" costs

The deferred set is honest, not convenient: with combat, AI and victory absent,
this simulation cannot finish a match. `battleFinished` is wired and validated
but nothing fires it. That is a real gap and it is stated here rather than
implied away by a green test suite.

It does not block anything #22, #27 or #28 need. The benchmark workload in #27
requires 80 visible animated units under active simulation, movement, camera,
selection and HUD — all of which are ported. The physical gate in #28 measures
that workload.

## 9. Commands

```
cd ThreeRuntime
npm test                            # the whole runtime suite, determinism included
npm run build                       # bundles to Resources/ThreeRuntime
node --test tests/simulation.test.js  # the determinism and lifecycle suite alone
```
