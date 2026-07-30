# CP-G2a-R2 — boarding exclusion

**Rule:** Builder selection must not take units that are `.boarding` or `.aboard`.

## Code

- `Unit.canBeAssignedToConstruction` returns `false` for `.boarding` and `.aboard` (mirrors `BoardingSystem.embark` clearing assignment/cargo when a citizen climbs aboard).
- `SkirmishSimulation.assignBuilders` / `sendToConstruction` gate on `canBeAssignedToConstruction` for both preferred selection and auto-pick.

## Proof

| Layer | Evidence |
|---|---|
| Unit guard | `ConstructionIntegrityTests.testBoardingAndAboardCitizensCannotBeAssigned` |
| Live embark | Not exercised — `BoardingSystem` remains dirty work outside G2a; guard preserves future boarding behaviour without reopening transport scope |

When boarding ships in a later checkpoint, citizens walking to a transport or already aboard will not be stolen by construction auto-pick or `orderConstruct`.
