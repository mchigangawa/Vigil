#!/bin/sh
# Full-stack Cleaning Mode check: real manager, real CGEventTap, real overlay.
# Posts a synthetic tap-to-click on the real exit hot zone and reports whether
# the hold registers and exits.
#
# Requires Accessibility permission for the TERMINAL running it (not for Vigil).
# BLOCKS ALL INPUT for ~3 seconds. A hard teardown runs regardless, and Cleaning
# Mode's own auto-exit timer is the backstop if even that fails.
set -e
cd "$(dirname "$0")/.."
printf 'This blocks keyboard and trackpad for ~3s. Continue? [y/N] '
read -r reply
case "$reply" in [yY]*) ;; *) echo "aborted"; exit 0 ;; esac
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
swiftc -D DEBUG -o "$OUT/e2e" \
  Vigil/Core/CleaningTapBridge.swift Vigil/Core/Preferences.swift Vigil/Core/HotKeyManager.swift \
  Vigil/Core/KeepAwakeManager.swift Vigil/Core/AccessibilityPermission.swift \
  Vigil/Core/CleaningModeManager.swift Vigil/UI/DesignSystem.swift \
  Vigil/UI/CleaningOverlayController.swift Vigil/UI/CleaningOverlayView.swift \
  Tests/EndToEnd/main.swift
"$OUT/e2e"
