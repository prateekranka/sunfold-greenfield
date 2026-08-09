# CP-C9 — Economy tuning and nine-minute proof · closure

Seed `20260726` · map `riverlands` · Sunfold Cycle 1 iPad Air 13 · iPadOS 26.5 · build
`cp-c9-r2` · bundle `com.sunfold.greenfield`.

CP-C9 closes the home-economy question from `Docs/Design/05-RESOLUTIONS-R1.md` §2 (B4 +
B5). The headless economy-ceiling run reaches the approved nine-minute population bar
without a no-choice stall. The device pass proves the shipped costs, refunds, population
grant, and real deposit gathering. It does not hand-play the full nine-minute arc; that
limitation is recorded below.

---

## What CP-C9 changed

### Region-aware economy tuning

`SkirmishTuning` now owns deposit yields. Home and off-home regions use separate tables:

| Region | Provisions | Matter | Lumen | Aether |
|---|---:|---:|---:|---:|
| Home | ∞ | 700 | 550 | 180 |
| Off-home | ∞ | 420 | 300 | 180 |

These are per-deposit yields, not regional totals. The home Aether row is the value a home
Aether deposit *would* carry; the home deposit plan places none, so home Aether supply is
actually 0 — see the bill table below.

The off-home values are the pre-CP-C9 values. They remain unchanged for expansions, both
neutral outcrops, and the Dominion. The lookup is `depositYield(for:in:)`; there is no
kind-only overload. A call site must name the region.

The Dwelling is now **55 Matter / 14 s**. Its population grant remains **+8**.

`WorldPopulator` no longer has a local `startingYield` switch. It passes `tuning` into
`placeDeposits` and seeds each deposit with the region-aware yield. Deposit placement, the
`depositPlan`, `innerLimit`, bounded 48-attempt search, and every `DeterministicRandom`
draw are unchanged. The same seed therefore produces the same positions. `Adversary.swift`
contains comments only for this checkpoint.

The approved authority is `Docs/Design/05-RESOLUTIONS-R1.md` §2 (B4 + B5). An earlier draft
applied 700 Matter and 550 Lumen to every region, including the Dominion. Review caught
that overreach. CP-C9 closes with the home-only increase.

### Measurement correction

The first harness version had five instrumentation defects. CP-C9 fixes the measurement
without changing the reference player's intended policy or the simulation rules.

1. `usefulActionAvailable()` previously rejected every building action while any foundation
   was incomplete. The game permits other buildings while one foundation is incomplete. The
   capability check now delegates to `SkirmishSimulation.buildBlocker(for:faction:)`. The
   reference player's one-building policy remains in `act()`, under the name
   `policyWaitsForFoundation`.
2. `stallSeconds` counted a preferred purchase that was temporarily unaffordable, even when
   another useful action existed. The decision bar is now `noChoiceStallSeconds`: it counts
   only a denied committed order when no other useful action exists. The raw per-resource
   signal remains as `affordabilityDelaySeconds`. The tests require every resource kind and
   at least one non-zero delay.
3. Denial episodes now record the denied resource, requested action, start, end, duration,
   and whether a productive action existed throughout. They are written to `-denials.csv`.
4. `army_count` remains the `UnitKind.isMilitary` combat classification. `isMilitary` was
   not changed. Evidence now reports `pathfinder_count`, `vanguard_count`,
   `quarrel_count`, and `trained_army_count` separately.
5. Output uses `SUNFOLD_NINE_MINUTE_ECONOMY_CSV_DIR`. The mode, seed, and duration always
   form the filename, so a smoke run cannot overwrite a ten-minute record. Home deposits
   now report `absent`, `exhausted(at:)`, or `neverExhausted` instead of collapsing absent
   and unexhausted into `never`.

