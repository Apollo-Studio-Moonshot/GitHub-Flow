import SwiftUI

/// Central design tokens. Everything is built on system colors so light and
/// dark mode come for free, with a signature indigo accent on top.
enum Theme {
    static let corner: CGFloat = 10
    static let cardCorner: CGFloat = 12

    static let accent = Color(red: 0.40, green: 0.36, blue: 0.92)
    static let accentSecondary = Color(red: 0.22, green: 0.58, blue: 0.95)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var field: Color { Color(nsColor: .textBackgroundColor) }
    static var hairline: Color { Color(nsColor: .separatorColor) }

    static var subtleFill: Color { Color.primary.opacity(0.045) }
    static var hoverFill: Color { Color.primary.opacity(0.07) }
    static var selectionFill: Color { accent.opacity(0.14) }

    static let success = Color(red: 0.16, green: 0.66, blue: 0.42)
    static let warning = Color(red: 0.94, green: 0.63, blue: 0.16)
    static let danger = Color(red: 0.90, green: 0.31, blue: 0.36)

    static let additionFill = Color(red: 0.20, green: 0.75, blue: 0.45).opacity(0.16)
    static let deletionFill = Color(red: 0.95, green: 0.33, blue: 0.36).opacity(0.15)
    static let hunkFill = accent.opacity(0.09)

    static let monoFont = Font.system(size: 11.5, weight: .regular, design: .monospaced)
}

extension ChangeKind {
    var tint: Color {
        switch self {
        case .added, .untracked: Theme.success
        case .modified: Theme.warning
        case .deleted: Theme.danger
        case .renamed, .copied: Theme.accentSecondary
        case .conflicted: Color(red: 0.93, green: 0.42, blue: 0.65)
        case .typeChanged: .purple
        }
    }
}

extension DiffLine.Kind {
    var fill: Color {
        switch self {
        case .addition: Theme.additionFill
        case .deletion: Theme.deletionFill
        case .context: .clear
        case .meta: Theme.hunkFill
        }
    }

    var gutterColor: Color {
        switch self {
        case .addition: Theme.success.opacity(0.9)
        case .deletion: Theme.danger.opacity(0.9)
        case .context: .clear
        case .meta: Theme.accent
        }
    }

    var marker: String {
        switch self {
        case .addition: "+"
        case .deletion: "−"
        case .context: " "
        case .meta: " "
        }
    }
}

// MARK: - Buttons

struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .shadow(color: tint.opacity(configuration.isPressed ? 0 : 0.25), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Reusable chrome

struct IconButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering && isEnabled ? Theme.hoverFill : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        let hue = Self.hue(for: name)
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.62, brightness: 0.94),
                            Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(Self.initials(from: name))
                .font(.system(size: max(9, size * 0.37), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    static func initials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        return parts.isEmpty ? "?" : parts.joined().uppercased()
    }

    static func hue(for name: String) -> Double {
        var total = 0
        for scalar in name.unicodeScalars {
            total = (total &* 31 &+ Int(scalar.value)) % 10_000
        }
        return Double(total % 360) / 360.0
    }
}

struct RepoGlyph: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.accentGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Theme.accent.opacity(0.28), radius: 5, y: 2)
    }
}

struct StatusLetter: View {
    let kind: ChangeKind

    var body: some View {
        Text(kind.letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(kind.tint)
            .frame(width: 15, height: 15)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(kind.tint.opacity(0.14))
            )
            .help(kind.label)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 8.5, weight: .bold))
            }
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct EmptyStateView: View {
    let systemName: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Appearance

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Dates

extension Date {
    /// "3 minutes ago"
    var relativeDescription: String {
        formatted(.relative(presentation: .named))
    }

    var absoluteDescription: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
