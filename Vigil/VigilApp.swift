import SwiftUI
import AppKit

@main
struct VigilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(delegate.coordinator)
        } label: {
            MenuBarLabel(coordinator: delegate.coordinator)
        }
        // A panel rather than a plain menu, so the countdown can tick live and
        // the layout can carry more than a list of items.
        .menuBarExtraStyle(.window)
    }
}

/// The glyph in the menu bar, tinted by what Vigil is currently doing.
private struct MenuBarLabel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Image(systemName: coordinator.status.symbolName(style: coordinator.preferences.iconStyle))
            .symbolRenderingMode(.hierarchical)
            // Each mode has its own hue, so the glyph's colour alone says what
            // Vigil is doing without opening the panel.
            .foregroundStyle(coordinator.status.isAccented
                             ? coordinator.status.tint
                             : Color.primary)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch coordinator.status {
        case .idle: return "Vigil: idle"
        case .keepAwake: return "Vigil: Keep Awake is on"
        case .cleaning: return "Vigil: Cleaning Mode is active"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let coordinator = AppCoordinator()

    private lazy var preferencesWindow = AuxiliaryWindowController(
        title: "Vigil Preferences",
        size: NSSize(width: 620, height: 520)
    ) { [coordinator] in
        PreferencesView().environmentObject(coordinator)
    }

    private lazy var onboardingWindow = AuxiliaryWindowController(
        title: "Welcome to Vigil",
        size: NSSize(width: 560, height: 560)
    ) { [coordinator] in
        OnboardingView().environmentObject(coordinator)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestAuthorizationIfNeeded()

        coordinator.openPreferences = { [weak self] in self?.preferencesWindow.show() }
        coordinator.closeOnboarding = { [weak self] in self?.onboardingWindow.close() }

        // Explain the Accessibility request before macOS throws up its own
        // dialog with no context.
        if !coordinator.preferences.hasCompletedOnboarding {
            onboardingWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutDown()
    }

    /// Vigil has no windows of its own most of the time; quitting on the last
    /// window closing would kill the menu bar item.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
