#!/bin/bash
# Isolated compile check for a parallel agent.
#
# Several agents edit disjoint source files at the same time. They must not share
# a derivedData directory (concurrent writes corrupt the module cache) and must not
# run `xcodegen generate` concurrently (concurrent writes corrupt project.pbxproj).
#
# Usage:  scripts/agent-build.sh <agent-name>
#
# Exits non-zero and prints only the compiler diagnostics when the build fails.

set -uo pipefail

AGENT="${1:?usage: agent-build.sh <agent-name>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build-agents/$AGENT"
SIM_ID="A59055F8-1354-4936-97B8-7033DF90B0BB"
LOCK="$ROOT/build-agents/.xcodegen.lock"

cd "$ROOT"
mkdir -p "$ROOT/build-agents"

# project.yml globs Sources/, so any agent's `generate` produces a project
# containing every agent's files. Serialize it so two writers never interleave.
# mkdir is the portable atomic test-and-set; macOS has no flock(1).
for _ in $(seq 1 180); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    xcodegen generate >/dev/null 2>&1
    rmdir "$LOCK" 2>/dev/null
    trap - EXIT
    break
  fi
  sleep 1
done

xcodebuild \
  -project SunfoldGreenfield.xcodeproj \
  -scheme SunfoldGreenfield \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DD" \
  2>&1 | tee "$DD.log" | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | head -60

exit "${PIPESTATUS[0]}"
