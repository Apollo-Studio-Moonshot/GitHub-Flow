import SwiftUI

struct RepositoryView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var tabAnimation

    var body: some View {
        VStack(spacing: 0) {
            RepositoryHeader()

            if let operation = model.snapshot?.operation {
                OperationBanner(operation: operation)
            }

            Divider().opacity(0.5)
            tabBar
            Divider().opacity(0.5)

            content
        }
        .background(Theme.canvas)
        .task(id: model.selectedRepositoryID) {
            await model.loadSelectedRepository()
        }
        .task {
            // Gentle background polling keeps status live when files change
            // outside the app, without a file-watcher dependency.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    break
                }
                await model.autoRefresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.selectedRepository?.existsOnDisk == false {
            EmptyStateView(
                systemName: "folder.badge.questionmark",
                title: "Repository not found",
                message: "The folder for this repository has moved or been deleted."
            )
        } else if model.snapshot == nil, model.isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.tab {
            case .changes:
                ChangesView()
            case .history:
                HistoryView()
            case .stashes:
                StashesView()
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(MainTab.allCases) { tab in
                SegmentButton(
                    tab: tab,
                    isSelected: model.tab == tab,
                    namespace: tabAnimation
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.tab = tab
                    }
                }
            }

            Spacer(minLength: 8)

            if let activity = model.activityLabel {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(activity)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct SegmentButton: View {
    @Environment(AppModel.self) private var model

    let tab: MainTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11.5, weight: .semibold))

                if tab == .changes, !model.allChanges.isEmpty {
                    Text("\(model.allChanges.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.accent : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.08))
                        )
                } else if tab == .stashes, !model.stashes.isEmpty {
                    Text("\(model.stashes.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.accent : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.08))
                        )
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OperationBanner: View {
    let operation: RepoOperation

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text("\(operation.title) — resolve conflicts, then commit to continue.")
                .font(.system(size: 10.5, weight: .medium))
            Spacer()
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.warning.opacity(0.1))
    }
}

struct RepositoryHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            RepoGlyph(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.repositoryName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if model.snapshot?.isDetached == true {
                        Pill(text: "detached", tint: Theme.warning)
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 8.5))
                    Text(model.selectedRepository?.path ?? "")
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let snapshot = model.snapshot, snapshot.hasUpstream {
                HStack(spacing: 5) {
                    if snapshot.ahead > 0 {
                        Pill(text: "\(snapshot.ahead) ahead", systemImage: "arrow.up", tint: Theme.accent)
                    }
                    if snapshot.behind > 0 {
                        Pill(text: "\(snapshot.behind) behind", systemImage: "arrow.down", tint: Theme.warning)
                    }
                }
            }

            syncControls

            if let snapshot = model.snapshot,
               snapshot.hasCommits,
               !snapshot.hasUpstream,
               snapshot.hasRemote,
               !snapshot.branch.isEmpty {
                Button("Publish") {
                    Task { await model.publishBranch() }
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(model.isBusy)
                .help("Publish “\(snapshot.branch)” to \(snapshot.remoteOrDefaultName)")
            }

            if let snapshot = model.snapshot, !snapshot.hasRemote {
                Button("Add Remote…") {
                    model.sheet = .manageRemotes
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isBusy)
                .help("Add a remote so you can push this repository")
            }

            BranchPicker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var syncControls: some View {
        HStack(spacing: 1) {
            IconButton(
                systemName: "arrow.triangle.2.circlepath",
                help: "Fetch (⇧⌘F)",
                isEnabled: canFetch
            ) {
                Task { await model.fetch() }
            }

            IconButton(
                systemName: "arrow.down.to.line",
                help: "Pull (⇧⌘P)",
                isEnabled: canSyncUpstream
            ) {
                Task { await model.pull() }
            }

            IconButton(
                systemName: "arrow.up.to.line",
                help: "Push (⌥⌘P)",
                isEnabled: canSyncUpstream
            ) {
                Task { await model.push() }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var canFetch: Bool {
        !model.isBusy && (model.snapshot?.hasRemote ?? false)
    }

    private var canSyncUpstream: Bool {
        canFetch && (model.snapshot?.hasUpstream ?? false)
    }
}

struct BranchPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if let snapshot = model.snapshot {
                if !snapshot.localBranches.isEmpty {
                    Section("Local branches") {
                        ForEach(snapshot.localBranches) { branch in
                            Button {
                                Task { await model.switchBranch(branch) }
                            } label: {
                                if branch.isCurrent {
                                    Label(branch.name, systemImage: "checkmark")
                                } else {
                                    Text(branch.name)
                                }
                            }
                            .disabled(branch.isCurrent)
                        }
                    }
                }

                if !snapshot.remoteBranches.isEmpty {
                    Section("Remote branches") {
                        ForEach(snapshot.remoteBranches) { branch in
                            Button {
                                Task { await model.switchBranch(branch) }
                            } label: {
                                Text(branch.name)
                            }
                        }
                    }
                }

                Divider()
            }

            Button("New Branch…") { model.sheet = .newBranch }
                .disabled(model.snapshot?.hasCommits == false)

            Divider()

            Button("Manage Branches…") { model.sheet = .manageBranches }
                .disabled(model.snapshot?.hasCommits == false)

            Button("Manage Remotes…") { model.sheet = .manageRemotes }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.currentBranchName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch branch")
    }
}
