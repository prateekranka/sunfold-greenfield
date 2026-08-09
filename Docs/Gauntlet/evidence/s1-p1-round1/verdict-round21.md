# Round 21 — builder handoff & director completion note

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Why this round existed

The director's round-20b probe found the S-view gather contact frames still
touched the canvas bottom (rows 509–511, solid opaque warm-brown pixels) and
attributed it to the deposit's y-extent (0.295m → row 513.5 by projection).
The round-21 builder's measurement refined the diagnosis: the clip was TWO
things —
1. **The crouched gold feet**: the deep gather crouch (thigh+knee cumulative
   1.20) puts the feet at world y≈0.40 → projected row 509–513, the solid
   opaque rows the director saw;
2. **The deposit itself**: ore bottom 502.5, glow-disc bottom 504.5.

## Fix applied (build_sprites.py, the only file touched)

- **Deposit repositioned** (y pulled in, mound RAISED in z so the hands rest
  ON the ore; x ≥ 0.18 kept for the round-5 N-view hem clearance):
  - glow disc: (0.18, 0.18, 0.015) r0.10 → (0.185, 0.145, 0.015) r0.07
  - nuggets (x,y,z,r): (0.19,0.18,0.055,0.11), (0.24,0.15,0.045,0.085),
    (0.18,0.22,0.06,0.075), (0.22,0.21,0.035,0.06) →
    (0.19,0.175,0.165,0.095), (0.235,0.19,0.13,0.08), (0.23,0.13,0.12,0.07),
    (0.18,0.20,0.12,0.065) — max y+r 0.27 but raised z → screen bottom ≈ 492,
    nothing past row 494 at S.
- **Gather pose retuned (f2–f5)**: root_z −0.08/−0.125/−0.085/−0.065 →
  −0.065/−0.055/−0.055/−0.055; thigh/knee cumulative 1.20 → 0.46–0.52.
  New S foot bottoms: f2 496.5, f3 492.5, f4 492.5, f5 494.4 — all inside
  the ≤497 bar. Hands (unchanged reach) still overlap the raised mound:
  S f3 hand rows 451–467 vs mound 442–487; N overlap 5.1px. **The N-gather
  "hand ON deposit" (round-14 passed feature) is preserved.**

## Fast-loop verification (64 villager-gather frames, EXIT=0, 0 Tracebacks)

- S gather f3/f4 lowest opaque = 491 (bar ≤497 ✓).
- All 8 dirs, all gather frames: opaque max 495; nothing ≥510 anywhere.
- Hand skin-pixels inside the gold bbox: S f3 764, S f4 912, N f3 630,
  N f4 971 — hands ON the deposit in S and N contact frames.
- Shadows present below the feet in all 8 dirs (bottoms 478–496 any-alpha);
  unit shadow still merges with the standard base disc.
- Deposit still chunky: 3184 gold px vs 3471 old (~7% smaller, solid
  grounded cluster).
- Gather motion energy preserved: S f1-vs-f3 53.4 (old 65.7), f1-vs-f4 53.5
  (57.6); N f1-vs-f3 36.1 (39.6) — reach/contact/stow cycle intact.

## Director completion (round 21b)

The builder hit its cap with the full repo render mid-flight; the delegation
teardown killed it, leaving a MIXED frames dir (115 fresh villager frames +
141 stale pathfinder/gather). The director re-ran the full 256-frame render
with --python-exit-code 1 (EXIT=0, 0 Tracebacks), and — per the round-18
lesson — verified ALL 256 frames fresh by mtime BEFORE packing. Then post.py
→ dark kit → pairs → gauntlet_evidence.py, final pixel probes, and the 4
modlens pre-flights (E/W must read "standing beside a planted pole"), then a
fresh blind critic.

## Not regressed (round-19/20 greens)

256/256 fresh + MD5-distinct; E/W mirror; grounding pins; tip clearance ≥48;
walk bob ≤10 with real gait; person-carrying-standard read; gold ore node;
ivory robe; teal accents; no exhaust/plume; shadows survive keying.
