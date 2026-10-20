#!/usr/bin/env bash
# Regenerate Tele.xcodeproj from project.yml (brew install xcodegen), then open it in Xcode.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
[[ "${1:-}" == "open" ]] && open Tele.xcodeproj
