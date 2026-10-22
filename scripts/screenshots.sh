#!/bin/bash
# Simulator screenshots of the -demo library (synthetic beats, real detection). Usage: scripts/screenshots.sh [outdir]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots}"
SIM="${SIM:-iPhone 17}"
BID=com.awkbeats.prepstation
UDID=$(xcrun simctl list devices available | grep -m1 "    $SIM (" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcodebuild build -project PrepStation.xcodeproj -scheme PrepStation -destination "id=$UDID" -derivedDataPath build/DD -quiet COMPILER_INDEX_STORE_ENABLE=NO
xcrun simctl install "$UDID" build/DD/Build/Products/Debug-iphonesimulator/PrepStation.app
mkdir -p "$OUT"
run() { xcrun simctl terminate "$UDID" $BID 2>/dev/null || true; xcrun simctl launch "$UDID" $BID "$@" >/dev/null; }
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null; }
run -demo; sleep 9; shot prepstation-1-library
run -demo -demoDetail; sleep 9; shot prepstation-2-beat
run -demo -demoBottom; sleep 9; shot prepstation-3-beat-save
run -demo -demoFilter; sleep 9; shot prepstation-4-filter-ready
run -demo -demoEmpty; sleep 4; shot prepstation-5-empty
run -demo -demoSettings; sleep 6; shot prepstation-6-settings
xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
ls -la "$OUT"
