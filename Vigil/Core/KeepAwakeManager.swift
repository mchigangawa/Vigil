import Foundation
import IOKit.pwr_mgt
import Combine
import os

/// Why a Keep Awake assertion is currently held.
enum KeepAwakeReason: Equatable {
    /// The user's own Keep Awake toggle.
    case userToggle
    /// Held implicitly for the duration of Cleaning Mode.
    case cleaningMode
    /// Held by the Presentation Mode preset.
    case presentation
}

/// Owns IOKit power-management assertions.
///
/// Assertions are reference-counted by reason, so Cleaning Mode can hold the
/// display awake without disturbing (or being disturbed by) the user's own
/// Keep Awake toggle and its timer.
@MainActor
final class KeepAwakeManager: ObservableObject {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "KeepAwake")

    /// True while the user-facing Keep Awake toggle is on.
    @Published private(set) var isUserSessionActive = false
    /// Wall-clock deadline of the current user session, if it is timed.
    @Published private(set) var userSessionExpiry: Date?
    /// The duration the current user session was started with.
    @Published private(set) var activeDuration: KeepAwakeDuration?
    /// Whether the current user session is also holding the display on.
    @Published private(set) var userSessionKeepsDisplayOn = false
    /// When the current session began, for progress display.
    @Published private(set) var sessionStart: Date?

    /// Fired when a timed session runs out on its own.
    var onTimerExpired: (() -> Void)?

    private var systemAssertion: IOPMAssertionID = IOPMAssertionID(0)
    private var displayAssertion: IOPMAssertionID = IOPMAssertionID(0)

    /// Reasons currently requesting "system stays awake" / "display stays on".
    private var systemHolders: Set<KeepAwakeReason> = []
    private var displayHolders: Set<KeepAwakeReason> = []

    private var expiryTimer: Timer?

    // MARK: - User-facing session

    func startUserSession(duration: KeepAwakeDuration, keepDisplayOn: Bool) {
        stopUserSession(notifyExpiry: false)

        acquire(.userToggle, keepDisplayOn: keepDisplayOn)
        isUserSessionActive = true
        activeDuration = duration
        sessionStart = Date()
        userSessionKeepsDisplayOn = keepDisplayOn

        if let seconds = duration.seconds {
            let deadline = Date().addingTimeInterval(seconds)
            userSessionExpiry = deadline
            scheduleExpiry(at: deadline)
        } else {
            userSessionExpiry = nil
        }

        Preferences.shared.keepAwakeWasActive = duration.restoresAcrossLaunches
        Self.log.info("Keep Awake started (\(duration.rawValue, privacy: .public), display: \(keepDisplayOn, privacy: .public))")
    }

    func stopUserSession(notifyExpiry: Bool = false) {
        guard isUserSessionActive || expiryTimer != nil else { return }

        expiryTimer?.invalidate()
        expiryTimer = nil
        release(.userToggle)
        isUserSessionActive = false
        userSessionExpiry = nil
        activeDuration = nil
        sessionStart = nil
        userSessionKeepsDisplayOn = false
        Preferences.shared.keepAwakeWasActive = false

        Self.log.info("Keep Awake stopped")
        if notifyExpiry { onTimerExpired?() }
    }

    /// Ensures an assertion exists without touching an already-running timer.
    ///
    /// Used by Lock & Keep Awake: if a timed session is already going, this must
    /// not shorten, extend, or reset it.
    func ensureActiveForLock(defaultDuration: KeepAwakeDuration, keepDisplayOn: Bool) {
        guard !isUserSessionActive else {
            Self.log.info("Lock: existing Keep Awake session left untouched")
            return
        }
        startUserSession(duration: defaultDuration, keepDisplayOn: keepDisplayOn)
    }

    /// Seconds remaining on the current timed session, if any.
    var remaining: TimeInterval? {
        guard let expiry = userSessionExpiry else { return nil }
        return max(0, expiry.timeIntervalSinceNow)
    }

    /// How far through a timed session we are, 0...1. Nil when the session has
    /// no time limit and there is therefore nothing to fill.
    var progress: Double? {
        guard let start = sessionStart,
              let expiry = userSessionExpiry
        else { return nil }
        let total = expiry.timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(1, max(0, 1 - (expiry.timeIntervalSinceNow / total)))
    }

    // MARK: - Internal holders (Cleaning Mode, Presentation Mode)

    func acquire(_ reason: KeepAwakeReason, keepDisplayOn: Bool) {
        systemHolders.insert(reason)
        if keepDisplayOn {
            displayHolders.insert(reason)
        } else {
            displayHolders.remove(reason)
        }
        reconcile()
    }

    func release(_ reason: KeepAwakeReason) {
        systemHolders.remove(reason)
        displayHolders.remove(reason)
        reconcile()
    }

    // MARK: - Assertion plumbing

    /// Brings the live IOKit assertions in line with the current holder sets.
    private func reconcile() {
        setAssertion(&systemAssertion,
                     wanted: !systemHolders.isEmpty,
                     type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                     name: "Vigil is keeping this Mac awake")

        // `kIOPMAssertionTypePreventUserIdleDisplaySleep` is the modern spelling
        // of the older `kIOPMAssertionTypeNoDisplaySleep`; both keep the panel
        // lit, but this one is the supported name on current macOS.
        setAssertion(&displayAssertion,
                     wanted: !displayHolders.isEmpty,
                     type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                     name: "Vigil is keeping the display on")
    }

    private func setAssertion(_ id: inout IOPMAssertionID, wanted: Bool, type: String, name: String) {
        let held = id != IOPMAssertionID(0)
        guard held != wanted else { return }

        if wanted {
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     name as CFString,
                                                     &newID)
            if result == kIOReturnSuccess {
                id = newID
            } else {
                Self.log.error("IOPMAssertionCreateWithName(\(type, privacy: .public)) failed: \(result)")
            }
        } else {
            let result = IOPMAssertionRelease(id)
            if result != kIOReturnSuccess {
                Self.log.error("IOPMAssertionRelease failed: \(result)")
            }
            id = IOPMAssertionID(0)
        }
    }

    private func scheduleExpiry(at date: Date) {
        expiryTimer?.invalidate()
        let timer = Timer(fireAt: date, interval: 0, target: self,
                          selector: #selector(expiryFired), userInfo: nil, repeats: false)
        // Common mode so the timer still fires while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    @objc private func expiryFired() {
        Self.log.info("Keep Awake timer expired")
        stopUserSession(notifyExpiry: true)
    }

    /// Unconditional teardown. Safe to call more than once.
    ///
    /// Called on quit and on the system's own sleep notification so an
    /// assertion can never outlive the app.
    func releaseEverything() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        systemHolders.removeAll()
        displayHolders.removeAll()
        reconcile()
        isUserSessionActive = false
        userSessionExpiry = nil
        activeDuration = nil
        sessionStart = nil
        Self.log.info("All power assertions released")
    }
}
