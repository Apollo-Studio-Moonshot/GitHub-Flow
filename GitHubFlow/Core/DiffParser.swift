import Foundation

/// A small, dependency-free unified-diff parser.
enum DiffParser {
    static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var builder: FileBuilder?

        func flush() {
            if var builder {
                files.append(builder.build())
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git ") {
                flush()
                builder = FileBuilder(header: line)
                continue
            }

            builder?.consume(line)
        }

        flush()
        return files.filter { !$0.path.isEmpty }
    }

    private struct FileBuilder {
        var oldPath: String = ""
        var newPath: String = ""
        var isBinary = false
        var isNew = false
        var isDeleted = false
        var hunks: [DiffHunk] = []

        var hunkHeader: String?
        var hunkLines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var inHunk = false

        init(header: String) {
            let paths = Self.parseGitHeaderPaths(header)
            oldPath = paths.old
            newPath = paths.new
        }

        mutating func consume(_ line: String) {
            if line.hasPrefix("@@") {
                closeHunk()
                hunkHeader = line
                let starts = Self.parseHunkRange(line)
                oldLine = starts.old
                newLine = starts.new
                inHunk = true
                return
            }

            if inHunk {
                if line.hasPrefix("+") {
                    hunkLines.append(DiffLine(kind: .addition, text: String(line.dropFirst()), oldLine: nil, newLine: newLine))
                    newLine += 1
                    return
                }
                if line.hasPrefix("-") {
                    hunkLines.append(DiffLine(kind: .deletion, text: String(line.dropFirst()), oldLine: oldLine, newLine: nil))
                    oldLine += 1
                    return
                }
                if line.hasPrefix(" ") {
                    hunkLines.append(DiffLine(kind: .context, text: String(line.dropFirst()), oldLine: oldLine, newLine: newLine))
                    oldLine += 1
                    newLine += 1
                    return
                }
                if line.hasPrefix("\\") {
                    // "\ No newline at end of file" – informational only.
                    return
                }
                if line.isEmpty {
                    return
                }
                // Anything else ends the hunk (e.g. the next "diff --git" was handled above).
                closeHunk()
            }

            if line.hasPrefix("new file mode") {
                isNew = true
            } else if line.hasPrefix("deleted file mode") {
                isDeleted = true
            } else if line.hasPrefix("rename from ") {
                oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                newPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("copy from ") {
                oldPath = String(line.dropFirst("copy from ".count))
            } else if line.hasPrefix("copy to ") {
                newPath = String(line.dropFirst("copy to ".count))
            } else if line.hasPrefix("--- ") {
                let path = Self.parsePatchPath(String(line.dropFirst(4)))
                if path == "/dev/null" {
                    isNew = true
                } else if !path.isEmpty {
                    oldPath = path
                }
            } else if line.hasPrefix("+++ ") {
                let path = Self.parsePatchPath(String(line.dropFirst(4)))
                if path == "/dev/null" {
                    isDeleted = true
                } else if !path.isEmpty {
                    newPath = path
                }
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                isBinary = true
            }
        }

        mutating func closeHunk() {
            guard inHunk, let header = hunkHeader else {
                inHunk = false
                return
            }
            hunks.append(DiffHunk(id: hunks.count, header: header, lines: hunkLines))
            hunkLines = []
            hunkHeader = nil
            inHunk = false
        }

        mutating func build() -> FileDiff {
            closeHunk()
            let path = newPath.isEmpty ? oldPath : newPath
            let additions = hunks.reduce(0) { $0 + $1.additions }
            let deletions = hunks.reduce(0) { $0 + $1.deletions }

            var note: String?
            if hunks.isEmpty && !isBinary {
                if !oldPath.isEmpty && oldPath != path {
                    note = "Renamed without content changes."
                } else if isNew {
                    note = "New empty file."
                }
            }

            return FileDiff(
                oldPath: oldPath.isEmpty ? path : oldPath,
                newPath: path,
                isBinary: isBinary,
                isNew: isNew,
                isDeleted: isDeleted,
                hunks: hunks,
                additions: additions,
                deletions: deletions,
                note: note
            )
        }

        // MARK: Header parsing

        private static func parseGitHeaderPaths(_ header: String) -> (old: String, new: String) {
            // diff --git a/foo b/foo
            let remainder = header.dropFirst("diff --git ".count)
            guard let range = remainder.range(of: " b/", options: .backwards) else {
                return ("", "")
            }
            let old = stripPrefix(String(remainder[..<range.lowerBound]), prefix: "a/")
            let new = String(remainder[range.upperBound...])
            return (old, new)
        }

        private static func parsePatchPath(_ raw: String) -> String {
            var path = raw
            if let tabIndex = path.firstIndex(of: "\t") {
                path = String(path[..<tabIndex])
            }
            path = path.trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 {
                path = String(path.dropFirst().dropLast())
            }
            if path.hasPrefix("a/") || path.hasPrefix("b/") {
                path = String(path.dropFirst(2))
            }
            return path
        }

        private static func stripPrefix(_ value: String, prefix: String) -> String {
            value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
        }

        private static func parseHunkRange(_ header: String) -> (old: Int, new: Int) {
            var oldStart = 0
            var newStart = 0
            for token in header.split(separator: " ") {
                if token.hasPrefix("-") {
                    let value = token.dropFirst().split(separator: ",").first.map(String.init) ?? "0"
                    oldStart = Int(value) ?? 0
                } else if token.hasPrefix("+") {
                    let value = token.dropFirst().split(separator: ",").first.map(String.init) ?? "0"
                    newStart = Int(value) ?? 0
                }
            }
            return (oldStart, newStart)
        }
    }
}
