#!/bin/bash
# Capture the running native UI from an already-installed sample-library build.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo 'Usage: capture-simulator.sh SIMULATOR_UDID OUTPUT_DIRECTORY' >&2
  exit 2
fi
shotr_device="$1"
shotr_output="$2"
mkdir -p "$shotr_output"
xcrun simctl status_bar "$shotr_device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
for shotr_screen in light dark search tags gallery; do
  shotr_appearance=light
  if [ "$shotr_screen" = dark ]; then shotr_appearance=dark; fi
  xcrun simctl ui "$shotr_device" appearance "$shotr_appearance"
  case "$shotr_screen" in
    search|tags|gallery) xcrun simctl launch --terminate-running-process "$shotr_device" com.calum.shots "--capture-$shotr_screen" ;;
    *) xcrun simctl launch --terminate-running-process "$shotr_device" com.calum.shots ;;
  esac
  # Allow SwiftUI presentation and thumbnail tasks to settle before capturing.
  sleep 3
  xcrun simctl io "$shotr_device" screenshot "$shotr_output/$shotr_screen.png"
done
