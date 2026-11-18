import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                searchBar
                Divider().opacity(0.6)

                if model.commits.isEmpty {
                    EmptyStateView(
                        systemName: "clock",
                        title: "No commits yet",
                        message: "Your first commit will appear here."
                    )
                } else if model.filteredCommits.isEmpty {
                    EmptyStateView(
                        systemName: "magnifyingglass",
                        title: "No matching commits",
                        message: "Try a different search."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.filteredCommits) { commit in
                                CommitRow(
                                    commit: commit,
                                    isSelected: model.selectedCommitSHA == commit.sha
                                )
                                .onTapGesture {
                                    model.selectedCommitSHA = commit.sha
                                }
                                .contextMenu {
                                    Button("Copy Commit SHA") { model.copySHA(commit) }
                                    Divider()
                                    Button("Revert Commit…") { model.pendingRevert = commit }
                                        .disabled(model.snapshot?.hasChanges == true)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .frame(minWidth: 296, idealWidth: 348, maxWidth: 460)
            .background(Theme.canvas)

            CommitDetailPane()
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchBar: some View {
        @Bindable var model = model

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search commits", text: $model.historySearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !model.historySearch.isEmpty {
                Button {
                    model.historySearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 12)

            Text("\(model.commits.count)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .help("Commits loaded")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.surface.opacity(0.55))
    }
}

private struct CommitRow: View {
    let commit: CommitInfo
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InitialsAvatar(name: commit.author, size: 23)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(commit.author)
                        .lineLimit(1)
                    Text("·")
                    Text(commit.date.relativeDescription)
                    if commit.isMerge {
                        Pill(text: "merge", tint: Theme.accentSecondary)
                    }
                    ForEach(Array(commit.refs.prefix(2)), id: \.self) { ref in
                        Pill(text: ref, tint: Theme.accent)
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(commit.shortSHA)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : (isHovering ? Theme.hoverFill : .clear))
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}

private struct CommitDetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let commit = model.selectedCommit {
                header(commit)
                Divider().opacity(0.5)

                if let detail = model.commitDetail {
                    if detail.files.isEmpty {
                        EmptyStateView(
                            systemName: "doc.text",
                            title: "No file changes",
                            message: "This commit doesn’t change any files."
                        )
                    } else {
                        fileChips(detail.files)
                        Divider().opacity(0.5)
                        DiffPane(
                            diffs: model.selectedCommitFile.map { [$0] } ?? [],
                            fallbackTitle: detail.files.first?.path,
                            emptyTitle: "Select a file",
                            emptyMessage: "Choose a file to see its changes in this commit."
                        )
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    systemName: "clock.arrow.circlepath",
                    title: "Select a commit",
                    message: "Pick a commit to see its details."
                )
            }
        }
    }

    private func header(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commit.subject)
                .font(.system(size: 14, weight: .semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let body = model.commitDetail?.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -2)
            }

            HStack(spacing: 7) {
                InitialsAvatar(name: commit.author, size: 18)

                Text(commit.author)
                    .font(.system(size: 10.5, weight: .medium))

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(commit.date.absoluteDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .help(commit.date.relativeDescription)

                Spacer()

                if commit.isMerge {
                    Pill(text: "merge commit", tint: Theme.accentSecondary)
                }

                Button {
                    model.copySHA(commit)
                } label: {
                    HStack(spacing: 3) {
                        Text(commit.shortSHA)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Copy full SHA")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileChips(_ files: [FileDiff]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(files) { file in
                    let isSelected = model.selectedCommitFileID == file.id
                    Button {
                        model.selectedCommitFileID = file.id
                    } label: {
                        HStack(spacing: 5) {
                            Text(letter(for: file))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(tint(for: file))
                            Text(file.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if file.additions > 0 {
                                Text("+\(file.additions)")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Theme.success)
                            }
                            if file.deletions > 0 {
                                Text("−\(file.deletions)")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Theme.selectionFill : Color.primary.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? Theme.accent.opacity(0.5) : .clear, lineWidth: 0.75)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(file.path)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Theme.surface.opacity(0.4))
    }

    private func letter(for file: FileDiff) -> String {
        if file.isNew { return "A" }
        if file.isDeleted { return "D" }
        if file.oldPath != file.newPath { return "R" }
        return "M"
    }

    private func tint(for file: FileDiff) -> Color {
        if file.isNew { return Theme.success }
        if file.isDeleted { return Theme.danger }
        if file.oldPath != file.newPath { return Theme.accentSecondary }
        return Theme.warning
    }
}
