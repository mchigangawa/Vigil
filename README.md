# Vigil

A macOS menu bar utility with three toggles: **Keep Awake**, **Cleaning Mode**, and **Lock & Keep Awake**.

No Dock icon, no accounts, no telemetry. Everything it stores stays in your own user preferences on this Mac. The one thing that touches the network is the update check, and only when you ask for it — see [Updates](#updates).

- **Bundle identifier:** `zw.co.munyaradzichigangawa.Vigil`
- **Requires:** macOS 13 (Ventura) or later, Apple Silicon or Intel
- **Built with:** Swift 5, SwiftUI (`MenuBarExtra`) + AppKit

---

## Getting it running

### 1. Add your Apple ID to Xcode

There is currently **no code signing identity on this machine**, so the app will not run until you add one:

1. Xcode → Settings → Accounts → **+** → Apple ID, and sign in.
2. Open `Vigil.xcodeproj`, select the **Vigil** target → **Signing & Capabilities**.
3. Leave *Automatically manage signing* checked, and pick your name under **Team** (it appears as "Your Name (Personal Team)").

A free personal team is enough. No paid Apple Developer account is needed.

### 2. Build and run

Press ⌘R in Xcode. The eye glyph appears in the menu bar; there is no Dock icon and no window.

### 3. Grant Accessibility permission

On first launch Vigil explains what it needs before macOS asks. **Cleaning Mode** and **Lock & Keep Awake** need Accessibility permission:

> System Settings → Privacy & Security → Accessibility → enable **Vigil**

Keep Awake works without it.

### Troubleshooting: "I allowed Accessibility but Vigil says I didn't"

This is the most confusing failure in the project, and it is caused by **signing**, not by the app.

macOS pins an Accessibility grant to the binary's *designated requirement*. Check yours:

```sh
codesign -d -r- /path/to/Vigil.app
```

- **Ad-hoc signed** (no Team selected) prints `designated => cdhash H"..."`. That
  hash changes on **every single build**, so the grant you gave applies only to
  the exact binary that was running when you gave it. Rebuild, and Vigil stays
  ticked in System Settings while the permission silently no longer applies —
  which looks precisely like macOS ignoring you.
- **Signed with a team** prints `identifier "zw.co.munyaradzichigangawa.Vigil"
  and anchor apple generic and certificate leaf[...]`. That is stable across
  rebuilds, so the grant sticks.

**The durable fix is to select a Team** in Signing & Capabilities (step 1 above).
A free personal team is enough. Vigil detects an ad-hoc build at runtime and
says so in the permission notice, so you are not left guessing.

**To check whether your build is affected:**

```sh
./Tools/check-signing.sh
```

It reports STABLE or STILL AD-HOC and tells you what to do next.

**To clear a stale grant:**

```sh
tccutil reset Accessibility zw.co.munyaradzichigangawa.Vigil
```

Then relaunch and grant once more. If Vigil is already in the list, remove it
with **−** and re-add it — re-ticking an existing stale entry does not always
refresh the requirement.

---

## What each feature does

### Keep Awake

Holds an IOKit power assertion so the Mac will not idle-sleep. Durations: 15 min, 30 min, 1 hour, 4 hours, until turned off, or until Vigil quits. A live countdown shows in the menu.

"Keep display on" is a separate switch — turn it off to let the screen sleep while a background build or download keeps running.

The two indefinite options differ in one way: **Until turned off** is restored if you relaunch Vigil; **Until Vigil quits** is not.

#### No-limit mode requires wall power

The two indefinite options only apply while the Mac is **plugged in** — an
unbounded assertion on battery is how a laptop gets flattened in a bag. On
battery they are capped at **1 hour**, and the chips are disabled in the menu
with a "Plug in for no time limit" hint.

This is enforced in `AppCoordinator`, not just in the UI, so every entry point
obeys it: the menu, global shortcuts, Presentation Mode, Lock & Keep Awake, and
session restore on launch.

- **Unplugging mid-session** converts a running no-limit session into a 1-hour
  one from that moment, with a notification. It converts rather than stopping,
  because unplugging to walk to another desk shouldn't kill your session — but
  it must not stay unbounded.
- **Your stored preference is left alone.** If you picked "Until turned off"
  while plugged in, that stays your default and takes effect again next time you
  are on power; only the running session is capped.
- **Desktop Macs** (no battery) are always allowed no-limit mode.

Separately, Keep Awake also turns itself off below a battery threshold
(default 10%) when not on AC power, with a notification saying why.

### Cleaning Mode

Blocks the keyboard and trackpad system-wide so you can wipe the machine down, behind a full-screen overlay on every display and Space. The display is held awake for the duration, independently of your own Keep Awake setting.

**Three independent ways out**, so you can never be locked out:

1. **The auto-exit timer always fires** — 75 seconds by default, adjustable from 15 to 300 seconds. This is the guarantee; it does not depend on anything else working.
2. **Press and hold the on-screen exit button** for 2 seconds (adjustable). This is the one gesture the event tap lets through. Sliding off the button cancels the hold, so a wiping hand cannot trigger it by accident.
3. **Automatic teardown** if Accessibility permission is revoked mid-session, or if macOS disables the event tap — input is restored and you get a notification saying what happened.

Pointer *movement* is deliberately left unblocked. Clicks, keystrokes, scrolling and drags are all swallowed, but if the cursor were frozen you could not reach the exit button — which is precisely the lockout this feature must never create.

### Lock & Keep Awake

Engages a Keep Awake assertion, then locks the screen — for leaving a long build running on an unattended machine.

If a Keep Awake timer is already running, it is left completely alone: not reset, not shortened, not extended.

Locking posts a synthetic ⌃⌘Q. If the screen is still unlocked 0.6s later, it falls back to the login window's own `CGSession -suspend` helper.

### Supporting features

| Feature | Notes |
|---|---|
| Menu bar icon states | Distinct glyph for idle / Keep Awake / Cleaning Mode, tinted when active |
| Global shortcuts | Configurable per action, in Preferences → Shortcuts. Each needs a modifier key |
| Launch at login | `SMAppService` (macOS 13+). macOS may ask you to approve it in Login Items |
| Notifications | On mode start, end, and auto-expiry. Toggleable |
| Presentation Mode | Keep Awake with the display forced on — see the caveat below |
| Local usage log | Off by default. Per-day counts only, kept 30 days, never leaves the Mac |
| Software updates | Checks GitHub Releases and installs in place. Automatic checks off by default |

---

## Updates

Preferences › Updates checks GitHub Releases for a newer build and can install
it in place: Vigil downloads the release zip, verifies the bundle identifier
matches before overwriting anything, then hands off to a small detached script
that waits for the app to quit, swaps the bundle, and relaunches.

- **Automatic checks are off by default.** This is the only network access Vigil
  has. Turned on, it checks at launch and once a day.
- **Only GitHub hosts are accepted.** A download URL on any other host is
  refused rather than followed, so a tampered response cannot redirect the
  installer.
- **The bundle identifier is verified** before the swap, so a wrong or
  substituted asset cannot be installed over Vigil.

Two things to know:

- **Installing an update changes the code signature**, which means macOS will
  drop the Accessibility grant and you will have to allow Vigil again. That is
  unavoidable for an unsigned build — see the signing section above.
- **Updating from a build running out of Xcode's DerivedData** replaces a build
  product your next ⌘R overwrites anyway. Vigil detects this and says so.
  Export to `/Applications` for in-place updates to be useful.

## Releasing

Three GitHub Actions workflows in `.github/workflows`:

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yaml` | push to `main`, any PR | Runs the test suites, builds Debug unsigned, uploads a zipped app artifact |
| `auto-tag.yaml` | push to `main` | Reads `MARKETING_VERSION` from the project and pushes a matching `vX.Y.Z` tag if it doesn't exist |
| `release.yaml` | a `vX.Y.Z` tag | Runs tests, builds Release, zips the app, creates a GitHub Release with the zip attached |

So a release is: bump `MARKETING_VERSION`, merge to `main`, and the tag, build,
and release happen on their own — and the in-app updater picks it up.

**One-time setup:** `auto-tag.yaml` needs a `RELEASE_TOKEN` repository secret
(a PAT with `repo` scope). Tags pushed with the default `GITHUB_TOKEN` do not
trigger other workflows, so without it the tag lands but `release.yaml` never
fires.

**Released builds are unsigned and un-notarized.** They are fine for your own
machine; anyone else downloading one will have to right-click › Open past
Gatekeeper.

## Honest limitations

- **Presentation Mode cannot toggle Do Not Disturb directly.** macOS has no public API for Focus modes. Instead, make a Shortcut in the Shortcuts app that sets a Focus, and put its name in Preferences → General. Leave it blank and Presentation Mode is simply Keep Awake with the display held on.

- **Pinch and magnify gestures are not blocked in Cleaning Mode.** Quartz reuses event type numbers 29 and 30 for `tapDisabledByTimeout` / `tapDisabledByUserInput`, the same values AppKit uses for gesture and magnify. Subscribing to them would make a real tap-disable indistinguishable from a pinch, which would break the recovery path that keeps the feature safe. Rotate, gesture begin/end, smart-magnify and pressure events *are* blocked, along with every click, keystroke, scroll and drag — and a pinch on its own cannot activate anything.

- **Free provisioning profiles expire after 7 days.** An exported `.app` sitting in `/Applications` will stop launching after a week. Running it from Xcode refreshes it, so ⌘R every so often avoids the issue entirely. This is a limitation of free personal-team signing, not of the app.

- **Not notarized and not sandboxed.** The App Sandbox is off for this target because `CGEventTap` cannot intercept global input inside it. This is scoped to this app only and affects nothing else on the machine. It is also why this build is for your own machine rather than distribution.

- **Closing the lid still sleeps the Mac.** No power assertion can prevent
  clamshell sleep, so Lock & Keep Awake keeps the machine up only with the lid
  open.

- **Notification authorization can fail** for an app signed with a personal team. It is logged and ignored; every other feature still works.

---

## Test checklist

Automated verification already done: the project builds clean with no warnings, launches without crashing, reports `LSUIElement` true, ships with `com.apple.security.app-sandbox = false`, leaves no power assertions behind after quitting (`pmset -g assertions`), and restores an indefinite session as indefinite on AC but capped on battery.

To exercise on-battery behaviour without unplugging, **Debug builds only**:

```sh
defaults write zw.co.munyaradzichigangawa.Vigil debugForceBatteryPower -bool true
# ...and to undo
defaults delete zw.co.munyaradzichigangawa.Vigil debugForceBatteryPower
```

This flag is inside `#if DEBUG` and is never compiled into a Release build.

The rest needs a human at the keyboard:

- [ ] Keep Awake prevents sleep for the chosen duration and releases cleanly afterward
- [ ] "Keep display on" off → screen sleeps, Mac stays awake
- [ ] On battery, the no-limit duration chips are disabled with the plug-in hint
- [ ] Unplugging during a no-limit session caps it at 1 hour and notifies
- [ ] Cleaning Mode blocks all keyboard and trackpad input except the hold-to-exit gesture
- [ ] Cleaning Mode exits on its own with no user action at all
- [ ] Revoking Accessibility permission mid-Cleaning-Mode restores input and warns
- [ ] Lock & Keep Awake locks the screen without disturbing a running Keep Awake timer
- [ ] `pmset -g assertions | grep -i vigil` is empty after quitting
- [ ] No Dock icon, absent from ⌘-Tab
- [ ] Overlay covers every display and follows you across Spaces
- [ ] Works on both Apple Silicon and Intel

### Automated tests

```sh
./Tests/run-tests.sh
```

25 assertions covering Cleaning Mode's input policy — what gets blocked, that
the cursor can still reach the exit, that the hold gesture works, that wiping
across the button cannot trigger it, that tap-disable notices are never
swallowed, and the multi-display and not-yet-laid-out cases.

These matter because they are the rules that decide whether you can get *out* of
Cleaning Mode, and they normally only execute inside a live `CGEventTap` that
needs Accessibility permission. `CleaningTapBridge.decide()` is split out from
the tap callback specifically so they can be checked directly.

There is also a full-stack check — real manager, real event tap, real overlay,
synthetic tap on the real hot zone:

```sh
./Tests/run-e2e.sh      # blocks input for ~3s; asks first
```

It needs Accessibility permission for the **terminal**, not for Vigil.

#### A note on the exit gesture

It is "click here, then hold still", not "press and hold". With **tap to click**
enabled — the default on Mac laptops — a tap is reported as a mouse-down and a
mouse-up about 60ms apart. Cancelling the hold on release therefore made the
gesture impossible for anyone who taps instead of physically depressing the
trackpad. Only *leaving* the button cancels now: the gesture needs a click
inside the button and the pointer to stay there for the full duration. A wiping
hand drags the cursor away almost at once, which is what keeps it hard to
trigger by accident.

Useful while testing:

```sh
# Watch Vigil's own logs
log stream --predicate 'subsystem == "zw.co.munyaradzichigangawa.Vigil"' --style compact

# Confirm assertions appear and disappear
pmset -g assertions | grep -i vigil
```

---

## Layout

```
Vigil/
├── VigilApp.swift              MenuBarExtra shell, app delegate, icon state
├── Core/
│   ├── AppCoordinator.swift    Wires managers together; owns all actions
│   ├── KeepAwakeManager.swift  IOKit assertions, reference-counted by reason
│   ├── CleaningModeManager.swift  CGEventTap lifecycle and the three exits
│   ├── CleaningTapBridge.swift    Plain state shared with the C tap callback
│   ├── ScreenLocker.swift      Synthetic ⌃⌘Q with CGSession fallback
│   ├── AccessibilityPermission.swift
│   ├── HotKeyManager.swift     Carbon RegisterEventHotKey
│   ├── BatteryMonitor.swift    IOKit power-source notifications (no polling)
│   ├── LaunchAtLogin.swift     SMAppService
│   ├── NotificationManager.swift
│   ├── UsageLog.swift
│   └── Preferences.swift
└── UI/
    ├── DesignSystem.swift          Tokens + shared components (Vg.*)
    ├── MenuContentView.swift       The menu bar panel
    ├── CleaningOverlayView.swift   Full-screen overlay content
    ├── CleaningOverlayController.swift  One NSPanel per display
    ├── PreferencesView.swift       Sidebar + detail settings
    ├── OnboardingView.swift
    ├── HotKeyRecorderView.swift
    └── AuxiliaryWindow.swift
```

---

## Design

All UI shares one token set in `Vigil/UI/DesignSystem.swift` — spacing, radii, type
ramp, and a state palette — plus a handful of components (`VgCard`, `VgActionRow`,
`VgChip`, `VgProgressBar`, `VgStatusPill`, `VgNotice`). Change a token there and
every surface follows.

**Each mode owns a colour**, so the menu bar glyph alone tells you what Vigil is
doing without opening anything:

| State | Colour | Glyph |
|---|---|---|
| Idle | neutral grey | `eye` |
| Keep Awake | amber | `moon.zzz` |
| Cleaning Mode | cyan | `hand.raised` |
| Lock actions | indigo | `lock.display` |

Countdowns use monospaced digits so the layout never jitters as they tick, and
rows carry real hover states — `buttonStyle(.plain)` gives none on macOS, which
makes a custom panel feel dead.
