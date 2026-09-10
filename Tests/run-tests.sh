#!/bin/sh
# Exercises Cleaning Mode's input policy against the real shipping source.
#
# These are the rules that decide whether you can get out of Cleaning Mode, and
# they normally only run inside a CGEventTap — which needs Accessibility
# permission and a live session. CleaningTapBridge.decide() is split out so they
# can be checked directly, with no permission and nothing on screen.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
swiftc -O Vigil/Core/CleaningTapBridge.swift Tests/TapPolicy/main.swift -o "$OUT/taptests"
"$OUT/taptests"
