#!/usr/bin/env bash
# Captures an app's raw App Store screenshots (its screenshot_test in apps/<app>/app.yml, or the key
# named by SCREENSHOT_TEST_KEY, e.g. pr_screenshot_test) on a
# fresh iPhone 17 Pro Max simulator (6.9", 1320x2868) with a 9:41 status bar.
# Usage: scripts/capture-screenshots.sh <app> [output-dir] [appearance...]
# Writes <output-dir>/<appearance>/<screen>.png; defaults to build/screenshots/<app>/raw and light dark.
set -euo pipefail
cd "$(dirname "$0")/.."

app=${1:?usage: capture-screenshots.sh <app> [output-dir] [appearance...]}
project=$(ruby scripts/app-config.rb "$app" project_path)
scheme=$(ruby scripts/app-config.rb "$app" scheme)
test_id=$(ruby scripts/app-config.rb "$app" "${SCREENSHOT_TEST_KEY:-screenshot_test}")
name=$(ruby scripts/app-config.rb "$app" name)
out=${2:-build/screenshots/$app/raw}
shift $(( $# > 1 ? 2 : 1 ))
appearances=("$@")
[[ ${#appearances[@]} -gt 0 ]] || appearances=(light dark)
device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
derived=build/screenshots/$app/DerivedData

runtime=${R_SIM_RUNTIME:-$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"] if runtimes else "")
')}
[[ -n "$runtime" ]] || { echo "No iOS simulator runtime is installed" >&2; exit 1; }
echo "Using $runtime"

udid=$(xcrun simctl create "$name Screenshots" "$device_type" "$runtime")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' EXIT
scripts/boot-simulator.sh "$udid" 300

xcodebuild build-for-testing -project "$project" -scheme "$scheme" \
  -destination "id=$udid" -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -quiet

rm -rf "$out" "build/screenshots/$app"/*.xcresult
for appearance in "${appearances[@]}"; do
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl status_bar "$udid" override --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState discharging --batteryLevel 100
  mkdir -p "$out/$appearance"
  TEST_RUNNER_SCREENSHOT_DIR="$PWD/$out/$appearance" xcodebuild test-without-building \
    -project "$project" -scheme "$scheme" -destination "id=$udid" -derivedDataPath "$derived" \
    -only-testing:"$test_id" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 600 \
    -resultBundlePath "build/screenshots/$app/${SCREENSHOT_TEST_KEY:-screenshot_test}-$appearance.xcresult" -quiet
done

python3 - "$out" <<'PY'
import struct, sys, pathlib
for png in sorted(pathlib.Path(sys.argv[1]).rglob("*.png")):
    width, height = struct.unpack(">II", png.read_bytes()[16:24])
    print(f"{png}: {width}x{height}")
    if (width, height) != (1320, 2868):
        sys.exit(f"{png} is {width}x{height}, expected 1320x2868")
PY
