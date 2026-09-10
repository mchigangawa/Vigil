import Foundation
import ServiceManagement
import os

/// Launch-at-login via `SMAppService` (macOS 13+).
enum LaunchAtLogin {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "LaunchAtLogin")

    /// Reads the live registration state rather than a cached preference, so it
    /// stays correct if the user changes it in System Settings.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS is holding the item in "approval required" — the user has
    /// to allow it in System Settings > General > Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            log.error("Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
