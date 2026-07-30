# CP-G2a-R2 — carry disposition

**Policy (chosen):** Immediate faction stock credit when a citizen is assigned to construction.

## Rule

`SkirmishSimulation.sendToConstruction`:

1. If `unit.cargo` is non-nil, add `cargo.amount` to `stock[faction][cargo.kind]`.
2. Set `unit.cargo = nil` in the same assignment.
3. Walk the citizen to the foundation empty-handed.

This is **not** a second Core/drop-off delivery. The load is credited once and cannot be delivered again.

## Why not walk-to-drop-off first

G2a prefers construction responsiveness: assigning a laden citizen must not strand resources or require a separate deliver order. Immediate credit keeps Matter/Provisions/etc. in the pool the moment the player commits the builder.

## Proof

- Unit: `ConstructionIntegrityTests.testConstructionAssignmentDepositsCarriedLoadToStock` (Core trickle paused; delta = carried − Farm cost; cargo nil after).
- Device: paused-trickle before/after AX `Matter N` frames `32a-carry-matter-before.png` / `32b-carry-matter-after.png` (Provisions leaf ≠ Matter).
