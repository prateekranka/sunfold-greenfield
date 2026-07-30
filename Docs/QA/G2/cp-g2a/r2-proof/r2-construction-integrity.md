# CP-G2a-R2 — construction integrity proof

**Branch:** `cursor/cp-g2a-r2-construction-integrity-a2b9`  
**Base:** `cursor/cp-g2a-r1-placement-closure-13bb` (R1 placement closure; placement-mode exit not reopened)  
**Build:** `./scripts/agent-build.sh cp-g2a-r2` → `** BUILD SUCCEEDED **` (see `build-proof.md`)  
**Device:** iPad Air 13 (M3), iPadOS 26.5, UDID `A59055F8-1354-4936-97B8-7033DF90B0BB`  
**Orientation:** LandscapeLeft, `scale: 1.0`

## Rules shipped (R2)

| Rule | Implementation |
|---|---|
| Builders stay until complete | `ConstructionSystem.releaseBuilders` only on `isComplete`; `assignBuilders` no longer replaces existing site workers |
| Stalled sites accept builders | `orderConstruct` + tap incomplete friendly foundation with citizens selected |
| Boarding / aboard exclusion | `Unit.canBeAssignedToConstruction` rejects `.boarding` and `.aboard`; `assignBuilders` uses it for preferred and auto-pick |
| Carried load on construction start | `sendToConstruction` credits `cargo` to faction stock before clearing — no silent `cargo = nil` |
| Exact fractional cancel refund | HUD `refundLabel` uses `ResourcePool.displayAmount`; sim `cancelConstruction` unchanged float math |

## Simulator proof (LandscapeLeft)

| Frame | Scenario | Pass criteria |
|---|---|---|
| `30-builder-assign-exact-refund.png` | Farm foundation selected while constructing | Shows `Constructing 0%`, `2 citizens building`, cancel reads `+52.5 Matter` (not 53); Matter stock 50 after 70 commit |
| `32-carry-disposition-matter-bump.png` | Citizen carrying Matter assigned to incomplete foundation | Top-bar Matter rises 233 → 240 (+7 carried load credited before build walk) |
| `boarding-exclusion.md` | Boarding guard | Unit-level guard + `ConstructionIntegrityTests.testBoardingAndAboardCitizensCannotBeAssigned` (live embark not wired in this snapshot) |

## Focused tests (compile + link; `xcodebuild test` hook-blocked)

`Tests/ConstructionIntegrityTests.swift`:

- `testBuildersStayAssignedUntilFoundationCompletes`
- `testStalledFoundationAcceptsBuildersAgain`
- `testBoardingAndAboardCitizensCannotBeAssigned`
- `testConstructionAssignmentDepositsCarriedLoadToStock`
- `testCancelRefundUsesExactFractionalMatter`
- `testRefundLabelPreservesFractionalMatter`

## Out of scope (unchanged)

Production (G2b), objective/hints, control groups, animation, repeat-placement mode, audio matrix beyond stubs, unrelated map/visual dirty work. R1 placement-mode exit not reopened.
