# CP-G2a Read-only Review

**Date:** 2026-07-30

**Reviewer route:** OpenCode Go, Kimi K3, maximum reasoning

**Decision:** `REVIEW_REVISE`

The reviewer inspected the current source and the native iPadOS 26.5 evidence. The
review did not modify the repository. A before-and-after manifest comparison found no
file changes from the review run.

## Primary player-visible defect

After a successful placement, the placement session remains at the new foundation.
The new foundation makes that same footprint illegal. The ghost therefore changes to
red `BLOCKED`, as shown in `13-farm-founded-constructing.png`. The flow does not clearly
return the player to normal control or move the ghost to another legal position.

## Proof gaps before closure

- Add durable build and focused-test output for the exact CP-G2a tree.
- Prove Farm, Matter Extractor, and Dwelling placement and completion.
- Prove legal, illegal, unaffordable, cancel-placement, and cancel-foundation states.
- Verify completion audio and Reduced Motion behavior in the rendered app.
- Verify that stalled foundations can receive builders again.
- Prevent builder selection from taking units that are boarding or aboard.
- Preserve carried resources when a citizen starts construction, or define their disposition.
- Show exact fractional refunds instead of rounding `52.5` to `53`.

The next pass must fix the post-place state first. It must not expand into CP-G2b.
