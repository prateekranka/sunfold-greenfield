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

## Cycle 10 — crystal-islet debris composition · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- The coherent Cycle 09 ring still floated in a mostly empty black field.
- Existing debris was too small to contribute to the diorama silhouette at the gameplay
  camera.
- The approved reference uses large crystal-bearing islets as a second scale layer around and
  inside the ring.

### Correction

- Added 21 authored islet anchors around the outer ring and in the inner void.
- Built each anchor from deterministic clustered rock lobes and a restrained cyan crystal
  crown. The final field contains 126 anchor lobes and 70 anchor crystals.
- Increased the loose field to 180 rocks and 17 small crystals.
- Batched the full field into seven static instanced draw groups: dark and warm loose rocks,
  loose crystals, dark and warm anchor rocks, and normal and bright anchor crystals.
- Disabled cosmetic raycasts for the complete field. It creates no platform, bridge, path,
  collision, resource, objective, or walkable-ground state.

### Rendered and performance proof

- The final local and hosted overview frames were inspected against the approved Broken Ring
  reference.
- Local: 600 frames in 9.9864 seconds at 60.082 FPS, 18.5 ms p95, 18.7 ms maximum, and zero
  frames above 20 ms.
- Hosted: 600 frames in 9.9845 seconds at 60.093 FPS, 16.8 ms p95, 18.7 ms maximum, and zero
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
- Scoped `git diff --check` — passed.
- Hosted page returned HTTP 200. The hosted bundle hash matches the committed asset.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-debris-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-debris-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-debris-gameplay-performance-10s.json`
- Hosted debris contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-debris-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle10-debris-interaction-proof.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle10-debris-final-gameplay-performance-10s.json`
- Ground tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle10-ground-test.stdout.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle10-deploy.stdout.txt`

### Honest limitation

Cycle 10 adds the reference's missing second scale layer, but the islets remain a low-poly
procedural kit rather than individually sculpted Blender assets. The reference still has
richer silhouettes, mineral variation, vegetation, contact shadows, and deep blue-purple
nebula structure. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Implementation commit `250eb91` is visible on `origin/main`.
- Worker version `c129584a-9130-4195-a437-02b2240bbf7b` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-10&v=250eb91`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `060b70f2a60d2d57587478b53c940eddeea1de8d2465d56b8f2460dd6102e014`.

### Next cycle

Add a low-cost blue-purple nebula backdrop and distance haze behind the existing stars and
debris. Preserve black-space contrast, unit readability, controls, topology, and the 60 FPS
gate.

## Cycle 11 — procedural nebula backdrop · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 10 supplied object density, but the spaces between those objects remained a flat black
  field.
- The approved reference uses dark blue-purple cloud lanes and distance haze to separate near
  structures from far debris.

### Correction

- Added one deterministic 256×256 color texture built from warped fBm, weathering fields,
  ridged filaments, and dark lanes.
- Projected the texture on a camera-centered 200-unit sky sphere. It follows every pan and zoom
  without exposing a plane edge or adding parallax to the distant sky.
- Repeated the texture at low cost to reveal cloud structure across the gameplay field.
- Added cool distance fog while preserving a dark center, warm solar contrast, and unit
  readability.
- The sky uses one draw group, disables raycasts, and creates no platform, collision, path, or
  walkable-ground state.
- Passed the review URL's `v` parameter into the runtime script request. A long-lived review
  browser now requests the exact checkpoint bundle instead of reusing a stale URL.

### Rendered and performance proof

- The final local and hosted overview frames were inspected against the approved Broken Ring
  reference.
- Local accepted run: 600 frames in 9.9857 seconds at 60.086 FPS, 17.7 ms p95, 18.6 ms maximum,
  and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9842 seconds at 60.095 FPS, 17.8 ms p95, 18.7 ms maximum,
  and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted runtime script URL is
  `https://dev.helios.contenthelper.in/helios-rift-proof.bundle.js?v=f7a6142`.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check` for the proof, terrain generator, and map source — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Scoped `git diff --check` — passed.
- Hosted page returned HTTP 200. The hosted bundle hash matches the committed asset.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-gameplay-performance-10s.json`
- Hosted nebula and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle11-final-interaction-proof.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle11-nebula-accepted-gameplay-performance-10s.json`
- Ground tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle11-ground-test.stdout.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle11-deploy-versioned.stdout.txt`

### Honest limitation

