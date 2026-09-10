import Foundation
import Combine

/// How long a Keep Awake session should last.
enum KeepAwakeDuration: String, CaseIterable, Identifiable, Codable {
    case minutes15
    case minutes30
    case hour1
    case hours4
    case untilTurnedOff
    case untilAppQuits

    var id: String { rawValue }

    /// Nil means "no timer" — the assertion runs until something else stops it.
    var seconds: TimeInterval? {
        switch self {
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .hour1: return 60 * 60
        case .hours4: return 4 * 60 * 60
        case .untilTurnedOff, .untilAppQuits: return nil
        }
    }

    var title: String {
        switch self {
        case .minutes15: return "15 minutes"
        case .minutes30: return "30 minutes"
        case .hour1: return "1 hour"
        case .hours4: return "4 hours"
        case .untilTurnedOff: return "Until turned off"
        case .untilAppQuits: return "Until Vigil quits"
        }
    }

    /// `.untilTurnedOff` is the only indefinite mode that survives a relaunch.
    /// `.untilAppQuits` deliberately does not — that is the whole difference
    /// between the two options.
    var restoresAcrossLaunches: Bool { self == .untilTurnedOff }

    /// Runs with no time limit. These are only allowed on AC power: an
    /// unbounded assertion on battery is how a laptop gets flattened in a bag.
    var isIndefinite: Bool { seconds == nil }
}

/// Which menu bar glyph style to use.
enum MenuBarIconStyle: String, CaseIterable, Identifiable, Codable {
    case symbolic
    case filled

    var id: String { rawValue }
    var title: String { self == .symbolic ? "Outline" : "Filled" }
}

/// User-facing settings, backed by `UserDefaults`.
///
/// Everything here is local to this machine. Vigil never reads or writes
/// anything off-device.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    private enum Key {
        static let keepAwakeDuration = "keepAwakeDuration"
        static let keepDisplayOn = "keepDisplayOn"
        static let cleaningAutoExitSeconds = "cleaningAutoExitSeconds"
        static let cleaningExitHoldSeconds = "cleaningExitHoldSeconds"
        static let iconStyle = "menuBarIconStyle"
        static let notificationsEnabled = "notificationsEnabled"
        static let batteryGuardEnabled = "batteryGuardEnabled"
        static let batteryGuardThreshold = "batteryGuardThreshold"
        static let usageLogEnabled = "usageLogEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let keepAwakeWasActive = "keepAwakeWasActive"
        static let presentationShortcutName = "presentationShortcutName"
        static let hotKeyKeepAwake = "hotKey.keepAwake"
        static let hotKeyCleaning = "hotKey.cleaning"
        static let hotKeyLock = "hotKey.lock"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.keepAwakeDuration: KeepAwakeDuration.hour1.rawValue,
            Key.keepDisplayOn: true,
            Key.cleaningAutoExitSeconds: 75.0,
            Key.cleaningExitHoldSeconds: 2.0,
            Key.iconStyle: MenuBarIconStyle.symbolic.rawValue,
            Key.notificationsEnabled: true,
            Key.batteryGuardEnabled: true,
            Key.batteryGuardThreshold: 10,
            Key.usageLogEnabled: false,
            Key.hasCompletedOnboarding: false,
            Key.keepAwakeWasActive: false,
            Key.presentationShortcutName: "",
        ])
    }

    // MARK: - Keep Awake

    var keepAwakeDuration: KeepAwakeDuration {
        get { KeepAwakeDuration(rawValue: defaults.string(forKey: Key.keepAwakeDuration) ?? "") ?? .hour1 }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Key.keepAwakeDuration) }
    }

    var keepDisplayOn: Bool {
        get { defaults.bool(forKey: Key.keepDisplayOn) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.keepDisplayOn) }
    }

    /// Set while an indefinite `.untilTurnedOff` session is running so the
    /// state can be restored on next launch.
    var keepAwakeWasActive: Bool {
        get { defaults.bool(forKey: Key.keepAwakeWasActive) }
        set { defaults.set(newValue, forKey: Key.keepAwakeWasActive) }
    }

    // MARK: - Cleaning Mode

    /// Hard ceiling on a Cleaning Mode session. Clamped so the user can never
    /// configure themselves into a lockout longer than five minutes.
    var cleaningAutoExitSeconds: Double {
        get { min(max(defaults.double(forKey: Key.cleaningAutoExitSeconds), 10), 300) }
        set { objectWillChange.send(); defaults.set(min(max(newValue, 10), 300), forKey: Key.cleaningAutoExitSeconds) }
    }

    /// How long the exit button must be held. Clamped to a range that is
    /// deliberate but never unreachable.
    var cleaningExitHoldSeconds: Double {
        get { min(max(defaults.double(forKey: Key.cleaningExitHoldSeconds), 0.5), 5) }
        set { objectWillChange.send(); defaults.set(min(max(newValue, 0.5), 5), forKey: Key.cleaningExitHoldSeconds) }
    }

    // MARK: - Appearance & behaviour

    var iconStyle: MenuBarIconStyle {
        get { MenuBarIconStyle(rawValue: defaults.string(forKey: Key.iconStyle) ?? "") ?? .symbolic }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    var batteryGuardEnabled: Bool {
        get { defaults.bool(forKey: Key.batteryGuardEnabled) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.batteryGuardEnabled) }
    }

    var batteryGuardThreshold: Int {
        get { min(max(defaults.integer(forKey: Key.batteryGuardThreshold), 5), 50) }
        set { objectWillChange.send(); defaults.set(min(max(newValue, 5), 50), forKey: Key.batteryGuardThreshold) }
    }

    var usageLogEnabled: Bool {
        get { defaults.bool(forKey: Key.usageLogEnabled) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.usageLogEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Name of a user-created Shortcut that toggles a Focus mode.
    ///
    /// macOS has no public API to toggle Do Not Disturb / Focus, so Presentation
    /// Mode drives it through the Shortcuts app instead. Empty means
    /// Presentation Mode just does Keep Awake with the display forced on.
    var presentationShortcutName: String {
        get { defaults.string(forKey: Key.presentationShortcutName) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.presentationShortcutName) }
    }

    // MARK: - Hot keys

    func hotKey(for action: HotKeyAction) -> HotKeyCombo? {
        guard let data = defaults.data(forKey: key(for: action)) else { return nil }
        return try? JSONDecoder().decode(HotKeyCombo.self, from: data)
    }

    func setHotKey(_ combo: HotKeyCombo?, for action: HotKeyAction) {
        objectWillChange.send()
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key(for: action))
        } else {
            defaults.removeObject(forKey: key(for: action))
        }
    }

    private func key(for action: HotKeyAction) -> String {
        switch action {
        case .toggleKeepAwake: return Key.hotKeyKeepAwake
        case .toggleCleaningMode: return Key.hotKeyCleaning
        case .lockAndKeepAwake: return Key.hotKeyLock
        }
    }
}
