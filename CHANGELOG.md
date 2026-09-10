# Changelog

All notable changes to Vigil are documented here.
Versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0]

### Added
- **Keep Awake** — IOKit power assertions with 15m / 30m / 1h / 4h / until-off /
  until-quit durations, a live countdown, and a separate "keep the display on"
  switch. No-limit durations require wall power.
- **Cleaning Mode** — a session-level `CGEventTap` blocks keyboard and pointer
  input behind a full-screen overlay on every display, with three independent
  exits: an auto-exit timer, a click-and-hold-still gesture, and automatic
  teardown if permission is revoked or the tap dies.
- **Lock & Keep Awake** — locks the screen while holding the machine awake,
  leaving an already-running Keep Awake timer untouched.
- Global shortcuts, launch at login, battery guard, notifications, an opt-in
  local usage log, preferences, and first-run onboarding.
- **Software updates** — checks GitHub Releases and can install in place.
  Automatic checks are off by default; this is Vigil's only network access.
- Tests for Cleaning Mode's input policy plus a full-stack tap harness.

### Notes
- App Sandbox is off by design: `CGEventTap` cannot intercept global input
  inside it.
- Closing the lid still sleeps the Mac. No power assertion can prevent that.
