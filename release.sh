#!/usr/bin/env bash
# Archive Tele and send it to App Store Connect.
#   ./release.sh archive     build/Tele.xcarchive (Release, signed with DEVELOPMENT_TEAM from Local.xcconfig)
#   ./release.sh upload      export the archive for App Store Connect and upload it
#   ./release.sh validate    export and validate only
# Signing uses the Apple ID signed in to Xcode (Settings > Accounts), which must belong to a paid
# Apple Developer Program team. For CI, set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (an App Store
# Connect API key .p8) and the upload runs without Xcode's account.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Local.xcconfig 2>/dev/null | head -1)"
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in Local.xcconfig first." >&2; exit 1; }
ARCHIVE=build/Tele.xcarchive
EXPORT=build/export

auth=""
tool_auth=""
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  auth="-authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID -authenticationKeyPath $ASC_KEY_PATH"
  tool_auth="--apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID"
fi

export_options() {
  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
PLIST
}

case "${1:-archive}" in
  archive)
    [[ -d Tele.xcodeproj ]] || ./generate.sh
    rm -rf "$ARCHIVE"
    xcodebuild archive -project Tele.xcodeproj -scheme Tele -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates $auth \
      | grep -E "error|warning: .*sign|ARCHIVE (SUCCEEDED|FAILED)" || true
    [[ -d "$ARCHIVE" ]] && echo "Archive at $ARCHIVE"
    ;;
  upload|validate)
    [[ -d "$ARCHIVE" ]] || { echo "No archive. Run: ./release.sh archive" >&2; exit 1; }
    mkdir -p build
    if [[ "$1" == upload ]]; then export_options upload; else export_options export; fi
    rm -rf "$EXPORT"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
      -exportPath "$EXPORT" -allowProvisioningUpdates $auth
    [[ "$1" == validate ]] && xcrun altool --validate-app -f "$EXPORT"/*.ipa -t ios $tool_auth
    ;;
  *) echo "usage: ./release.sh archive|upload|validate" >&2; exit 1 ;;
esac