`Tests/AdversaryTests.swift` also reads Matter `420` and the Lumen Spire affordability
fixture from tuning instead of freezing those values. New coverage is in
`Tests/EconomyTuningTests.swift`, `Tests/NineMinuteEconomyHarness.swift`,
`Tests/NineMinuteEconomyTests.swift`, and `scripts/cp-c9-economy-plot.py`.

---

## Bill versus supply — home region, 9:00 horizon

This is the table required by `Docs/Design/05-RESOLUTIONS-R1.md` §2. It includes the army
and Voyager separately. It is not a buildings-only bill.

| Line | Provisions | Matter | Lumen | Aether |
|---|---:|---:|---:|---:|
| Starting stock | 180 | 160 | 40 | 0 |
| 9-min Core trickle | 135 | 108 | 54 | 0 |
| Home deposits (2 Matter, 1 Lumen, 2 Provisions) | ∞ | 1400 | 550 | 0 |
| **Total home supply** | **∞** | **1668** | **644** | **0** |
| Tier-1 buildings incl. 4 Dwellings | 0 | 780 | 145 | 0 |
| Voyager research | 180 | 180 | 100 | 80 |
| Reference army (12 Cit · 13 Pf · 9 Vg · 8 Qr) | 1740 | 180 | 370 | 0 |
| **Total bill** | **1920** | **1140** | **615** | **80** |
| **Headroom** | ∞ | **+528** | **+29** | **−80** |

The 1668 Matter and 644 Lumen ceilings match `05-RESOLUTIONS-R1.md` §2. Home Lumen
headroom is **+29**, and the home Lumen deposit exhausts at **8:18.75**. This is thin,
finite supply by design. The approved home yields are not inflated further.

Home Aether is structurally **0**. The home deposit plan is
`[provisions, provisions, matter, matter, lumen]`; it contains no Aether node. Voyager's
80 Aether cannot be paid from home. `00-CONTENT-SPEC.md` says that Voyager is reached only
after leaving home.

---

## Corrected economy-ceiling measurement at 9:00

Mode `economy-ceiling` · seed `20260726` · map `riverlands`.

| Reading | Value |
|---|---|
| Population | 42 / 42 |
| Completed Dwellings | 4 |
| Citizens | 12 |
| Pathfinder / Vanguard / Quarrel | 13 / 9 / 8 |
| Light Transport / Bastion Walker | 1 / 0 |
| `army_count` (`isMilitary`) / `trained_army_count` | 17 / 30 |
| Stock | 1281.08 P · 678 M · 209 L · 0 Ae |
| Home Matter remaining | 360.90 |
| Home Lumen remaining | 0.000 |
| `noChoiceStallSeconds` | **0.000** |
| Raw affordability delay | Provisions 12.700 s · Lumen 25.950 s · Matter 0 · Aether 0 · **total 38.650 s** |
| Home exhaustion | Provisions `neverExhausted` · Matter `neverExhausted` · Lumen `exhausted at 498.750 s (8:18.75)` · Aether `absent` |
| First three minutes | Useful action available at every sample |

The raw affordability delay is normal RTS pressure. It is not a no-choice stall.

### Denial episodes

All seven episodes had another productive action available for the whole episode. They
therefore contribute to raw affordability delay, not to `noChoiceStallSeconds`.

| Start | End | Duration | Denied | Action |
|---:|---:|---:|---|---|
| 42.000 | 42.250 | 0.250 | provisions | `train:citizen` |
| 56.000 | 61.700 | 5.700 | provisions | `train:citizen` |
| 70.000 | 75.450 | 5.450 | provisions | `train:citizen` |
| 84.000 | 85.300 | 1.300 | provisions | `train:citizen` |
| 338.500 | 342.300 | 3.800 | lumen | `train:quarrel` |
| 342.350 | 351.700 | 9.350 | lumen | `train:quarrel` |
| 353.500 | 366.300 | 12.800 | lumen | `train:quarrel` |

### Decision gate

