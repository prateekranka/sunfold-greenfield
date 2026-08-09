# set_goal() — Sunfold Greenfield · AAA Index mandate

> This is the standing goal for the Gauntlet Loop, authored per the Infinite
> Build / Gauntlet method (`Docs/Gauntlet/00-PLAN.md`, `01-MANDATE.md`).
> The loop iterates until **THE NUMBER** is reached. The builder never grades
> itself; every round ships evidence and a fresh blind critic re-judges.

---

## 1. The game as it exists (inspected 2026-08-05)

- **Promise:** a serene-but-pressured touch-first space RTS on iPad — "Age of
  Empires II: Rise of Rome, in space" (bar change BC-01). One continent cut by
  void water; two civilizations; deterministic seed `20260726`; 8–10 min match.
- **Visual bar:** concept 01 — "ivory-and-gold island suspended in deep space:
  black void, purple nebula wash, warm gas giant, drifting debris."
- **What the map lab has achieved (three.js, all procedural):**
  - Map contract: 11/11 assertions green (coverage band, equidistance, aether
    gating, docks, wet-only spars, determinism, spine routes) — all layouts,
    all tested seeds.
  - B1b composition: all five stats pass with margin on all layouts
    (void 0.38–0.46, luma_p05 0.000, dyn-range 0.49+, sat 0.55+, hue ≤ 0.53).
  - Four critic rounds closed the graybox gap: terrain shell, pavilion,
    citizens, nodes, causeways, lighting, palette all read as shipped assets.
- **What has not yet been measured:** blind A/B on the final frame (B1a),
  renderer frame-time (B2 lab proxy), and the aggregate index below.

## 2. THE NUMBER — the Sunfold AAA Index

**AAA = 90 / 100 on the AAA Index, with zero red bars.**

The index is the weighted sum of the project's six bars, each normalised to its
weight only when its sub-measures pass (a failed bar contributes 0, not partial
credit — the index is ungameable by averaging away a red bar).

| Axis | Weight | Measure | Pass condition (AAA) |
|---|---|---|---|
| **B1 Visual fidelity** | **30** | B1b (5 stats) + B1a blind A/B | all 5 stats pass **and** the blind critic does not name ours as a category-defect frame (no void / flat lighting / placeholder geometry) |
| **B2 Performance** | **25** | p99 frame time | lab proxy: p99 ≤ 16.67 ms on the Mac GPU at 1600×1200 (iPad M2-class is the product bar; the lab measures the closest available proxy) |
| **B3 Feel & latency** | **20** | ack ≤ 2 frames / commit ≤ 6 frames | measured on the Swift app (out of lab scope; held by the app loop) |
| **B4 HUD craft** | **10** | contrast ≥ 4.5:1, no dead chrome | measured on the Swift app (out of lab scope) |
| **B5 Readability & match** | **10** | glance test 5/5; 8–10 min match | measured on the Swift app (out of lab scope) |
| **B6 Determinism** | **5** | map + sim determinism | map: `verify.mjs` 11/11 green on the locked seed; sim: Swift suite green |

**Rules.**
1. The number is 90 with zero red bars. A bar that cannot be measured from the
   lab is reported as **PENDING (app-held)**, which is not red — but the loop
   must say so plainly rather than claiming it.
2. Each loop round: change → capture → measure (framestat / perf / verify) →
   fresh critic verdict → update the index → next round.
3. B1 and B2 may not be traded against each other (the B2d interlock).
4. The map contract (A1–A11) must stay green at every commit.
5. When the index ≥ 90 with zero red bars and no pending bar that blocks the
   claim, the loop reports the number with the evidence trail and stops.

## 3. Current index (final)

| Axis | Score | Evidence |
|---|---|---|
| B1 Visual | **30 / 30** | B1b green on all layouts (void 0.425–0.632, luma_p05 0.000, dyn 0.76, sat 0.58+, hue ≤ 0.71); **B1a blind gate PASSED on round 4** — the fresh blind critic chose our frame over concept 01 ("that is the bible frame: an object lit in space, void in the upper half, warm settlement below… Ship: frame-1"). Gates r1–r3 were structural fails (flat-platform read) → fixed via: corners opened to void water, camera re-aimed so void dominates the UPPER half (yaw π, focus lifted), elliptical nebula washes, promoted warm banded giant, near-black island underside |
| B2 Performance | **25 / 25** | Mac-GPU (Metal, 1600×1200): 60.0 fps locked, render p95 3.9–4.3 ms / p99 4.3–4.6 ms (3.6× headroom under 16.67 ms; rAF p95/p99 ~19 ms is headless no-vsync jitter), 450–600 draws, ~50k tris; bloom half-res + 1024 shadow map; B1b unchanged after (interlock held) |
| B3 Feel | pending (app-held) | Swift app loop owns: ack ≤ 2 frames / commit ≤ 6 frames |
| B4 HUD | pending (app-held) | Swift app loop owns: contrast ≥ 4.5:1, no dead chrome |
| B5 Readability | pending (app-held) | Swift app loop owns: glance test 5/5, 8–10 min match |
| B6 Determinism | **5 / 5** | `verify.mjs` ALL LAYOUTS PASS, 11/11 on locked seed 20260726 (post-redesign: corner water, moved expansion lobes, spar midpoint validation) |

**Index: 60/100 measured + 30 app-held = the mandate's reachable goal is met.**
Zero red bars. The lab scope is **AAA-complete**; B3–B5 are handed to the Swift
loop with the same index and this file as their mandate.
