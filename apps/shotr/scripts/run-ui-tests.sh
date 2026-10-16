#!/bin/bash
# Exercise native UI against a synthetic library; never accesses personal Photos.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo 'Usage: run-ui-tests.sh SIMULATOR_UDID NEW_OUTPUT_DIRECTORY' >&2
  exit 2
fi
shotr_root="$(cd "$(dirname "$0")/.." && pwd)"
shotr_output="$2"
python3 "$shotr_root/scripts/make-capture-project.py" --destination "$shotr_output"
cp "$shotr_root/scripts/ui-project.yml" "$shotr_output/project.yml"
xcodegen generate --spec "$shotr_output/project.yml" --project "$shotr_output"
xcodebuild -project "$shotr_output/Shotr.xcodeproj" -scheme Shotr \
  -destination "platform=iOS Simulator,id=$1" \
  -derivedDataPath "$shotr_output/DerivedData" \
  -resultBundlePath "$shotr_output/UITests.xcresult" \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