The remaining delays are normal RTS resource pressure, not a no-choice stall. The basis is
`noChoiceStallSeconds = 0.000`, another productive action throughout all seven denial
episodes, and a useful action at every sample in the first three minutes. Game balance was
not changed to remove temporary unaffordability.

---

## Determinism

Two independent full long runs wrote to separate directories. Their sample CSVs and denial
CSVs were byte-identical. Both pairs match the committed artifacts in this directory.

Regenerating the SVG from the same CSV is also byte-identical. The output-directory change
therefore fixes evidence retention without changing the seeded simulation or plot output.

---

## Device results

Device: Sunfold Cycle 1 iPad Air 13, iPadOS 26.5, build `cp-c9-r2`.

- The shipped build palette reads **“Dwelling. Raises the population cap. Costs 55 Matter.”**
- Founding one Dwelling charged 55 Matter and offered `Cancel · +41.25 Matter`, the 75%
  refund.
- Completion moved population from **10 → 18**, confirming the +8 grant.
- Real gathering against home deposits was visible in the inspector: `Gathering Lumen` and
  `Gathering Matter`. Home Lumen income read **+10/s**, with stock rising **40 → 175**.
- With the adversary live, the hand-played match ended **DEFEAT · CONQUEST at 5:58**. The
  headless contested run ended at 5:59, within one second.
- With `-sunfoldNoAdversary`, the on-device equivalent of economy-ceiling mode, a second
  match ran cleanly to **4:01**.

### Device limitation

The full 9:00 arc to approximately 40 population with four Dwellings was **not hand-played
to completion on device**. Coordinate taps through a real-time RTS were the limiting
factor, not the economy. Under live adversary pressure an undefended Core falls at about
5:58, so the CP-C9 economy bar is measured in adversary-off mode. The nine-minute arc is
proven by the deterministic harness, reproduced twice byte-identically. This is the one
open CP-C9 item.

---

## Test and build records

- Plain `swift test`: **99 tests, 2 skipped, 0 failures**. The two skips are the opt-in
  long-run harness tests.
- Gated long run, `SUNFOLD_RUN_LONG_ECONOMY_HARNESS=1 swift test --filter NineMinuteEconomyTests`:
  **4 tests, 0 failures**.
- Before the correction round: **95 tests, 2 failures**. Both failures were the new CP-C9
  bar assertions.
- `./scripts/agent-build.sh cp-c9-r2`: `** BUILD SUCCEEDED **`.

---

## Evidence files

### CSV

- `sunfold-nine-minute-economy-contested-20260726-600s.csv`
- `sunfold-nine-minute-economy-contested-20260726-600s-denials.csv`
- `sunfold-nine-minute-economy-economy-ceiling-20260726-600s.csv`
- `sunfold-nine-minute-economy-economy-ceiling-20260726-600s-denials.csv`

### SVG

- `sunfold-nine-minute-economy-contested-20260726-600s.svg`
- `sunfold-nine-minute-economy-economy-ceiling-20260726-600s.svg`

### Device PNG

- `device/01-opening-0m01-landscape.png`
- `device/02-dwelling-costs-55-matter.png`
- `device/03-dwelling-founded-cancel-refund-41-25.png`
- `device/04-dwelling-complete-pop-3-of-18.png`
- `device/05-contested-defeat-5m58-matches-harness.png`
- `device/06-economy-mode-4m01-build-palette-55.png`

## What is not proven

1. The full nine-minute economy-ceiling arc was not hand-played to completion on device.
   The deterministic headless harness proves it twice, with byte-identical samples and
   denial episodes.
2. A live adversary match reaches the Core defeat at about 5:58. That is a valid live
   result, but it is not a nine-minute economy pass. The economy-ceiling measurement is
   therefore adversary-off by design.
3. This checkpoint does not close faction modifiers, the per-resource drop-off model, the
   Dominion contest rule, or the later age and Tier-2 checkpoints.
