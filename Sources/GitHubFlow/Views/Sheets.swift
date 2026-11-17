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
