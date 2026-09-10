import Foundation
import IOKit.ps
import Combine
import os

/// Watches battery charge so Keep Awake can stand down before it drains a
/// machine the user has walked away from.
///
/// Driven by IOKit's power-source change notifications — no polling.
@MainActor
final class BatteryMonitor: ObservableObject {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "Battery")

    /// Percentage 0...100, or nil on a machine with no battery.
    @Published private(set) var percentage: Int?
    @Published private(set) var isOnAC: Bool = true
    /// False on a desktop Mac, which has no battery to protect.
    @Published private(set) var hasBattery: Bool = false

    /// Called when charge falls below the configured threshold on battery power.
    var onLowBattery: ((Int) -> Void)?
    /// Called when the machine is plugged in or unplugged. Not fired for the
    /// initial reading — only for genuine transitions.
    var onACStateChanged: ((Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var didWarnBelowThreshold = false
    private var previousIsOnAC: Bool?

    init() {
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ userInfo in
            guard let userInfo else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context)?.takeRetainedValue() else {
            Self.log.error("Could not create power-source notification source")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var foundPercentage: Int?
        var onAC = true

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                foundPercentage = Int((Double(current) / Double(max) * 100).rounded())
            }
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                onAC = (state == kIOPSACPowerValue)
            }
        }

        percentage = foundPercentage
        hasBattery = (foundPercentage != nil)
        isOnAC = onAC

        // Only report genuine transitions, so a listener is not told "you just
        // plugged in" the moment the app launches.
        if let previous = previousIsOnAC, previous != onAC {
            Self.log.info("Power source changed: \(onAC ? "AC" : "battery", privacy: .public)")
            onACStateChanged?(onAC)
        }
        previousIsOnAC = onAC

        evaluateThreshold()
    }

    private func evaluateThreshold() {
        let prefs = Preferences.shared
        guard prefs.batteryGuardEnabled, !isOnAC, let percentage else {
            didWarnBelowThreshold = false
            return
        }

        if percentage <= prefs.batteryGuardThreshold {
            // Only fire once per descent below the line.
            guard !didWarnBelowThreshold else { return }
            didWarnBelowThreshold = true
            Self.log.notice("Battery at \(percentage, privacy: .public)% — below guard threshold")
            onLowBattery?(percentage)
        } else {
            didWarnBelowThreshold = false
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}
