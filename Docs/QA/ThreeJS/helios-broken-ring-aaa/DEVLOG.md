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

Status: **Done and deployed with Cycle 04**

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

## Cycle 04 — movement-state frame gate · 2026-08-09

Status: **Done and deployed**

### Player-visible correction

- Citizens and Guards now finish startup on walk frame zero, which is their authored standing
  cell, with playback frozen.
- A movement order now unfreezes that prepared clip instead of reapplying the same atlas state
  to every selected unit.
- A repeated movement order leaves an already-walking unit's clip and phase intact.
- A unit that finishes ordinary movement freezes again on walk frame zero. Gather and build
  clips still transition back through the same standing cell.
- Unit art, speed, paths, commands, selection, objectives, and camera behavior are unchanged.

### Diagnosis

- The 27-node path graph is not a frame-time risk: 10,000 representative path requests took
  215.1 ms, or 0.022 ms each.
- The first instrumented central command completed in 4.7 ms and produced no frame above
  20 ms.
- The remaining avoidable work was repeated state application. Every new movement order reset
  all selected units to the walk clip, even when they were already walking.
- No renderer, atlas file, shader, terrain geometry, or simulation change was required.

### Rendered and performance proof

- The opening frame still shows the same authored standing poses for all 12 local units.
- The final probe selected all 12 units, ordered them toward the central objective, zoomed,
  panned, and issued a second group order while they remained active.
- It rendered 600 frames in 10.0007 seconds at 59.996 FPS average.
- Frame time was 17.6 ms p95, 17.7 ms p99, and 17.8 ms maximum.
- No frame exceeded 20 ms or 33.34 ms.
- The first command handler took 6.8 ms. The repeated order took 1.3 ms.
- Per user direction, no additional iPad touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/helios-rift-proof.js` — passed.
- Targeted Helios esbuild — passed without rewriting unrelated dirty lab bundles.
- Real in-app Browser opening frame — visually inspected.
- Real rendered two-order movement, zoom, and pan frame gate — passed.
- No focused unit test was added; the changed behavior is renderer timing, and the rendered
  performance probe is the narrowest useful regression proof.

### Evidence

- Final frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-04-performance-two-order-10s.json`
- Opening standing frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-04-opening-standing-frame.png`
- Command profile: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-04-core-command-profile.json`
- Path-graph benchmark: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/pathgraph-benchmark.json`
- Targeted build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-04-standing-prime.stdout.txt`

### Dev delivery

- Commit `4cb24fa` is visible on `origin/main`.
- Worker version `4381c0dd-bbad-48e3-97b5-4d433a09e915` serves the combined Cycle 03/04
  artifact only at `dev.helios.contenthelper.in`.
- The committed bundle, deploy-site bundle, and hosted bundle SHA-256 values all equal
  `64590a5a627ad4100aae2827f3007eb7c6e0c2e57b8db7f570ba2af120f2d018`.
- A clean hosted load showed the detailed four-sector ring, 12 Citizens, FPS 60, and no
  browser exception.
- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-04-fps60.jpg`
- Hosted bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-04-bundle-hashes.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-04.stdout.txt`

### Next cycle

Give the solar objective bounded plasma structure, readable fissures, and a stronger corona.
Keep capture rules, pathing, fragment geometry, resource islets, starfield, and HUD unchanged.

## Cycle 05 — molten solar objective · 2026-08-10

Status: **Done and deployed**

### Reference defect

- The central objective read as a pale flat disk instead of a volatile star.
- Its broad translucent corona hid the surface during a flare.
- The reference uses a stronger hierarchy: molten surface, bright limb, restrained halo,
  white-hot glare, and small surrounding particles.

### Rendered correction

- Added a deterministic 384×192 warped Voronoi plasma texture with organic fissures, warm
  plate variation, micro-heat, and cloud heat.
- Increased the objective radius from 3.8 to 4.8 world units and its height from 4.1 to 5.3.
- Added a bright limb, annular halo, rotating sixteen-ray glare, and 64 deterministic sparks.
- Added slow independent rotation for the surface, glare, and sparks.
- Added separate neutral and flare corona opacity values. The flare no longer replaces the
  molten surface with a flat yellow shell.
- Preserved objective capture, hazard timing, bridge state, resource state, platform IDs,
  and movement rules.

### Rendered and performance proof

- The accepted frame shows a readable molten objective at the default gameplay camera.
- The active probe selected all 12 units, issued two group orders, and crossed a forced flare
  transition.
