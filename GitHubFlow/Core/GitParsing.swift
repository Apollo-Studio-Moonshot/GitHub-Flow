import Foundation

enum GitParsing {
    // MARK: - Status

    /// Parses `git status --porcelain=v1 -z` output.
    static func parseStatus(_ output: String) -> [FileChange] {
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var changes: [FileChange] = []
        var index = 0

        while index < entries.count {
            let entry = entries[index]
            index += 1
            guard entry.count > 3 else { continue }

            let characters = Array(entry)
            let x = characters[0]
            let y = characters[1]
            guard characters[2] == " " else { continue }

            let path = String(characters.dropFirst(3))
            var originalPath: String?

            if x == "R" || x == "C" || y == "R" || y == "C" {
                if index < entries.count {
                    let candidate = entries[index]
                    if !candidate.isEmpty {
                        originalPath = candidate
                        index += 1
                    }
                }
            }

            if x == "?" && y == "?" {
                changes.append(FileChange(path: path, originalPath: nil, kind: .untracked, staged: false))
                continue
            }

            if isConflicted(x: x, y: y) {
                changes.append(FileChange(path: path, originalPath: originalPath, kind: .conflicted, staged: false))
                continue
            }

            if let kind = changeKind(for: x) {
                changes.append(FileChange(path: path, originalPath: originalPath, kind: kind, staged: true))
            }
            if let kind = changeKind(for: y) {
                changes.append(FileChange(path: path, originalPath: originalPath, kind: kind, staged: false))
            }
        }

        return changes.sorted { lhs, rhs in
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.staged && !rhs.staged
        }
    }

    private static func isConflicted(x: Character, y: Character) -> Bool {
        x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D")
    }

    private static func changeKind(for status: Character) -> ChangeKind? {
        switch status {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        default: nil
        }
    }

    // MARK: - Log

    static func parseCommits(_ output: String) -> [CommitInfo] {
        output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 8 else { return nil }

                let parents = fields[5].split(separator: " ").map(String.init)
                return CommitInfo(
                    sha: fields[0],
                    shortSHA: fields[1],
                    author: fields[2],
                    email: fields[3],
                    date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0),
                    parents: parents,
                    decorations: fields[6],
                    subject: fields[7]
                )
            }
    }

    // MARK: - Branches

    static func parseBranches(_ output: String) -> [BranchInfo] {
        var branches: [BranchInfo] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { continue }

            let refName = fields[0]
            if refName.hasSuffix("/HEAD") { continue }

            branches.append(
                BranchInfo(
                    name: fields[1],
                    sha: fields[2],
                    upstream: fields[3].isEmpty ? nil : fields[3],
                    isCurrent: fields[4] == "*",
                    isRemote: refName.hasPrefix("refs/remotes/"),
                    lastCommitDate: Date(timeIntervalSince1970: TimeInterval(fields[5]) ?? 0),
                    subject: fields[6]
                )
            )
        }

        return branches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
