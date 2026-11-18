import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    RepoGlyph(size: 68)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)

                    VStack(spacing: 6) {
                        Text("GitHub Flow")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("A calmer, faster way to work with Git.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    WelcomeAction(
                        symbol: "folder.badge.plus",
                        title: "Add Existing",
                        subtitle: "Open a local repository",
                        tint: Theme.accentSecondary
                    ) {
                        if let url = Pickers.chooseRepository() {
                            Task { await model.addExistingRepository(at: url) }
                        }
                    }

                    WelcomeAction(
                        symbol: "arrow.down.circle",
                        title: "Clone",
                        subtitle: "Copy a remote repository",
                        tint: Theme.accent
                    ) {
                        model.sheet = .clone
                    }

                    WelcomeAction(
                        symbol: "plus.rectangle.on.folder",
                        title: "Create",
                        subtitle: "Start a new repository",
                        tint: Theme.success
                    ) {
                        model.sheet = .create
                    }
                }
                .frame(maxWidth: 620)

                if !model.repositories.isEmpty {
                    recentSection
                        .frame(maxWidth: 520)
                }

                if !model.isGitAvailable {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Git wasn’t found on this Mac. Install the Xcode Command Line Tools to continue.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.warning.opacity(0.1))
                    )
                }
            }
            .padding(40)
        }
    }

    private var backdrop: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Theme.accent.opacity(0.16), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 520
            )
            .blendMode(.plusLighter)
            .opacity(0.6)
        }
        .ignoresSafeArea()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Recent")
                .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(model.repositories.prefix(4)) { repository in
                    Button {
                        model.selectedRepositoryID = repository.id
                    } label: {
                        HStack(spacing: 9) {
                            RepoGlyph(size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(repository.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(repository.path)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RecentRowStyle())
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    )
            )
        }
    }
}

private struct RecentRowStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Theme.hoverFill : .clear)
            )
            .onHover { isHovering = $0 }
    }
}

private struct WelcomeAction: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(tint)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Theme.surface.opacity(isHovering ? 1 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .strokeBorder(isHovering ? tint.opacity(0.5) : Theme.hairline, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(isHovering ? 0.12 : 0.04), radius: isHovering ? 9 : 3, y: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }
}