Cycle 11 adds meaningful atmosphere with one low-cost sky texture. It is not volumetric and
does not reproduce every fine filament in the reference. The reference still has deeper
fragment sidewalls, richer contact shadows, more vegetation, and more textured building
materials. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Nebula implementation commit `b436188` is visible on `origin/main`.
- Versioned-review commit `f7a6142` is visible on `origin/main`.
- Worker version `44bf6fed-c17a-4490-bce8-7e7d9eda94d0` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-11&v=f7a6142`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `163cc92614b458555bd449f0fed119730f84617661d981163507e3fd02d950ec`.

### Next cycle

Deepen the fragment sidewalls with layered structural blocks, warm ribs, and restrained
contact shadow. Preserve the top deck, logical platforms, bridges, controls, and the 60 FPS
gate.

## Cycle 12 — fragment sidewall architecture · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 11 left the fragment edge as a thin, nearly black strip below the gold rim.
- The approved reference uses attached stacked masonry, warm structural braces, and dark
  cavity lines to give each sector architectural mass.

### Correction

- Added one shared chamfered masonry geometry and instanced it in three staggered tiers on
  both exposed edges of every fragment.
- Each fragment now has 78 sidewall blocks: 13 blocks across three tiers on its inner edge
  and the same arrangement on its outer edge.
- Added five embedded brace stations on each edge. Ten vertical brass ribs and 20 short
  brackets share one instanced draw group per fragment.
- Added one restrained contact-shadow band below each inner and outer gold rim.
- The complete correction uses four draw groups per fragment. It changes visual geometry
  only. It does not create walkable ground or alter a platform, bridge, waypoint, collision
  shape, formation slot, repair target, or objective.

### Rendered and performance proof

- Four local visual revisions were inspected at the close gameplay camera. The first read as
  loose debris; the accepted fourth revision reads as attached chamfered masonry.
- Local accepted run: 600 frames in 9.9832 seconds at 60.101 FPS, 17.4 ms p95, 18.8 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9838 seconds at 60.097 FPS, 16.9 ms p95, 18.7 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted runtime script URL is
  `https://dev.helios.contenthelper.in/helios-rift-proof.bundle.js?v=e63155f`.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check` for both changed terrain source files — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed asset.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-gameplay-performance-10s.json`
- Hosted sidewall and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle12-sidewall-final-interaction-proof.json`
- Local frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle12-sidewall-r4-gameplay-performance-10s.json`
- Ground tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle12-ground-test.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle12-build-r4.stdout.txt`
- Bundle hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle12-bundle-hashes.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle12-deploy.stdout.txt`

### Honest limitation

Cycle 12 materially improves the edge depth and silhouette, but it does not blind-match the
reference. The concept still has richer chipped terminal faces, stronger warm solar bounce,
denser deck mechanisms, and more vegetation. The north base buildings remain smoother and
brighter than the surrounding map. The browser frame proof is not a device GPU percentile
export.

### Dev delivery

