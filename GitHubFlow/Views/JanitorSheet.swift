import SwiftUI

struct JanitorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBranches: Set<String> = []
    @State private var selectedIgnores: Set<String> = []
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                symbol: "wand.and.stars",
                title: "Repository Janitor",
                subtitle: "Clean up stale branches, oversized history, and ignore gaps."
            )

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    branchesSection
                    largeObjectsSection
                    ignoresSection
                }
                .padding(18)
            }
        }
        .frame(width: 720, height: 620)
        .background(Theme.canvas)
        .task { await model.loadJanitor() }
        .confirmationDialog(
            "Delete \(selectedBranches.count) branch\(selectedBranches.count == 1 ? "" : "es")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Branches", role: .destructive) {
                let names = selectedBranches
                let branches = model.staleBranches.filter { names.contains($0.name) }
                selectedBranches.removeAll()
                Task { await model.deleteStaleBranches(branches) }
            }
        } message: {
            Text("A safety snapshot of each branch tip is kept in the Safety tab, so this can be undone.")
        }
    }

    // MARK: - Branches

    private var branchesSection: some View {
        section(
            title: "Stale branches",
            subtitle: "Merged or untouched for 30+ days.",
            symbol: "arrow.triangle.branch"
        ) {
            if model.isScanningJanitor && model.staleBranches.isEmpty {
                ProgressView().controlSize(.small).padding(.vertical, 16)
            } else if model.staleBranches.isEmpty {
                Text("No stale branches found.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(model.staleBranches) { branch in
                    HStack(spacing: 8) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { selectedBranches.contains(branch.name) },
                                set: { isOn in
                                    if isOn { selectedBranches.insert(branch.name) }
                                    else { selectedBranches.remove(branch.name) }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(branch.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Text(branch.subject)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Pill(text: branch.reason, tint: branch.isMerged ? Theme.success : Theme.warning)

                        Text(branch.date.relativeDescription)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)

                        Text(String(branch.sha.prefix(7)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }

                HStack {
                    Spacer()
                    Button {
                        showsDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete Selected (\(selectedBranches.count))",
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(selectedBranches.isEmpty || model.isBusy)
                }
            }
        }
    }

    // MARK: - Large objects

    private var largeObjectsSection: some View {
        section(
            title: "Large files in history",
            subtitle: "Blobs larger than 1 MB, largest first.",
            symbol: "externaldrive"
        ) {
            if !model.hasScannedLargeObjects {
                HStack(spacing: 10) {
                    Text("Scanning history can take a moment on large repositories.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.scanLargeObjects() }
                    } label: {
                        Label("Scan History", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isScanningJanitor)
                }
            } else if model.largeObjects.isEmpty {
                Text("No blobs over 1 MB found.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.largeObjects) { object in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.warning)
                            .frame(width: 14)
                        Text(object.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Self.byteText(object.size))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                Text("History rewriting is intentionally left to git; use this list to decide what to filter.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Ignore suggestions

    private var ignoresSection: some View {
        section(
            title: "Missing .gitignore entries",
            subtitle: "Common local clutter that is not ignored yet.",
            symbol: "eye.slash"
        ) {
            if model.ignoreSuggestions.isEmpty {
                Text("Nothing to add — your .gitignore already covers the usual suspects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.ignoreSuggestions) { suggestion in
                    HStack(spacing: 8) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { selectedIgnores.contains(suggestion.pattern) },
                                set: { isOn in
                                    if isOn { selectedIgnores.insert(suggestion.pattern) }
                                    else { selectedIgnores.remove(suggestion.pattern) }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Text(suggestion.pattern)
                            .font(.system(size: 11, design: .monospaced))
                        Text(suggestion.reason)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }

                HStack {
                    Spacer()
                    Button {
                        let patterns = selectedIgnores
                        let suggestions = model.ignoreSuggestions.filter { patterns.contains($0.pattern) }
                        selectedIgnores.removeAll()
                        Task { await model.applyIgnoreSuggestions(suggestions) }
                    } label: {
                        Label("Add to .gitignore (\(selectedIgnores.count))", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(selectedIgnores.isEmpty || model.isBusy)
                }
            }
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Theme.surface.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
        )
    }

    private static func byteText(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
