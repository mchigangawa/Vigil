import SwiftUI

// MARK: - Tokens

/// Vigil's design tokens.
///
/// One place for spacing, radii, colour and type so every surface — the menu
/// panel, the overlay, preferences, onboarding — reads as the same product.
enum Vg {

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 7
        static let m: CGFloat = 11
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
    }

    /// State colours. Each mode owns a hue so the menu bar glyph, the panel and
    /// the overlay all agree at a glance about what Vigil is doing.
    enum Tint {
        /// Warm amber — "awake".
        static let awake = Color(red: 0.98, green: 0.64, blue: 0.16)
        /// Cool cyan — "hands off".
        static let cleaning = Color(red: 0.22, green: 0.72, blue: 0.88)
        /// Indigo — locked and secured.
        static let lock = Color(red: 0.45, green: 0.47, blue: 0.94)
        static let neutral = Color.secondary
        static let warning = Color(red: 0.96, green: 0.58, blue: 0.20)
    }

    enum Typo {
        static let title = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let body = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let micro = Font.system(size: 10, weight: .medium)
        /// Countdowns — monospaced digits so the layout never jitters as it ticks.
        static let timer = Font.system(size: 13, weight: .medium, design: .monospaced)
        static let bigTimer = Font.system(size: 26, weight: .medium, design: .rounded).monospacedDigit()
    }
}

// MARK: - Surfaces

/// A grouped container: soft material fill, hairline border, rounded corners.
struct VgCard<Content: View>: View {
    var padding: CGFloat = Vg.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Vg.Radius.m, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Vg.Radius.m, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

/// A small caps label used to head a group.
struct VgSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Vg.Typo.micro)
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Rows

/// A tappable row that lifts on hover.
///
/// `buttonStyle(.plain)` on macOS gives no hover affordance at all, which makes
/// a custom panel feel dead; this restores it without borrowing the heavy
/// bordered button chrome.
struct VgActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor
    var trailingText: String?
    var isProminent: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vg.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                        .fill(tint.opacity(isProminent ? 0.20 : 0.13))
                        .frame(width: 28, height: 28)
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Vg.Typo.rowTitle)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Vg.Typo.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Vg.Space.s)

                if let trailingText {
                    Text(trailingText)
                        .font(Vg.Typo.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, Vg.Space.s)
            .padding(.vertical, Vg.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Selectable chip, used for the duration picker.
struct VgChip: View {
    let label: String
    let isSelected: Bool
    var tint: Color = .accentColor
    var isEnabled: Bool = true
    /// Shown on hover when the chip is unavailable, to say why.
    var disabledHelp: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(isSelected && isEnabled ? 0 : 0.07),
                                      lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = isEnabled && $0 }
        .help(isEnabled ? "" : (disabledHelp ?? ""))
    }

    private var foreground: Color {
        guard isEnabled else { return Color.primary.opacity(0.28) }
        return isSelected ? Color.white : Color.primary.opacity(0.75)
    }

    private var fill: Color {
        guard isEnabled else { return Color.primary.opacity(0.03) }
        return isSelected ? tint : Color.primary.opacity(isHovering ? 0.10 : 0.05)
    }
}

/// Thin capsule progress track.
struct VgProgressBar: View {
    /// 0...1
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(colors: [tint.opacity(0.75), tint],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Compact state indicator for the panel header.
struct VgStatusPill: View {
    let text: String
    let tint: Color
    var isLive: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.35), lineWidth: isLive ? 3 : 0)
                )
            Text(text)
                .font(Vg.Typo.micro)
                .foregroundStyle(isLive ? tint : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isLive ? tint.opacity(0.12) : Color.primary.opacity(0.05))
        )
    }
}

/// An inline notice — used for the permission prompt and transient banners.
struct VgNotice: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Vg.Tint.warning
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    /// Extra explanatory line, shown smaller beneath the message.
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: Vg.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Vg.Typo.caption.weight(.semibold))
                Text(message)
                    .font(Vg.Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }

                HStack(spacing: Vg.Space.m) {
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.link)
                            .font(Vg.Typo.caption.weight(.medium))
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.link)
                            .font(Vg.Typo.caption.weight(.medium))
                    }
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(Vg.Space.s + 2)
        .background(
            RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Vg.Radius.s, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Helpers

extension View {
    /// Applies a transform only on the platforms/versions where it exists.
    @ViewBuilder
    func vgApply<V: View>(@ViewBuilder _ transform: (Self) -> V) -> some View {
        transform(self)
    }
}

extension TimeInterval {
    /// "1:04:09" / "4:09" — always monospace-friendly.
    var vgClockString: String {
        let total = Int(rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
