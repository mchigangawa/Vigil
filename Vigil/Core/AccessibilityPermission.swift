import AppKit
import ApplicationServices
import Combine
import Security

/// Watches the Accessibility (AXIsProcessTrusted) grant.
///
/// Cleaning Mode's event tap and Lock & Keep Awake's synthetic keystroke both
/// depend on this. macOS gives no notification when the grant is revoked, so a
/// low-frequency poll is the only way to notice — it runs at 2s while something
/// depends on the permission and 10s otherwise.
@MainActor
final class AccessibilityPermission: ObservableObject {

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// Called when the grant disappears out from under a running feature.
    var onRevoked: (() -> Void)?

    private var timer: Timer?
    private var heightenedWatch = false

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// True when this build carries only an ad-hoc signature.
    ///
    /// This matters a great deal here. macOS pins an Accessibility grant to the
    /// binary's *designated requirement*; for an ad-hoc signature that
    /// requirement is a bare `cdhash`, which changes on every single build. The
    /// result is the most confusing failure in this whole app: Vigil stays
    /// ticked in System Settings while the grant silently stops applying to the
    /// rebuilt binary. Signing with a real team (even a free personal one)
    /// produces an identifier-and-certificate requirement instead, which
    /// survives rebuilds.
    static let isAdHocSigned: Bool = {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let signingFlags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else { return false }

        // kSecCodeSignatureAdhoc
        return (signingFlags & 0x0002) != 0
    }()

    /// One line explaining why a granted permission may not have stuck.
    static var staleGrantHint: String? {
        guard isAdHocSigned else { return nil }
        return "This build is ad-hoc signed, so macOS ties the permission to this exact build and forgets it whenever you rebuild. Pick a Team in Signing & Capabilities to make it stick. For now: remove Vigil from the list with \u{2212}, then add it again."
    }

    init() {
        startPolling(interval: 10)
    }

    /// Re-checks immediately. Call after returning from System Settings.
    @discardableResult
    func refresh() -> Bool {
        let now = AXIsProcessTrusted()
        if now != isTrusted {
            isTrusted = now
            if !now { onRevoked?() }
        }
        return now
    }

    /// Triggers the system's own permission prompt, then opens System Settings.
    ///
    /// The prompt only appears once per app build; the deep link is what
    /// actually helps on every subsequent attempt.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    /// Tightens the poll interval while a feature depends on the grant.
    func setHeightenedWatch(_ on: Bool) {
        guard heightenedWatch != on else { return }
        heightenedWatch = on
        startPolling(interval: on ? 2 : 10)
    }

    private func startPolling(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}
