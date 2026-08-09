#!/bin/sh
# Issue #24 — production Sunwoven Weaver pipeline.
# Rebuilds the editable .blend, both GLBs, manifests, validation reports,
# renders, the browser sequence proof, and the QA evidence.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
blender=/Applications/Blender.app/Contents/MacOS/Blender
export PYTHONDONTWRITEBYTECODE=1

cd "$repo"
python3 Tools/citizens/codex_envelope.py
"$blender" --background --factory-startup --python Tools/citizens/build_sunwoven.py
"$blender" --background --factory-startup --python Tools/citizens/validate_sunwoven_blend.py
"$blender" --background --factory-startup --python Tools/citizens/validate_sunwoven_topology.py
python3 Tools/citizens/inspect_glb.py
node ThreeRuntime/scripts/validate-sunwoven.mjs
(cd ThreeRuntime && npm test)
node Tools/citizens/build-sunwoven-web.mjs
node Tools/citizens/capture-sunwoven-proof.mjs
Tools/citizens/build-sunwoven-reference-sheets.sh
comparison_status=0
if python3 Tools/citizens/compare_canonical.py; then
    comparison_status=0
else
    comparison_status=$?
fi
python3 Tools/citizens/assemble_qa_report.py

if [ "$comparison_status" -ne 0 ]; then
    echo "Sunwoven pipeline complete with canonical comparison failure." >&2
fi
exit "$comparison_status"
