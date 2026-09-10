import SwiftUI
import AppKit

/// The panel that drops down from the menu bar glyph.
struct MenuContentView: View {

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var showAllDurations = false

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.m) {
            header

            if let banner = coordinator.banner {
                VgNotice(icon: "exclamationmark.triangle.fill",
                         title: "Heads up",
                         message: banner)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !coordinator.permission.isTrusted {
                VgNotice(icon: "lock.shield.fill",
                         title: "Accessibility permission needed",
                         message: "Cleaning Mode and Lock can't work until you allow Vigil in System Settings.",
                         tint: .accentColor,
                         actionTitle: "Open System Settings\u{2026}",
                         action: { coordinator.permission.requestAccess() },
                         secondaryActionTitle: "Re-check",
                         secondaryAction: { coordinator.permission.refresh() },
                         detail: AccessibilityPermission.staleGrantHint)
            }

            keepAwakeCard
            actionsCard
            footer
        }
        .padding(Vg.Space.l)
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.18), value: coordinator.banner)
        .animation(.easeInOut(duration: 0.18), value: coordinator.keepAwake.isUserSessionActive)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Vg.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                    .fill(coordinator.status.tint.opacity(0.16))
                    .frame(width: 26, height: 26)
                Image(systemName: coordinator.status.symbolName(style: .filled))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(coordinator.status.tint)
            }

            Text("Vigil").font(Vg.Typo.title)

            Spacer()

            VgStatusPill(text: coordinator.status.label,
                         tint: coordinator.status.tint,
                         isLive: coordinator.status.isAccented)
        }
    }

    // MARK: - Keep Awake

    private var keepAwakeCard: some View {
        VgCard {
            VStack(alignment: .leading, spacing: Vg.Space.m) {
                HStack(spacing: Vg.Space.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                            .fill(Vg.Tint.awake.opacity(isAwake ? 0.20 : 0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Vg.Tint.awake)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keep Awake").font(Vg.Typo.rowTitle)
                        Text(subtitleText)
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Vg.Space.s)

                    Toggle("", isOn: Binding(
                        get: { isAwake },
                        set: { _ in coordinator.toggleKeepAwake() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Vg.Tint.awake)
                }

                // A no-limit session has nothing to count down, so the block
                // is omitted entirely rather than showing an empty timer.
                if isAwake, coordinator.keepAwake.remaining != nil {
                    countdown
                }

                Divider().opacity(0.5)

                durationPicker

                Toggle(isOn: Binding(
                    get: { coordinator.preferences.keepDisplayOn },
                    set: { coordinator.preferences.keepDisplayOn = $0 }
                )) {
                    Text(coordinator.preferences.keepDisplayOn
                         ? "Keep the display on"
                         : "Let the display sleep")
                        .font(Vg.Typo.body)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let remaining = coordinator.keepAwake.remaining {
            VStack(alignment: .leading, spacing: Vg.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(remaining.vgClockString)
                        .font(Vg.Typo.bigTimer)
                        .foregroundStyle(Vg.Tint.awake)
                    Text("left")
                        .font(Vg.Typo.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let progress = coordinator.keepAwake.progress {
                    VgProgressBar(value: progress, tint: Vg.Tint.awake)
                }
            }
        }
    }

    /// Four common durations up front, the rest a click away — the full list of
    /// six was the single busiest thing in the old panel.
    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Vg.Space.s) {
            HStack {
                VgSectionLabel(text: "Duration")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { showAllDurations.toggle() }
                } label: {
                    Image(systemName: showAllDurations ? "chevron.up" : "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(showAllDurations ? "Show fewer options" : "More options")
            }

            let shown: [KeepAwakeDuration] = showAllDurations
                ? KeepAwakeDuration.allCases
                : [.minutes15, .minutes30, .hour1, .hours4]

            FlowChips(durations: shown,
                      selected: selectedDuration,
                      allowsIndefinite: coordinator.allowsIndefinite) { duration in
                if isAwake {
                    coordinator.startKeepAwake(duration: duration)
                } else {
                    coordinator.preferences.keepAwakeDuration = duration
                }
            }

            if !coordinator.allowsIndefinite && showAllDurations {
                Label("Plug in for no time limit", systemImage: "powerplug.fill")
                    .font(Vg.Typo.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// While a session runs, show what it is *actually* doing rather than the
    /// stored preference — the two differ when an indefinite choice was capped
    /// because the Mac is on battery.
    private var selectedDuration: KeepAwakeDuration {
        coordinator.keepAwake.activeDuration ?? coordinator.preferences.keepAwakeDuration
    }

    private var isAwake: Bool { coordinator.keepAwake.isUserSessionActive }

    private var subtitleText: String {
        guard isAwake else { return "Your Mac sleeps normally" }

        // With no countdown on screen, the subtitle is what tells the user the
        // session is open-ended — and that it lasts only while on power.
        if coordinator.keepAwake.activeDuration?.isIndefinite == true {
            return "No time limit while plugged in"
        }
        return coordinator.preferences.keepDisplayOn
            ? "Mac and display staying on"
            : "Mac awake, display may sleep"
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VgCard(padding: Vg.Space.xs) {
            VStack(spacing: 1) {
                VgActionRow(
                    title: coordinator.cleaning.isActive ? "Exit Cleaning Mode" : "Cleaning Mode",
                    subtitle: "Block input so you can wipe it down",
                    systemImage: "hand.raised.fill",
                    tint: Vg.Tint.cleaning,
                    trailingText: shortcutText(.toggleCleaningMode),
                    isProminent: coordinator.cleaning.isActive
                ) { coordinator.toggleCleaningMode() }

                VgActionRow(
                    title: "Lock & Keep Awake",
                    subtitle: "Secure the screen, keep work running",
                    systemImage: "lock.display",
                    tint: Vg.Tint.lock,
                    trailingText: shortcutText(.lockAndKeepAwake)
                ) { coordinator.lockAndKeepAwake() }

                VgActionRow(
                    title: "Presentation Mode",
                    subtitle: "Display forced on",
                    systemImage: "rectangle.inset.filled.on.rectangle",
                    tint: Vg.Tint.awake
                ) { coordinator.startPresentationMode() }
            }
        }
    }

    private func shortcutText(_ action: HotKeyAction) -> String? {
        coordinator.preferences.hotKey(for: action)?.displayString
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Vg.Space.m) {
            if let percentage = coordinator.battery.percentage, !coordinator.battery.isOnAC {
                Label("\(percentage)%", systemImage: batterySymbol(percentage))
                    .font(Vg.Typo.caption)
                    .foregroundStyle(percentage <= coordinator.preferences.batteryGuardThreshold
                                     ? Vg.Tint.warning : .secondary)
            }

            if coordinator.preferences.usageLogEnabled {
                Text(coordinator.usageLog.todaySummary)
                    .font(Vg.Typo.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            FooterButton(systemImage: "gearshape.fill", help: "Preferences") {
                coordinator.openPreferences?()
            }
            FooterButton(systemImage: "power", help: "Quit Vigil") {
                NSApp.terminate(nil)
            }
        }
        .padding(.top, Vg.Space.xxs)
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case ..<15: return "battery.25"
        case ..<50: return "battery.50"
        case ..<85: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - Small pieces

/// Wraps duration chips onto as many rows as they need.
private struct FlowChips: View {
    let durations: [KeepAwakeDuration]
    let selected: KeepAwakeDuration
    let allowsIndefinite: Bool
    let onSelect: (KeepAwakeDuration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Vg.Space.xs) {
                    ForEach(row) { duration in
                        VgChip(label: duration.shortTitle,
                               isSelected: duration == selected,
                               tint: Vg.Tint.awake,
                               isEnabled: allowsIndefinite || !duration.isIndefinite,
                               disabledHelp: "Needs to be plugged in") {
                            onSelect(duration)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The two indefinite options are wordier, so they get their own row rather
    /// than being squeezed in beside the short ones.
    private var rows: [[KeepAwakeDuration]] {
        let timed = durations.filter { $0.seconds != nil }
        let openEnded = durations.filter { $0.seconds == nil }
        return [timed, openEnded].filter { !$0.isEmpty }
    }
}

private struct FooterButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

extension KeepAwakeDuration {
    /// Compact label for the chip row.
    var shortTitle: String {
        switch self {
        case .minutes15: return "15m"
        case .minutes30: return "30m"
        case .hour1: return "1h"
        case .hours4: return "4h"
        case .untilTurnedOff: return "Until off"
        case .untilAppQuits: return "Until quit"
        }
    }
}
