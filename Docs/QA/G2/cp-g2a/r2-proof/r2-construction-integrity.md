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
| `30-builder-assign-exact-refund.png` | Farm foundation selected while constructing | Shows `Constructing 0%`, `2 citizens building`, cancel reads `+52.5 Matter` (not 53) |
| `32a-carry-matter-before.png` / `32b-carry-matter-after.png` | Paused trickle; citizen carrying Matter assigned to incomplete Farm | AX `Matter N` rises by carried load; Provisions chip unchanged; selection shows constructing |
| `boarding-exclusion.md` | Boarding guard | Unit-level guard + `ConstructionIntegrityTests.testBoardingAndAboardCitizensCannotBeAssigned` |

Prior single-frame `32-carry-disposition-matter-bump.png` mislabeled Provisions `240` as Matter and is removed.

## Replay A–G (device)

| | Scenario | Expect |
|---|---|---|
| A | Builders stay on incomplete Farm | Assigned citizens remain `.constructing` until complete |
| B | Stall then re-assign | Stopped builder leaves; new citizen accepts via foundation tap |
| C | Boarding / aboard exclusion | Guard rejects; auto-pick skips |
| D | Carry disposition | Paused: Matter AX rises by cargo; cargo cleared once |
| E | Exact cancel refund | Cancel label `+52.5 Matter` |
| F | Light Transport + incomplete Farm tap | Farm selected (inspect); no order marker |
| G | Two Farms / add builders | Independent caps; `alreadyAssigned` retained |

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