- Implementation commit `e63155f` is visible on `origin/main`.
- Worker version `33814f5d-dd73-46b7-a364-201d310b25af` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-12&v=e63155f`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `307e833edb54b715985f27ff87a0358f7f32d60f7683e3c9c95d17a78daa1058`.

### Next cycle

Integrate the Civilization Core, Farm, and Formation Yard into the map's weathered
stone-metal material language. Preserve their silhouettes, health-state readability,
gameplay footprints, controls, and the 60 FPS gate.

## Cycle 13 — weathered foundation buildings · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 12 left the north Civilization Core, Farm, and Formation Yard smoother and brighter
  than the weathered Broken Ring around them.
- At the gameplay camera, their pale surfaces read as imported display models rather than
  structures built from the same graphite, ivory, teal, and brass material language.

### Correction

- Rebalanced the Blender source palette toward warm ivory, dark ceramic, woven brass, teal
  fabric, living soil, crop gold, scorch, ash, and restrained emissive accents.
- Added a deterministic `SunfoldSurface` vertex-color field after modifiers and curve
  conversion. Broad weathering, cross-grain, fine grain, and lower-edge darkening now vary
  the surface without changing geometry.
- Added one thin authored contact pad to each healthy and destroyed composition. It grounds
  each silhouette without adding a runtime shadow pass.
- Preserved the required `SW_Teal_Lantern` and `SW_Ember` material names used by runtime
  motion and damage feedback.
- Preserved every building footprint, node hierarchy, motion node, and healthy, damaged,
  critical, and destroyed visibility composition.
- The Blender glTF path now exports the active color layer as `COLOR_0` while preserving the
  authored material `baseColorFactor`. The validator fails closed on white palette loss or
  a primitive without `COLOR_0`.

### Asset contract

- Civilization Core: 1,253,264 bytes, 27,243 exported vertices, 27,196 triangles,
  181 weathered primitives, and 12 materials.
- Farm: 885,880 bytes, 17,236 exported vertices, 14,480 triangles,
  192 weathered primitives, and 12 materials.
- Formation Yard: 516,664 bytes, 10,355 exported vertices, 10,698 triangles,
  90 weathered primitives, and 12 materials.
- All three assets remain below the existing 1.5 MB, 30,000-vertex, 30,000-triangle, and
  12-material ceilings.

### Rendered and performance proof

- All 12 offline Blender state renders were inspected. The real map was then inspected in
  healthy, critical, and destroyed states at the gameplay camera.
- Local accepted run: 600 frames in 9.9938 seconds at 60.037 FPS, 18.6 ms p95, 18.7 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9856 seconds at 60.087 FPS, 16.9 ms p95, 18.6 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted runtime script URL is
  `https://dev.helios.contenthelper.in/helios-rift-proof.bundle.js?v=f300cbd`.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- Blender 5.2 source generation for all three `.blend` and GLB assets — passed.
- Fail-closed GLB surface, hierarchy, palette, and asset-budget validation — passed.
- `node --test ThreeRuntime/tests/gltf-buildings.test.js ThreeRuntime/tests/ground-navigation.test.js`
  — 7 of 7 passed.
- Targeted Helios esbuild — passed.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed and deploy-site assets.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-final-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-final-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-final-gameplay-performance-10s.json`
- Hosted versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle13-weathered-buildings-final-interaction-proof.json`
- Runtime state comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-building-runtime-states.png`
- Blender state sheet: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-building-states-r3.png`
- Final GLB validation: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-building-final-validation.json`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-focused-tests.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-build-r3.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-hosted-http-and-hash-r2.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle13-deploy.stdout.txt`

### Honest limitation

Cycle 13 integrates the building kit into the map's material language and preserves readable
damage. It does not blind-match the reference. Large deck areas remain sparse, while the
concept has restrained living clusters, maintenance mechanisms, richer chipped terminal
faces, and stronger warm solar bounce. The browser frame proof is not a device GPU percentile
export.

### Dev delivery

- Implementation commit `f300cbd` is visible on `origin/main`.
- Worker version `e48b68b8-29c5-4f9b-bb7c-44e61ccae1f2` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-13&v=f300cbd`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `ac9b49b1b0e93f47398784cc04822d2e9d37f49f633d9a22fedf196bff4343a5`.

### Next cycle

Add one restrained, instanced Sunwoven deck-life prop family to the empty ring sectors.
Keep it cosmetic and preserve walkable ground, pathing, controls, and the 60 FPS gate.

## Cycle 14 — woven deck life · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 13 integrated the buildings, but large deck margins still read as sterile and empty.
- The approved reference uses a small number of living green clusters to show that the ring
  was inhabited without turning the battlefield into visual clutter.

### Correction

- Added 14 authored Sunwoven sun-reed clusters outside the central spawn, landmark, resource,
  bridge-approach, and building corridors.
- One low-poly family combines a dark ceramic planter, five woven stems, five folded fabric
  leaves, and three restrained lumen buds.
- Four global instanced draw groups render 14 planters, 70 stems, 70 leaves, and 42 buds.
- The complete family is cosmetic, ignores raycasts, creates no walkable ground, and changes
  no path, collision shape, resource, objective, bridge, or simulation rule.

### Visual iteration

- R1 passed the technical contract but failed the close visual review. It read as three dark
  cactus rods on a pale block.
- R2 uses a darker flared ceramic bowl, five finer stems, broader folded leaves, more graceful
  lean, and dimmer teal tip lights. It reads as living woven sun-reeds at close range and as
  restrained green life at the gameplay overview.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9946 seconds at 60.032 FPS, 17.3 ms p95, 18.6 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9880 seconds at 60.072 FPS, 17.3 ms p95, 18.7 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted contract confirms four draw groups, 14 clusters, no walkable ground, no pathing
  effect, disabled raycasts, and the exact versioned runtime script.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check` for the changed terrain generator and Helios map source — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed asset.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-final-overview.png`
- Hosted close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-east-close-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-final-gameplay-performance-10s.json`
- Hosted deck-life and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle14-deck-life-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-deck-life-r2-overview.png`
- Local close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-deck-life-r2-east-close-final.png`
- Local reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-deck-life-r2-reference-comparison.png`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-focused-tests.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-build-r2.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-hosted-http-and-hash.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle14-deploy.stdout.txt`

