# CP-C2 — Combat core · **CLOSED as CP-C2′** · 2026-07-31

**Closed the same day, by the device pass folded into CP-C3, exactly as the
"What unblocks it" section below predicted.** The missing evidence — a capture of
HP falling and a unit dying — now exists:

- `Docs/QA/G3/cp-c3/03-fight-crop.png` — a Gravemark Vanguard standing over a
  Sunwoven citizen whose health bar is visibly part-drained, paused at 4:32.
- `Docs/QA/G3/cp-c3/05-core-life-readout.png` — the selection panel reading
  **Civilization Core · SUNWOVEN · 303 / 600**, paused at 5:16.
- `Docs/QA/G3/cp-c3/07-player-wiped-pop-zero.png` — POP **0/10** and no Core.

All of it with no player input: the adversary walked to the player and did it.
`Docs/QA/G3/cp-c3/STATUS.md` is the full record.

The original status is kept below unedited, because the judgement it records —
refusing to close on a green build and a green test suite — is the reason the
proof exists at all.

---

**(Original, 2026-07-31: this checkpoint is not closed and must not be recorded
as shipped.)**

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
