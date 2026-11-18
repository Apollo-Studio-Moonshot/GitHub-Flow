import SwiftUI

struct StandupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var range: StandupRange = .today

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "text.badge.checkmark",
                title: "Standup Digest",
                subtitle: "Commits across every repository you track."
            )

            Divider().opacity(0.6)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Picker("Range", selection: $range) {
                        ForEach(StandupRange.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)

                    Spacer()

                    if let standup = model.standup {
                        Text("\(standup.commits.count) commit\(standup.commits.count == 1 ? "" : "s") · \(standup.repositories.count) repo\(standup.repositories.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        model.copyStandup()
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled((model.standup?.commits.isEmpty ?? true))
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                content
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 680, height: 600)
        .background(Theme.canvas)
        .task {
            await model.loadStandup(range: range)
        }
        .onChange(of: range) { _, newValue in
            Task { await model.loadStandup(range: newValue) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingStandup && model.standup == nil {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let standup = model.standup, !standup.commits.isEmpty {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(standup.repositories, id: \.self) { repository in
                            repositorySection(
                                name: repository,
                                commits: standup.commits(in: repository)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    )
            )
        } else {
            EmptyStateView(
                systemName: "moon.zzz",
                title: "No commits in this range",
                message: "Try a wider range, or commit something first."
            )
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface.opacity(0.35))
            )
        }
    }

    private func repositorySection(name: String, commits: [StandupCommit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(name)
                    .font(.system(size: 11.5, weight: .semibold))
                Text("\(commits.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            ForEach(commits) { commit in
                HStack(alignment: .top, spacing: 8) {
                    InitialsAvatar(name: commit.author, size: 20)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(commit.subject)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Text(commit.author)
                            Text("·")
                            Text(commit.date.relativeDescription)
                            Text("·")
                            Text(commit.shortSHA)
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commit.sha, forType: .string)
                        model.showToast("Copied commit SHA")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy commit SHA")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