- It rendered 600 frames in 10.0071 seconds at 59.957 FPS average.
- Frame time was 16.8 ms p95, 17.6 ms p99, and 17.7 ms maximum.
- No frame exceeded 20 ms or 33.34 ms.
- The two command handlers took 1.7 ms and 0.3 ms.
- Per user direction, no additional iPad touch check was run.

### Focused checks

- Targeted Helios esbuild — passed.
- Real in-app Browser neutral and flare states — visually inspected.
- Real rendered two-order movement and flare-transition frame gate — passed.
- Scoped `git diff --check` — passed before the checkpoint commit.
- No focused unit test was added. This checkpoint changes presentation only, and rendered
  inspection plus the frame probe is the narrowest useful proof.

### Evidence

- Final frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-05-solar-final-r2.jpg`
- Reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-vs-cycle-05-solar-final-r2.png`
- Normalized reference crop: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/reference-solar-normalized-256.png`
- Normalized rendered crop: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-05-solar-final-r2-core-256.jpg`
- Visual metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-05-solar-visual-metrics-final.json`
- Frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-05-solar-final-r2-performance-10s.json`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-05-solar-final-r2.stdout.txt`

### Honest limitation

The objective is materially closer to the reference, but it is not a blind-match result.
Its fissure cells remain larger and its plasma less turbulent. The full map still lacks the
reference's large crystal islets, debris density, and nebula depth.

### Dev delivery

- Commit `b97a3ce` is visible on `origin/main`.
- Worker version `7910078f-a95f-4195-a3a0-8e1b8604a552` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-05&v=b97a3ce`.
- The committed bundle, deploy-site bundle, and hosted bundle SHA-256 values all equal
  `45bdbeeb23398b583bc96282ee49eef7185992767b38b968d38399e15a2599b3`.
- A clean hosted load showed the molten objective, 12 Citizens, FPS 60, and no startup error.
- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-05-fps60.jpg`
- Hosted bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-05-bundle-hashes.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-05.stdout.txt`

### Next cycle

Land units have been observed traversing and stopping in open void. Reproduce that path and
enforce legal platform and bridge movement before adding buildings, training, or HUD systems.

## Cycle 06 — land-unit void exclusion · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- The command plane accepted taps anywhere, including open space.
- A failed graph search returned the raw destination as a direct path.
- Resource and objective nodes were disconnected from their platforms.
- Bridge paths jumped from a platform center to a bridge midpoint instead of following the
  rendered approach and deck.
- A flare disabled repaired core bridges but did not restore them after the flare ended.

### Gameplay correction

- Added one ground rule for annular fragments, circular platforms, and physically repaired
  bridges.
- Open-void commands now stop immediately with `Land units need stable ground`.
- Disconnected expansion islets now report that transport is required.
- A graph search with no route returns no path. It cannot fall back to a straight void line.
- Path graph bridges now use approach, midpoint, and exit nodes aligned with rendered bridge
  endpoints.
- Every complete path is sampled against the ground rule before movement starts.
- Every movement step checks the same rule and stops before an invalid position.
- Formation slots near an edge move to nearby ground. The 12-unit group uses 12 unique slots.
- Flare locks now restore the physical repaired state when the flare ends.

### Rendered proof

- A real right-click at world point `(-10, -10)` produced the stable-ground message.
- All 12 selected units kept empty paths and remained on valid ground.
- A second real right-click moved all 12 units from the north fragment, over the enabled north
  core bridge, and onto the core platform.
- The arrival used 12 unique formation slots. Every unit finished on valid ground.
- A forced flare disabled both repaired core routes. Ending it restored both routes.

### Frame-rate gate

- The valid 12-unit bridge route sampled 600 rendered frames in 9.9906 seconds.
- Average frame rate was 60.056 FPS.
- Frame time was 16.8 ms p95, 17.6 ms p99, and 17.7 ms maximum.
- No frame exceeded 20 ms or 33.34 ms.
- The probe checked every local unit on every frame: 7,200 checks and zero invalid samples.
- Per user direction, no additional iPad touch check was run.

### Focused checks

- `node --test tests/ground-navigation.test.js` — 5 of 5 passed.
- Scoped syntax checks for the five changed source modules — passed.
- Targeted Helios esbuild — passed without rewriting unrelated dirty lab bundles.
- Real in-app Browser void rejection, valid bridge route, flare recovery, and 60 FPS gate —
  passed.
- Scoped `git diff --check` — passed before the checkpoint commit.

### Evidence

