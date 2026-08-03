# Neutral citizen glTF pipeline

Issue #23 proves the editable Blender to GLB to Three.js path. It does not contain production faction citizens.

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
