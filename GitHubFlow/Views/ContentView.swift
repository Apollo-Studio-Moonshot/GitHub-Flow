import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 224, ideal: 252, max: 320)
        } detail: {
            detail
                .background(Theme.canvas)
        }
        .navigationTitle(model.selectedRepository?.name ?? "GitHub Flow")
        .task { await model.bootstrap() }
        .sheet(item: $model.sheet) { route in
            switch route {
            case .clone:
                CloneRepositorySheet()
            case .create:
                CreateRepositorySheet()
            case .newBranch:
                NewBranchSheet()
            case .manageBranches:
                BranchManagerSheet()
            case .manageRemotes:
                RemotesSheet()
            }
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: Binding(
                get: { model.pendingDiscard != nil },
                set: { if !$0 { model.pendingDiscard = nil } }
            ),
            presenting: model.pendingDiscard
        ) { change in
            Button("Discard Changes", role: .destructive) {
                Task { await model.discard(change) }
            }
        } message: { change in
            Text("Uncommitted changes to “\(change.path)” will be permanently discarded. This can’t be undone.")
        }
        .confirmationDialog(
            "Discard all changes?",
            isPresented: $model.showsDiscardAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard All Changes", role: .destructive) {
                Task { await model.discardAllChanges() }
            }
        } message: {
            Text("Every uncommitted change will be permanently deleted.")
        }
        .confirmationDialog(
            "Revert this commit?",
            isPresented: Binding(
                get: { model.pendingRevert != nil },
                set: { if !$0 { model.pendingRevert = nil } }
            ),
            presenting: model.pendingRevert
        ) { commit in
            Button("Revert Commit", role: .destructive) {
                Task { await model.revert(commit) }
            }
        } message: { commit in
            Text("A new commit will undo “\(commit.subject)”.")
        }
        .confirmationDialog(
            "Undo the last commit?",
            isPresented: $model.pendingUndoLastCommit,
            titleVisibility: .visible
        ) {
            Button("Undo Commit", role: .destructive) {
                Task { await model.undoLastCommit() }
            }
        } message: {
            Text("The commit will be removed, but its changes stay staged so you can edit and commit again.")
        }
        .confirmationDialog(
            "Drop this stash?",
            isPresented: Binding(
                get: { model.pendingStashDrop != nil },
                set: { if !$0 { model.pendingStashDrop = nil } }
            ),
            presenting: model.pendingStashDrop
        ) { stash in
            Button("Drop Stash", role: .destructive) {
                Task { await model.dropStash(stash) }
            }
        } message: { stash in
            Text("“\(stash.message)” will be permanently deleted.")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast.text)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.18), value: model.toast)
        .preferredColorScheme(model.settings.appearance.colorScheme)
    }

    @ViewBuilder
    private var detail: some View {
        if model.selectedRepository != nil {
            RepositoryView()
        } else {
            WelcomeView()
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        )
    }
}
