import AppKit
import CoreGraphics
import os

/// Locks the screen.
enum ScreenLocker {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "Lock")

    /// Virtual key code for "Q". Control-Command-Q is the system lock shortcut.
    private static let kVK_ANSI_Q: CGKeyCode = 12

    enum Failure: Error {
        case noAccessibility
        case allMethodsFailed
    }

    /// Posts Control-Command-Q, and falls back to `CGSession -suspend` if the
    /// screen is still unlocked shortly afterwards.
    ///
    /// The synthetic keystroke is preferred because it stays in-process. The
    /// fallback exists because the shortcut can be remapped or suppressed.
    static func lock(hasAccessibility: Bool, completion: @escaping (Result<Void, Failure>) -> Void) {
        guard hasAccessibility else {
            log.error("Lock requested without Accessibility permission")
            completion(.failure(.noAccessibility))
            return
        }

        postLockShortcut()

        // Give the WindowServer a moment, then verify and fall back if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if isScreenLocked() {
                log.info("Locked via synthetic Control-Command-Q")
                completion(.success(()))
                return
            }

            log.notice("Synthetic keystroke did not lock; falling back to CGSession")
            if runCGSessionSuspend() {
                completion(.success(()))
            } else {
                completion(.failure(.allMethodsFailed))
            }
        }
    }

    private static func postLockShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let flags: CGEventFlags = [.maskCommand, .maskControl]

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_Q, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_Q, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Long-standing fallback: the login window's own session-suspend helper.
    private static func runCGSessionSuspend() -> Bool {
        let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            log.error("CGSession helper not present at expected path")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-suspend"]
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            if !ok { log.error("CGSession -suspend exited \(process.terminationStatus)") }
            return ok
        } catch {
            log.error("CGSession -suspend failed to launch: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Reads the WindowServer's own view of whether the screen is locked.
    static func isScreenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
