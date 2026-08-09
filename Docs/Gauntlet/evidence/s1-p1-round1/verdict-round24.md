# Round 24 — builder handoff & director findings

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Builder result (round 24)

**Iteration 1 (director's x=0.26 test): FAILED, and correctly disproved.**
The builder measured that the E-view pole column is set by world **Y**
(col = 256 − 232.7·y), not X — x=0.26 only shifted rows. The "pole at
x302–310" the director measured in round 23 was the **grip arm/hand sphere**,
not the pole. Root-cause proof by measurement, not assertion.

**Iteration 2 (the fix, in the script now):** standard moved FORWARD of the
body axis — pole + base disc ground-anchored at **(0.26, 0.18)** (was
(0.22, −0.02)); pole h 2.058 → **2.184** (keeps S/SW tip clearance ≥48);
pennant + grip-hand sphere now **ground-anchored at the pole** (were
chest-anchored, drifting ±14px in side-view columns); grip arm re-aimed in
main() so the hand lands on the shaft at world (0.260, 0.179, 0.599);
standard shadow center (0.21, 0.18). All four part offsets updated
coherently. Seed unchanged.

**Fast-loop geometry (32 pathfinder-idle frames, EXIT=0, 0 Tracebacks):**
E pole now at cols 209–218 (LEFT of the robe, clear gap at the waist band)
vs old 256–265 (over the robe center → "mounted"). W pole at 293–296
(RIGHT of the body). E/W direction widths flip (E bbox x172–304, W x208–340)
— mirrors. 0 edge-touching opaque px in all 8 dirs. NOT run before cap:
modlens E/W/N reads on iteration 2, tip-clearance table (classifier bug —
skin (131,107,86) misclassified as gold), walk grip check.

## Director verification (independent, on /tmp/r24_fast2 + /tmp/r24_contact)

- **Modlens gate on iteration-2 E (dark composite): FAILS.**
  "A low-poly 3D model of a stylized wooden pole mechanism or prop…
  water pump, streetlight, or fantasy device is ambiguous." The figure STILL
  does not read as a person in E.
- **Modlens W (same set): PASSES.** "A 3D low-poly character model holding
  a long staff."
- **Pixel forensics (E vs W, idle f1):**

  | | W (d2) | E (d4) |
  |---|---|---|
  | pole tip row | y210 | y142 |
  | figure head row | y290 | y306 |
  | bare pole above head | ~80px | ~164px |
  | teal pennant px | 383 px (rows 233–393) | 403 px (rows 384–413 — LOW, near the body) |

- The 68px E/W tip-height asymmetry is the x-offset (0.26) projecting into
  opposite vertical shifts per side — the round-13/14 E/W pole-length
  asymmetry physics, re-opened by iteration 2's x move. It is CORRECT 3D
  projection, but it means E shows a long bare pole above the figure with
  the pennant edge-on/invisible → the "streetlight" read.

## Director conclusion for round 25

The figure reads fine in W/N/S/villager. E fails because the pole alone
reads as infrastructure: ~164px of naked pole above the head + pennant
invisible edge-on from E. The fix is the **pennant must read from E/W**
(and ideally all 8): a cross-blade pennant or a billboarded flag so the top
of the pole always carries a readable "flag/standard" cue. The pole is a
STANDARD, not a lamp post — the flag is what tells the eye that. Keep the
round-24 geometry (it fixed the side-view gap and mirror); do NOT revert x.
Also fix the tip-clearance classifier (gold = saturated: r−b > 60 AND
g > 110 AND r > 170; skin is (131,107,86), r−b ≈ 45 — exclude cols ±8
around the pole cluster) and verify the walk grip (ground-anchored hand +
re-aimed arm) in all 8 walk directions.
