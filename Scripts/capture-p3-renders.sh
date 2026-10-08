#!/bin/bash
#
# capture-p3-renders.sh — runs the Phase 3 offscreen render tests with
# KADENCE_CAPTURE_DIR set and copies the PNGs they write (in the sandboxed
# test host's temporary directory) to screenshots/3 with SUFFIX. No UI input:
# the renders never leave the test process.
# Usage: SUFFIX=p3t14 Scripts/capture-p3-renders.sh [TestSuite …]
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:-p3}"
TMP="$HOME/Library/Containers/XIX.Kadence/Data/tmp/kadence-captures"
rm -rf "$TMP"
ONLY=()
for suite in "${@:-SourceRenderTests}"; do ONLY+=("-only-testing:KadenceTests/$suite"); done
TEST_RUNNER_KADENCE_CAPTURE_DIR=1 xcodebuild -scheme Kadence -destination 'platform=macOS' "${ONLY[@]}" test >/dev/null 2>&1
echo "tests rc=$?"
mkdir -p screenshots/3
for f in "$TMP"/*-p3.png; do
  [[ -e "$f" ]] || continue
  name=$(basename "$f" -p3.png)
  cp "$f" "screenshots/3/$name-$SUFFIX.png"; echo "  rendered $name-$SUFFIX.png"
done
