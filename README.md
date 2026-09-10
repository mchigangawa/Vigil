# Vigil

A macOS menu bar utility that does three things well:

- **Keep Awake** — stop the Mac sleeping, for a set time or until you say otherwise.
- **Cleaning Mode** — switch off the keyboard and trackpad so you can wipe the machine down.
- **Lock & Keep Awake** — lock the screen while a long build or download keeps running.

No Dock icon, no accounts, no telemetry. Settings live in your own user defaults. The only network request Vigil ever makes is an update check, and only if you ask for one.

**Requires** macOS 13 (Ventura) or later · Apple Silicon or Intel
**Built with** Swift, SwiftUI (`MenuBarExtra`) and AppKit

---

## Install

### From a release

Download the latest `Vigil-vX.Y.Z.zip` from [Releases](../../releases), unzip it, and move `Vigil.app` to `/Applications`.

Release builds are **unsigned and un-notarized**, so the first launch needs a nudge past Gatekeeper: right-click the app → **Open** → **Open**. Once only.

### From source

```sh
git clone https://github.com/mchigangawa/Vigil.git
cd Vigil
open Vigil.xcodeproj
```

Select the **Vigil** target → **Signing & Capabilities** → set **Team** to your own (a free personal team is fine — no paid Apple Developer account needed), then press ⌘R.

