import SwiftUI

struct StashesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            saveToolbar
            Divider().opacity(0.6)

            if model.stashes.isEmpty {
                EmptyStateView(
                    systemName: "archivebox",
                    title: "No stashes yet",
                    message: "Save uncommitted changes here to restore them later."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.stashes) { stash in
                            StashRow(stash: stash)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Theme.canvas)
    }

    private var saveToolbar: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stashes")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save tracked and untracked changes for later.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(model.stashes.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Optional stash message", text: $model.stashMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.hairline, lineWidth: 0.75)
                    )
                    .onSubmit { Task { await model.saveStash() } }

                Button {
                    Task { await model.saveStash() }
                } label: {
                    Label("Save Stash", systemImage: "archivebox")
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(model.allChanges.isEmpty || model.isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.55))
    }
}

private struct StashRow: View {
    @Environment(AppModel.self) private var model

    let stash: StashInfo

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(stash.message)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text("\(stash.reference) · \(stash.date.relativeDescription) · \(stash.shortSHA)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            IconButton(
                systemName: "arrow.uturn.backward",
                help: "Apply stash",
                isEnabled: !model.isBusy
            ) {
                Task { await model.applyStash(stash) }
            }

            IconButton(
                systemName: "arrow.uturn.down",
                help: "Pop stash (apply and remove)",
                isEnabled: !model.isBusy
            ) {
                Task { await model.popStash(stash) }
            }

            IconButton(
                systemName: "trash",
                help: "Drop stash",
                tint: Theme.danger,
                isEnabled: !model.isBusy
            ) {
                model.pendingStashDrop = stash
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Theme.hoverFill : Theme.surface.opacity(0.42))
        )
        .onHover { isHovering = $0 }
    }
}
