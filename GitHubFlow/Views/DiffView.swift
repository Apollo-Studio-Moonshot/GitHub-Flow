import SwiftUI

/// Shows one or more file diffs with a fixed header and a scrollable body.
struct DiffPane: View {
    let diffs: [FileDiff]
    var fallbackTitle: String?
    var emptySymbol: String = "doc.text.magnifyingglass"
    var emptyTitle: String = "No changes"
    var emptyMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if diffs.count <= 1 {
                DiffHeader(
                    path: diffs.first?.path ?? fallbackTitle ?? "",
                    oldPath: diffs.first.flatMap { $0.oldPath == $0.newPath ? nil : $0.oldPath },
                    additions: totalAdditions,
                    deletions: totalDeletions,
                    isBinary: diffs.first?.isBinary ?? false
                )
                Divider().opacity(0.5)
            }

            if diffs.isEmpty {
                EmptyStateView(
                    systemName: emptySymbol,
                    title: emptyTitle,
                    message: emptyMessage
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffs) { diff in
                            if diffs.count > 1 {
                                DiffHeader(
                                    path: diff.path,
                                    oldPath: diff.oldPath == diff.newPath ? nil : diff.oldPath,
                                    additions: diff.additions,
                                    deletions: diff.deletions,
                                    isBinary: diff.isBinary
                                )
                                Divider().opacity(0.5)
                            }

                            if diff.isBinary {
                                EmptyStateView(
                                    systemName: "doc.zipper",
                                    title: "Binary file",
                                    message: "This file can’t be displayed as text."
                                )
                                .frame(height: 160)
                            } else if diff.hunks.isEmpty {
                                EmptyStateView(
                                    systemName: "equal.circle",
                                    title: diff.note ?? "No changes",
                                    message: nil
                                )
                                .frame(height: 160)
                            } else {
                                ForEach(diff.hunks) { hunk in
                                    HunkHeaderRow(header: hunk.header)
                                    ForEach(hunk.lines.indices, id: \.self) { index in
                                        DiffLineRow(line: hunk.lines[index])
                                    }
                                }
                                Color.clear.frame(height: 12)
                            }
                        }
                    }
                }
                .background(Theme.field.opacity(0.35))
            }
        }
    }

    private var totalAdditions: Int { diffs.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { diffs.reduce(0) { $0 + $1.deletions } }
}

struct DiffHeader: View {
    let path: String
    var oldPath: String?
    var additions: Int = 0
    var deletions: Int = 0
    var isBinary: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                if let oldPath, oldPath != path {
                    Text(oldPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                Text(path)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isBinary {
                Pill(text: "binary", tint: .secondary)
            } else {
                if additions > 0 {
                    Text("+\(additions)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.success)
                }
                if deletions > 0 {
                    Text("−\(deletions)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.7))
    }
}

struct HunkHeaderRow: View {
    let header: String

    var body: some View {
        Text(header)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hunkFill)
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            Text(line.newLine.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            Text(line.kind.marker)
                .foregroundStyle(markerColor)
                .frame(width: 16, alignment: .center)

            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .meta ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
        }
        .font(Theme.monoFont)
        .padding(.vertical, 0.5)
        .background(line.kind.fill)
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: Theme.success.opacity(0.85)
        case .deletion: Theme.danger.opacity(0.85)
        case .context, .meta: .clear
        }
    }
}
