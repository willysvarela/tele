#!/usr/bin/env bash
# App Store screenshots from the simulator, in demo mode (no TV needed).
#   tools/screenshots.sh [simulator name]      default: iPhone 18 Pro Max (6.9-inch class)
# Output: build/screenshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
NAME="${1:-iPhone 18 Pro Max}"
SIM="$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[[ -n "$SIM" ]] || { echo "No simulator named $NAME" >&2; exit 1; }
OUT=build/screenshots; mkdir -p "$OUT"
xcodebuild -project Tele.xcodeproj -scheme Tele -destination "id=$SIM" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Tele.app
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
SIMCTL_CHILD_TELE_DEMO=1 xcrun simctl launch "$SIM" com.willysvarela.teleremote >/dev/null; sleep 6   # warm up a cold simulator
shot() {   # shot <file> <TELE_DEMO value>
  xcrun simctl terminate "$SIM" com.willysvarela.teleremote 2>/dev/null || true
  SIMCTL_CHILD_TELE_DEMO="$2" xcrun simctl launch "$SIM" com.willysvarela.teleremote >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$1.png" >/dev/null
  echo "$OUT/$1.png"
}
shot 1-remote 1
shot 2-devices devices
xcrun simctl status_bar "$SIM" clear
