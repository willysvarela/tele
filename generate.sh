#!/usr/bin/env bash
# Regenerate Tele.xcodeproj from project.yml (brew install xcodegen), then open it in Xcode.
# Signing: put DEVELOPMENT_TEAM in Local.xcconfig (see Local.xcconfig.example).
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f Local.xcconfig ]]; then
  printf '// Set your Apple team ID here (see Local.xcconfig.example).\n// DEVELOPMENT_TEAM = ABCDE12345\n' > Local.xcconfig
  echo "Created Local.xcconfig without a team; pick one in Xcode or edit the file."
fi
xcodegen generate
[[ "${1:-}" == "open" ]] && open Tele.xcodeproj
