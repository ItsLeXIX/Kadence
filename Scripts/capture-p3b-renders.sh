#!/bin/bash
#
# capture-p3b-renders.sh — runs slice 2 offscreen render tests with
# KADENCE_CAPTURE_DIR set and copies the PNGs they record as test
# attachments (`Slice2Render`) from the result bundle to screenshots/3b.
# Nothing is read from the sandboxed test host's container, no app is
# launched for input, and no UI is driven: the renders never leave the
# test process.
#
# Usage: SUFFIX=p3bf01 Scripts/capture-p3b-renders.sh Suite[/test] …
#   Only attachments named `<name>-$SUFFIX.png` / `.txt` are copied.
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:?set SUFFIX, e.g. p3bf01}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ONLY=()
for suite in "$@"; do ONLY+=("-only-testing:KadenceTests/$suite"); done
TEST_RUNNER_KADENCE_CAPTURE_DIR=1 xcodebuild -scheme Kadence -destination 'platform=macOS' \
  "${ONLY[@]}" -resultBundlePath "$WORK/run.xcresult" test >"$WORK/test.log" 2>&1
rc=$?
echo "tests rc=$rc"
grep -E '\*\* TEST' "$WORK/test.log"
mkdir -p "$WORK/out" screenshots/3b
xcrun xcresulttool export attachments --path "$WORK/run.xcresult" --output-path "$WORK/out" >/dev/null
python3 - "$WORK/out" "$SUFFIX" <<'EOF'
import json, os, re, shutil, sys
out, suffix = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(out, "manifest.json"))):
    for a in test["attachments"]:
        # Xcode appends `_<n>_<UUID>` to the name it was recorded under.
        name = re.sub(r"_\d+_[0-9A-F-]{36}(\.png|\.txt)$", r"\1", a["suggestedHumanReadableName"])
        if name.endswith(f"-{suffix}.png") or name.endswith(f"-{suffix}.txt"):
            shutil.copy(os.path.join(out, a["exportedFileName"]), os.path.join("screenshots/3b", name))
            print("  rendered", name)
EOF
exit $rc
