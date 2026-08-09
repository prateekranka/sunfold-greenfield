# Round 18 — verdict & director correction

**Date:** 2026-08-06 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; deepseek-v4-flash
+ gemini-3.6-flash; 21 images + 3 zoom crops + pixel probes)

VERDICT: REVISE — **but the named gap is a pipeline integrity failure, not
art.** The critic caught it correctly: the shipped kit was packed from a
MIXED frames directory. The 04:19 render pass produced ONLY the villager
(160 frames fresh, feet pinned 455–457 ✓); all 96 pathfinder frames were
stale (walk 01:26, idle 03:10 — predating the round-17 fix). The 04:19
sheets, 04:20 dark kit, and 04:20:57 evidence were all packed from that mix
(diff=0 against the stale frames). Every pathfinder artifact showed the
pre-fix defects: W/NW clip at row 511, feet unpinned (463–511), S tip
clearance 16px (bar ≥48), E pole through the body reading "climbing", E/W
pole tops 140 vs 241 (101px), E not a mirror of W.

## Root cause (director investigation)

`build_sprites.py` cleanup `_remove(o)` (line 810) did
`if o.name in bpy.data.objects:` — accessing `.name` on an already-freed
StructRNA raises `ReferenceError: StructRNA of type Object has been
removed`, which crashed the script right after the villager pass. Blender
exits **0** on script exceptions unless `--python-exit-code 1` is passed,
so the "full render" reported success (EXIT=0, `ls frames | wc -l` = 256 —
the count included stale files). Same masked-exit-code trap class the
project has paid for repeatedly; the director trusted the exit code and
count instead of verifying mtimes. My error.

## Correction applied

1. `_remove` guarded with try/except ReferenceError (idempotent by
   construction).
2. Full re-render re-run with `--python-exit-code 1` (a failure can no
   longer masquerade as success), all 256 frames verified fresh by mtime
   BEFORE packing.
3. post.py → dark kit → evidence to be re-run on the complete fresh set,
   then the round-18 critic's check list re-judged (the critic's numbers
   were measuring stale frames; the art was never actually judged).

## The critic's verification notes (still valid, will be re-checked)

- Villager (fresh frames): clean — load, pack, gold node, ivory+teal
  palette, feet pinned ✓.
- 21/21 modlens runs succeeded; 3 transient failures retried OK.

## Files

build_sprites.py @ 04:49 (round-18 cleanup fix). Re-render in flight.
