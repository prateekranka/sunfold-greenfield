# CP-G2a-R2 — construction integrity proof

**Branch:** `cursor/cp-g2a-r2-construction-integrity-a2b9`  
**Base:** `cursor/cp-g2a-r1-placement-closure-13bb` (R1 placement closure; placement-mode exit not reopened)  
**Build:** `./scripts/agent-build.sh cp-g2a-r2` → see `build-proof.md`  
**Device:** iPad Air 13 (M3), iPadOS 26.5, UDID `A59055F8-1354-4936-97B8-7033DF90B0BB`  
**Orientation:** LandscapeLeft, `scale: 1.0`  
**Status:** R2 revise in progress — **do not claim CP-G2a closed.**

## Rules shipped (R2)

| Rule | Implementation |
|---|---|
| Builders stay until complete | `ConstructionSystem.releaseBuilders` only on `isComplete`; `assignBuilders` no longer replaces existing site workers |
| Stalled sites accept builders | `orderConstruct` + tap incomplete friendly foundation when selection has `canBeAssignedToConstruction` citizens |
| Non-builder selection inspects | Light Transport / boarding / empty eligibility → `selectBuilding` (never silent no-op; never false order marker) |
| Boarding / aboard exclusion | `Unit.canBeAssignedToConstruction` rejects `.boarding` and `.aboard`; `assignBuilders` uses it for preferred and auto-pick |
| Carried load on construction start | **Intentional G2a disposition:** `sendToConstruction` credits `cargo` to faction stock once, then clears cargo — not a second drop-off; no duplicate credit |
| Exact fractional cancel refund | HUD `refundLabel` uses `ResourcePool.displayAmount`; sim `cancelConstruction` unchanged float math |
| Per-site builder cap | `maxBuildersPerSite = 4` is independent per foundation; adding builders keeps `alreadyAssigned` |

## Carry disposition (policy)

Immediate stock credit on construct is the chosen G2a rule:

1. Citizen holding cargo is assigned to an incomplete foundation.
2. `sendToConstruction` adds `cargo.amount` to faction stock for `cargo.kind`.
3. `unit.cargo` is set to `nil` in the same call — cargo is cleared once.
4. The citizen walks to the site empty-handed; GatheringSystem will not deliver the same load again.

Proved by `ConstructionIntegrityTests.testConstructionAssignmentDepositsCarriedLoadToStock` (paused trickle so Matter delta is cargo − Farm cost only).

## Resource rail note

Top-bar chips are **Provisions → Matter → Lumen → Aether** (`ResourceKind.allCases`).  
AX labels are `"Provisions N"`, `"Matter N"`, … — the first chip leaf/gold glyph is **Provisions**, not Matter.  
Do not read Provisions totals as Matter.

## Simulator proof (LandscapeLeft)

| Frame | Scenario | Pass criteria |
|---|---|---|
| `30-builder-assign-exact-refund.png` | Paused Farm foundation with builders | AX: `Constructing 0%`, `2 citizens building`; cancel `Cancel construction`; rail `Provisions 187` / `Matter 95` (70 charged; Provisions leaf ≠ Matter) |
| `boarding-exclusion.md` | Boarding guard | Unit-level guard + `testBoardingAndAboardCitizensCannotBeAssigned` |
| (focused tests) | Carry disposition | `testConstructionAssignmentDepositsCarriedLoadToStock` — paused trickle; Matter delta = cargo − Farm cost; cargo cleared once |

Prior single-frame `32-carry-disposition-matter-bump.png` mislabeled Provisions as Matter and was deleted. Device before/after Matter bump not re-captured this revise; unit test is the durable proof.

## Replay A–G (device `A59055F8-1354-4936-97B8-7033DF90B0BB`)

| | Scenario | Result |
|---|---|---|
| A | Builders stay on incomplete Farm | Observed: `2 citizens building` at `Constructing 0%` while paused |
| B | Stall then re-assign | Covered by `testStalledFoundationAcceptsBuildersAgain` |
| C | Boarding / aboard exclusion | Covered by unit guard test |
| D | Carry disposition | Covered by hardened cargo test + `carry-disposition.md` policy |
| E | Exact cancel refund | Observed cancel affordance; label path uses `displayAmount` → `52.5` |
| F | Light Transport + incomplete Farm tap | Covered by `testLightTransportOnlySelectionInspectsIncompleteFarm` (LT world-pick unreliable in this session) |
| G | Two Farms / add builders | Covered by independent-cap + alreadyAssigned tests |

**Do not claim CP-G2a closed.**

## Focused tests

`Tests/ConstructionIntegrityTests.swift` via `/Users/prateekranka/.codex/bin/xctest-focused.sh`:

- `testBuildersStayAssignedUntilFoundationCompletes`
- `testStalledFoundationAcceptsBuildersAgain`
- `testTwoFoundationsHaveIndependentBuilderCaps`
- `testAddingBuildersDoesNotDropAlreadyAssignedOnSameSite`
- `testLightTransportOnlySelectionInspectsIncompleteFarm`
- `testOrderConstructSetsMarkerOnlyWhenBuildersAssigned`
- `testBoardingAndAboardCitizensCannotBeAssigned`
- `testConstructionAssignmentDepositsCarriedLoadToStock`
- `testCancelRefundUsesExactFractionalMatter`
- `testRefundLabelPreservesFractionalMatter`

## Out of scope (unchanged)

Production (G2b), objective/hints, control groups, animation, repeat-placement mode, audio matrix beyond stubs, unrelated map/visual dirty work. R1 placement-mode exit not reopened.
