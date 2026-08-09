#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
blender=/Applications/Blender.app/Contents/MacOS/Blender
export PYTHONDONTWRITEBYTECODE=1

cd "$repo"
"$blender" --background --factory-startup --python Tools/citizens/preflight.py
B23_STEPS=build,export,render,manifest "$blender" --background --factory-startup --python Tools/citizens/build_lab.py
B23_CITIZEN=spike_slender B23_STEPS=export "$blender" --background --factory-startup --python Tools/citizens/build_lab.py
B23_CITIZEN=spike_broad B23_STEPS=export "$blender" --background --factory-startup --python Tools/citizens/build_lab.py
"$blender" --background --factory-startup --python Tools/citizens/validate_blend.py
python3 Tools/citizens/inspect_glb.py
node ThreeRuntime/scripts/validate-glb.mjs
node Tools/citizens/build-web.mjs
node Tools/citizens/capture-web-proof.mjs
Tools/citizens/build-reference-sheets.sh
(cd ThreeRuntime && npm test && npm run build)
