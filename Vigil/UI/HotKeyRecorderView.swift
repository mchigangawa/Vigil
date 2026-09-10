import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Captures a key combination for a global shortcut.
///
/// While recording, a local `NSEvent` monitor takes every key down so the
/// keystroke configures the shortcut instead of triggering something else.
struct HotKeyRecorderView: View {

    let action: HotKeyAction
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorText: String?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Vg.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(Vg.Typo.body)
                if let errorText {
                    Text(errorText)
                        .font(Vg.Typo.caption)
                        .foregroundStyle(Vg.Tint.warning)
                } else if isRecording {
                    Text("Listening \u{2014} Escape to cancel")
                        .font(Vg.Typo.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: Vg.Space.m)

            recorderChip

            Button {
                coordinator.preferences.setHotKey(nil, for: action)
                HotKeyManager.shared.reloadFromPreferences()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(hasShortcut ? 1 : 0)
            .disabled(!hasShortcut)
            .help("Clear shortcut")
        }
        .onDisappear { stopRecording() }
    }

    /// The shortcut itself, styled like a key cap.
    private var recorderChip: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(chipLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(chipForeground)
                .frame(minWidth: 96)
                .padding(.horizontal, Vg.Space.m)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                        .fill(isRecording
                              ? Color.accentColor.opacity(0.16)
                              : Color.primary.opacity(isHovering ? 0.09 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                        .strokeBorder(isRecording
                                      ? Color.accentColor.opacity(0.6)
                                      : Color.primary.opacity(0.10),
                                      lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var hasShortcut: Bool {
        coordinator.preferences.hotKey(for: action) != nil
    }

    private var chipLabel: String {
        if isRecording { return "Press keys\u{2026}" }
        return coordinator.preferences.hotKey(for: action)?.displayString ?? "Click to set"
    }

    private var chipForeground: Color {
        if isRecording { return .accentColor }
        return hasShortcut ? .primary : .secondary
    }

    // MARK: - Recording

    private func startRecording() {
        errorText = nil
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }

            // Escape cancels without binding anything.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])
            let combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifierFlags: flags.rawValue)

            guard combo.isValid else {
                errorText = "Add a modifier key"
                return nil
            }

            coordinator.preferences.setHotKey(combo, for: action)
            HotKeyManager.shared.reloadFromPreferences()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