### Honest limitation

Cycle 14 adds the missing living deck rhythm without clutter or performance loss. It does not
blind-match the reference. Fragment termini remain thin and clean compared with the concept's
heavy chipped buttresses and solar-joint architecture. Small maintenance mechanisms and warm
solar bounce also remain richer in the concept. The browser frame proof is not a device GPU
percentile export.

### Dev delivery

- Implementation commit `6980510` is visible on `origin/main`.
- Worker version `f06a87e3-dd2e-4f4a-b9ae-32d61d1b87b9` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-14&v=6980510`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `aea0775cadc38556846a423d37422dc1b3907e3739aee3b5450ea4992d050144`.

### Next cycle

Strengthen both ends of every fragment with attached visual buttresses and solar-joint
architecture. Preserve bridge endpoints, walkable ground, pathing, controls, and the 60 FPS
gate.

## Cycle 15 — attached fragment terminals · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 14 added living deck detail, but each fragment still ended in a thin, clean cut with
  oversized bright sockets.
- The approved reference uses heavy chipped terminal faces and warm structural joints to
  communicate the mass of each broken ring segment.

### Correction

- Added three staggered masonry tiers to both cut faces of every fragment: 144 chamfered
  blocks across the map.
- Added 32 warm structural ribs and 64 brackets. Two shared instanced draw groups render each
  fragment's complete terminal architecture.
- Reworked all 16 end sockets as dark stone-metal pedestals with restrained brass rings and
  hubs instead of broad bright discs.
- The terminal blocks overlap the existing understructure cut plane. They do not float in the
  gap or alter a bridge landing.
- The correction changes no bridge endpoint, walkable surface, path, collision shape,
  resource, objective, or simulation rule.

### Visual iteration

- R1 hid most of the masonry behind the old end cap. The sockets grew, but the fragment still
  read as a flat cut.
- R2 exposed the blocks, but they read as detached parallel rails and the bright socket rings
  dominated the close view.
- R3 moved the masonry back onto the cut plane, increased its attached depth, raised the top
  course, restored a narrower end cap, and replaced the bright socket faces with dark caps and
  restrained brass detail. The terminal now reads as one attached wall at close and overview
  cameras.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9879 seconds at 60.073 FPS, 18.6 ms p95, 18.7 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9957 seconds at 60.026 FPS, 16.8 ms p95, 18.7 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted contract confirms three tiers, 36 blocks, eight ribs, 16 brackets, and two
  terminal draw groups on each of the four fragments.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/rts-maps/terrain-generator.js` — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed and deploy-site assets.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-final-overview.png`
- Hosted gameplay close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-final-final.png`
- Hosted terminal close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-close-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-final-gameplay-performance-10s.json`
- Hosted terminal and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle15-terminal-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-terminal-r3-local-overview.png`
- Local terminal close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-r3-se-gap-final.png`
- Local reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-terminal-r3-reference-comparison.png`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-ground-test.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-build-r3.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-hosted-http-and-hash-r2.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle15-deploy.stdout.txt`

### Honest limitation

Cycle 15 gives each fragment a heavier, attached cut-face silhouette and reduces socket glare.
It does not blind-match the reference. The concept still has stronger warm solar bounce under
the inner ring and around its terminal joints, plus more small maintenance mechanisms. The
browser frame proof is not a device GPU percentile export.

### Dev delivery

- Implementation commit `9fac3b5` is visible on `origin/main`.
- Worker version `4165c745-efe2-42bd-aed5-dc715158dcca` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-15&v=9fac3b5`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `5be4e5dff6d0378a63041e9c5c21677d66ed9137630ef76a0498e0702a335dd5`.

### Next cycle

Add restrained warm solar bounce to the inner fragment walls and terminal faces. Preserve
deck readability, bridge endpoints, walkable ground, pathing, controls, and the 60 FPS gate.

