#!/bin/bash
#
# capture-p3c-renders.sh — runs slice 3 offscreen render tests with
# KADENCE_CAPTURE_DIR set and copies the PNGs they record as test
# attachments (`Slice3Render`) from the result bundle to screenshots/3c.
# Nothing is read from the sandboxed test host's container, no app is
# launched for input, and no UI is driven: the renders never leave the
# test process.
#
# Usage: SUFFIX=p3ct10 Scripts/capture-p3c-renders.sh Suite[/test] …
#   RENDER_SUFFIX=p3ct15 SUFFIX=p3ct15 … renders every frame under one suffix.
#   Only attachments named `<name>-$SUFFIX.png` / `.txt` are copied.
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:?set SUFFIX, e.g. p3ct10}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ONLY=()
for suite in "$@"; do ONLY+=("-only-testing:KadenceTests/$suite"); done
TEST_RUNNER_KADENCE_CAPTURE_DIR=1 TEST_RUNNER_KADENCE_RENDER_SUFFIX="${RENDER_SUFFIX:-}" xcodebuild -scheme Kadence -destination 'platform=macOS' \
  "${ONLY[@]}" -resultBundlePath "$WORK/run.xcresult" test >"$WORK/test.log" 2>&1
rc=$?
echo "tests rc=$rc"
grep -E '\*\* TEST' "$WORK/test.log"
mkdir -p "$WORK/out" screenshots/3c
xcrun xcresulttool export attachments --path "$WORK/run.xcresult" --output-path "$WORK/out" >/dev/null
python3 - "$WORK/out" "$SUFFIX" <<'EOF'
import json, os, re, shutil, sys
out, suffix = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(out, "manifest.json"))):
    for a in test["attachments"]:
        # Xcode appends `_<n>_<UUID>` to the name it was recorded under.
        name = re.sub(r"_\d+_[0-9A-F-]{36}(\.png|\.txt)$", r"\1", a["suggestedHumanReadableName"])
        # Item 20's plan dump keeps its spec name.
        if name.endswith(f"-{suffix}.png") or name.endswith(f"-{suffix}.txt") or name == "notification-plan-moodle.txt":
            shutil.copy(os.path.join(out, a["exportedFileName"]), os.path.join("screenshots/3c", name))
            print("  rendered", name)
EOF
exit $rc
