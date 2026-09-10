import AppKit
import SwiftUI
import Combine
import os

/// What the menu bar glyph is currently saying.
enum VigilStatus: Equatable {
    case idle
    case keepAwake
    case cleaning

    func symbolName(style: MenuBarIconStyle) -> String {
        switch self {
        case .idle:
            return style == .filled ? "eye.fill" : "eye"
        case .keepAwake:
            return style == .filled ? "moon.zzz.fill" : "moon.zzz"
        case .cleaning:
            return style == .filled ? "hand.raised.fill" : "hand.raised"
        }
    }

    /// Each state owns a hue, shared by the menu bar glyph, the panel header
    /// and the overlay, so the colour alone says what Vigil is doing.
    var tint: Color {
        switch self {
        case .idle: return Vg.Tint.neutral
        case .keepAwake: return Vg.Tint.awake
        case .cleaning: return Vg.Tint.cleaning
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .keepAwake: return "Awake"
        case .cleaning: return "Cleaning"
        }
    }

    var isAccented: Bool { self != .idle }
}

/// Wires the managers together and owns everything the menu and preferences
/// windows talk to.
@MainActor
final class AppCoordinator: ObservableObject {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "Coordinator")

    let preferences = Preferences.shared
    let keepAwake = KeepAwakeManager()
    let permission = AccessibilityPermission()
    let battery = BatteryMonitor()
    let usageLog = UsageLog()
    let cleaning: CleaningModeManager

    /// Transient message surfaced at the top of the menu.
    @Published var banner: String?
    /// Ticks once a second so the menu's countdown stays live while open.
    @Published private(set) var clock = Date()

    /// Set by the app delegate, which owns the auxiliary windows.
    var openPreferences: (() -> Void)?
    var closeOnboarding: (() -> Void)?

    private var clockTimer: Timer?
    private var tickCount: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        cleaning = CleaningModeManager(keepAwake: keepAwake, permission: permission)
        wireUp()
    }

    var status: VigilStatus {
        if cleaning.isActive { return .cleaning }
        if keepAwake.isUserSessionActive { return .keepAwake }
        return .idle
    }

    // MARK: - Wiring

    private func wireUp() {
        // Republish child changes so the menu redraws.
        for child: any ObservableObject in [keepAwake, cleaning, permission, battery, usageLog] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        keepAwake.onTimerExpired = { [weak self] in
            self?.notify("Keep Awake finished", "The timer ran out. Your Mac can sleep again.")
        }

        cleaning.onDeactivated = { [weak self] cause in
            self?.handleCleaningEnded(cause)
        }

        cleaning.onActivationFailed = { [weak self] message in
            guard let self else { return }
            self.show(banner: message)
            // Only send the user to System Settings when that is actually where
            // the problem is; a tap that failed for another reason has nothing
            // for them to change there.
            if !self.permission.isTrusted {
                self.permission.openSystemSettings()
            }
        }

        permission.onRevoked = { [weak self] in
            guard let self else { return }
            if self.cleaning.isActive {
                self.cleaning.deactivate(cause: .permissionRevoked)
            }
            self.show(banner: "Accessibility permission was turned off. Cleaning Mode and Lock need it.")
        }

        battery.onACStateChanged = { [weak self] isOnAC in
            guard let self, !isOnAC else { return }
            self.enforceIndefinitePowerRule()
        }

        battery.onLowBattery = { [weak self] percent in
            guard let self, self.keepAwake.isUserSessionActive else { return }
            self.keepAwake.stopUserSession()
            self.notify("Keep Awake switched off",
                        "Battery is at \(percent)% and not charging, so Vigil let your Mac sleep.")
            self.show(banner: "Keep Awake stopped \u{2014} battery at \(percent)%.")
        }

        HotKeyManager.shared.setHandler({ [weak self] in self?.toggleKeepAwake() }, for: .toggleKeepAwake)
        HotKeyManager.shared.setHandler({ [weak self] in self?.toggleCleaningMode() }, for: .toggleCleaningMode)
        HotKeyManager.shared.setHandler({ [weak self] in self?.lockAndKeepAwake() }, for: .lockAndKeepAwake)
        HotKeyManager.shared.reloadFromPreferences()

        startClock()
        observeSystemSleep()
        restoreKeepAwakeIfNeeded()
    }

    private func startClock() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onClockTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func onClockTick() {
        tickCount &+= 1

        // Only publish a new clock value when something on screen is actually
        // counting. Otherwise this redrew the menu bar item once a second for
        // the entire life of the app, for a display that never changed.
        if keepAwake.userSessionExpiry != nil || cleaning.isActive {
            clock = Date()
        }

        // Re-read power state periodically rather than trusting that every
        // IOKit transition was delivered, then re-assert the rule. Ten seconds
        // is frequent enough that an unbounded session can't outlive the cable
        // by long, and cheap enough not to matter.
        if tickCount % 10 == 0 {
            battery.refresh()
        }
        enforceIndefinitePowerRule()
    }

    /// The system can still sleep on a lid close or an explicit Sleep command.
    /// Drop everything rather than wake up holding a stale tap.
    private func observeSystemSleep() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.cleaning.isActive { self.cleaning.deactivate(cause: .programmatic) }
            }
        }

        // Being unplugged while asleep is exactly the case an edge-triggered
        // power handler misses, so re-read and re-assert on the way back up
        // rather than waiting for the next periodic check.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.battery.refresh()
                self.enforceIndefinitePowerRule()
            }
        }
    }

    /// Restores an indefinite "Until turned off" session across a relaunch.
    private func restoreKeepAwakeIfNeeded() {
        guard preferences.keepAwakeWasActive,
              preferences.keepAwakeDuration.restoresAcrossLaunches
        else {
            preferences.keepAwakeWasActive = false
            return
        }
        let restored = effectiveDuration(for: .untilTurnedOff)
        keepAwake.startUserSession(duration: restored,
                                   keepDisplayOn: preferences.keepDisplayOn)
        Self.log.info("Restored Keep Awake session from previous launch as \(restored.rawValue, privacy: .public)")
    }

    // MARK: - Actions

    func toggleKeepAwake() {
        if keepAwake.isUserSessionActive {
            keepAwake.stopUserSession()
            notify("Keep Awake off", "Your Mac can sleep normally again.")
        } else {
            startKeepAwake(duration: preferences.keepAwakeDuration)
        }
    }

    /// What a session started right now would actually run for.
    ///
    /// The stored preference is the user's *intent*; this is what power state
    /// permits. Keeping them separate means unplugging doesn't quietly rewrite
    /// the default they picked while plugged in.
    func effectiveDuration(for requested: KeepAwakeDuration) -> KeepAwakeDuration {
        guard requested.isIndefinite, !allowsIndefinite else { return requested }
        return Self.batteryFallbackDuration
    }

    /// Indefinite Keep Awake needs wall power. A desktop with no battery always
    /// qualifies.
    var allowsIndefinite: Bool {
        #if DEBUG
        // Lets the on-battery behaviour be exercised without unplugging:
        //   defaults write zw.co.munyaradzichigangawa.Vigil debugForceBatteryPower -bool true
        // Debug builds only — never compiled into a Release build.
        if UserDefaults.standard.bool(forKey: "debugForceBatteryPower") { return false }
        #endif
        return !battery.hasBattery || battery.isOnAC
    }

    /// What an indefinite request becomes while running on battery.
    static let batteryFallbackDuration: KeepAwakeDuration = .hour1

    func startKeepAwake(duration: KeepAwakeDuration) {
        // Record intent even when power state won't allow it right now, so the
        // choice takes effect the next time the Mac is plugged in.
        preferences.keepAwakeDuration = duration

        let effective = effectiveDuration(for: duration)
        keepAwake.startUserSession(duration: effective, keepDisplayOn: preferences.keepDisplayOn)
        usageLog.record(.keepAwake)

        if effective != duration {
            Self.log.info("Indefinite Keep Awake downgraded to \(effective.rawValue, privacy: .public) on battery")
            show(banner: "On battery, so Keep Awake is capped at \(effective.title.lowercased()). Plug in for no time limit.")
            notify("Keep Awake on",
                   "Running on battery, so it's capped at \(effective.title.lowercased()) instead of no limit.")
        } else {
            notify("Keep Awake on", keepAwakeNotificationBody(effective))
        }
    }

    /// Caps a running no-limit session the moment it is no longer entitled to
    /// one. Idempotent, and safe to call as often as you like.
    ///
    /// This is a standing **invariant**, not a reaction to unplugging, and that
    /// distinction is the point. Starting a no-limit session while plugged in
    /// and then pulling the cable is the obvious way to get an unbounded
    /// assertion on battery, and an edge-triggered handler misses it whenever
    /// the transition itself is missed — unplugged while asleep, a dropped
    /// IOKit callback, a session restored from disk. Re-checking the condition
    /// continuously means the state cannot persist even if the event does not
    /// arrive.
    ///
    /// Deliberately caps rather than stopping outright: unplugging to walk to
    /// another desk shouldn't kill a session, but it must not stay unbounded.
    private func enforceIndefinitePowerRule() {
        guard keepAwake.isUserSessionActive,
              let active = keepAwake.activeDuration,
              active.isIndefinite,
              !allowsIndefinite
        else { return }

        let fallback = Self.batteryFallbackDuration
        keepAwake.startUserSession(duration: fallback, keepDisplayOn: keepAwake.userSessionKeepsDisplayOn)
        Self.log.info("Unplugged during an indefinite session; capped at \(fallback.rawValue, privacy: .public)")
        show(banner: "Unplugged \u{2014} Keep Awake now ends in \(fallback.title.lowercased()).")
        notify("Keep Awake capped",
               "You're on battery now, so Keep Awake will stop in \(fallback.title.lowercased()) instead of running indefinitely.")
    }

    func toggleCleaningMode() {
        if cleaning.isActive {
            cleaning.deactivate(cause: .userGesture)
        } else {
            guard permission.refresh() else {
                show(banner: "Cleaning Mode needs Accessibility permission.")
                permission.requestAccess()
                return
            }
            usageLog.record(.cleaning)
            cleaning.activate()
        }
    }

    func lockAndKeepAwake() {
        guard permission.refresh() else {
            show(banner: "Locking needs Accessibility permission.")
            permission.requestAccess()
            return
        }

        // Never disturb a Keep Awake timer that is already running.
        keepAwake.ensureActiveForLock(defaultDuration: effectiveDuration(for: preferences.keepAwakeDuration),
                                      keepDisplayOn: false)
        usageLog.record(.lock)

        ScreenLocker.lock(hasAccessibility: true) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.notify("Locked", "Your Mac is locked and staying awake.")
                case .failure(.noAccessibility):
                    self.show(banner: "Locking needs Accessibility permission.")
                case .failure(.allMethodsFailed):
                    self.show(banner: "Vigil couldn't lock the screen. Keep Awake is still on.")
                }
            }
        }
    }

    /// Keep Awake with the display forced on, plus an optional Focus toggle.
    ///
    /// macOS exposes no public API for Do Not Disturb / Focus, so this runs a
    /// Shortcut the user names in preferences. With no Shortcut configured it
    /// is simply Keep Awake with the screen held on.
    func startPresentationMode() {
        preferences.keepDisplayOn = true
        keepAwake.startUserSession(duration: effectiveDuration(for: preferences.keepAwakeDuration),
                                   keepDisplayOn: true)
        usageLog.record(.keepAwake)

        let shortcutName = preferences.presentationShortcutName.trimmingCharacters(in: .whitespaces)
        guard !shortcutName.isEmpty else {
            notify("Presentation Mode on", "Display stays on. Add a Focus Shortcut in Preferences to also silence notifications.")
            return
        }
        runShortcut(named: shortcutName)
        notify("Presentation Mode on", "Display stays on and \u{201C}\(shortcutName)\u{201D} was run.")
    }

    /// Invokes the Shortcuts CLI with the name passed as a separate argument —
    /// never interpolated into a shell string.
    private func runShortcut(named name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        do {
            try process.run()
        } catch {
            Self.log.error("Could not run shortcut: \(error.localizedDescription, privacy: .public)")
            show(banner: "Couldn't run the Shortcut \u{201C}\(name)\u{201D}.")
        }
    }

    // MARK: - Feedback

    private func handleCleaningEnded(_ cause: CleaningModeManager.ExitCause) {
        switch cause {
        case .userGesture:
            notify("Cleaning Mode off", "Your keyboard and trackpad are back.")
        case .timerExpired:
            notify("Cleaning Mode ended", "The timer ran out and input is back on.")
        case .permissionRevoked:
            notify("Cleaning Mode stopped", "Accessibility permission was turned off, so input was restored.")
            show(banner: "Cleaning Mode stopped: Accessibility permission was revoked.")
        case .tapFailed:
            notify("Cleaning Mode stopped", "macOS disabled the input tap, so input was restored.")
            show(banner: "Cleaning Mode stopped: macOS disabled the input tap.")
        case .programmatic:
            break
        }
    }

    private func notify(_ title: String, _ body: String) {
        NotificationManager.shared.post(title: title, body: body)
    }

    func show(banner text: String) {
        banner = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if self.banner == text { self.banner = nil }
        }
    }

    private func keepAwakeNotificationBody(_ duration: KeepAwakeDuration) -> String {
        let display = preferences.keepDisplayOn ? "Display stays on." : "Display can still sleep."
        switch duration {
        case .untilTurnedOff, .untilAppQuits:
            return "\(display) No time limit."
        default:
            return "\(display) For \(duration.title.lowercased())."
        }
    }

    // MARK: - Shutdown

    /// Releases every assertion and tap. Called from `applicationWillTerminate`.
    func shutDown() {
        cleaning.emergencyTeardown()
        keepAwake.releaseEverything()
        HotKeyManager.shared.unregisterAll()
        Self.log.info("Vigil shut down cleanly")
    }
}
