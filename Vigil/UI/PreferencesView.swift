import SwiftUI
import AppKit

/// Preferences, as a sidebar + detail pane rather than a tab strip — it scales
/// better as sections grow and matches how macOS settings read since Ventura.
struct PreferencesView: View {

    private enum Pane: String, CaseIterable, Identifiable {
        case general, cleaning, shortcuts, updates, privacy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .cleaning: return "Cleaning"
            case .shortcuts: return "Shortcuts"
            case .updates: return "Updates"
            case .privacy: return "Privacy"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .cleaning: return "hand.raised.fill"
            case .shortcuts: return "keyboard.fill"
            case .updates: return "arrow.down.circle.fill"
            case .privacy: return "hand.raised.square.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: return Vg.Tint.awake
            case .cleaning: return Vg.Tint.cleaning
            case .shortcuts: return Vg.Tint.lock
            case .updates: return Vg.Tint.cleaning
            case .privacy: return .secondary
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 560, maxWidth: .infinity,
               minHeight: 460, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xxs) {
            ForEach(Pane.allCases) { pane in
                SidebarRow(title: pane.title,
                           icon: pane.icon,
                           tint: pane.tint,
                           isSelected: selection == pane) {
                    selection = pane
                }
            }
            Spacer()
        }
        .padding(Vg.Space.s)
        .frame(width: 168)
        .background(.ultraThinMaterial)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Vg.Space.xl) {
                Text(selection.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                switch selection {
                case .general: GeneralPane()
                case .cleaning: CleaningPane()
                case .shortcuts: ShortcutsPane()
                case .updates: UpdatesPane()
                case .privacy: PrivacyPane()
                }
            }
            .padding(Vg.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let title: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vg.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(width: 18)
                Text(title)
                    .font(Vg.Typo.rowTitle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Vg.Space.s)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10)
                          : (isHovering ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Shared building blocks

/// A titled group of settings with an optional explanatory footnote.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.s) {
            VgSectionLabel(text: title)
            VgCard {
                VStack(alignment: .leading, spacing: Vg.Space.m) {
                    content
                }
            }
            if let footnote {
                Text(footnote)
                    .font(Vg.Typo.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Vg.Space.xs)
            }
        }
    }
}

