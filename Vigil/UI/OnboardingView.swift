import SwiftUI

/// First-run explanation, shown before macOS raises its own permission dialog.
struct OnboardingView: View {

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Divider()

            VStack(alignment: .leading, spacing: Vg.Space.l) {
                features
                permissionNote
            }
            .padding(Vg.Space.xl)

            Spacer(minLength: 0)
            Divider()
            actions
        }
        .frame(minWidth: 520, maxWidth: .infinity,
               minHeight: 520, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appear = true } }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: Vg.Space.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Vg.Radius.l, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Vg.Tint.awake.opacity(0.28),
                                                Vg.Tint.cleaning.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 62, height: 62)
                Image(systemName: "eye.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .scaleEffect(appear ? 1 : 0.86)
            .opacity(appear ? 1 : 0)

            VStack(alignment: .leading, spacing: 3) {
                Text("Vigil")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Menu bar controls for staying awake, cleaning up, and locking down.")
                    .font(Vg.Typo.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Vg.Space.xl)
    }

    // MARK: - Features

    private var features: some View {
        VStack(spacing: Vg.Space.s) {
            featureCard(icon: "moon.zzz.fill",
                        tint: Vg.Tint.awake,
                        title: "Keep Awake",
                        detail: "Stops your Mac sleeping for as long as you choose. Works right away \u{2014} no permission needed.")

            featureCard(icon: "hand.raised.fill",
                        tint: Vg.Tint.cleaning,
                        title: "Cleaning Mode",
                        detail: "Switches off the keyboard and trackpad so you can wipe the machine down. It always ends by itself on a timer, so you can't get locked out.")

            featureCard(icon: "lock.display",
                        tint: Vg.Tint.lock,
                        title: "Lock & Keep Awake",
                        detail: "Locks the screen while a long build or download keeps running.")
        }
    }

    private func featureCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        VgCard {
            HStack(alignment: .top, spacing: Vg.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Vg.Typo.rowTitle)
                    Text(detail)
                        .font(Vg.Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Permission

    private var permissionNote: some View {
        VgNotice(
            icon: "lock.shield.fill",
            title: "One permission to grant",
            message: "Cleaning Mode and Lock need Accessibility permission \u{2014} that's what lets Vigil intercept keystrokes and post the lock shortcut. macOS will ask you to allow it in System Settings. Vigil makes no network connections and stores nothing off this Mac.",
            tint: .accentColor,
            detail: AccessibilityPermission.staleGrantHint
        )
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Skip for now") {
                coordinator.preferences.hasCompletedOnboarding = true
                coordinator.closeOnboarding?()
            }
            .buttonStyle(.plain)
            .font(Vg.Typo.body)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                coordinator.preferences.hasCompletedOnboarding = true
                coordinator.permission.requestAccess()
                coordinator.closeOnboarding?()
            } label: {
                Text("Grant Accessibility\u{2026}")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Vg.Space.l)
    }
}
