# Helios Rift — Broken Ring devlog

This log records rendered corrections for the active Three.js map. Each cycle starts from
the live game, changes one bounded visual system, and ends with a Git commit and a dev-only
deployment after its focused gates pass.

## Cycle 00 — takeover baseline · 2026-08-09

Status: **Proof Pending**

### Preserved behavior

- Four broad ring sectors and four broken gaps.
- Eight data-driven bridges, including four core routes.
- Four expansion islets and four starting areas.
- Solar objective, solar flare, resource nodes, minimap, selection, movement, and repair.
- Eight Citizens and four Lumen Guards in the local player's opening group.

### Observed rendered result

- The complete ring fits the normal 1600×900 in-app Browser viewport.
- The topology is immediately recognizable as a broken ring.
- The browser console has no warning or error entries.
- The HUD reports 12 units and 30 FPS.
- Commit `ac20998` is visible on `origin/main`.
- The same bundle is deployed at `https://dev.helios.contenthelper.in/` as Worker version
  `2ce69824-e2f7-4ce3-91f4-80bdf6003042`.
- Hosted and local bundle SHA-256 values both equal
  `f4d64d0dc655d19b4c45b31e7b7a484e2e46fc581ed7bb3edb4e9c42debc7d8f`.

### Highest-leverage mismatch

The scene is too dark, flat, and top-down compared with the approved reference. The current
fog suppresses the upper sectors. The shallow platform read hides the authored
understructure. The solar core is a small pale marker instead of the dominant orange star.

### Focused checks

- `node Tools/citizens/build-helios-play-site.mjs` — passed.
- Scoped `node --check` for the Helios, map, camera, Guard proof, and deploy sources — passed.
- Data contract: four visual fragments, four spawn pads, eight resource zones, eight bridges,
  and finite visual bridge endpoints — passed.
- `git diff --check` — passed.
- In-app Browser render — played at the default viewport with 12 units and no console errors.

### Evidence

- Reference analysis: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-analysis.md`
- Current render: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/current-local-default-viewport.png`
- Comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-vs-current-default.png`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-current-site.stdout.txt`
- Hosted render: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-00.png`
- Deploy output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-00.stdout.txt`
- Hosted bundle hash: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-bundle-hash.txt`

### Next cycle

Correct composition readability. Adjust only Helios camera presentation, fog/exposure,
platform depth cues, and solar-core authority. Rebuild and compare before any geometry
detail expansion.

## Cycle 01 — composition authority · 2026-08-09

Status: **Done for this bounded cycle; overall reference parity remains Proof Pending**

### Rendered correction

- Changed only Helios presentation and the shared camera's optional presentation inputs.
- Measured a 43-degree pitch, 80-unit overview distance, and a small overview target offset.
- Increased fragment depth from 1.8 to 4.2 units and extended the inner and outer wall ribs.
- Rebalanced basalt, deck, seam, gold, conduit, resource, crystal, and rock materials.
- Added ACES tone mapping, controlled exposure, longer fog, and stronger key/fill/rim light.
- Rebuilt the solar objective with a larger emissive core, additive corona, radial halo,
  explicit capture ring, data-driven beam, and wider warm point light.

### Observed result

- The ring now fills the gameplay frame at a scale close to the dedicated reference.
- All four fragment gaps, bridge states, player groups, pads, and the solar objective remain
  readable in the opening overview.
- The deeper three-quarter camera exposes the inner walls and front understructure.
- The browser startup trace has no exception, warning, or error entry.
- A 59.98-second mixed-play probe rendered 3,599 frames at 60.00 FPS average.
- Frame time was 18.5 ms p95, 18.6 ms p99, and 18.7 ms maximum.
- No sampled frame exceeded 20 ms.
- The probe included 12 moving Citizens, repeated zoom/pan input, solar-core capture, one
  bridge repair, and a flare state.

### Focused checks

- `node --check` for all five edited source modules — passed.
- `git diff --check` for the exact write scope — passed.
- Helios deploy-site build — passed.
- Default-camera preservation and custom-camera construction assertion — passed.
- In-app Browser startup and one-minute active-play frame pacing — passed.

### Evidence

- Final overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-01-final-overview.png`
- Reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-vs-cycle-01-final.png`
- Active-play frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-01-stress-60fps-core-captured.png`
- Frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-01-performance.json`
- Review: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-01-review.md`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-01-r3.stdout.txt`

### Remaining limitation

This pass proves desktop Chromium frame pacing only. Native iPadOS 26.x WebKit proof is
still required. The largest visual gap is now authored fragment geometry and material
breakup, not camera composition.

### Next cycle

Add layered edge armor, inset deck plates, cracks, sockets, and stronger wall silhouettes.
Do not add new gameplay systems during that visual correction.