## Cycle 16 — restrained solar bounce · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 15 gave the fragment cut faces physical mass, but the inner masonry still fell toward
  near-black at the hero camera.
- The approved reference keeps the outer hull cool while reflected solar light reveals the
  inner wall and terminal structure.

### Correction

- Split inner-wall masonry from outer-wall masonry without changing block transforms or
  counts.
- Applied one shared graphite-and-amber material to 156 inner-wall blocks and 144 terminal
  blocks across the four fragments.
- The material uses a restrained dark-amber emissive lift. It adds one instanced draw group
  per fragment and no dynamic light.
- Outer walls retain the original cool material. The solar core remains the brightest object.
- The correction adds no collider, walkable surface, path, resource, objective, bridge, or
  simulation state.

### Visual iteration

- R1 proved the material split but made the wall read as uniformly red brick.
- R2 reduced the emissive intensity from 0.24 to 0.16 and moved the instance palette back
  toward graphite. The accepted wall remains dark stone-metal at close range and gains a
  readable amber lift at the hero overview.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9926 seconds at 60.044 FPS, 16.8 ms p95, 18.6 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9878 seconds at 60.073 FPS, 16.8 ms p95, 17.7 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted contract confirms 39 inner bounce blocks, 36 terminal bounce blocks, and five
  sidewall draw groups on each fragment.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/rts-maps/terrain-generator.js` — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed and deploy-site assets.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-final-overview.png`
- Hosted gameplay close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-final-final.png`
- Hosted inner-wall close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-inner-wall-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-final-gameplay-performance-10s.json`
- Hosted material and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle16-solar-bounce-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-solar-bounce-r2-local-overview.png`
- Local inner-wall close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-r2-inner-wall-final.png`
- Local reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-solar-bounce-r2-reference-comparison.png`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-ground-test.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-build-r2.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-hosted-http-and-hash.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle16-deploy.stdout.txt`

### Honest limitation

Cycle 16 reveals the inner masonry without turning it into a glowing band. It does not
blind-match the reference. The concept still has more authored maintenance mechanisms around
terminal joints and broad deck margins. The browser frame proof is not a device GPU percentile
export.

### Dev delivery

- Implementation commit `caf70cd` is visible on `origin/main`.
- Worker version `84b7beb4-ce7f-4d66-a8ff-26680ddc78e2` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-16&v=caf70cd`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `1c19482e99dc87bae37d4726d57b6957c4b1f295b09c443c5a2a4faa7863033e`.

### Next cycle

Add one restrained terminal maintenance-mechanism family outside bridge and movement
corridors. Preserve deck readability, walkable ground, pathing, controls, and the 60 FPS gate.

## Cycle 17 — terminal gravity winches · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Cycle 16 made the fragment structure readable, but the broad terminal deck margins still
  lacked small authored machinery.
- The approved reference uses restrained functional detail to show that the broken ring was
  maintained and inhabited.

### Correction

- Added eight human-scale gravity winches, one beside each fragment end and outside all bridge,
  building, landmark, resource, and primary movement corridors.
- Five shared instanced draw groups render eight dark ceramic plinths, 16 brass yokes, eight
  horizontal drums, 16 teal lumen coil rings, and eight top braces.
- Every winch is cosmetic and raycast-disabled. The family creates no walkable ground and
  changes no path, collider, bridge, resource, objective, or simulation rule.

### Visual iteration

- R1 used three bright top spokes and read as a toy propeller.
- R2 replaced the spokes with one crank and grip, but the stacked cylinders read as a cup.
- R3 changed the silhouette to a horizontal cable winch with paired yokes, framed drum, two
  teal coil rings, a low rectangular plinth, and a restrained top brace. It reads as machinery
  at close range and as a small functional accent at the hero camera.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9853 seconds at 60.088 FPS, 17.5 ms p95, 17.7 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9944 seconds at 60.034 FPS, 17.1 ms p95, 17.6 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- The hosted contract confirms eight winches, five draw groups, disabled raycasts, no
  walkable ground, and no pathing effect.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/rts-maps/terrain-generator.js` — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed and deploy-site assets.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-final-overview.png`
- Hosted gameplay close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-final-final.png`
- Hosted winch close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winch-close-final.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-final-gameplay-performance-10s.json`
- Hosted mechanism and versioned-script contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle17-winches-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-winches-r3-local-overview.png`
- Local winch close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-r3-terminal-margin-final.png`
- Local reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-winches-r3-reference-comparison.png`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-ground-test.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-build-r3.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-hosted-http-and-hash.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle17-deploy.stdout.txt`

### Honest limitation

Cycle 17 adds small authored function without clutter. It does not blind-match the reference.
Disabled bridges remain dark, featureless bars that read as unfinished geometry rather than
damaged infrastructure. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Implementation commit `4cfb3c8` is visible on `origin/main`.
- Worker version `dbef7cfb-27c8-441a-8d5d-a175f8ec338c` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-17&v=4cfb3c8`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `50d6ea67d4d5173703a8c0cde966d3ef079b9bd51a9cc1bc9b2c19f664fab2b3`.

