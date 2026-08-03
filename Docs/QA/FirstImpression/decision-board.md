# First-Impression Pass — Consolidated Decision Board

Prepared for human sign-off. Wayfinder decisions **#4 – #8** are open and block the majority of the
ticket pack. Nothing below has been merged. No gated design choice will be implemented until the
corresponding decision is approved.

Authoritative source: `Docs/Wayfinder/FIRST-IMPRESSION-MAP.md`. Ticket pack:
`Docs/Wayfinder/implementation/README.md`.

Evidence captured on the project iPad (`75898CE1-A691-4973-817A-973D4249A38F`, iPad Air 13-inch M2)
at baseline `113ead0` lives in `Docs/QA/FirstImpression/fi-01/`.

---

## Baseline product truth established before any decision

These are measured facts from the running build, not assumptions. They change what some of the
options below cost.

| Observation | Evidence |
|---|---|
| The two channels render as giant **vertical translucent slabs** standing in the void, overlapping the celestial body, edged by glowing causeway spars that cross dry ground. Land ends in a hard polygon rim with **no water surface at all**. | `before-channel-artifact-113ead0.png` |
| No void water is visible anywhere in the opening camera frame. | `before-opening-camera-113ead0.png` |
| The opening Light Transport is **beached on dry regolith** beside a jetty, nowhere near water. | `before-opening-camera-113ead0.png` |
| A pale polygonal **seam network** covers the terrain at every camera position. | `before-midmap-seams-113ead0.png` |
| The minimap's two dark blobs **do not correspond** to the slabs in the world — rendering and minimap disagree today. | `before-channel-artifact-113ead0.png` |
| Minimap **tap-to-centre, drag-to-scrub, viewport box and edge clamping already work.** FI-10 is largely built. | `fi10-minimap-tap-clamp-works-113ead0.png` |
| The minimap **well exposes no accessibility element** — only its four buttons do. A VoiceOver user cannot move the camera. | `describe` accessibility tree |
| An **unattended** match resolves as `DEFEAT / CONQUEST` at **5:59** with zero player orders. Matches the recorded CP-C9 5:58 baseline, so this is known behaviour, not a regression. | `baseline-defeat-conquest-5m59s.png` |
| There is **no animation system**. `AGENTS.md` records "Animation. Units slide; needs per-unit activity state the sim does not expose." | `AGENTS.md` |

The last two rows matter most. They mean the acceptance route has a real six-minute pressure clock,
and that every unit-identity and combat ticket (FI-06 through FI-09) starts from zero animation
infrastructure rather than from a system that needs tuning.

---

## Decision #4 — How are formations created and deformed?

Blocks **FI-04**, and through it **FI-13**.

The locked direction already says: preserve an *explicit* formation, and do **not** infer one from
every multi-unit selection. Unformed groups take independent non-overlapping destinations.

| Option | What the player does | Cost |
|---|---|---|
| **A — Explicit toggle** | A formation button or control-group action marks the selection as "in formation". A plain tap order on an unformed group spreads it. | Extra HUD affordance; discoverable but stiff, and one more thing to teach on touch. |
| **B — Auto-formation on multi-select** | Any multi-unit selection becomes a loose box automatically. | Cheapest to build, but it **contradicts the locked direction** and removes the unformed-spread behaviour the pass asks for. |
| **C — Drag-order creates the formation** ⭐ | Tap-order = unformed spread. **Drag** the destination to set facing and width = formation, held while moving. | One learned gesture, no new HUD. Matches how Age of Empires IV actually does it. |

**Recommended: C.** It satisfies the locked rule exactly — a tap never infers a formation, a
deliberate drag creates one — and it is the AoE IV play-feel reference the Gauntlet judges against.

**Player-visible trade-off:** C gives real control at the cost of one gesture a first-time player
must discover; a long-press hint on the first multi-select can cover that. B is a day cheaper and
would fail the pass's own contract. A always works but adds permanent HUD weight for something the
player does constantly.

**Deformation behaviour to approve alongside it:** compress along the travel axis through a choke,
never clip an obstacle or another unit, and restore the intended shape once clear. I recommend
compress-then-restore rather than split-and-rejoin, because split groups read as broken on a small
screen at normal camera height.

---

## Decision #5 — What makes each unit readable in motion?

Blocks **FI-06**, and through it **FI-06A, FI-07, FI-08, FI-11, FI-12, FI-13**. This is the single
largest gate in the pack.

Locked priority order: silhouette → walking style → weapon and attack animation → sound → faction
colour. Motion must be restrained and physically believable.

| Option | What ships | Cost |
|---|---|---|
| **A — Silhouette + procedural gait** | Four distinct low-poly silhouettes (Citizen stooped with tool; Pathfinder lean and tall; Vanguard broad with shield and heavy tread; Quarrel crouched with a long weapon) driven by restrained procedural motion — bob, lean, stride cadence, turn-in-place. No skeletons. | Weeks less work. Reads clearly at normal camera height. Limbs do not truly articulate, so close inspection is weaker. |
| **B — Rigged authored models** | Blender-authored rigs with keyframed walk, gather, attack and death cycles. | The AAA answer, and the only one that survives a close camera. A multi-week pipeline with a real 60 fps risk at 40–80 units, and it blocks five downstream tickets the whole time. |
| **C — Silhouette + gait now, rigging deferred** ⭐ | Ship A, and record rigging as explicit follow-on work after the pass closes. | Unblocks FI-06A/07/08/11/12/13 now; accepts that "AAA limb motion" is not part of this pass. |