- Void rejection frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-void-command-rejected-final.jpg`
- Void result: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-void-command-result-final.json`
- Valid arrival frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-valid-bridge-arrival-fps60-stable.jpg`
- Active route metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-land-route-performance-final-10s.json`
- Flare route recovery: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-flare-bridge-restore-final.json`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-06-ground-navigation-tests-final.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/build-cycle-06-land-legality-final.stdout.txt`

### Dev delivery

- Commit `fdc8267` is visible on `origin/main`.
- Worker version `4e87a23c-ec73-467c-918e-a69e2f3af98b` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-06&v=fdc8267`.
- The committed bundle, deploy-site bundle, and hosted bundle SHA-256 values all equal
  `e175c7d42f31a3a1b22cdbaea6dc26e62714c49b103693eba1b8060bd146cc7b`.
- The hosted void command produced `Land units need stable ground`, left all 12 unit paths
  empty, kept every unit on valid ground, and showed FPS 60.
- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-06-void-rejected-fps60.jpg`
- Hosted bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-06-bundle-hashes.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-06.stdout.txt`

### Next cycle

Build a coherent Sunwoven 3D kit in Blender: Civilization Core, Farm, and Formation Yard.
Each building needs healthy, damaged, critical, and destroyed reads at the gameplay camera.
Do not combine the model kit with the iPad-first construction and training HUD.

## Cycle 07 — Sunwoven foundation building kit · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- The north base used placeholder primitives with no Sunwoven building hierarchy.
- Core, Farm, and military production had no distinct silhouettes.
- Building HP changes had no authored damage progression or destruction payoff.

### Blender correction

- Added reproducible Blender sources and exports for the Civilization Core, Farm, and
  Formation Yard.
- The Core uses a circular ceramic body, layered fabric eaves, gold rings, teal panels,
  outer pavilion arches, flags, and a slow crown ring.
- The Farm uses a low rectangular field, three crop rows, luminous irrigation channels,
  perimeter posts, and restrained crop sway.
- The Formation Yard uses a rectangular training deck, square fabric pavilion, central loom,
  weapon rack, perimeter masts, and a distinct military silhouette.
- Every asset exports named healthy, damaged, critical, and destroyed visibility groups.
  Damage bands change at 75%, 50%, and 0% life.
- Added authored missing-panel, broken-frame, scorch, ember, and wreck compositions. The
  destroyed state replaces the standing building instead of hiding it without a payoff.

### Runtime integration

- Added one GLTF loader library that preloads each bundled asset once and clones it per
  instance.
- The simulation remains authoritative for life. The renderer maps life ratios to named
  visual groups and does not change combat, economy, or victory rules.
- Moved the north Matter node clear of the building footprints.
- Moved local Citizens and Guards to an inward-facing arc that does not intersect the Core,
  Farm, or Formation Yard.
- Added proof controls for exact building life, aggregate damage state, camera position,
  all-local selection, and legal movement orders.
- Narrowed both the lab builder and the dev-site builder so deployment cannot overwrite
  unrelated dirty lab bundles.

### Asset budgets

- Civilization Core: 980,388 bytes, 26,691 vertices, 26,388 triangles, 11 materials.
- Farm: 700,348 bytes, 16,804 vertices, 14,264 triangles, 11 materials.
- Formation Yard: 402,040 bytes, 9,923 vertices, 10,482 triangles, 11 materials.
- All three assets pass the 1.5 MB, 30,000-vertex, 30,000-triangle, and 12-material limits.

### Rendered and performance proof

- Healthy, critical, and destroyed compositions were inspected in the real gameplay camera.
- The final local run selected and moved all 12 units through two legal formation orders
  while the camera and all building damage bands changed.
- Local: 600 frames in 9.9884 seconds at 60.070 FPS, 16.8 ms p95, 18.7 ms maximum, and zero
  frames above 20 ms.
- Hosted: 600 frames in 9.9975 seconds at 60.015 FPS, 18.6 ms p95, 18.7 ms maximum, and zero
  frames above 20 ms.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Per user direction, no additional iPad touch check was run.

### Focused checks

- Python source compile — passed.
- Headless Blender build and 12-state render — passed without a traceback.
- GLB contract and mobile budget validator — passed for all three assets.
- `node --test tests/gltf-buildings.test.js` — 2 of 2 passed.
- Targeted Helios esbuild — passed without rewriting unrelated lab bundles.
- Real local and hosted Browser state transitions, legal movement, and frame gates — passed.
- Scoped `git diff --check` — passed before each commit.

### Evidence

- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-07-buildings-fps60.png`
- Strict reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-reference-vs-rendered-buildings-arches-yard.png`
- Blender state sheet: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-building-states-contact-sheet-arches-yard.png`
- Local healthy frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-sunwoven-buildings-healthy-arches-yard-wide.png`
- Local critical frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-sunwoven-buildings-critical-arches-yard.png`
- Local destroyed frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-sunwoven-buildings-destroyed-arches-yard.png`
- Asset validation: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-building-glb-validation-arches-yard.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-building-gameplay-performance-final-10s.json`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-07-building-gameplay-performance-10s.json`
- Hosted bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-07-bundle-hashes.txt`
- Blender output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-blender-build-arches-yard.stdout.txt`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-07-building-tests-arches-yard-r2.stdout.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-07.stdout.txt`

