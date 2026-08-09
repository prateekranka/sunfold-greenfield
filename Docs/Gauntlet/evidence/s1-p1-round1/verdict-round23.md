# Round 23 — builder handoff & director pre-flight findings

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Builder result (round 23) — blob root cause found and fixed

**Root cause:** the round-22 emission-mix set the Transparent BSDF color to
BLACK. In EEVEE Next that flips the whole Mix(Transparent, Emission) into the
**opaque pass** — alpha discarded, disc renders solid (0,0,0,255). Clean
bisect in the full pathfinder scene: variant A (trans black) = blob (5449
opaque-black px); variant C (trans white) = soft plateau (0,0,0,153) with
EASE falloff 153→…→2→0, 0 blob px. Ruled out by bisect: apply_pose/scale
breakage (matrix_world scale (1,1,1)), disc-as-object, sun-shadow reception
(shadow ON/OFF byte-identical).

**Fix (build_sprites.py only):** `trans.inputs["Color"] = (1,1,1,1)` — one
line; emission black, SHADOW_ALPHA 0.60, SHADOW_COLOR (0,0,0), flat-to-0.6R
+ EASE ramp unchanged. Sun shadows restored to use_shadow=True. Seed
unchanged. The director's Principled-black fallback was measured and would
have FAILED ((15,13,11,153) → dark-kit diff ≈13.8 < 15) — emission fix is
exact (0,0,0) and simpler.

**Fast loop (32 pathfinder-idle frames, EXIT=0, 0 Tracebacks):** 0 blob px
all 8 dirs; plateau (0,0,0,153); dark-composite diff>15 below feet: S 457 /
SW 224 / W 235 / NW 327 / N 615 / NE 326 / E 264 / SE 258 — hundreds per
direction, max_diff 34; white composite darkest mid-gray (41,41,41) — soft
shadow, no blob, no ring.

**Full pipeline:** 256 frames rendered 07:30–07:34 (single serial pass,
EXIT=0, 0 Tracebacks, 0 MD5 dups), post.py → dark kit → pairs → evidence
regenerated 07:35 by the director.

## Director pre-flight (4 modlens reads, 07:36)

| image | read |
|---|---|
| dark_pathfinder_walk_W_f1 | "character figure holding onto a tall vertical wooden staff" ✓ |
| dark_pathfinder_idle_N_f1 | "character wearing light-colored robes and holding/standing beside a tall wooden staff" ✓ |
| dark_villager_idle_S_f1 | "character model with tan head, beige conical torso, teal ring" ✓ |
| dark_pathfinder_idle_E_f1 | "wooden pole mechanism with attached containers, a handle crank" ✗ |

The shadow fix WORKED (W/N/villager all read planted persons now). Only E
fails: the figure reads as "mounted on / attached to" the pole. Zoom-crop
arbitration: "wooden scarecrow or training dummy mounted on a central
vertical pole".

## Director analysis — E-specific read

- E/W are mirrors (round-19 verified: E vs flip(W) mean diff 3.96 idle), yet
  W passes and E fails → read asymmetry on symmetric geometry.
- Geometry: the standard was rebuilt at x=0.22 in round 17 (ground-anchor
  work); the round-8 validated clearance was x=0.26. Measured E idle: body
  ends x298, pole at x302–310 — **4px gap** @512. The grip arm (chest
  x=0.24) + pennant (x=0.22) sit tight against the body in E, so vision
  reads pole-first: arm = "handle crank", backpack = "containers".
- Hypothesis for round 24: push the standard's x back out 0.22 → 0.26 (the
  round-8/14-validated clearance) so the E gap grows to ~15px and the
  "beside" read survives. Constraints: S gather f3/f4 ≤497 (unit shadow
  R=0.21 must not push the deposit frames to the edge — the standard shadow
  at (0.17,−0.02) may need to track the pole's x), tip clearance ≥48,
  E/W mirror preserved, pennant clear of the head in N-family.

## Open for round 24

E-view "mounted on pole" read; verify the 0.26 hypothesis on a fast loop
before the full render.
