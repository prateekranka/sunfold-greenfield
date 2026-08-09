# CP-C5 — Military roster breadth · device evidence

Seed `20260726` · map `riverlands` · iPad Air 13 (M3) simulator `75898CE1-A691-4973-817A-973D4249A38F`
· iPadOS 26 · LandscapeLeft · build `build-agents/cp-c5-final` · bundle `com.sunfold.greenfield`.

Two device passes were run:

- **Pass A — roster acceptance**, launched with the pre-existing `-sunfoldNoAdversary` flag. The
  adversary is disabled so that no combat loss can confound the resource ledger. Every cost claim
  below comes from this pass.
- **Pass B — live fight**, launched normally. Used for the adversary wave, the Vanguard/Quarrel
  silhouette read in a contested match, and the Dominion re-measurement.

Splitting them is deliberate: a ledger reconciled against the Core trickle is only trustworthy if
nothing else is spending or destroying. Pass A is the clean measurement; Pass B is the messy truth.

---

## What is proven

### Trainer exclusivity — both directions

Read from the accessibility tree, not from pixels, so these are the strings the app actually
publishes.

| Building | Tiles offered | Empty slots |
|---|---|---|
| Formation Yard | `Train Pathfinder. Costs 35 Provisions · 10 Lumen.`<br>`Train Vanguard. Costs 45 Provisions · 20 Matter.` | `No additional unit is trained here.` |
| Lumen Spire | `Train Quarrel. Costs 35 Provisions · 30 Lumen.` | `No additional unit is trained here.` ×2 |

The Yard never offers Quarrel. The Spire never offers Pathfinder or Vanguard. The unused slots
say so in plain words rather than going blank.

Evidence: `04-yard-trains-two-units-only.png`, `07-spire-trains-quarrel-only.png`.

### Prerequisite gating, with a named reason

Before any Formation Yard exists, the Lumen Spire tile is dimmed and reads
`Requires a completed Formation Yard.`, and the grid renders that same string as a visible
on-screen reason line. Tapping the dimmed tile surfaces the reason and does **not** enter
placement.

Once a Yard **completes** — not when its foundation is laid — the same tile becomes actionable and
reads `Lumen Spire. Trains Quarrels. Costs 90 Matter · 45 Lumen.`

Evidence: `01-military-page-yard-required.png`, `02-dimmed-tap-no-placement.png`,
`03-military-page-spire-gated.png`, `05-spire-unlocked-after-yard.png`.

### Costs charged exactly

Each purchase was reconciled against the Core trickle (0.25 Provisions/s, 0.20 Matter/s,
0.10 Lumen/s) across the elapsed match time. Every line closed to the unit.

| Purchase | Charged | Spec |
|---|---|---|
| Formation Yard | 110 Matter · 20 Lumen | `SkirmishTuning.formationYardCost` (corrected this checkpoint from 110/40) |
| Vanguard ×2 | 90 Provisions · 40 Matter | 45 Prov · 20 Matter each |
| Pathfinder ×1 | 35 Provisions · 10 Lumen | — |
| Lumen Spire | 90 Matter · 45 Lumen | new this checkpoint |
| Quarrel ×3 | 105 Provisions · 90 Lumen | 35 Prov · 30 Lumen each |

The Spire foundation's cancel button read `+67.5 Matter` — 75 % of 90, matching
`cancelRefundFraction` — which independently confirms the 90 Matter charge from a second surface.

Evidence: `06-spire-founded-ledger.png`, `08-three-quarrel-population-cap.png`.

### Placement legality enforced at the point of use

Dragging the Spire ghost onto ground outside home territory turns it red and the panel reads
`Lumen Spire · Trains Quarrels · 90 Matter · 45 Lumen · BLOCKED · Move onto clear home ground`.
Releasing there neither places nor charges. Moving to legal ground founds it and charges once.

### Production holds reach the player, and nothing is charged into the void

Queuing the third Quarrel took population to 10/10. The tile dimmed and the reason line read
`Population 10/10.` — one of the strings shipped by this checkpoint, confirmed live rather than
only in source.

All three queued Quarrels spawned and the queue drained to `No units training`. No item was
charged and then lost, which is the `ProductionSystem.step` defect this checkpoint fixed.

### The full acceptance sequence

Formation Yard → two Vanguard and one Pathfinder → Lumen Spire → three Quarrel → move the six as
a group, in one uninterrupted match.

The marquee returned `6 Selected · 1 Pathfinders · 2 Vanguards · 3 Quarrels · 345/345`. That total
is an independent check on the composition: 45 (Pathfinder) + 2×75 (Vanguard) + 3×50 (Quarrel) =
345 exactly, against `UnitKind.maxLife`.

One ground tap moved all six across standable land. Re-selecting at the destination returned the
identical composition at 345/345 — no unit lost, no desync, no spawn-in-terrain. Population
tracked 4 → 7 → 10 with no drift.

Evidence: `09-six-selected-group.png`, `10-six-arrived-group-move.png`.

### Determinism

`swift test` — **86 tests, 0 failures** (`swift-test.txt`).

`AdversaryTests.testTwoNoInputRunsShareOneWorldHashForTheWholeMatch` runs the full no-input match
twice and asserts the two world hashes are equal. Observed hash: **`4f761a7b50d6df3c` at tick
7192**, identical across both runs.