### Honest limitation

The three buildings are a coherent first authored kit, not a blind AAA match. The strict
comparison still shows flatter silhouettes, untextured materials, weaker contact shadows,
and less weathering than the concept. The surrounding fragment remains dark and sparse
instead of warm, stone-rich, and vegetated. The desktop debug overlay also blocks too much
of the playfield.

### Dev delivery

- Implementation commit `7ca4824` is visible on `origin/main`.
- Deployment-isolation commit `b8ca69a` is visible on `origin/main`.
- Worker version `34be548a-39e3-494f-9188-a4f72e4bac74` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-07&v=7ca4824`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `455026547b1a66434501bee27a912a34cc3c8e321898fe2c89b35b8029eecab7`.

### Next cycle

Replace the desktop debug overlay with a compact iPad-first tactical HUD. Preserve the live
map, touch controls, building kit, simulation rules, and 60 FPS gate. Do not add a parallel
construction, production, or combat system during the HUD checkpoint.

## Cycle 08 — compact iPad tactical HUD · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- The desktop debug block obscured the upper battlefield and presented internal state as a
  developer transcript.
- Resources, objective state, selected units, base life, and commands had no iPad-first
  hierarchy.
- The console-only hint control did not provide an in-game first-use guide.

### Correction

- Replaced the debug block with safe-area-aware top, center, and bottom rails.
- The top rail reads the existing Energy, Matter, Lumen, and Aether stock, Solar Core owner,
  and frame counter.
- The center ribbon states the current objective and broken-bridge count.
- The bottom cards show selected local units, Civilization Core health, the existing Select
  all and Repair commands, the Guide, and the existing minimap.
- Added a coarse-pointer field guide for tap, double-tap, drag, pinch, and stable-ground rules.
- Added keyboard access through `1`, `2`, `H`, and Escape. Opening the Guide focuses Close;
  Escape returns focus to Guide.
- The HUD is a presentation layer over existing state and commands. It adds no construction,
  production queue, training, combat, or economy rule.

### Rendered and interaction proof

- The exact iPad landscape layout audit used a 1194×834 CSS viewport with coarse pointer
  emulation. No bottom panel overlapped another panel.
- Primary command targets measured 120×66 points. Guide Close measured 44×44 points.
- A real CDP pointer press on empty ground cleared selection. Keyboard `1` then selected all
  12 local units. Repair became available.
- Guide opening focused Close. Escape closed it and restored focus to Guide.
- The final local and hosted frames were inspected at the same 1194×834 gameplay viewport.
- Per user direction, no additional iPad simulator touch check was run.

### Performance proof

- Local: 600 frames in 9.9918 seconds at 60.049 FPS, 18.6 ms p95, 18.7 ms maximum, and zero
  frames above 20 ms.
- Hosted: 600 frames in 9.9905 seconds at 60.057 FPS, 17.5 ms p95, 18.7 ms maximum, and zero
  frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.

### Focused checks

- `node --check ThreeRuntime/src/helios-rift-proof.js` — passed.
- Targeted Helios esbuild — passed without rewriting the two unrelated dirty lab bundles.
- Scoped `git diff --check` — passed.
- Local and hosted keyboard, focus, Guide, selection, movement, damage-state, ground, and
  frame-time gates — passed.
- Hosted page returned HTTP 200. The hosted bundle hash matches the local asset.

### Evidence

- Hosted frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-08-hud-final.png`
- Local frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-08-hud-headless-final.png`
- Debug-versus-HUD comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-08-debug-vs-ipad-hud.png`
- Exact iPad layout audit: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-08-ipad-landscape-layout-audit.json`
- Local interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-08-hud-interaction-proof.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-08-hud-interaction-proof.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-08-hud-gameplay-performance-10s.json`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-08-hud-gameplay-performance-10s.json`
- Hosted HTTP and bundle proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-08-http-proof.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/deploy-cycle-08.stdout.txt`

