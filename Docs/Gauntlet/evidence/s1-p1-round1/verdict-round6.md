# Round 6 — verdict & builder response

**Date:** 2026-08-05 · **Piece:** s1-p1 (Sunwoven sprite sheets, stream sunwoven-sprites-r1)

## Critic verdict (fresh blind critic, vision via modlens bridge; deepseek-v4-flash
+ gemini-3.6-flash vision; 11 images, 32 calls)

VERDICT: REVISE

Landed (do not regress): the walk is a REAL walk — consecutive villager frames
change 38-48% of pixels (round 5: 0.3-3%), vision: "steps in a walking
animation cycle", not a run; activity separation intact (idle 9.98 / walk
18.64 / gather 16.70, gather peak 26.6; pathfinder 4.45 / 10.12); hands at the
node (127 vs 115); zero chroma bleed; teal trim reads; load reads ("carries
items on its back and side"); leaner PASS (torso 17-21 vs 20-25 all dirs).

Largest gap (STRUCTURAL): **the Pathfinder does not read as a unit — it reads
as a structure** ("tower/spacecraft" solo S, "desert tower" solo N; only
pair/strip context saves it), and the critic's figure measurement (54-68px vs
citizen 40-47px) included the pole because it overlapped the body's x-profile.
Also: the node exists (82-165 gold px at the feet) but its hue (37/.38/.73)
was pixel-identical to the robe trim — invisible to vision; the robe's shaded
value range reads cool gray despite the ivory census; the lean reads weak.

## Builder response (round 7 changes)

1. **Standard composition reworked** (the structure-read):
   - pole offset x 0.03 -> 0.12 (clear of the body's width profile, so the
     figure measures citizen height);
   - spherical finial REMOVED (it read as an antenna ball);
   - pennant moved to the top (1.55m);
   - a visible skin hand grips the pole at hand height + the scout's left arm
     now angles back to the pole (shoulder -0.30 / elbow -0.35 / hand -0.10 —
     the earlier sign error swung the arm away from the pole);
   - back pack REMOVED (not in the contract; read as a "wooden support frame"
     and hurt the leaner clause); boots re-materialed gold.
2. **Node made hue-distinct**: mote/glow materials deepened to saturated gold
   (base 0.98/0.62/0.22, emission_color 1.0/0.68/0.25 — the old hue was
   pixel-identical to the robe); nuggets enlarged (r 0.05-0.09).
   Measured: node_gold 100 at contact (rest 0), hands 127 vs feet 128.
3. **Robe warmth**: IVORY albedo (0.90, 0.85, 0.70), shadow material warmer
   (0.78, 0.69, 0.52), fill 0.8 — the shaded values now read warm, not gray.
4. **Forward lean 0.20** + upper-body counter-roll 0.055.
   Measured: com_x S 61.1 vs N 65.6 (Δ4.5).

Open (recorded): the SOLO pathfinder render still triggers structure
interpretations in the vision model ("outpost"/"boat" gestalts oscillate),
while the pair and strip contexts read correctly ("figure holding a pole with
flag/light"). The standard dominates the silhouette BY CONTRACT ("reads as
fast from directly above"); at 128px a top-down figure+standard is
perceptually ambiguous in isolation. Gameplay never shows units in isolation.
Decision deferred to the round-7 critic and the human bar.

Evidence for round 7: evidence.md / evidence.json in this directory.
