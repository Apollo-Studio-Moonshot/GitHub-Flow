import Foundation

/// Pure, testable analysis used by the Flow Center. Kept free of git and UI so
/// the heuristics can be unit-tested directly.
enum FlowAnalyzer {
    // MARK: - Diff footprint

    /// Parses `git diff --numstat` output. Binary entries use `-` for both
    /// counts and are surfaced as binary files with zero line counts.
    static func parseNumstat(_ output: String) -> [ImpactFile] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { return nil }

                let path = String(parts[2])
                guard !path.isEmpty else { return nil }

                let isBinary = parts[0] == "-" || parts[1] == "-"
                let additions = Int(parts[0]) ?? 0
                let deletions = Int(parts[1]) ?? 0
                return impactFile(path: path, additions: additions, deletions: deletions, isBinary: isBinary)
            }
            .sorted { lhs, rhs in
                if lhs.changes != rhs.changes { return lhs.changes > rhs.changes }
                return lhs.path < rhs.path
            }
    }

    static func impactFile(
        path: String,
        additions: Int,
        deletions: Int,
        isBinary: Bool
    ) -> ImpactFile {
        let category = classify(path)
        let flags = flags(
            path: path,
            additions: additions,
            deletions: deletions,
            isBinary: isBinary,
            category: category
        )
        return ImpactFile(
            path: path,
            additions: additions,
            deletions: deletions,
            isBinary: isBinary,
            category: category,
            flags: flags
        )
    }

    static func classify(_ path: String) -> ImpactCategory {
        let lower = path.lowercased()
        let name = (path as NSString).lastPathComponent.lowercased()

        if lower.hasPrefix(".github/workflows/")
            || lower.hasPrefix(".github/actions/")
            || lower.hasPrefix(".gitlab/")
            || lower.contains("/ci/")
            || lower.hasPrefix("ci/")
            || name == "jenkinsfile"
            || name == ".gitlab-ci.yml"
            || name == ".travis.yml"
            || name == "azure-pipelines.yml" {
            return .ci
        }

        if lower.hasPrefix("migrations/")
            || lower.contains("/migrations/")
            || lower.contains("migration")
            || lower.contains("/schema")
            || lower.hasPrefix("schema")
            || name.hasSuffix(".sql") {
            return .migrations
        }

        let dependencyNames: Set<String> = [
            "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "podfile.lock",
            "go.sum", "cargo.lock", "poetry.lock", "gemfile.lock", "composer.lock",
            "package.json", "podfile", "gemfile", "go.mod", "cargo.toml",
            "pyproject.toml", "requirements.txt", "package.resolved"
        ]
        if name.hasSuffix(".lock") || dependencyNames.contains(name) {
            return .dependencies
        }

        if lower.contains("/test/")
            || lower.contains("/tests/")
            || lower.contains("/__tests__/")
            || lower.hasPrefix("test/")
            || lower.hasPrefix("tests/")
            || lower.hasPrefix("spec/")
            || name.hasSuffix("_test.go")
            || name.contains(".test.")
            || name.contains(".spec.")
            || name.hasPrefix("test_") {
            return .tests
        }

        if lower.hasPrefix("docs/")
            || lower.hasPrefix("doc/")
            || name.hasPrefix("readme")
            || name.hasPrefix("changelog")
            || name == "license"
            || name == "license.md"
            || [".md", ".mdx", ".rst", ".adoc"].contains(where: { name.hasSuffix($0) }) {
            return .docs
        }

        if name == "dockerfile"
            || name == "makefile"
            || name == ".gitignore"
            || name == ".gitattributes"
            || name == ".editorconfig"
            || name.hasPrefix(".env")
            || lower.hasPrefix(".github/")
            || [".yml", ".yaml", ".json", ".toml", ".ini", ".plist", ".conf", ".cfg", ".env"]
                .contains(where: { name.hasSuffix($0) }) {
            return .config
        }

        if lower.contains(".xcassets/")
            || [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".pdf",
                ".ttf", ".otf", ".woff", ".woff2", ".mp4", ".mov", ".mp3", ".wav"]
                .contains(where: { lower.hasSuffix($0) }) {
            return .assets
        }

        return .code
    }

    static func flags(
        path: String,
        additions: Int,
        deletions: Int,
        isBinary: Bool,
        category: ImpactCategory
    ) -> [String] {
        var result: [String] = []
        let lower = path.lowercased()
        let name = (path as NSString).lastPathComponent.lowercased()

        let secretNames: Set<String> = [
            ".env", ".env.local", ".env.production", ".npmrc", ".pypirc",
            "credentials", "credentials.json", "id_rsa", "id_ed25519"
        ]
        if secretNames.contains(name)
            || name.hasPrefix(".env")
            || lower.contains("secret")
            || lower.contains("credential")
            || name.hasSuffix(".pem")
            || name.hasSuffix(".key") {
            result.append("Possible secret")
        }

        if category == .migrations { result.append("Migration") }
        if category == .dependencies { result.append("Dependency change") }
        if isBinary { result.append("Binary") }
        if additions + deletions > 400 { result.append("Large diff") }
        return result
    }

    static func groups(from files: [ImpactFile]) -> [ImpactGroup] {
        ImpactCategory.allCases.compactMap { category in
            let matching = files.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }
            return ImpactGroup(
                category: category,
                files: matching.sorted { lhs, rhs in
                    if lhs.changes != rhs.changes { return lhs.changes > rhs.changes }
                    return lhs.path < rhs.path
                }
            )
        }
    }

    // MARK: - Readiness checks

    static func checks(
        isOnBase: Bool,
        ahead: Int,
        behind: Int,
        hasUpstream: Bool,
        uncommittedCount: Int,
        conflictRisk: Bool?,
        branchAgeDays: Int?,
        filesChanged: Int,
        additions: Int,
        deletions: Int
    ) -> [FlowCheck] {
        var result: [FlowCheck] = []

        if isOnBase {
            result.append(
                FlowCheck(
                    id: "base",
                    title: "Start from a feature branch",
                    detail: "You’re on the base branch. Create a short-lived branch before making changes.",
                    level: .warn
                )
            )
            result.append(
                FlowCheck(
                    id: "clean",
                    title: "Working tree is clean",
                    detail: uncommittedCount == 0
                        ? "No uncommitted changes."
                        : "\(uncommittedCount) uncommitted file\(uncommittedCount == 1 ? "" : "s") — commit or stash them first.",
                    level: uncommittedCount == 0 ? .pass : .warn
                )
            )
            result.append(
                FlowCheck(
                    id: "remote",
                    title: "Up to date with remote",
                    detail: behind == 0
                        ? "You’re not behind the upstream branch."
                        : "\(behind) commit\(behind == 1 ? "" : "s") behind upstream. Pull before branching.",
                    level: behind == 0 ? .pass : .warn
                )
            )
            return result
        }

        result.append(
            FlowCheck(
                id: "commits",
                title: "Has commits to ship",
                detail: ahead == 0
                    ? "This branch has no commits ahead of its base yet."
                    : "\(ahead) commit\(ahead == 1 ? "" : "s") ahead of base.",
                level: ahead > 0 ? .pass : .fail
            )
        )

        result.append(
            FlowCheck(
                id: "synced",
                title: "Up to date with base",
                detail: behind == 0
                    ? "No base commits are missing from this branch."
                    : "\(behind) commit\(behind == 1 ? "" : "s") behind base. Merge or rebase before opening a pull request.",
                level: behind == 0 ? .pass : .warn
            )
        )

        let conflictLevel: FlowCheckLevel
        let conflictDetail: String
        switch conflictRisk {
        case .some(false):
            conflictLevel = .pass
            conflictDetail = "A trial merge reports no conflicts."
        case .some(true):
            conflictLevel = .fail
            conflictDetail = "A trial merge reports conflicts. Resolve them before merging."
        case .none:
            conflictLevel = .warn
            conflictDetail = "The conflict check couldn’t run for this git version."
        }
        result.append(
            FlowCheck(id: "conflicts", title: "Merges without conflicts", detail: conflictDetail, level: conflictLevel)
        )

        result.append(
            FlowCheck(
                id: "upstream",
                title: "Published to remote",
                detail: hasUpstream
                    ? "The branch has an upstream, so a pull request can be opened."
                    : "Publish the branch before opening a pull request.",
                level: hasUpstream ? .pass : .warn
            )
        )

        result.append(
            FlowCheck(
                id: "clean",
                title: "Working tree is clean",
                detail: uncommittedCount == 0
                    ? "Everything is committed."
                    : "\(uncommittedCount) uncommitted file\(uncommittedCount == 1 ? "" : "s") — remember to include them or stash them.",
                level: uncommittedCount == 0 ? .pass : .warn
            )
        )

        let smallChanges = additions + deletions <= 800
        let smallFiles = filesChanged <= 20
        result.append(
            FlowCheck(
                id: "size",
                title: "Easy to review",
                detail: smallChanges && smallFiles
                    ? "\(filesChanged) file\(filesChanged == 1 ? "" : "s"), +\(additions) −\(deletions)."
                    : "\(filesChanged) files, +\(additions) −\(deletions). Large changes take longer to review and merge.",
                level: smallChanges && smallFiles ? .pass : .warn
            )
        )

        if let age = branchAgeDays {
            result.append(
                FlowCheck(
                    id: "age",
                    title: "Short-lived branch",
                    detail: age <= 7
                        ? "First commit was \(age) day\(age == 1 ? "" : "s") ago."
                        : "First commit was \(age) days ago. Long-lived branches drift from base.",
                    level: age <= 7 ? .pass : .warn
                )
            )
        }

        return result
    }

    // MARK: - Pull request copy

    static func prTitle(branch: String, subjects: [String]) -> String {
        if subjects.count == 1, let subject = subjects.first, !subject.isEmpty {
            return subject
        }
        return humanizedBranchName(branch)
    }

    static func humanizedBranchName(_ branch: String) -> String {
        let segment: String
        if let slash = branch.lastIndex(of: "/") {
            segment = String(branch[branch.index(after: slash)...])
        } else {
            segment = branch
        }

        let words = segment
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "Changes" }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func prBody(
        branch: String,
        base: String?,
        ahead: Int,
        behind: Int,
        groups: [ImpactGroup],
        subjects: [String],
        riskFlags: [String],
        additions: Int,
        deletions: Int,
        filesChanged: Int
    ) -> String {
        var lines: [String] = []

        let target = base.map { "`\($0)`" } ?? "the base branch"
        lines.append("## Summary")
        lines.append(
            "`\(branch)` is ready to merge into \(target) — \(ahead) commit\(ahead == 1 ? "" : "s"), "
                + "\(filesChanged) file\(filesChanged == 1 ? "" : "s") (+\(additions) −\(deletions))."
        )
        if behind > 0 {
            lines.append("")
            lines.append("> This branch is \(behind) commit\(behind == 1 ? "" : "s") behind base.")
        }

        lines.append("")
        lines.append("## Changes")
        if subjects.isEmpty {
            lines.append("- No commits ahead of base yet.")
        } else {
            for subject in subjects.prefix(12) {
                lines.append("- \(subject)")
            }
            if subjects.count > 12 {
                lines.append("- …and \(subjects.count - 12) more commit\(subjects.count - 12 == 1 ? "" : "s").")
            }
        }

        lines.append("")
        lines.append("## Impact")
        if groups.isEmpty {
            lines.append("- No file changes detected.")
        } else {
            for group in groups {
                lines.append(
                    "- **\(group.title)** — \(group.files.count) file\(group.files.count == 1 ? "" : "s") "
                        + "(+\(group.additions) −\(group.deletions))"
                )
            }
        }

        lines.append("")
        lines.append("## Risk")
        if riskFlags.isEmpty {
            lines.append("- No notable risks detected by the offline analysis.")
        } else {
            for flag in riskFlags {
                lines.append("- \(flag)")
            }
        }

        lines.append("")
        lines.append("## Testing")
        lines.append("- [ ] Ran the relevant test suite")
        lines.append("- [ ] Manually verified the changed areas")

        return lines.joined(separator: "\n")
    }

    // MARK: - Hosting links

    static func compareURL(remoteURL: String?, baseRef: String?, branch: String) -> String? {
        guard let remoteURL, let baseRef, !baseRef.isEmpty, !branch.isEmpty else { return nil }
        guard let location = parseRemote(remoteURL) else { return nil }

        let base = shortBaseName(baseRef)
        let encodedBase = encode(base)
        let encodedBranch = encode(branch)
        let repositoryURL = "https://\(location.host)/\(location.path)"

        if location.host.lowercased().contains("gitlab") {
            return "\(repositoryURL)/-/merge_requests/new"
                + "?merge_request%5Bsource_branch%5D=\(encodedBranch)"
                + "&merge_request%5Btarget_branch%5D=\(encodedBase)"
        }

        if location.host.lowercased().contains("bitbucket") {
            return "\(repositoryURL)/pull-requests/new?source=\(encodedBranch)&dest=\(encodedBase)"
        }

        return "\(repositoryURL)/compare/\(encodedBase)...\(encodedBranch)?expand=1"
    }

    /// "origin/main" -> "main"; leaves a plain branch name untouched.
    static func shortBaseName(_ ref: String) -> String {
        guard let slash = ref.firstIndex(of: "/") else { return ref }
        let prefix = String(ref[..<slash])
        let knownRemotes = ["origin", "upstream", "fork"]
        if knownRemotes.contains(prefix) || prefix.contains(".") {
            return String(ref[ref.index(after: slash)...])
        }
        return ref
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    static func parseRemote(_ remote: String) -> (host: String, path: String)? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var host = ""
        var path = ""

        if let atIndex = trimmed.firstIndex(of: "@"),
           let colonIndex = trimmed[atIndex...].firstIndex(of: ":") {
            host = String(trimmed[trimmed.index(after: atIndex)..<colonIndex])
            path = String(trimmed[trimmed.index(after: colonIndex)...])
        } else if let url = URL(string: trimmed), let urlHost = url.host {
            host = urlHost
            path = url.path
        } else {
            return nil
        }

        host = host.trimmingCharacters(in: .whitespaces)
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !host.isEmpty, !path.isEmpty else { return nil }
        return (host, path)
    }
}