The assertion is deliberately *relative* — no frozen hash literal exists anywhere in `Tests/`.
That matters this checkpoint: `UnitKind` is `String`-backed, so renaming `.ranged` → `.quarrel`
moved every raw value and would have invalidated any transcribed constant. Nothing had to be
weakened to make the suite pass.

Cross-platform check: the host run ends `Gravemark wins by conquest at 5:59 (tick 7192)`. The
device, same seed, no input, ended `DEFEAT · CONQUEST · Match time 5:59`. Host and device agree.

### Adversary keeps fielding Quarrels

The Formation Yard no longer trains Quarrel, so the adversary had to be re-routed to pick a
trainer by capability rather than by building kind. Pass B confirms it works: wave 2 arrived as
4 Vanguard + 2 Quarrel, matching `composition(ofWave: 2)`. Had the routing fix been missed, every
wave from the second on would have silently shrunk.

Evidence: `12-adversary-wave2-vanguard-quarrel.png`, `13-live-fight-core-under-attack.png`.

---

## What is not proven

Read this section as the honest boundary of the pass.

1. **The Spire does not accept Lumen drop-off.** `02-BUILDING-ROSTER.md:94` says the Lumen Spire
   "Trains Quarrel **and accepts Lumen**." It does not. `acceptsDropOff` is a plain `Bool`, so it
   cannot express "Lumen only" — setting it `true` would make the Spire a drop-off point for all
   four resources, which the design does not say. Left `false` and recorded rather than guessed.
   Closing this needs a per-resource drop-off type, which is a data-model change beyond CP-C5.

2. **Faction modifiers are absent.** Sunwoven and Gravemark field numerically identical rosters.
   Deferred to CP-C8 by recorded decision; nothing in this checkpoint pretends otherwise.

3. **Dwelling tuning still drifts from the design.** Live is 80 Matter / 15 s;
   `02-BUILDING-ROSTER.md:17` says 55 Matter / 14 s. Population grant (+8) and starting cap (10)
   already match. Recorded, not fixed — CP-C9 owns the economy retune, and changing a cost here
   would move a number that checkpoint is going to re-derive anyway.

4. **The R1 §6.4 spawn-slot rule was not adopted.** R1 specifies `id.raw % ringSlotCount` for
   choosing a spawn slot. The shipped ring search in `ProductionSystem.spawnPosition` is already
   deterministic and was left alone. This is a deliberate deviation from the letter of R1, not an
   oversight; the property R1 is protecting (reproducible spawn placement) holds either way.

5. **Citizen gathering was never exercised on device in this pass.** Both passes ran on the Core
   trickle alone. Gather assignment requires a tap to land within `Deposit.workRadius + touchSlop`
   (4.0 m) of a deposit centre, and `SelectionModel.pick` resolves units before deposits — so a
   citizen standing on a node swallows the tap that would re-assign it. That is pre-existing
   behaviour, untouched by CP-C5, and `GatheringSystem` is covered by host tests. But no device
   evidence of gathering was produced here, so do not read this document as proof the economy
   loop works end to end on device.

6. **Pass A ran with the adversary disabled.** The ledger figures come from a match with
   `-sunfoldNoAdversary`. They are exact, but they were measured in a quiet world. Combat was
   verified separately in Pass B.

7. **Not built from a clean clone.** The working tree is deliberately dirty with other agents'
   in-flight work, so the build under test is this tree, not a pristine checkout of the commit.
   A clean-clone build was not attempted.

8. **The Spire's height and silhouette are an implementation choice.** The design specifies a
   footprint (3.0), HP (210) and role, and says nothing about height or shape. The mesh reads as
   an open arch carrying a glowing lens — legible as a lumen building and visually subordinate to
   the Formation Yard — but nothing in `Docs/Design/` blesses it.

---

## Findings raised by this pass

Not defects introduced by CP-C5, but observed while proving it. Recorded so they are not lost.

- **The Vanguard/Quarrel read does not work by the mechanism the design claims.**
  `01-UNIT-ROSTER.md:156-176` asks for "a long haft held vertical — the vertical line is the read
  at distance" against Quarrel's "horizontal bow-like arc". From the fixed top-down camera a
  vertical haft is foreshortened to almost nothing. What actually separates them on screen is
  **elongated versus compact**: the Quarrel's launcher projects as a long dark shaft, the Vanguard
  reads as a solid blob. The two *are* reliably distinguishable — see
  `11-vanguard-quarrel-silhouette.png`, six units at gameplay zoom — but the design's stated
  reason for why is not what is doing the work. Worth reconciling the doc with the camera.

- **A dimmed tile loses its identity to a screen reader.** When the Lumen Spire is gated, its
  accessibility label becomes only `Requires a completed Formation Yard.` — the building name and
  cost are gone. Sighted players still see the icon; a VoiceOver user cannot tell *which* building
  is gated. The label should carry both, e.g. "Lumen Spire. Requires a completed Formation Yard."

- **Pluralisation bug in the multi-select summary:** the panel reads `1 Pathfinders`. The Vanguard
  and Quarrel rows pluralise correctly at counts above one; the bug shows only at exactly one.

- **The Dominion leak is unchanged and still open.** Re-measured in Pass B at 5:58 with no player
  input: `Dominion: you 0 of 45 seconds, enemy 12`. Gravemark banks capture progress purely from
  waves crossing the ring on their way to the Core. CP-C5 neither fixed it nor made it worse.
