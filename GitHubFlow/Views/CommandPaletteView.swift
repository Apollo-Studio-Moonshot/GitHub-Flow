import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                searchField
                Divider().opacity(0.6)

                if filteredCommands.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No matching commands")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 46)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                PaletteRow(
                                    command: command,
                                    isSelected: index == safeIndex
                                ) {
                                    run(command)
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                }

                Divider().opacity(0.6)

                HStack(spacing: 12) {
                    Text("↑↓ navigate")
                    Text("↩ run")
                    Text("esc close")
                    Spacer()
                    Text("\(filteredCommands.count) command\(filteredCommands.count == 1 ? "" : "s")")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surface.opacity(0.4))
            }
            .frame(width: 580)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
            )
            .padding(.top, 72)
        }
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onExitCommand { close() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)

            TextField("Type a command or branch name…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFocused)
                .onSubmit { runFirst() }
                .onKeyPress(.downArrow) {
                    selectedIndex = min(safeIndex + 1, max(0, filteredCommands.count - 1))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectedIndex = max(0, safeIndex - 1)
                    return .handled
                }

            Text("⌘K")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - Commands

    private var allCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = []

        for tab in MainTab.allCases {
            commands.append(
                PaletteCommand(
                    id: "tab.\(tab.rawValue)",
                    title: "Show \(tab.title)",
                    subtitle: "Navigate to the \(tab.title) tab",
                    symbol: tab.symbol,
                    category: "Navigate"
                ) {
                    model.tab = tab
                }
            )
        }

        commands.append(
            PaletteCommand(
                id: "action.refresh",
                title: "Refresh Repository",
                subtitle: "Reload status, history, and the flow summary",
                symbol: "arrow.clockwise",
                category: "Repository"
            ) {
                Task { await model.refresh() }
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.fetch",
                title: "Fetch",
                subtitle: "Update remote-tracking branches",
                symbol: "arrow.triangle.2.circlepath",
                category: "Repository"
            ) {
                Task { await model.fetch() }
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.pull",
                title: "Pull",
                subtitle: "Fetch and merge the upstream branch",
                symbol: "arrow.down.to.line",
                category: "Repository"
            ) {
                Task { await model.pull() }
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.push",
                title: "Push",
                subtitle: "Publish local commits",
                symbol: "arrow.up.to.line",
                category: "Repository"
            ) {
                Task { await model.push() }
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.newBranch",
                title: "New Branch…",
                subtitle: "Create a short-lived branch",
                symbol: "arrow.triangle.branch",
                category: "Repository"
            ) {
                model.sheet = .newBranch
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.manageBranches",
                title: "Manage Branches…",
                subtitle: "Merge, rename, or delete branches",
                symbol: "list.bullet.indent",
                category: "Repository"
            ) {
                model.sheet = .manageBranches
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.manageRemotes",
                title: "Manage Remotes…",
                subtitle: "Add or edit remote URLs",
                symbol: "network",
                category: "Repository"
            ) {
                model.sheet = .manageRemotes
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.captureSnapshot",
                title: "Capture Safety Snapshot",
                subtitle: "Save the current working tree to the Safety Net",
                symbol: "camera",
                category: "Safety"
            ) {
                Task { await model.captureSnapshot() }
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.standup",
                title: "Standup Digest…",
                subtitle: "Summarize commits across every repository",
                symbol: "text.badge.checkmark",
                category: "Productivity"
            ) {
                model.sheet = .standup
            }
        )

        commands.append(
            PaletteCommand(
                id: "action.janitor",
                title: "Repository Janitor…",
                subtitle: "Find stale branches, large blobs, and ignore gaps",
                symbol: "wand.and.stars",
                category: "Productivity"
            ) {
                model.sheet = .janitor
            }
        )

        if model.flowSummary?.compareURL != nil {
            commands.append(
                PaletteCommand(
                    id: "action.openPR",
                    title: "Open Pull Request Page",
                    subtitle: "Open the hosting provider’s compare page",
                    symbol: "arrow.up.right.square",
                    category: "Flow"
                ) {
                    model.openFlowCompare()
                }
            )
        }

        if model.flowSummary != nil {
            commands.append(
                PaletteCommand(
                    id: "action.copyPR",
                    title: "Copy Pull Request Draft",
                    subtitle: "Copy the generated title and description",
                    symbol: "doc.on.doc",
                    category: "Flow"
                ) {
                    model.copyFlowPRBody()
                }
            )

            commands.append(
                PaletteCommand(
                    id: "action.explainBranch",
                    title: "Explain This Branch",
                    subtitle: "Generate an offline review narrative",
                    symbol: "text.bubble",
                    category: "Flow"
                ) {
                    Task { await model.explainBranch() }
                }
            )
        }

        for repository in model.repositories {
            commands.append(
                PaletteCommand(
                    id: "repo.\(repository.id.uuidString)",
                    title: "Switch to \(repository.name)",
                    subtitle: repository.path,
                    symbol: "folder",
                    category: "Repositories"
                ) {
                    model.selectedRepositoryID = repository.id
                }
            )
        }

        if let snapshot = model.snapshot {
            for branch in snapshot.localBranches where !branch.isCurrent {
                commands.append(
                    PaletteCommand(
                        id: "branch.\(branch.id)",
                        title: "Check Out \(branch.name)",
                        subtitle: branch.subject,
                        symbol: "arrow.triangle.branch",
                        category: "Branches"
                    ) {
                        Task { await model.switchBranch(branch) }
                    }
                )
            }

            for branch in snapshot.remoteBranches {
                commands.append(
                    PaletteCommand(
                        id: "remote.\(branch.id)",
                        title: "Check Out \(branch.name)",
                        subtitle: "Create a local tracking branch",
                        symbol: "arrow.down.right.and.arrow.up.left",
                        category: "Branches"
                    ) {
                        Task { await model.switchBranch(branch) }
                    }
                )
            }
        }

        return commands
    }

    private var filteredCommands: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allCommands }
        return allCommands.filter { command in
            command.title.localizedCaseInsensitiveContains(trimmed)
                || command.subtitle.localizedCaseInsensitiveContains(trimmed)
                || command.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var safeIndex: Int {
        guard !filteredCommands.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), filteredCommands.count - 1)
    }

    private func runFirst() {
        guard let command = filteredCommands.first else { return }
        run(command)
    }

    private func run(_ command: PaletteCommand) {
        close()
        command.action()
    }

    private func close() {
        model.showsCommandPalette = false
    }
}

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let category: String
    let action: () -> Void
}

private struct PaletteRow: View {
    let command: PaletteCommand
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(command.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(command.category)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.selectionFill : (isHovering ? Theme.hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) { isHovering = hovering }
        }
    }
}
