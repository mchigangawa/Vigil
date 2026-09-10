import Foundation
import UserNotifications
import os

/// Local, on-device notifications for mode changes.
/// File-scope so the completion handlers below can log without hopping back to
/// the main actor just to read a constant.
private let notificationLog = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil",
                                     category: "Notifications")

@MainActor
final class NotificationManager {

    static let shared = NotificationManager()

    private var authorized = false
    private var didRequest = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.authorized = granted
                if let error {
                    // An app signed with a personal team and run from Xcode can
                    // fail here. It is not fatal — everything else still works.
                    notificationLog.notice("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func post(title: String, body: String) {
        guard Preferences.shared.notificationsEnabled, authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                notificationLog.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
