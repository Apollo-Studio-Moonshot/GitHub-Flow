import SwiftUI

struct SafetyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if model.recoverySnapshots.isEmpty {
                EmptyStateView(
                    systemName: "shield.lefthalf.filled",
                    title: "No safety snapshots",
                    message: "Before discarding, undoing, or deleting anything, GitHub Flow captures the state here so it can be restored."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.recoverySnapshots) { snapshot in
                            SnapshotRow(snapshot: snapshot)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.canvas)
        .task { await model.loadSnapshots() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Safety Net")
                    .font(.system(size: 14, weight: .semibold))
                Text("Destructive actions are reversible — snapshots live inside the repository.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.captureSnapshot() }
            } label: {
                Label("Capture Snapshot", systemImage: "camera")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isBusy)

            Button {
                Task { await model.loadSnapshots() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.55))
    }
}

private struct SnapshotRow: View {
    @Environment(AppModel.self) private var model

    let snapshot: RecoverySnapshot

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(snapshot.kind.title)
                    Text("·")
                    Text(snapshot.date.relativeDescription)
                    Text("·")
                    Text(snapshot.shortSHA)
                        .font(.system(size: 9, design: .monospaced))
                    if let branch = snapshot.branchName {
                        Text("·")
                        Text(branch)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isHovering {
                Button {
                    model.pendingSnapshotRestore = snapshot
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help(restoreHelp)

                Button {
                    model.pendingSnapshotDelete = snapshot
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .help("Delete snapshot")
            }

            Button {
                model.pendingSnapshotRestore = snapshot
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help(restoreHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Theme.hoverFill : Theme.surface.opacity(0.42))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
    }

    private var displayMessage: String {
        switch snapshot.kind {
        case .branch:
            if let branch = snapshot.branchName { return "Branch “\(branch)” before deletion" }
            return snapshot.message
        case .commit:
            return "Commit “\(snapshot.message)” before rewriting"
        case .workingTree:
            return snapshot.message
        }
    }

    private var restoreHelp: String {
        switch snapshot.kind {
        case .branch:
            return "Recreate the deleted branch at this commit"
        case .commit:
            return "Restore the commit state with a soft reset"
        case .workingTree:
            return "Restore the working tree from this snapshot"
        }
    }

    private var tint: Color {
        switch snapshot.kind {
        case .workingTree: Theme.accentSecondary
        case .commit: Theme.accent
        case .branch: Theme.success
        }
    }
}