### Honest limitation

The HUD is a compact command shell for the current proof, not a complete production RTS HUD.
It has no construction palette, training queue, time controls, diplomacy, or combat command
grid because those systems are outside this checkpoint. The iPad landscape layout is
browser-emulated; this cycle does not add a fresh device GPU percentile export.

### Dev delivery

- Implementation commit `7497c8c` is visible on `origin/main`.
- Worker version `f87e19d9-d6f2-4275-9d32-eac948ad4a26` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-08&v=7497c8c`.
- The local and hosted Helios bundle SHA-256 values both equal
  `00185851ff2b5dc7bb52df46d9eeb1460932ac4cb4b580ddf44ac9c64ab12529`.

### Next cycle

Replace the visible alternating fragment bands with one coherent lit terrain material. Use
world-space variation to create warm stone, cooler gravity wear, cracks, and edge weathering
without changing fragment geometry, map topology, walkability, bridges, controls, or gameplay
rules. Preserve the 60 FPS gate.

## Cycle 09 — material-driven Broken Ring terrain · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Six repeated light and dark deck panels split each fragment into broad alternating bands.
- The surface read as assembled debug strips instead of one weathered, sun-worn land mass.
- Color changed by mesh instead of by coherent material structure.

### Correction

- Added one deterministic 256×256 RGBA terrain field. Its channels carry broad form,
  weathering, ridges, and grain.
- Added sun-worn deck and gravity-weathered armor material variants. Both sample the field in
  world XZ space at broad, detail, and micro scales.
- The standard lit material remains authoritative. The terrain field varies color, roughness,
  metalness, and derivative normals.
- Removed every legacy alternating deck-panel mesh. Each fragment now has one continuous deck,
  eight authored cracks, and three hairline structural inlays.
- Kept geometry displacement disabled. Logical platforms, bridge routes, collision rules,
  controls, units, resources, and objectives are unchanged.
- Made the lab builder's working directory explicit. Root and runtime build routes now create
  the same generated bundle.

### Source direction

- Adapted the material-customization approach from
  `https://simondev.io/demos/gamedev/#customizing-materials`.
- Adapted the procedural terrain thread's layered fBm, ridged, weathered, and multi-frequency
  ideas from `https://x.com/iced_coffee_dev/status/2084276803833581736`.
- Used those ideas for visual surface detail only. Runtime movement still uses the authored
  ground contract.

### Rendered and performance proof

- The final local and hosted frames were inspected against the approved Broken Ring reference.
- Local: 600 frames in 9.9894 seconds at 60.064 FPS, 17.0 ms p95, 18.5 ms maximum, and zero
  frames above 20 ms.
- Hosted: 600 frames in 9.9885 seconds at 60.069 FPS, 18.1 ms p95, 18.8 ms maximum, and zero
  frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check` for both changed terrain source files — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root-versus-runtime generated bundle hashes — identical.
- Scoped `git diff --check` — passed.
- Hosted page returned HTTP 200. The hosted bundle hash matches the committed asset.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-terrain-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-terrain-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-terrain-gameplay-performance-10s.json`
- Hosted material contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-terrain-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle-09-terrain-interaction-proof.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle-09-terrain-final-gray-gameplay-performance-10s.json`
- Ground tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle09-ground-test.stdout.txt`
- Build determinism hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle09-determinism-root.sha256` and `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle09-determinism-runtime.sha256`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle09-deploy.stdout.txt`

### Honest limitation

Cycle 09 removes the alternating-band presentation and adds coherent procedural material
variation. It does not yet blind-match the reference. The reference still has denser crystal
islets, layered debris, richer sidewall relief, vegetation, contact shadows, and nebula depth.
The terrain uses visual normal detail without vertex displacement so the existing path and
collision proof remains exact. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Terrain commit `816d06c` is visible on `origin/main`.
- Reproducible-build commit `4ab8e29` is visible on `origin/main`.
- Worker version `c4c70fa5-8a06-49d6-85cb-0f7447d3c441` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-09&v=4ab8e29`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `eae74d6347afa0f055a3d3e406840190affa4d970bacd7cbb62482af023858ec`.

### Next cycle

Add an authored field of crystal islets and layered debris around the ring. Improve the
diorama silhouette and resource readability without adding walkable ground, changing map
topology, or weakening the 60 FPS gate. Treat nebula depth as a separate later checkpoint.
