# CP-C2 — Combat core · IMPLEMENTED, NOT PLAY-VERIFIED · 2026-07-31

**This checkpoint is not closed and must not be recorded as shipped.**

## What is proven

- `./scripts/agent-build.sh combat` → `** BUILD SUCCEEDED **` (`build-agents/combat.log:1328`).
- `swift test` → **39 tests, 0 failures**, up from 31. Run by the director, not
  taken from the builder. Eight of those are new combat tests covering the damage
  formula, the minimum-damage floor, death and population release, seed
  determinism, tick-grouping independence, and refund of a production queue when
  the building is destroyed.
- The build installs and runs on `75898CE1-…` (iPad Air 13, iOS 26.5) and renders
  correctly in landscape: `01-combat-build-runs-landscape.png`.

## What is NOT proven, and why

**No fight has been observed in play.** The only hostile entities on the map are
Gravemark's, in the Gravemark home region on the far side of the map. Gravemark
has no AI — it does not move, build, train or attack — so there is no way to
bring two hostile units into contact without walking a Sunwoven unit across the
entire map in real time, which is not a verification, it is a wait.

Per the mandate's pause boundary on shipping unverifiable work, the honest
status is: **combat exists in the simulation and is proven by tests; it has
never been seen to happen by a player.** A green build and a green test suite
have both, separately, lied to this project before.

## What unblocks it

**CP-C3 — Adversary v0.** A scheduled deterministic opponent that trains units
and sends attack waves puts hostile units in front of the player, and combat
becomes verifiable in play in seconds instead of minutes. Combat verification
should be folded into CP-C3's device pass rather than chased on its own.

Do not close CP-C2 until a capture exists showing HP falling and a unit dying.
