import SwiftUI

// MARK: - Clone

struct CloneRepositorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var remote = ""
    @State private var destination = Self.defaultDestination()
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "arrow.down.circle",
                title: "Clone a Repository",
                subtitle: "Copy a repository from a URL or a path on this Mac."
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "Repository URL")
                TextField("https://github.com/owner/repo.git", text: $remote)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(isWorking)

                FieldLabel(text: "Location")
                HStack(spacing: 8) {
                    Text(destination.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.field)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 0.5)
                        )

                    Button("Choose…") { chooseFolder() }
                        .disabled(isWorking)
                }

                if let name = derivedName {
                    Text("Clones into \(destination.appendingPathComponent(name).path)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let errorText {
                    ErrorBox(text: errorText)
                }
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cloning…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                Button {
                    startClone()
                } label: {
                    Text("Clone")
                }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canClone || isWorking)
            }
            .padding(14)
        }
        .frame(width: 500)
    }

    private var canClone: Bool {
        derivedName != nil
    }

    private var derivedName: String? {
        var path = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        while path.hasSuffix("/") { path.removeLast() }
        let component = (path as NSString).lastPathComponent
        guard !component.isEmpty, component != ".git" else { return nil }
        if component.hasSuffix(".git") {
            return String(component.dropLast(4))
        }
        return component
    }

    private func chooseFolder() {
        if let url = Pickers.chooseDirectory(prompt: "Choose", message: "Choose where to clone the repository.") {
            destination = url
        }
    }

    private func startClone() {
        guard let name = derivedName else {
            errorText = "Enter a repository URL."
            return
        }

        isWorking = true
        errorText = nil

        Task {
            do {
                _ = try await model.cloneRepository(
                    remote: remote.trimmingCharacters(in: .whitespacesAndNewlines),
                    into: destination,
                    name: name
                )
                isWorking = false
                dismiss()
            } catch {
                isWorking = false
                errorText = (error as? GitError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static func defaultDestination() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("GitHub", isDirectory: true)
    }
}

// MARK: - Create

struct CreateRepositorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destination = Self.defaultDestination()
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "plus.rectangle.on.folder",
                title: "Create a Repository",
                subtitle: "Start a new Git repository in a folder of your choice."
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "Name")
                TextField("my-project", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(isWorking)

                FieldLabel(text: "Location")
                HStack(spacing: 8) {
                    Text(destination.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.field)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 0.5)
                        )

                    Button("Choose…") { chooseFolder() }
                        .disabled(isWorking)
                }

                Text("The repository starts empty on the “main” branch.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                if let errorText {
                    ErrorBox(text: errorText)
                }
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text("Creating…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                Button {
                    create()
                } label: {
                    Text("Create Repository")
                }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isWorking)
            }
            .padding(14)
        }
        .frame(width: 500)
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.contains(":")
    }

    private func chooseFolder() {
        if let url = Pickers.chooseDirectory(prompt: "Choose", message: "Choose where to create the repository.") {
            destination = url
        }
    }

    private func create() {
        isWorking = true
        errorText = nil
        let repoName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                _ = try await model.createRepository(named: repoName, in: destination)
                isWorking = false
                dismiss()
            } catch {
                isWorking = false
                errorText = (error as? GitError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static func defaultDestination() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("GitHub", isDirectory: true)
    }
}

// MARK: - New branch

struct NewBranchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var switchToNewBranch = true
    @State private var isWorking = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "arrow.triangle.branch",
                title: "New Branch",
                subtitle: "Create a branch from \(model.currentBranchName)."
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "Branch name")
                TextField("feature/my-change", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isNameFocused)
                    .onSubmit { create() }
                    .disabled(isWorking)

                Toggle("Switch to the new branch", isOn: $switchToNewBranch)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .disabled(isWorking)
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                Button {
                    create()
                } label: {
                    Text("Create Branch")
                }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            .padding(14)
        }
        .frame(width: 440)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        let branchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else { return }

        isWorking = true
        Task {
            let created = await model.createBranch(named: branchName, checkout: switchToNewBranch)
            isWorking = false
            if created { dismiss() }
        }
    }
}

// MARK: - Branches

struct BranchManagerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showsNewBranch = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            SheetHeader(
                symbol: "arrow.triangle.branch",
                title: "Branches",
                subtitle: "Merge, rename, or delete local branches."
            )

            Divider()

            if let snapshot = model.snapshot, !snapshot.localBranches.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(snapshot.localBranches) { branch in
                            BranchManagerRow(branch: branch)
                        }
                    }
                    .padding(10)
                }
            } else {
                EmptyStateView(
                    systemName: "arrow.triangle.branch",
                    title: "No branches yet",
                    message: "Make your first commit to start creating branches."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    showsNewBranch = true
                } label: {
                    Label("New Branch", systemImage: "plus")
                }
                .disabled(model.snapshot?.hasCommits == false || model.isBusy)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540, height: 460)
        .sheet(isPresented: $showsNewBranch) {
            NewBranchSheet()
        }
        .sheet(item: $model.pendingBranchRename) { branch in
            RenameBranchSheet(branch: branch)
        }
        .confirmationDialog(
            "Delete this branch?",
            isPresented: Binding(
                get: { model.pendingBranchDelete != nil },
                set: { if !$0 { model.pendingBranchDelete = nil } }
            ),
            presenting: model.pendingBranchDelete
        ) { branch in
            Button("Delete Branch", role: .destructive) {
                Task { await model.deleteBranch(branch) }
            }
        } message: { branch in
            Text("“\(branch.name)” will be permanently deleted, including any commits that aren’t on another branch.")
        }
    }
}

