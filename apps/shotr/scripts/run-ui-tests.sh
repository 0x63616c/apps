#!/bin/bash
# Exercise native UI against a synthetic library; never accesses personal Photos.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo 'Usage: run-ui-tests.sh SIMULATOR_UDID NEW_OUTPUT_DIRECTORY' >&2
  exit 2
fi
shots_root="$(cd "$(dirname "$0")/.." && pwd)"
shots_output="$2"
python3 "$shots_root/scripts/make-capture-project.py" --destination "$shots_output"
cp "$shots_root/scripts/ui-project.yml" "$shots_output/project.yml"
xcodegen generate --spec "$shots_output/project.yml" --project "$shots_output"
xcodebuild -project "$shots_output/Shots.xcodeproj" -scheme Shots \
  -destination "platform=iOS Simulator,id=$1" \
  -derivedDataPath "$shots_output/DerivedData" \
  -resultBundlePath "$shots_output/UITests.xcresult" \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
