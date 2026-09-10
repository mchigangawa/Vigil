import AppKit
import SwiftUI
import Combine

/// Live values the overlay renders. One instance is shared by every screen's
/// window so all displays stay in step.
@MainActor
final class CleaningOverlayModel: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var holdProgress: Double = 0
    @Published var blockedEventCount: Int = 0
    @Published var holdSeconds: Double = 2
    /// Full length of this session, so the countdown ring has a denominator.
    @Published var totalSeconds: Double = 75

    /// Set by the overlay view once the exit button has been laid out, in the
    /// window's own coordinate space.
    var reportExitFrame: ((NSRect, NSWindow?) -> Void)?
}

/// A view that swallows every click that reaches it.
///
/// The overlay covers the screen, but a hosting view whose SwiftUI content
/// declines hit testing would let a click fall through to the app underneath.
/// Returning `self` unconditionally makes the overlay a hard floor for input
/// that the event tap deliberately passed through.
private final class AbsorbingContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override var acceptsFirstResponder: Bool { false }
}

/// A borderless, non-activating panel pinned above everything, on every Space.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one full-screen overlay window per display.
@MainActor
final class CleaningOverlayController {

    let model = CleaningOverlayModel()

    private var panels: [OverlayPanel] = []
    private var bridge: CleaningTapBridge?
    private var screenObserver: NSObjectProtocol?

    func show(bridge: CleaningTapBridge) {
        self.bridge = bridge
        model.holdSeconds = Preferences.shared.cleaningExitHoldSeconds
        model.totalSeconds = Preferences.shared.cleaningAutoExitSeconds
        model.holdProgress = 0
        model.blockedEventCount = 0

        model.reportExitFrame = { [weak self] rectInWindow, window in
            self?.updateHotZone(rectInWindow: rectInWindow, window: window)
        }

        buildPanels()

        // Displays can be plugged in, unplugged, or rearranged mid-session.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildForScreenChange() }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        bridge?.exitHotZones = []
        bridge = nil
        model.reportExitFrame = nil
    }

    func update(remaining: TimeInterval, holdProgress: Double, blocked: Int) {
        // The manager ticks at 30Hz so the hold gesture stays responsive, but
        // publishing all of that straight through re-renders a full-screen view
        // on every display 30 times a second for a countdown that only shows
        // whole seconds. Forward a value only when it would actually change
        // what is on screen.
        if Int(remaining.rounded(.up)) != Int(model.remaining.rounded(.up)) {
            model.remaining = remaining
        }
        if abs(holdProgress - model.holdProgress) >= 0.02
            || (holdProgress == 0) != (model.holdProgress == 0)
            || holdProgress >= 1 {
            model.holdProgress = holdProgress
        }
        if blocked != model.blockedEventCount {
            model.blockedEventCount = blocked
        }
    }

    // MARK: - Windows

    private func buildPanels() {
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered,
                                     defer: false,
                                     screen: screen)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovable = false
            panel.ignoresMouseEvents = false
            // Above the menu bar, the Dock, and full-screen apps.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = false

            let hosting = NSHostingView(rootView: CleaningOverlayView(model: model))
            hosting.translatesAutoresizingMaskIntoConstraints = false

            let container = AbsorbingContainerView(frame: screen.frame)
            container.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            panel.contentView = container
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func rebuildForScreenChange() {
        guard let bridge else { return }
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        bridge.exitHotZones = []
        buildPanels()
    }

    // MARK: - Hot zone

    /// Converts the exit button's frame into the Quartz global coordinates the
    /// event tap sees, and registers it as a pass-through region.
    private func updateHotZone(rectInWindow: NSRect, window: NSWindow?) {
        guard let bridge, let window else { return }

        // SwiftUI reports a top-left origin within the hosting view; AppKit
        // windows are bottom-left. Flip before converting to screen space.
        let height = window.frame.height
        let cocoaInWindow = NSRect(x: rectInWindow.minX,
                                   y: height - rectInWindow.maxY,
                                   width: rectInWindow.width,
                                   height: rectInWindow.height)
        let onScreen = window.convertToScreen(cocoaInWindow)
        let quartz = Self.quartzRect(fromCocoaScreenRect: onScreen)

        // A little slack so a finger that drifts a few points mid-hold does not
        // cancel the only gesture out.
        let padded = quartz.insetBy(dx: -12, dy: -12)

        bridge.exitHotZones.removeAll { $0.intersects(padded) }
        bridge.exitHotZones.append(padded)
    }

    /// Cocoa screen space (origin bottom-left of the primary display, y up) to
    /// Quartz global display space (origin top-left, y down).
    static func quartzRect(fromCocoaScreenRect rect: NSRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX,
                      y: primary.frame.maxY - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }
}