private struct BranchManagerRow: View {
    @Environment(AppModel.self) private var model

    let branch: BranchInfo

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(branch.isCurrent ? Theme.accent : Color.secondary.opacity(0.6))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(branch.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    if branch.isCurrent {
                        Pill(text: "current", tint: Theme.accent)
                    }
                }

                Text(branch.subject.isEmpty ? "No commits" : branch.subject)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Merge into \(model.currentBranchName)") {
                    Task { await model.merge(branch) }
                }
                .disabled(branch.isCurrent || model.isBusy)

                Button("Rename…") { model.pendingBranchRename = branch }
                    .disabled(model.isBusy)

                Divider()

                Button("Delete…", role: .destructive) { model.pendingBranchDelete = branch }
                    .disabled(branch.isCurrent || model.isBusy)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Theme.hoverFill : Theme.surface.opacity(0.42))
        )
        .onHover { isHovering = $0 }
    }
}

struct RenameBranchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let branch: BranchInfo

    @State private var name: String
    @State private var isWorking = false
    @FocusState private var isFocused: Bool

    init(branch: BranchInfo) {
        self.branch = branch
        _name = State(initialValue: branch.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "pencil",
                title: "Rename Branch",
                subtitle: "Rename “\(branch.name)”."
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "New name")
                TextField("new-name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onSubmit { rename() }
                    .disabled(isWorking)
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                Button("Rename") { rename() }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename || isWorking)
            }
            .padding(14)
        }
        .frame(width: 440)
        .onAppear { isFocused = true }
    }

    private var canRename: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != branch.name
    }

    private func rename() {
        guard canRename else { return }
        isWorking = true
        Task {
            let succeeded = await model.renameBranch(branch, to: name)
            isWorking = false
            if succeeded { dismiss() }
        }
    }
}

// MARK: - Remotes

struct RemotesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var editingRemote: GitRemote?
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "network",
                title: "Remotes",
                subtitle: "Manage the URLs this repository fetches from and pushes to."
            )

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if model.remotes.isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("This repository has no remotes yet. Add one to fetch, pull, and push.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.remotes) { remote in
                                remoteRow(remote)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Divider()

                FieldLabel(text: editingRemote == nil ? "Add a remote" : "Edit “\(editingRemote?.name ?? "")”")

                HStack(spacing: 8) {
                    TextField("origin", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 110)
                        .disabled(editingRemote != nil || isWorking)

                    TextField("https://github.com/owner/repo.git", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .disabled(isWorking)
                }

                if let errorText {
                    ErrorBox(text: errorText)
                }

                HStack(spacing: 8) {
                    if editingRemote != nil {
                        Button("Cancel Edit") { resetForm() }
                            .disabled(isWorking)
                    }

                    Spacer()

                    Button(editingRemote == nil ? "Add Remote" : "Save Changes") {
                        submit()
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(!canSubmit || isWorking)
                }
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540)
        .task { await model.loadRemotes() }
    }

    private func remoteRow(_ remote: GitRemote) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "network")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(remote.name)
                    .font(.system(size: 11.5, weight: .medium))
                Text(remote.url)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            IconButton(systemName: "pencil", help: "Edit remote", isEnabled: !isWorking) {
                beginEditing(remote)
            }

            IconButton(
                systemName: "trash",
                help: "Remove remote",
                tint: Theme.danger,
                isEnabled: !isWorking
            ) {
                Task {
                    isWorking = true
                    await model.removeRemote(remote)
                    isWorking = false
                    if editingRemote == remote { resetForm() }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface.opacity(0.42))
        )
    }

    private var canSubmit: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (editingRemote != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func beginEditing(_ remote: GitRemote) {
        editingRemote = remote
        name = remote.name
        url = remote.url
        errorText = nil
    }

    private func resetForm() {
        editingRemote = nil
        name = ""
        url = ""
        errorText = nil
    }

    private func submit() {
        isWorking = true
        errorText = nil

        Task {
            if let editingRemote {
                let succeeded = await model.updateRemoteURL(editingRemote, url: url)
                isWorking = false
                if succeeded { resetForm() }
            } else {
                let succeeded = await model.addRemote(name: name, url: url)
                isWorking = false
                if succeeded { resetForm() }
            }
        }
    }
}

// MARK: - Shared sheet chrome

struct SheetHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.accent.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.4))
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct ErrorBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.danger)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.danger.opacity(0.1))
        )
    }
}
