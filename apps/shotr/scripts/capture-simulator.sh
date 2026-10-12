#!/bin/bash
# Capture the running native UI from an already-installed sample-library build.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo 'Usage: capture-simulator.sh SIMULATOR_UDID OUTPUT_DIRECTORY' >&2
  exit 2
fi
shots_device="$1"
shots_output="$2"
mkdir -p "$shots_output"
xcrun simctl status_bar "$shots_device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
for shots_screen in light dark search tags gallery; do
  shots_appearance=light
  if [ "$shots_screen" = dark ]; then shots_appearance=dark; fi
  xcrun simctl ui "$shots_device" appearance "$shots_appearance"
  case "$shots_screen" in
    search|tags|gallery) xcrun simctl launch --terminate-running-process "$shots_device" com.calum.shots "--capture-$shots_screen" ;;
    *) xcrun simctl launch --terminate-running-process "$shots_device" com.calum.shots ;;
  esac
  # Allow SwiftUI presentation and thumbnail tasks to settle before capturing.
  sleep 3
  xcrun simctl io "$shots_device" screenshot "$shots_output/$shots_screen.png"
done