### Next cycle

Make disabled bridges read as damaged infrastructure with fractured deck slabs and restrained
repair filaments. Preserve bridge state, route rules, controls, and the 60 FPS gate.

## Cycle 18 — fractured disabled bridges · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Disabled bridges were two clean dark bars with bright dots.
- They read as unfinished placeholder geometry, not damaged ring infrastructure.

### Correction

- Kept the enabled bridge as the existing four restored slabs, continuous understructure,
  gold rails, and center conduit.
- Replaced each disabled bridge with two terminal slabs, two staggered tongue slabs, six
  exposed warm braces, four curved repair filaments made from 16 ribbon segments, two small
  repair beacons, and one restrained center spark.
- Disabled bridges create no walkable ground. Repair replaces the fractured composition with
  the existing continuous crossing. Route and approach rules are unchanged.

### Visual iteration

- R1 established the fractured slabs and braces, but one-pixel V-shaped filaments read as
  debug wireframe.
- R2 changed the filaments to luminous double-sided ribbons, but the hard V bend looked
  synthetic.
- R3 divided each filament into four smooth sag segments. The result reads as damaged repair
  infrastructure at close range and stays restrained at the hero camera.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9838 seconds at 60.097 FPS, 17.2 ms p95, 17.8 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9832 seconds at 60.101 FPS, 17.5 ms p95, 17.8 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- The bridge transition proof changed `bridge-w-core` from four fractured pieces, six braces,
  and 16 filament segments with no walkable ground to four restored slabs and continuous
  walkable understructure. `bridge-e-core` remained disabled and fractured.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/rts-maps/terrain-generator.js` — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- Root and deploy-site generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200. The hosted bundle hash matches the
  committed and deploy-site assets.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-overview.png`
- Hosted gameplay close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-final.png`
- Hosted disabled-bridge close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-disabled-bridge-close-final.png`
- Hosted before and after: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-disabled-bridge-before-after.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-gameplay-performance-10s.json`
- Hosted bridge transition: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-bridge-transition.json`
- Hosted material contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle18-fractured-bridges-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-fractured-bridges-r3-local-overview.png`
- Local disabled-bridge close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-r3-disabled-east-core-final.png`
- Local reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-fractured-bridges-r3-reference-comparison.png`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-ground-test.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-build-r3.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-hosted-http-and-hash.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle18-deploy.stdout.txt`

### Honest limitation

Cycle 18 gives disabled crossings a readable damaged state and preserves repair behavior. It
does not blind-match the reference. Broad terrain color variation still reads as alternating
bands at the hero camera. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Implementation commit `5c4e16d` is visible on `origin/main`.
- Worker version `c53bc79d-2788-43df-a640-91e3fed25d88` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-18&v=5c4e16d`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `288ab08aa33a475b77879969f7747c6b408ba8303ce95986ac3c78e38fd8af2d`.

### Next cycle

Refine the existing world-space terrain material with smooth multi-scale color, slope, edge,
and micro-normal variation. Remove visible banding without displacing collision geometry or
changing pathing.

## Cycle 19 — continuous weathered terrain · 2026-08-10

Status: **Done and deployed**

### Player-visible defect

- Broad brown and gray variation still read as alternating material bands across each deck.
- The variation weakened the sense that every fragment belonged to one weathered structure.

### Correction

- Kept one deterministic 256×256 world-space terrain field and one lit terrain material per
  deck or armor family.
- Rebuilt the field from broad fBm, derivative-attenuated weathered fBm, ridged fBm, cellular
  distance, and fine value noise.
- Replaced broad color thresholds with continuous multi-scale masks. The same field now
  drives color, roughness, and derivative normal response.
- Shifted the deck toward cooler neutral graphite while retaining restrained warm sun wear.
- Kept walkable meshes, collision geometry, pathing, bridge endpoints, resources, objectives,
  and controls unchanged. The material contract explicitly reports no geometry displacement.

### Source adaptation

- The implementation adapts SimonDev's `MeshStandardMaterial.onBeforeCompile` approach for
  world-space procedural color and surface response.
- It uses the procedural-terrain thread's weathered fBm, ridged fBm, and cellular-noise ideas
  as low-relief deck variation rather than literal mountainous displacement.
- Sources: `https://simondev.io/demos/gamedev/#customizing-materials` and
  `https://x.com/iced_coffee_dev/status/2084276803833581736`.