Setting a Team is worth doing even for local use. See [Accessibility and code signing](#accessibility-and-code-signing).

---

## Permissions

Vigil needs **Accessibility** permission for two of its three features:

> System Settings → Privacy & Security → Accessibility → enable **Vigil**

| Feature | Needs Accessibility | Why |
|---|---|---|
| Keep Awake | No | IOKit power assertions need no permission |
| Cleaning Mode | Yes | Installs a `CGEventTap` to intercept input |
| Lock & Keep Awake | Yes | Posts a synthetic ⌃⌘Q |

Vigil explains this on first launch, before macOS raises its own dialog, and degrades gracefully if the permission is revoked while a feature is running.

### Accessibility and code signing

If you grant Accessibility and Vigil still behaves as though you didn't, the cause is almost always **signing** rather than a bug.

macOS ties an Accessibility grant to the binary's *designated requirement*:

```sh
codesign -d -r- /path/to/Vigil.app
```

- **Ad-hoc signed** (no Team selected) prints `designated => cdhash H"…"`. That hash changes on *every build*, so a grant applies only to the exact binary that was running when you gave it. Rebuild and the app stays ticked in System Settings while the permission silently stops applying.
- **Signed with a team** prints `identifier "…" and anchor apple generic and certificate leaf[…]`, which is stable across rebuilds.

Selecting a Team is the durable fix. Vigil detects an ad-hoc build at runtime and says so in the permission notice rather than leaving you guessing.

To check a build:

```sh
./Tools/check-signing.sh    # reports STABLE or STILL AD-HOC
```

To clear a stale grant:

```sh
tccutil reset Accessibility zw.co.munyaradzichigangawa.Vigil
```

Then grant it once more. If Vigil is already listed, remove it with **−** and re-add — re-ticking a stale entry does not always refresh the requirement.

---

## Features

### Keep Awake

Holds an IOKit power assertion so the Mac will not idle-sleep. Durations: 15 minutes, 30 minutes, 1 hour, 4 hours, until turned off, or until Vigil quits. A live countdown shows in the menu.

*Keep display on* is a separate switch — turn it off to let the screen sleep while a background build or download keeps running.

The two open-ended options differ in one way: **Until turned off** is restored when Vigil relaunches, **Until Vigil quits** is not.

**No-limit durations require wall power.** An unbounded assertion on battery is how a laptop gets flattened in a bag, so on battery they are capped at 1 hour and the menu shows a "plug in for no time limit" hint. This is enforced in the coordinator rather than only in the UI, so every entry point obeys it — menu, shortcuts, Presentation Mode, Lock & Keep Awake, and session restore at launch.

- **Unplugging mid-session** converts a running no-limit session into a 1-hour one from that moment. It converts rather than stopping: unplugging to move desks shouldn't kill the session, but it must not stay unbounded either.
- **Your stored preference is untouched.** Pick "Until turned off" on power, unplug, and only the *session* is capped — the default takes effect again next time you are plugged in.
- **Desktop Macs** (no battery) always allow no-limit mode.

Separately, Keep Awake stands down below a battery threshold (10% by default) when not on AC, with a notification saying why.

### Cleaning Mode

Blocks keyboard and pointer input system-wide behind a full-screen overlay on every display and Space, so you can wipe the machine down. The display is held awake for the duration, independently of your own Keep Awake setting.

**Three independent ways out**, so you cannot be locked out:

1. **The auto-exit timer always fires** — 75 seconds by default, adjustable from 15 to 300. It depends on nothing else working, which is what makes it the guarantee.
2. **Click the on-screen exit button and hold the pointer still** for 2 seconds (adjustable). This is the one gesture the event tap lets through.
3. **Automatic teardown** if Accessibility is revoked mid-session or macOS disables the event tap — input is restored and you are told what happened.

Two deliberate details:

- **Pointer movement is never blocked.** Clicks, keystrokes, scrolling and drags are all swallowed, but a frozen cursor could not reach the exit button — precisely the lockout this feature must never create.
- **The exit gesture is "click, then hold still", not "press and hold".** With tap-to-click enabled — the default on Mac laptops — a tap is reported as a mouse-down and mouse-up about 60 ms apart, so cancelling a hold on release makes the gesture impossible for anyone who taps rather than physically depressing the trackpad. Only *leaving* the button cancels. A wiping hand drags the cursor away almost immediately, which is what keeps it hard to trigger by accident.

### Lock & Keep Awake

Engages a Keep Awake assertion, then locks the screen — for leaving a long job running on an unattended machine.

If a Keep Awake timer is already running it is left completely alone: not reset, not shortened, not extended. The menu row and the notification both state how long the Mac will stay awake, so the duration is never a surprise.

Locking posts a synthetic ⌃⌘Q. If the screen is still unlocked 0.6 s later, it falls back to the login window's own `CGSession -suspend` helper.

### Supporting features

| Feature | Notes |
|---|---|
| Menu bar icon states | A distinct glyph and colour per mode, so status reads at a glance |
| Global shortcuts | Configurable per action in Preferences → Shortcuts; each needs a modifier |
| Launch at login | `SMAppService`; macOS may ask you to approve it in Login Items |
| Notifications | On mode start, end, and auto-expiry. Toggleable |
| Presentation Mode | Keep Awake with the display forced on |
| Local usage log | Off by default. Per-day counts only, kept 30 days, never leaves the Mac |
| Software updates | Checks GitHub Releases and can install in place. Automatic checks off by default |

---

## Updates

Preferences → Updates checks GitHub Releases for a newer build and can install it in place: Vigil downloads the release zip, verifies the bundle identifier matches before overwriting anything, then hands off to a small detached script that waits for the app to quit, swaps the bundle, and relaunches.

- **Automatic checks are off by default.** This is Vigil's only network access. Enabled, it checks at launch and once a day.
- **Only GitHub hosts are accepted.** A download URL on any other host is refused rather than followed, so a tampered response cannot redirect the installer.
- **The bundle identifier is verified** before the swap, so a wrong or substituted asset cannot be installed over Vigil.

Two things to know:

- **Installing an update changes the code signature**, so macOS drops the Accessibility grant and you will have to allow Vigil again. Unavoidable for unsigned builds — see [Accessibility and code signing](#accessibility-and-code-signing).
- **Update checks only work against a public repository.** The API call is unauthenticated, and GitHub answers 404 for private repos, so the app would report no releases regardless of how many exist. Embedding a token is not an alternative — anyone could extract it from the app.
- **Updating a build running from Xcode's DerivedData** replaces a build product your next ⌘R overwrites anyway. Vigil detects this and says so.

---

## Limitations

- **Closing the lid still sleeps the Mac.** No power assertion can prevent clamshell sleep, so Lock & Keep Awake keeps the machine up only with the lid open.

- **Presentation Mode cannot toggle Do Not Disturb directly.** macOS exposes no public API for Focus modes. Make a Shortcut that sets a Focus and put its name in Preferences → General; leave it blank and Presentation Mode is simply Keep Awake with the display held on.

- **Pinch and magnify gestures are not blocked in Cleaning Mode.** Quartz reuses event type numbers 29 and 30 for `tapDisabledByTimeout` / `tapDisabledByUserInput` — the same values AppKit uses for gesture and magnify — so subscribing to them would make a genuine tap-disable indistinguishable from a pinch and break the recovery path that keeps the feature safe. Rotate, gesture begin/end, smart-magnify and pressure events *are* blocked, along with every click, keystroke, scroll and drag. A pinch alone activates nothing.

- **The App Sandbox is off**, because `CGEventTap` cannot intercept global input inside it. This is scoped to this target and affects nothing else on the machine.

- **Free personal-team provisioning profiles expire after 7 days.** An exported `.app` left in `/Applications` stops launching after a week; rebuilding from Xcode refreshes it.

- **Notification authorization can fail** for an app signed with a personal team. It is logged and ignored; everything else still works.

---

## Development

### Build

```sh
xcodebuild -project Vigil.xcodeproj -scheme Vigil -configuration Debug \
  -destination 'platform=macOS' build
```

### Tests

```sh
./Tests/run-tests.sh
```

48 assertions across two suites:

- **Cleaning Mode input policy** — what is blocked, that the cursor can still reach the exit, that the hold gesture works, that wiping across the button cannot trigger it, that tap-disable notices are never swallowed, plus multi-display and not-yet-laid-out cases.
- **Update handling** — tag normalisation, numeric version ordering (so `1.10.0` correctly beats `1.9.0`), and the download host allowlist.

The input-policy tests matter because they decide whether a user can get *out* of Cleaning Mode, and that logic normally only runs inside a live `CGEventTap` needing Accessibility permission. `CleaningTapBridge.decide()` is split out of the tap callback specifically so it can be tested directly.

There is also a full-stack check — real manager, real event tap, real overlay, synthetic click on the real hot zone:

```sh
./Tests/run-e2e.sh      # blocks input for ~3s; asks for confirmation first
```

It needs Accessibility permission for the **terminal**, not for Vigil.

### Manual test checklist

Some behaviour needs a human at the keyboard:

- [ ] Keep Awake prevents sleep for the chosen duration and releases cleanly afterwards
- [ ] *Keep display on* off → screen sleeps, Mac stays awake
- [ ] On battery, no-limit durations are disabled with the plug-in hint
- [ ] Unplugging during a no-limit session caps it at 1 hour and notifies
- [ ] Cleaning Mode blocks all input except the exit gesture
- [ ] Cleaning Mode exits on its own with no user action at all
- [ ] Revoking Accessibility mid-Cleaning-Mode restores input and warns
- [ ] Lock & Keep Awake locks without disturbing a running Keep Awake timer
- [ ] `pmset -g assertions | grep -i vigil` is empty after quitting
- [ ] No Dock icon, absent from ⌘-Tab
- [ ] Overlay covers every display and follows across Spaces

To exercise on-battery behaviour without unplugging (**Debug builds only** — the flag is inside `#if DEBUG`):

```sh
defaults write zw.co.munyaradzichigangawa.Vigil debugForceBatteryPower -bool true
defaults delete zw.co.munyaradzichigangawa.Vigil debugForceBatteryPower
```

Useful while testing:

```sh
log stream --predicate 'subsystem == "zw.co.munyaradzichigangawa.Vigil"' --style compact
pmset -g assertions | grep -i vigil
```

### Layout

```
Vigil/
├── VigilApp.swift                     MenuBarExtra shell, app delegate, icon state
├── Core/
│   ├── AppCoordinator.swift           Wires managers together; owns all actions
│   ├── KeepAwakeManager.swift         IOKit assertions, reference-counted by reason
│   ├── CleaningModeManager.swift      CGEventTap lifecycle and the three exits
│   ├── CleaningTapBridge.swift        Input policy, split out to be testable
│   ├── ScreenLocker.swift             Synthetic ⌃⌘Q with CGSession fallback
│   ├── AccessibilityPermission.swift  Grant watching and ad-hoc-build detection
│   ├── HotKeyManager.swift            Carbon RegisterEventHotKey
│   ├── BatteryMonitor.swift           IOKit power-source notifications, no polling
│   ├── ReleaseUpdateService.swift     GitHub Releases lookup and version compare
│   ├── UpdateManager.swift            Download, verify, in-place swap
│   ├── LaunchAtLogin.swift            SMAppService
│   ├── NotificationManager.swift
│   ├── UsageLog.swift
│   └── Preferences.swift
└── UI/
    ├── DesignSystem.swift             Tokens and shared components (Vg.*)
    ├── MenuContentView.swift          The menu bar panel
    ├── CleaningOverlayView.swift      Full-screen overlay content
    ├── CleaningOverlayController.swift  One NSPanel per display
    ├── PreferencesView.swift          Sidebar and detail settings
    ├── OnboardingView.swift
    ├── HotKeyRecorderView.swift
    └── AuxiliaryWindow.swift
```

### Design

All UI shares one token set in `Vigil/UI/DesignSystem.swift` — spacing, radii, type ramp, state palette — plus components (`VgCard`, `VgActionRow`, `VgChip`, `VgProgressBar`, `VgStatusPill`, `VgNotice`). Change a token there and every surface follows.

Each mode owns a colour, so the menu bar glyph alone says what Vigil is doing:

| State | Colour | Glyph |
|---|---|---|
| Idle | neutral grey | `eye` |
| Keep Awake | amber | `moon.zzz` |
| Cleaning Mode | cyan | `hand.raised` |
| Lock actions | indigo | `lock.display` |

Countdowns use monospaced digits so layouts don't jitter as they tick, and rows carry real hover states — `buttonStyle(.plain)` provides none on macOS, which makes a custom panel feel dead.

---

## Releasing

Two GitHub Actions workflows in `.github/workflows`:

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yaml` | push to `main`, any PR | Runs both test suites, builds Debug unsigned, uploads a zipped app artifact |
| `release.yaml` | push to `main`, or manual | Reads `MARKETING_VERSION`; if no matching tag exists, runs tests, builds Release, tags `vX.Y.Z`, and publishes a GitHub Release with the zipped app |

A release is therefore just: bump `MARKETING_VERSION`, merge to `main`. If the tag already exists the workflow exits early, so ordinary pushes cost one cheap version check.

**No repository secrets are required.** Tagging and releasing deliberately live in one workflow: split across two, the tag would need a personal access token, because a tag pushed with the default `GITHUB_TOKEN` does not trigger other workflows. Keeping them together means the built-in token suffices and no long-lived credential is stored in the repo.

The tag is created *after* the build succeeds, so a failed build never leaves a tag behind that blocks the next attempt.

---

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

Anything touching Cleaning Mode deserves extra care — it can take a user's keyboard and trackpad away, so every change must preserve all three independent exits.

## License

[MIT](LICENSE).
