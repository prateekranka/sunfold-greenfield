# Neutral citizen glTF pipeline

Issue #23 proves the editable Blender to GLB to Three.js path. It does not contain production faction citizens.

**In-world presentation** now uses AoE2-style sprites (see
`Docs/Architecture/aoe2-sprite-pipeline.md`). GLBs below remain the authoring
and bake source — not the runtime visual target.

## Production Sunwoven Weaver (issue #24)

`Tools/citizens/run_sunwoven.sh` builds the production Foundation Sunwoven
Weaver on the same shared 27-bone skeleton, exports both GLBs, validates,
renders and captures the sequence proof.

- Production proportions: `rig.PROPORTIONS["sunwoven"]` (slender: narrow
  shoulders, long reach, light limbs). Production motion:
  `clips.FACTION_MOTION["sunwoven"]` (same timing and contacts as #20, lighter
  recovery). The spike sets are untouched — the neutral pipeline still builds
  from them unchanged.
- Production geometry and faction materials live in `Tools/citizens/sunwoven_skin.py`:
  helmet (ivory + gold + cyan accent), robe and limbs (dark woven), chest plate
  (ivory + gold trim), belt (gold), boots (warm brown), woven back basket bound
  to `accessory_strap`, and the approved woven slip harness (two shoulder loops
  + one lower retaining strap) as skinned meshes — every part is clip-animated,
  never runtime physics.
- **Authored prop channels (multi-slot actions).** The gather-loop clips carry
  an authored chunk-arc on the `sunwoven_arc_prop` object through a second
  action slot (armature + prop object), exported as ONE glTF animation per clip
  (probed against the Blender 5.2 exporter; merge mode `ACTION`). The arc
  keyframes ship inside the clip — the runtime consumes the authored channel
  directly. Frame-piece settle is authored keyframe data in the manifest
  (`piece_settle`), applied deterministically at each `construct_contact`.
- Sequence: the manifest `sequence` table authors the clip order, waypoints and
  walk speed; `ThreeRuntime/src/sunwoven-lab.js` plays it at RTS scale and
  drives cargo/deposit/piece presentation from the committed event markers.
  `ThreeRuntime/src/sunwoven-sequence.js` implements the #20 interruption rules
  (before/after each authoritative event, airborne-cargo completion, invalid
  deposit redirect, resume preserving state) as a deterministic state machine.
- Outputs: `ThreeRuntime/assets/citizens/citizen_sunwoven.glb`,
  `sunwoven_lab.glb`, `sunwoven-event-markers.json`; validation under
  `Tools/citizens/build/` (`validation-sunwoven-blend.json`,
  `import-validation-sunwoven.json`, `mismatch-report-sunwoven.json`,
  `sunwoven-interruption-matrix.json`, `browser-proof-sunwoven.json`);
  QA evidence under `Docs/QA/ThreeJS/issue-24/`.

### Honest limit (recorded, not hidden)

Art-direction match for the canonical locked view is authored from the
documented locked traits and palette (see the QA report). This route has no
vision-capable model, so the overlay is not judged by eye; the measured gate —
the geometric locked-pose round trip (bone + skinned-vertex positions) — passes
at sub-millimetre error.

## Toolchain

- Blender 5.2.0 LTS, build `fbe6228777e7`, Python 3.13.13.
- Blender glTF 2.0 exporter bundled with Blender 5.2.0.
- Three.js r178 through `three@0.178.0`.
- Node.js 25.8.2.
- Chrome headless for the WebGL proof capture.

Use `--factory-startup` for every Blender pipeline command. Installed Blender preferences can change background-render behavior.

## Rebuild

Run:

```sh
Tools/citizens/run_pipeline.sh
```

The script rebuilds the editable `.blend`, both GLBs, manifests, validation reports, renders, browser proof, tests, and bundled runtime.

## Authored contract

`Tools/citizens/rig.py` defines one 27-bone hierarchy for both proportion probes. The hierarchy includes right-tool, left-tool, and carrier sockets. `Tools/citizens/clips.py` authors 18 named clips per proportion. Walk clips keep the root fixed. Tool and accessory motion uses authored tracks.

glTF does not define animation event markers. `Tools/citizens/manifest/event-markers.json` reconstructs them losslessly from clip names, frames, and the fixed 30 FPS authoring rate. `payload_attach` is derived from `gather_contact` plus the committed arc duration.

## Outputs and evidence

- Editable source: `Tools/citizens/assets/neutral_lab.blend`.
- Runtime assets: `ThreeRuntime/assets/lab/citizen_slender.glb` and `neutral_lab.glb`.
- Reference lock: `Tools/citizens/manifest/reference-manifest.json`.
- Inventory: `Tools/citizens/build/validation-glb.json`.
- Blender validation: `Tools/citizens/build/validation-blend.json`.
- Three.js validation: `Tools/citizens/build/import-validation.json`.
- Geometric round trip: `Tools/citizens/build/mismatch-report.json`.
- Browser proof: `Tools/citizens/build/browser-proof.json`.
- Visual comparison: side-by-side, overlay, and difference images under `Tools/citizens/build/`.
- Required lab and construction views: `Tools/citizens/build/renders/`.

The inventory reports counts without a pass threshold because the repository has no animation-asset count budget.

## Known limits

- The neutral meshes and proportion probes are technical-spike assets. Tickets #24 and #25 own production citizen modeling.
- Raw bone quaternion bases differ after export. The validator reports them but gates deformed skin vertices and bone positions.
- The pixel difference report is descriptive. Blender and WebGL lighting are not required to be pixel-identical. The geometric locked-pose report is the round-trip correctness gate.
