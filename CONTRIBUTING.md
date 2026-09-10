# Contributing to Vigil

Thanks for taking an interest. Vigil is small and deliberately stays that way,
so the most useful contributions are usually focused fixes rather than large
new subsystems.

## Getting set up

```sh
git clone https://github.com/mchigangawa/Vigil.git
cd Vigil
open Vigil.xcodeproj
```

Set a **Team** under Signing & Capabilities (a free personal team works). Do
this even for local work: an ad-hoc build's Accessibility grant breaks on every
rebuild, which makes Cleaning Mode maddening to develop against. `README.md`
explains why in detail.

Run the tests before and after your change:

```sh
./Tests/run-tests.sh
```

## The one rule that matters

**Cleaning Mode can take away a user's keyboard and trackpad.** Any change that
touches the event tap, the overlay, or the exit gesture must preserve all three
independent exits:

1. The auto-exit timer fires regardless of anything else working.
2. The exit gesture is reachable — which is why pointer movement is never
   blocked, and why the exit hot zone is derived from the button's real
   laid-out frame rather than a hardcoded rectangle.
3. Teardown happens automatically if Accessibility is revoked or the tap dies.

If your change makes any of those depend on another one, it is not safe.

Input policy lives in `CleaningTapBridge.decide()`, split out of the tap
callback precisely so it can be tested without Accessibility permission or a
live tap. Add cases there rather than in the callback.

## Testing expectations

- New behaviour in the tap policy or update handling needs assertions in
  `Tests/`. Both suites are plain Swift files with no test framework.
- If you change the exit gesture, run the full-stack check too:
  `./Tests/run-e2e.sh` (it blocks input for a few seconds and asks first).
- Anything touching power assertions: confirm `pmset -g assertions | grep -i
  vigil` is empty after quitting. A leaked assertion keeps a stranger's Mac
  awake indefinitely.

The PR template lists the rest.

## Style

Match the surrounding code. A few conventions worth knowing:

- Comments explain *why*, not what. Several non-obvious decisions in this
  codebase exist for concrete reasons — the tap-to-click handling, the event
  mask's excluded types, the reference-counted power assertions — and those
  reasons are written down next to the code.
- UI goes through the tokens and components in `Vigil/UI/DesignSystem.swift`
  rather than hardcoded values.
- Managers are `@MainActor` and own one responsibility;
  `AppCoordinator` wires them together and owns user-facing actions.

## Reporting bugs

Include your macOS version, whether the Mac is Apple Silicon or Intel, and how
many displays are attached — several past issues only appeared in multi-display
setups. For permission problems, include the output of:

```sh
./Tools/check-signing.sh
```

That distinguishes a genuine bug from a stale Accessibility grant, which is by
far the most common false alarm.