### Rendered and performance proof

- Local accepted run: 600 frames in 9.9902 seconds at 60.059 FPS, 17.9 ms p95, 18.6 ms
  maximum, and zero frames above 20 ms.
- Hosted final run: 600 frames in 9.9948 seconds at 60.031 FPS, 17.6 ms p95, 17.7 ms
  maximum, and zero frames above 20 ms.
- Both runs selected and moved all 12 local units through two legal formation orders while
  camera and building damage states changed.
- Both runs sampled all 12 units on every frame: 7,200 ground checks and zero invalid samples.
- Pointer deselection, keyboard selection, Guide focus, Escape focus restoration, and Repair
  availability passed on the hosted build.
- A fresh in-app Browser tab loaded the exact versioned script at 1280×720 and showed FPS 60.
  Its high-level screenshot wrapper timed out, but a direct CDP surface capture succeeded at
  2560×1440 without changing page state.
- Per user direction, no additional iPad simulator touch check was run.

### Focused checks

- `node --check ThreeRuntime/src/rts-maps/terrain-generator.js` — passed.
- `node --test ThreeRuntime/tests/ground-navigation.test.js` — 5 of 5 passed.
- Targeted Helios esbuild — passed.
- The version-2 material contract reports `weathered-fbm-ridged-cellular`,
  `continuous-multiscale`, no hard color bands, and no geometry displacement.
- Root, deploy-site, and hosted generated bundle SHA-256 values are identical.
- Scoped `git diff --check` — passed.
- Hosted page and versioned bundle returned HTTP 200.
- The two unrelated dirty lab bundle hashes remained unchanged.

### Evidence

- Hosted overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-final-overview.png`
- Hosted gameplay frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-final-final.png`
- Hosted deck close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-close-final.png`
- Hosted in-app Browser frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-in-app-browser-cdp.png`
- Hosted before and after: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-before-after.png`
- Hosted reference comparison: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-reference-comparison.png`
- Hosted frame metrics: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-final-gameplay-performance-10s.json`
- Hosted material contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-final-material-contract.json`
- Hosted interaction proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/hosted-cycle19-weathered-terrain-final-interaction-proof.json`
- Local overview: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-weathered-terrain-r3-local-overview.png`
- Local deck close frame: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-r3-west-deck-final.png`
- Local material contract: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-weathered-terrain-r3-local-material-contract.json`
- Focused tests: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-ground-test-r1.stdout.txt`
- Build output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-build-r3.stdout.txt`
- Bundle and preservation hashes: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-bundle-and-preservation-hashes.txt`
- Hosted hash and HTTP proof: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-hosted-http-and-hash-final.txt`
- Deployment output: `/Users/prateekranka/.codex/evidence/helios-broken-ring-aaa-takeover/20260809T153411Z.lD1se7/cycle19-dev-deploy.stdout.txt`

### Honest limitation

Cycle 19 removes the material-band read and preserves movement. It does not blind-match the
reference. The deck still lacks the reference's denser chipped slab hierarchy and authored
surface borders. The browser frame proof is not a device GPU percentile export.

### Dev delivery

- Implementation commit `fde7b1c` is visible on `origin/main`.
- Worker version `416d9c96-efc2-427b-964f-14fc7e71baea` serves this checkpoint only at
  `https://dev.helios.contenthelper.in/?qa=cycle-19&v=fde7b1c`.
- The committed, deploy-site, and hosted Helios bundle SHA-256 values all equal
  `8594836852e47ad5b95763b313d309d84d8409e3e84fc4097b17c208467a9152`.

### Next cycle

Add a restrained slab hierarchy and chipped structural borders to the playable deck. Preserve
walkable bounds, pathing, controls, and the 60 FPS gate.
