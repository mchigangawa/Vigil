import Foundation
import Combine

/// A tiny, opt-in, on-device tally of how often each mode is used.
///
/// Stored in `UserDefaults`, never leaves the machine, and is off by default.
/// Only counts per calendar day are kept — no timestamps, no context.
@MainActor
final class UsageLog: ObservableObject {

    struct DayCounts: Codable, Equatable {
        var keepAwake = 0
        var cleaning = 0
        var lock = 0
    }

    enum Event: String {
        case keepAwake, cleaning, lock
    }

    @Published private(set) var today = DayCounts()

    private let defaults: UserDefaults
    private let storageKey = "usageLog.byDay"
    /// Days older than this are dropped on every write.
    private let retentionDays = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        today = load()[Self.dayKey(for: Date())] ?? DayCounts()
    }

    func record(_ event: Event) {
        guard Preferences.shared.usageLogEnabled else { return }

        var all = load()
        let key = Self.dayKey(for: Date())
        var counts = all[key] ?? DayCounts()

        switch event {
        case .keepAwake: counts.keepAwake += 1
        case .cleaning: counts.cleaning += 1
        case .lock: counts.lock += 1
        }

        all[key] = counts
        all = prune(all)
        save(all)
        today = counts
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        today = DayCounts()
    }

    /// e.g. "Keep Awake 3\u{00D7} today"
    var todaySummary: String {
        var parts: [String] = []
        if today.keepAwake > 0 { parts.append("Keep Awake \(today.keepAwake)\u{00D7}") }
        if today.cleaning > 0 { parts.append("Cleaning \(today.cleaning)\u{00D7}") }
        if today.lock > 0 { parts.append("Lock \(today.lock)\u{00D7}") }
        return parts.isEmpty ? "Nothing logged today" : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Storage

    private func load() -> [String: DayCounts] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: DayCounts].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ value: [String: DayCounts]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func prune(_ value: [String: DayCounts]) -> [String: DayCounts] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return value
        }
        let cutoffKey = Self.dayKey(for: cutoff)
        return value.filter { $0.key >= cutoffKey }
    }

    /// ISO-ordered so plain string comparison is date comparison.
    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