**Recommended: C.** The pass's own contract is that *visible systems must be complete* — not that
they must be final art. A restrained procedural gait is a complete, honest system. A half-finished
rigging pipeline is not, and it would stall five tickets.

**Player-visible trade-off:** with C a player instantly tells the four units apart in motion and the
world stops sliding, but a player who pinches all the way in will see simplified articulation. With B
the close camera is beautiful and the pass slips substantially with real 60 fps risk.

**This is the decision I most want your call on**, because it is a fidelity-versus-scope judgement
rather than a technical one, and `AGENTS.md` records the fidelity ceiling as already raised once.

---

## Decision #6 — Combat and destruction timing

Blocks **FI-07, FI-08, FI-09**, and through them **FI-13**. Direction is already resolved: units fall,
remain briefly, then dissolve into faction particles; buildings show damage stages, collapse with dust
and light, then clear their footprints. Only **timing** is open.

| Option | Attack windup / recover | Death fall → hold → dissolve | Feel |
|---|---|---|---|
| **A — AoE IV-like** ⭐ | 0.25 s / 0.35 s | 0.4 s → 1.2 s → 0.8 s | Readable and weighty without being slow. |
| **B — Heavier, cinematic** | 0.45 s / 0.5 s | 0.5 s → 2.5 s → 1.5 s | More dramatic, but corpses accumulate and cost draw calls at battle density. |
| **C — Fast** | 0.15 s / 0.2 s | 0.25 s → 0.5 s → 0.4 s | Reads arcade-like, which the locked direction explicitly rejects. |

**Recommended: A.** It is the closest match to the stated AoE IV bar, and the 2.4 s total death
budget keeps corpse count bounded at 40–80 units.

**Player-visible trade-off:** A lets a player see who is winning an exchange at a glance. B looks
better in a single duel and worse in a real battle. C would violate the locked "restrained and
physically believable" direction.

---

## Decision #7 — Selection-panel and command-grid hierarchy

Blocks **FI-11, FI-12**, and through them **FI-13**. Already locked: command tiles show pictures only
at rest, and long-press explains name, role, cost, time, prerequisites and disabled reason.

| Option | 1 unit | 2–12 units | 13+ units |
|---|---|---|---|
| **A — Detail-first** | Full portrait, name, stats | Icon grid | Icon grid, scrolls |
| **B — Always uniform tiles** | Tile | Tiles | Tiles |
| **C — Adaptive** ⭐ | Full portrait, name, role, stats | Icon row with per-unit health | Grouped by type with counts |

**Recommended: C**, with a **400 ms** long-press plus a haptic tick and a detail sheet.

**Player-visible trade-off:** C always answers the question the player actually has at that selection
size, at the cost of three layout states to build and test. B is one layout and tells a player almost
nothing when they select an army. A is a reasonable middle but wastes the large-selection case.

**Also needs your call:** long-press is currently invisible on a touch screen. I recommend a
first-run coach hint, since the baseline already has a hint ladder at 30/60/90 s.

---

## Decision #8 — The complete-match acceptance route

Blocks **FI-13**, which closes the pass.

The measured baseline is that an unattended match **ends in defeat by conquest at 5:59**.

| Option | Route | Risk |
|---|---|---|
| **A — Defend then win** ⭐ | One uninterrupted match: survive the early Dominion push, establish the Hearth, expand, counterattack, destroy the Dominion Core. Roughly 10–14 minutes. | Proves both pressure *and* a real win path. **Requires that winning is actually achievable — currently unproven.** |
| **B — Short conquest** | Accept the natural ~6 minute window and let the match resolve by Core destruction either way. | Fast and certain, but a pass signed off on a *defeat* does not demonstrate a complete product. |
| **C — Scripted checklist** | Play a fixed ordered list of the seventeen observable moments once. | Guarantees coverage but is a checklist, not a match, and would not honour "one uninterrupted complete match". |

**Recommended: A, with C's checklist used as the ordering of beats inside it** — a single
uninterrupted match whose beats happen to cover every required moment and which ends in a genuine
win.

**Player-visible trade-off:** A is the only option that actually demonstrates the product the pass
promises. It carries the real risk that the win path turns out not to be reachable at current
difficulty, in which case we would discover that during FI-13 rather than now.

**Honest flag:** I have not proven a win is achievable. That is a material risk to A and I am not
going to assert otherwise.

---

## What each approval unlocks

| Decision | Unlocks |
|---|---|
| #4 | FI-04 → FI-13 |
| #5 | FI-06 → FI-06A, FI-07, FI-08, FI-11, FI-12 → FI-13 |
| #6 | FI-07, FI-08, FI-09 → FI-13 |
| #7 | FI-11, FI-12 → FI-13 |
| #8 | FI-13 |

**#5 is the critical path.** Approving it first unblocks the most work.

## Work proceeding without approval

FI-01 (void-water world repair) is in flight. FI-03, FI-02 and FI-05 are AFK tickets that need no
gated decision and follow it. FI-10 is largely already built and needs verification plus an
accessibility gap closed, not a rebuild.
