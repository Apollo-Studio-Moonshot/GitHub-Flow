import SwiftUI

struct ChangesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                changeList
                Divider().opacity(0.6)
                CommitComposer()
            }
            .frame(minWidth: 300, idealWidth: 352, maxWidth: 480)
            .background(Theme.canvas)

            DiffPane(
                diffs: model.workingDiffs,
                fallbackTitle: model.selectedChange?.path,
                emptySymbol: "doc.text.magnifyingglass",
                emptyTitle: "Select a file",
                emptyMessage: "Choose a changed file to see what changed."
            )
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var changeList: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider().opacity(0.6)

            if model.allChanges.isEmpty {
                EmptyStateView(
                    systemName: "checkmark.seal",
                    title: "Working tree clean",
                    message: "There are no uncommitted changes in this repository."
                )
            } else if model.filteredStagedChanges.isEmpty && model.filteredUnstagedChanges.isEmpty {
                EmptyStateView(
                    systemName: "magnifyingglass",
                    title: "No matching files",
                    message: "Try a different filter."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !model.filteredStagedChanges.isEmpty {
                            ChangeGroupHeader(
                                title: "Staged",
                                count: model.filteredStagedChanges.count,
                                actionTitle: "Unstage All"
                            ) {
                                Task { await model.unstageAll() }
                            }

                            ForEach(model.filteredStagedChanges) { change in
                                ChangeRow(change: change)
                            }
                        }

                        if !model.filteredUnstagedChanges.isEmpty {
                            ChangeGroupHeader(
                                title: "Changes",
                                count: model.filteredUnstagedChanges.count,
                                actionTitle: "Stage All"
                            ) {
                                Task { await model.stageAll() }
                            }

                            ForEach(model.filteredUnstagedChanges) { change in
                                ChangeRow(change: change)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var listToolbar: some View {
        @Bindable var model = model

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Filter files", text: $model.changesSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !model.changesSearch.isEmpty {
                Button {
                    model.changesSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 12)

            IconButton(
                systemName: "trash",
                help: "Discard all changes",
                isEnabled: !model.allChanges.isEmpty && !model.isBusy
            ) {
                model.showsDiscardAllConfirmation = true
            }
            .frame(width: 22, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.surface.opacity(0.55))
    }
}

private struct ChangeGroupHeader: View {
    let title: String
    let count: Int
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            SectionLabel(text: title)

            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct ChangeRow: View {
    @Environment(AppModel.self) private var model

    let change: FileChange

    @State private var isHovering = false

    private var isSelected: Bool { model.selectedChangeID == change.id }

    var body: some View {
        HStack(spacing: 7) {
            Button {
                Task { await model.toggleStaging(change) }
            } label: {
                Image(systemName: change.staged ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(change.staged ? Theme.accent : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(change.staged ? "Unstage file" : "Stage file")

            Image(systemName: change.kind.symbolName)
                .font(.system(size: 10.5))
                .foregroundStyle(change.kind.tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(change.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(change.directoryPath.isEmpty ? " " : change.directoryPath)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if isHovering {
                Button {
                    model.pendingDiscard = change
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Discard changes")
                .transition(.opacity)
            }

            StatusLetter(kind: change.kind)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : (isHovering ? Theme.hoverFill : .clear))
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedChangeID = change.id
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}

struct CommitComposer: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isSummaryFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 8) {
            if model.isAmendingLastCommit {
                amendBanner
            }

            HStack(spacing: 8) {
                InitialsAvatar(name: displayName, size: 26)

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.isAmendingLastCommit ? "Amend last commit" : "Commit to \(model.currentBranchName)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(stagedSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                IconButton(
                    systemName: model.isDescriptionExpanded ? "chevron.down" : "text.alignleft",
                    help: model.isDescriptionExpanded ? "Hide description" : "Add a description"
                ) {
                    withAnimation(.snappy(duration: 0.16)) {
                        model.isDescriptionExpanded.toggle()
                    }
                    if model.isDescriptionExpanded {
                        isSummaryFocused = false
                    }
                }
                .frame(width: 22, height: 20)
            }

            TextField("Summary (required)", text: $model.commitSummary)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSummaryFocused)
                .onSubmit { Task { await model.commit() } }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(fieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSummaryFocused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 0.75)
                )

            if model.isDescriptionExpanded {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.commitDescription)
                        .font(.system(size: 11.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 56)

                    if model.commitDescription.isEmpty {
                        Text("Description")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .background(fieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.75)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task { await model.commit() }
            } label: {
                HStack(spacing: 6) {
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    }
                    Text(commitButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ProminentButtonStyle())
            .disabled(!model.canCommit || model.isBusy)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Commit staged changes (⌘↩)")
        }
        .padding(12)
        .background(Theme.surface.opacity(0.4))
    }

    private var amendBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            Text("Editing the most recent commit")
                .font(.system(size: 10.5, weight: .medium))
            Spacer()
            Button("Cancel") {
                model.cancelAmendLastCommit()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.accent.opacity(0.1))
        )
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.field)
    }

    private var displayName: String {
        let name = model.settings.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "You" : name
    }

    private var stagedSummary: String {
        let count = model.stagedChanges.count
        if count == 0 {
            return model.isAmendingLastCommit ? "Message only" : "No files staged"
        }
        return "\(count) file\(count == 1 ? "" : "s") staged"
    }

    private var commitButtonTitle: String {
        if model.isAmendingLastCommit { return "Amend Commit" }
        return model.stagedChanges.isEmpty
            ? "Commit"
            : "Commit \(model.stagedChanges.count) file\(model.stagedChanges.count == 1 ? "" : "s")"
    }
}