/// Label on the left, control on the right — the standard settings rhythm.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Vg.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Vg.Typo.body)
                if let detail {
                    Text(detail)
                        .font(Vg.Typo.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Vg.Space.m)
            control
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xl) {
            SettingsGroup(
                title: "Keep Awake",
                footnote: "The no-limit options only apply while the Mac is plugged in. On battery they're capped at \(AppCoordinator.batteryFallbackDuration.title.lowercased()), and unplugging mid-session caps it from that moment."
            ) {
                SettingRow(title: "Default duration") {
                    Picker("", selection: Binding(
                        get: { coordinator.preferences.keepAwakeDuration },
                        set: { coordinator.preferences.keepAwakeDuration = $0 }
                    )) {
                        ForEach(KeepAwakeDuration.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Divider().opacity(0.5)

                SettingRow(title: "Keep the display on too",
                           detail: "Off lets the screen sleep while the Mac keeps running \u{2014} handy for a long download.") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.keepDisplayOn },
                        set: { coordinator.preferences.keepDisplayOn = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Vg.Tint.awake)
                }
            }

            SettingsGroup(
                title: "Lock & Keep Awake",
                footnote: "Locking uses the same duration as Keep Awake above, so a short default means your Mac sleeps when it runs out. Note that closing the lid still sleeps the Mac — no power assertion can prevent that."
            ) {
                SettingRow(title: "Keep the display on while locked",
                           detail: "A dark screen gives you no way to tell whether the Mac is awake or asleep.") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.lockKeepsDisplayOn },
                        set: { coordinator.preferences.lockKeepsDisplayOn = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Vg.Tint.lock)
                }
            }

            SettingsGroup(title: "Battery") {
                SettingRow(title: "Stand down when the battery is low") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.batteryGuardEnabled },
                        set: { coordinator.preferences.batteryGuardEnabled = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Vg.Tint.awake)
                }

                if coordinator.preferences.batteryGuardEnabled {
                    Divider().opacity(0.5)
                    SettingRow(title: "Threshold") {
                        HStack(spacing: Vg.Space.s) {
                            Text("\(coordinator.preferences.batteryGuardThreshold)%")
                                .font(Vg.Typo.timer)
                                .foregroundStyle(Vg.Tint.warning)
                                .frame(width: 38, alignment: .trailing)
                            Stepper("", value: Binding(
                                get: { coordinator.preferences.batteryGuardThreshold },
                                set: { coordinator.preferences.batteryGuardThreshold = $0 }
                            ), in: 5...50, step: 5)
                            .labelsHidden()
                        }
                    }
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingRow(title: "Menu bar icon") {
                    Picker("", selection: Binding(
                        get: { coordinator.preferences.iconStyle },
                        set: { coordinator.preferences.iconStyle = $0 }
                    )) {
                        ForEach(MenuBarIconStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }

            SettingsGroup(title: "Startup") {
                SettingRow(title: "Launch Vigil at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { newValue in
                            if case .failure(let error) = LaunchAtLogin.set(newValue) {
                                launchError = error.localizedDescription
                                launchAtLogin = LaunchAtLogin.isEnabled
                            } else {
                                launchError = nil
                            }
                        }
                }

                if LaunchAtLogin.needsApproval {
                    VgNotice(icon: "exclamationmark.circle.fill",
                             title: "Approval needed",
                             message: "macOS wants you to allow this in Login Items.",
                             actionTitle: "Open Login Items") {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                }
                if let launchError {
                    Text(launchError).font(Vg.Typo.caption).foregroundStyle(Vg.Tint.warning)
                }
            }

            SettingsGroup(
                title: "Presentation Mode",
                footnote: "macOS has no public way to toggle Do Not Disturb, so Presentation Mode runs a Shortcut you make in the Shortcuts app \u{2014} one that sets a Focus, for instance. Leave it blank and Presentation Mode simply keeps the display on."
            ) {
                SettingRow(title: "Focus Shortcut name") {
                    TextField("Optional", text: Binding(
                        get: { coordinator.preferences.presentationShortcutName },
                        set: { coordinator.preferences.presentationShortcutName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                }
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

// MARK: - Cleaning

private struct CleaningPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xl) {
            SettingsGroup(
                title: "Automatic exit",
                footnote: "Cleaning Mode always ends on its own after this long, whatever else happens. This is the safety net that guarantees you can never be locked out."
            ) {
                VStack(alignment: .leading, spacing: Vg.Space.s) {
                    HStack {
                        Text("Session length").font(Vg.Typo.body)
                        Spacer()
                        Text("\(Int(coordinator.preferences.cleaningAutoExitSeconds))s")
                            .font(Vg.Typo.timer)
                            .foregroundStyle(Vg.Tint.cleaning)
                    }
                    Slider(value: Binding(
                        get: { coordinator.preferences.cleaningAutoExitSeconds },
                        set: { coordinator.preferences.cleaningAutoExitSeconds = $0 }
                    ), in: 15...300, step: 5)
                    .tint(Vg.Tint.cleaning)
                }
            }

            SettingsGroup(
                title: "Exit gesture",
                footnote: "Press and hold the on-screen button this long to leave early. A longer hold is harder to trigger by accident while wiping the trackpad."
            ) {
                VStack(alignment: .leading, spacing: Vg.Space.s) {
                    HStack {
                        Text("Hold duration").font(Vg.Typo.body)
                        Spacer()
                        Text(String(format: "%.1fs", coordinator.preferences.cleaningExitHoldSeconds))
                            .font(Vg.Typo.timer)
                            .foregroundStyle(Vg.Tint.cleaning)
                    }
                    Slider(value: Binding(
                        get: { coordinator.preferences.cleaningExitHoldSeconds },
                        set: { coordinator.preferences.cleaningExitHoldSeconds = $0 }
                    ), in: 0.5...5, step: 0.5)
                    .tint(Vg.Tint.cleaning)
                }
            }

            SettingsGroup(title: "Permission") {
                HStack(spacing: Vg.Space.m) {
                    Image(systemName: coordinator.permission.isTrusted
                          ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(coordinator.permission.isTrusted ? .green : Vg.Tint.warning)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.permission.isTrusted
                             ? "Accessibility granted" : "Accessibility missing")
                            .font(Vg.Typo.rowTitle)
                        Text(coordinator.permission.isTrusted
                             ? "Cleaning Mode and Lock are ready to use."
                             : "Cleaning Mode and Lock can't run without it.")
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Vg.Space.s)

                    Button("System Settings\u{2026}") {
                        coordinator.permission.openSystemSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xl) {
            SettingsGroup(
                title: "Global shortcuts",
                footnote: "These work from any app. Each one needs at least one modifier key. Press Escape while recording to cancel."
            ) {
                VStack(spacing: Vg.Space.m) {
                    ForEach(Array(HotKeyAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 { Divider().opacity(0.5) }
                        HotKeyRecorderView(action: action)
                    }
                }
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xl) {
            SettingsGroup(title: "Notifications") {
                SettingRow(title: "Notify me when a mode starts or ends") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.notificationsEnabled },
                        set: { coordinator.preferences.notificationsEnabled = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsGroup(title: "Usage log") {
                SettingRow(title: "Keep a local count of how often I use each mode") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.usageLogEnabled },
                        set: { coordinator.preferences.usageLogEnabled = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if coordinator.preferences.usageLogEnabled {
                    Divider().opacity(0.5)
                    HStack {
                        Text(coordinator.usageLog.todaySummary)
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear log") { coordinator.usageLog.clear() }
                            .controlSize(.small)
                    }
                }
            }

            VgCard {
                HStack(alignment: .top, spacing: Vg.Space.m) {
                    Image(systemName: "lock.laptopcomputer")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What leaves this Mac").font(Vg.Typo.rowTitle)
                        Text("One thing, and only if you ask for it: update checks contact api.github.com to read Vigil's latest release. Nothing else. No accounts, no analytics, no telemetry. The usage log stays in your own user preferences and is off unless you turn it on.")
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}


// MARK: - Updates

private struct UpdatesPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    private var updates: UpdateManager { coordinator.updates }

    var body: some View {
        VStack(alignment: .leading, spacing: Vg.Space.xl) {
            SettingsGroup(title: "This copy") {
                SettingRow(title: "Version") {
                    Text(updates.currentVersion)
                        .font(Vg.Typo.timer)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.5)

                HStack(spacing: Vg.Space.m) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).font(Vg.Typo.rowTitle)
                        if !statusDetail.isEmpty {
                            Text(statusDetail)
                                .font(Vg.Typo.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Vg.Space.s)

                    if updates.isChecking || updates.isInstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check Now") {
                            Task { await coordinator.checkForUpdates() }
                        }
                        .controlSize(.small)
                    }
                }

                if let result = updates.result, result.hasUpdate {
                    Divider().opacity(0.5)
                    updateAvailable(result)
                }

                if let error = updates.errorMessage {
                    Divider().opacity(0.5)
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Vg.Typo.caption)
                        .foregroundStyle(Vg.Tint.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsGroup(
                title: "Automatic checks",
                footnote: "Checks GitHub for a new release at launch and once a day. This is the only time Vigil uses the network, which is why it is off unless you turn it on."
            ) {
                SettingRow(title: "Check for updates automatically") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.preferences.automaticUpdateChecks },
                        set: { coordinator.preferences.automaticUpdateChecks = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Vg.Tint.cleaning)
                }

                if let last = coordinator.preferences.lastUpdateCheck {
                    Divider().opacity(0.5)
                    SettingRow(title: "Last checked") {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if updates.isRunningFromDerivedData {
                VgNotice(icon: "hammer.fill",
                         title: "Running a build from Xcode",
                         message: "Installing an update would overwrite this build product, and your next \u{2318}R would replace it again. Export the app to /Applications to use in-place updates.",
                         tint: Vg.Tint.warning)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if updates.isInstalling {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18)).foregroundStyle(Vg.Tint.cleaning)
        } else if let result = updates.result, result.hasUpdate {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 18)).foregroundStyle(Vg.Tint.cleaning)
        } else if updates.result != nil {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18)).foregroundStyle(.green)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        if let stage = updates.stage { return stage }
        if updates.isChecking { return "Checking\u{2026}" }
        guard let result = updates.result else { return "Not checked yet" }
        return result.hasUpdate ? "Vigil \(result.latestVersion) is available" : "You're up to date"
    }

    private var statusDetail: String {
        if updates.isInstalling { return "Vigil will quit and reopen when this finishes." }
        guard let result = updates.result else { return "" }
        return result.hasUpdate
            ? "You're running \(result.currentVersion)."
            : "\(result.currentVersion) is the newest release."
    }

    private func updateAvailable(_ result: UpdateCheckResult) -> some View {
        VStack(alignment: .leading, spacing: Vg.Space.s) {
            if let notes = result.releaseNotes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(Vg.Typo.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            }

            HStack(spacing: Vg.Space.s) {
                Button("Install and Relaunch") {
                    Task { await updates.install() }
                }
                .controlSize(.small)
                .disabled(!updates.canInstall)

                Button("Release Notes\u{2026}") {
                    NSWorkspace.shared.open(result.releaseNotesURL)
                }
                .controlSize(.small)

                Spacer()
            }

            if result.downloadURL == nil {
                Text("That release has no downloadable build attached, so it can't be installed automatically.")
                    .font(Vg.Typo.caption)
                    .foregroundStyle(Vg.Tint.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
