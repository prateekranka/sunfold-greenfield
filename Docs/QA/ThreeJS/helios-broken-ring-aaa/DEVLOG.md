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

## Cycle 02 — native touch gameplay gate · 2026-08-09

Status: **Done and deployed**

### Player-visible correction

- One finger now pans the RTS camera.
- Two fingers now zoom the game camera without zooming the Safari page.
- A tap selects one local Citizen.
- A double-tap on stable ground issues the existing move, gather, or repair command.
- Touch drag and multi-touch gestures cannot become accidental selection or movement taps.
- Existing mouse selection, right-click commands, wheel zoom, and keyboard pan remain active.

### Observed iPadOS result

- Played on the iPadOS 26.5 `Sunfold iPad A16 11-inch` simulator.
- A real touch tap selected all 12 Citizens through the existing HUD control.
- A real double-tap moved all 12 Citizens across stable ring ground.
- A real pinch changed only the game camera. The Safari page and HUD scale stayed fixed.
- A real drag panned the game camera.
- The same run captured the solar core and issued a second movement command.
- The HUD remained visible throughout and continued reporting the active simulation state.

### Frame-rate gate

- Recorded 45 seconds of active touch play at native simulator resolution with touch markers.
- Sampled the in-game 500 ms requestAnimationFrame counter once per second from 2 to 44
  seconds.
- The 43 samples averaged 59.9767 FPS. Forty-one read 60, one read 58, and the next read 61.
- No sample was below 58 FPS.
- The paired 58/61 samples are consistent with the half-second counter boundary. They do not
  show a sustained slowdown.
- The evidence video is captured at 30 FPS. This pass does not provide device GPU frame-time
  percentiles and does not claim that it does.

### Focused checks

- `node --check` for the edited camera, proof, and focused test modules — passed.
- `node --test ThreeRuntime/tests/rts-camera-touch.test.js` — 2 of 2 passed.
- Helios deploy-site build — passed.
- Local mouse selection and right-click movement regression — passed.
- Real iPadOS 26.5 tap, double-tap, drag, and pinch interaction — passed.

### Evidence

- Native touch video: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/ipados-26-5-touch-gameplay-60fps-landscape.mp4`
- Final native frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/ipados-26-5-touch-gameplay-final.png`
- FPS summary: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/ipados-26-5-touch-fps-summary-r2.json`
- Per-second OCR samples: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/ipados-26-5-fps-ocr-samples-r2.txt`
- Touch-camera tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/touch-camera-tests.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-02-touch.stdout.txt`
- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-02-fps60-r2.png`
- Deploy output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-02.stdout.txt`
- Hosted bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-02-bundle-hashes.txt`

### Dev delivery

- Commit `5e94a46` is visible on `origin/main`.
- Worker version `539e004a-b016-44d9-9c5e-1a23ee0ee914` serves the checkpoint only at
  `dev.helios.contenthelper.in`.
- Hosted and local Helios bundle SHA-256 values both equal
  `1e9c59b7940bd36a4d6b3217c07519162bbeedb177cf7cee25dbcc799f6d7219`.
- A clean hosted reload showed 12 Citizens, FPS 60, and no browser exception.

### Next cycle

Resume the authored fragment geometry and material-breakup correction. Do not add another
gameplay system during that visual cycle.

## Cycle 03 — fragment relief and silhouette · 2026-08-09

Status: **Proof Pending; rendered correction is complete, dev deployment is held for the
first-command frame gate**

### Rendered correction

- Replaced each broad smooth wedge with four stepped inner and outer armor bands.
- Added 26 instanced, staggered faceted edge chunks per fragment without changing collision
  or walkable bounds.
- Split each deck into six inset slabs over a darker seam bed.
- Added eight deterministic three-segment cracks per fragment.
- Replaced one-pixel edge accents with physical gold rails.
- Strengthened both fragment ends with full-width termination braces and larger layered
  sockets.
- Kept all logical platform IDs, bridge endpoints, resources, objectives, controls, and
  navigation unchanged.

### Observed result

- The default gameplay view now shows real slab gaps, crack lines, stepped edge relief, warm
  rim thickness, and stronger fragment ends.
- The deck accent cadence was reduced after the first render read as alternating stripes.
- Rectangular edge modules were replaced after the second render read as mechanical gear
  teeth rather than worn space architecture.
- The final geometry contract reports four detailed fragments, 128 instances, 483
  renderables, and 21,126 source triangles across the complete terrain scene.

### Frame-rate gate

- A normal first-time-player sequence selected all 12 Citizens, issued one group movement
  command, zoomed, and panned.
- It rendered 600 frames in 10.0 seconds at 60.0 FPS average.
- Frame time was 17.1 ms p95, 17.5 ms p99, and 17.6 ms maximum.
- No frame exceeded 20 ms.
- A separate full-group command toward the central objective reproduced one 66.6 ms frame;
  the 10-second run averaged 59.70 FPS. This is not accepted as smooth throughout gameplay.
- The path graph is not the cause: 10,000 representative path queries completed in 215.1 ms,
  or 0.022 ms each. The remaining evidence points to first use of the decoded but not yet
  GPU-resident walk atlas.

### Focused checks

- Scoped `node --check` for the terrain source and generated Helios bundle — passed.
- Scoped `git diff --check` — passed.
- Deterministic geometry contract — passed.
- Targeted Helios esbuild — passed without rewriting unrelated dirty lab bundles.
- Real in-app Browser render and normal active-play frame probe — passed.
- Central-objective first-command frame gate — failed; dev deployment is held.
- Per user direction, no additional iPad touch check was run for this visual cycle.

### Evidence

- Final overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-03-local-overview-r4.png`
- Reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-vs-cycle-03-r4.png`
- Geometry contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-03-final-geometry-contract.json`
- Normal active-play metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-03-performance-normal-10s.json`
- Central-objective metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-03-performance-core-command-r2-10s.json`
- Path-graph benchmark: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/pathgraph-benchmark.json`
- Targeted build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-03-geometry-r3.stdout.txt`

### Next cycle

Prewarm the shared Citizen and Guard runtime atlases through Three.js before the units become
interactive. Repeat the central-objective command and normal sustained-motion frame gates.
Do not combine that correction with solar, islet, starfield, HUD, or map-topology work.
