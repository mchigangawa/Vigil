import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a standalone window.
///
/// An `LSUIElement` app has no Dock icon and never becomes active on its own,
/// so any window it opens has to activate the app explicitly or it will appear
/// behind whatever the user was working in.
///
/// Deliberately not generic over the content view: the app delegate stores
/// these as stored properties, and a `some View` content type cannot be named
/// there.
@MainActor
final class AuxiliaryWindowController {

    private var window: NSWindow?
    private let title: String
    private let size: NSSize
    private let content: () -> AnyView

    init<Content: View>(title: String, size: NSSize, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.size = size
        self.content = { AnyView(content()) }
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: content())
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        // The hosting view drives the window's minimum size from the SwiftUI
        // content, so this is a starting size rather than a hard one; the views
        // fill whatever they are given and the window can be resized larger.
        window.setContentSize(size)
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
