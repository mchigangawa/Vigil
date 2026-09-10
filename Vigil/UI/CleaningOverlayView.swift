import SwiftUI
import AppKit

/// Carries the exit button's laid-out frame (window space) up to the controller.
private struct ExitFrameKey: PreferenceKey {
    static var defaultValue: NSRect = .zero
    static func reduce(value: inout NSRect, nextValue: () -> NSRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Captures the hosting `NSWindow` so the exit frame can be mapped into the
/// global coordinate space the event tap works in.
private struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { if let w = view.window { onResolve(w) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onResolve(w) } }
    }
}

/// Full-screen content shown while Cleaning Mode is active.
///
/// Nothing here is interactive. The hold gesture is recognised by the event tap
/// and timed on the main thread, so this view only has to *show* what is
/// happening — a stuck or slow view can never trap the user.
struct CleaningOverlayView: View {

    @ObservedObject var model: CleaningOverlayModel

    @State private var window: NSWindow?
    @State private var exitFrame: NSRect = .zero
    @State private var pulse = false

    private let tint = Vg.Tint.cleaning

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: Vg.Space.xxl) {
                dial
                headline
                exitButton
                reassurance
            }
            .padding(Vg.Space.xxl * 2)
        }
        .ignoresSafeArea()
        .background(WindowReader { resolved in
            if window !== resolved {
                window = resolved
                publishExitFrame()
            }
        })
        // One source of truth for the hot zone: the button's real laid-out
        // frame, published whenever either it or the window changes.
        .onPreferenceChange(ExitFrameKey.self) { rect in
            guard rect != .zero, rect != exitFrame else { return }
            exitFrame = rect
            publishExitFrame()
        }
        .onAppear { pulse = true }
    }

    private func publishExitFrame() {
        guard let window, exitFrame != .zero else { return }
        model.reportExitFrame?(exitFrame, window)
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.55)
            RadialGradient(colors: [tint.opacity(0.22), .clear],
                           center: .center, startRadius: 60, endRadius: 900)
        }
    }

    // MARK: - Countdown dial

    /// A ring that drains as the session runs out, wrapped around the icon.
    /// It doubles as the reassurance that this ends on its own.
    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 5)

            Circle()
                .trim(from: 0, to: timeFraction)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timeFraction)

            Circle()
                .fill(tint.opacity(0.10))
                .padding(14)
                .scaleEffect(pulse ? 1.03 : 0.97)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 2) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(tint)
                Text(model.remaining.vgClockString)
                    .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: 168, height: 168)
    }

    private var timeFraction: Double {
        guard model.totalSeconds > 0 else { return 0 }
        return min(1, max(0, model.remaining / model.totalSeconds))
    }

    // MARK: - Copy

    private var headline: some View {
        VStack(spacing: Vg.Space.m) {
            Text("Cleaning Mode")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your keyboard and trackpad are switched off. Wipe away.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    // MARK: - Exit affordance

    private var exitButton: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.08))
                .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(isHolding ? 0.45 : 0.20), lineWidth: 1)
                )

            // Fills left to right as the hold progresses.
            GeometryReader { geo in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(colors: [tint.opacity(0.7), tint],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * model.holdProgress)
            }
            .clipShape(Capsule(style: .continuous))
            .animation(.linear(duration: 0.05), value: model.holdProgress)

            HStack(spacing: 12) {
                Image(systemName: isHolding ? "lock.open.fill" : "hand.point.up.left.fill")
                    .font(.system(size: 17, weight: .medium))
                Text(isHolding ? "Keep the pointer here\u{2026}" : "Click here, then hold still to exit")
                    .font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 460, height: 72)
        .scaleEffect(isHolding ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHolding)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ExitFrameKey.self, value: geo.frame(in: .global))
            }
        )
    }

    private var isHolding: Bool { model.holdProgress > 0 }

    // MARK: - Footer

    private var reassurance: some View {
        VStack(spacing: Vg.Space.s) {
            Label("Ends by itself when the ring runs out \u{2014} you can't get stuck",
                  systemImage: "checkmark.shield.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))

            if model.blockedEventCount > 0 {
                Text("\(model.blockedEventCount) inputs blocked")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .contentTransition(.numericText())
            }
        }
    }
}
