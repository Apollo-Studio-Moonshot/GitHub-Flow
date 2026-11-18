import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if model.repositories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No repositories")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Add Existing…") {
                        if let url = Pickers.chooseRepository() {
                            Task { await model.addExistingRepository(at: url) }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $model.selectedRepositoryID) {
                    Section {
                        ForEach(model.repositories) { repository in
                            RepositoryRow(
                                repository: repository,
                                isSelected: model.selectedRepositoryID == repository.id
                            )
                            .tag(repository.id)
                            .contextMenu {
                                Button("Reveal in Finder") { model.revealInFinder(repository) }
                                Button("Open in Terminal") { model.openInTerminal(repository) }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(repository.path, forType: .string)
                                }
                                Divider()
                                Button("Remove from List") { model.removeRepository(repository) }
                            }
                        }
                    } header: {
                        SectionLabel(text: "Repositories")
                            .padding(.leading, 2)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider().opacity(0.6)
            footer
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            RepoGlyph(size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("GitHub Flow")
                    .font(.system(size: 12, weight: .semibold))
                Text("Git client")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Button("Add Existing Repository…") {
                    if let url = Pickers.chooseRepository() {
                        Task { await model.addExistingRepository(at: url) }
                    }
                }
                Button("Clone Repository…") { model.sheet = .clone }
                Divider()
                Button("Create New Repository…") { model.sheet = .create }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.hoverFill)
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .help("Add a repository")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            SettingsLink {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("Settings")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(model.isGitAvailable ? Theme.success : Theme.danger)
                    .frame(width: 5, height: 5)
                Text(model.isGitAvailable ? "git ready" : "git missing")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct RepositoryRow: View {
    @Environment(AppModel.self) private var model

    let repository: RepositoryRef
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RepoGlyph(size: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(repository.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if !repository.existsOnDisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.warning)
                            .help("This folder no longer exists.")
                    }
                }

                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(repository.existsOnDisk ? Color.secondary.opacity(0.75) : Theme.warning)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if isSelected, let snapshot = model.snapshot, snapshot.hasChanges {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 6, height: 6)
                    .help("Uncommitted changes")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard repository.existsOnDisk else { return "Folder not found" }
        if isSelected, let snapshot = model.snapshot {
            return snapshot.branchDisplayName
        }
        return repository.lastOpened.relativeDescription
    }
}
