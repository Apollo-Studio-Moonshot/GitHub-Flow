import Foundation

/// A thin, `async` wrapper around the `git` command line tool.
///
/// The client is an `actor` so all git invocations are serialized and the
/// types it returns can safely cross isolation domains.
actor GitClient {
    static let shared = GitClient()

    let executable: URL

    init(executable: URL = GitClient.locateGit()) {
        self.executable = executable
    }

    nonisolated static func locateGit() -> URL {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    nonisolated var isGitAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
    }

    func version() async -> String? {
        guard let result = try? await run(["--version"]) else { return nil }
        return result.stdoutTrimmed
    }

    // MARK: - Repository inspection

    func isRepository(_ url: URL) async -> Bool {
        guard let result = try? await run(["rev-parse", "--is-inside-work-tree"], in: url) else {
            return false
        }
        return result.succeeded && result.stdoutTrimmed == "true"
    }

    func snapshot(at url: URL) async throws -> RepoSnapshot {
        let rootResult = try await run(["rev-parse", "--show-toplevel"], in: url)
        guard rootResult.succeeded else {
            throw GitError.notARepository(url.path)
        }
        let root = URL(fileURLWithPath: rootResult.stdoutTrimmed)

        let headResult = try await run(
            ["rev-parse", "--verify", "--quiet", "HEAD"],
            in: root,
            allowFailure: true
        )
        let hasCommits = headResult.succeeded

        var branch = ""
        var isDetached = false
        if hasCommits {
            let branchResult = try await run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
            branch = branchResult.stdoutTrimmed
            isDetached = branch == "HEAD" || branch.isEmpty
            if isDetached { branch = "" }
        } else {
            // Unborn branch: HEAD is a symbolic ref to a branch that has no commits.
            let symbolic = try await run(["symbolic-ref", "--short", "HEAD"], in: root, allowFailure: true)
            branch = symbolic.succeeded ? symbolic.stdoutTrimmed : ""
        }

        let statusResult = try await run(
            ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            in: root,
            allowFailure: true
        )
        let changes = statusResult.succeeded ? GitParsing.parseStatus(statusResult.stdout) : []

        let branches = await ((try? self.branches(at: root)) ?? [])

        let remoteResult = try? await run(["remote"], in: root)
        let remoteNames = (remoteResult?.stdout ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        var hasUpstream = false
        var ahead = 0
        var behind = 0
        if hasCommits && !isDetached {
            let upstreamResult = try await run(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                in: root,
                allowFailure: true
            )
            hasUpstream = upstreamResult.succeeded && !upstreamResult.stdoutTrimmed.isEmpty
            if hasUpstream {
                let counts = try await run(
                    ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                    in: root,
                    allowFailure: true
                )
                let parts = counts.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
                if parts.count >= 2 {
                    behind = Int(parts[0]) ?? 0
                    ahead = Int(parts[1]) ?? 0
                }
            }
        }

        let operation = await detectOperation(in: root)
        let stashes = try await listStashes(at: root)

        return RepoSnapshot(
            rootPath: root.path,
            branch: branch,
            isDetached: isDetached,
            hasCommits: hasCommits,
            ahead: ahead,
            behind: behind,
            hasRemote: !remoteNames.isEmpty,
            remoteName: remoteNames.first,
            hasUpstream: hasUpstream,
            changes: changes,
            branches: branches,
            stashes: stashes,
            operation: operation
        )
    }

    func branches(at root: URL) async throws -> [BranchInfo] {
        let format = [
            "%(refname)",
            "%(refname:short)",
            "%(objectname:short)",
            "%(upstream:short)",
            "%(HEAD)",
            "%(committerdate:unix)",
            "%(contents:subject)"
        ].joined(separator: "%1f")

        let result = try await run(
            ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
            in: root,
            allowFailure: true
        )
        guard result.succeeded else { return [] }
        return GitParsing.parseBranches(result.stdout)
    }

    func history(at root: URL, limit: Int = 200) async throws -> [CommitInfo] {
        let format = ["%H", "%h", "%an", "%ae", "%at", "%P", "%D", "%s"].joined(separator: "%x1f")
        let result = try await run(
            ["log", "-z", "--date-order", "--max-count=\(limit)", "--pretty=format:\(format)"],
            in: root,
            allowFailure: true
        )
        guard result.succeeded else { return [] }
        return GitParsing.parseCommits(result.stdout)
    }

    func commitDetail(at root: URL, commit: CommitInfo) async throws -> CommitDetail {
        let bodyResult = try await run(["show", "-s", "--pretty=format:%b", commit.sha], in: root)

        // `git show` prints no patch for merge commits (it needs `-m`/`--cc`),
        // so diff a merge against its first parent to get a regular patch.
        let patchArguments: [String]
        if commit.isMerge, let firstParent = commit.parents.first {
            patchArguments = [
                "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "-U3",
                firstParent, commit.sha
            ]
        } else {
            patchArguments = [
                "-c", "core.quotePath=false", "show", "--format=", "--patch", "--no-color", "--no-ext-diff", "-U3", commit.sha
            ]
        }

        let patchResult = try await run(patchArguments, in: root, allowFailure: true)
        let files = patchResult.succeeded ? DiffParser.parse(patchResult.stdout) : []
        let body = bodyResult.succeeded ? bodyResult.stdoutTrimmed : ""
        return CommitDetail(commit: commit, body: body, files: files)
    }

    func workingDiff(at root: URL, change: FileChange, hasCommits: Bool) async throws -> [FileDiff] {
        if change.isUntracked {
            let result = try await run(
                ["-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--no-index", "-U3", "--", "/dev/null", change.path],
                in: root,
                allowFailure: true
            )
            let parsed = DiffParser.parse(result.stdout)
            return parsed.map { $0.replacingPath(change.path) }
        }

        // A staged change must be shown against HEAD, an unstaged change against
        // the index. Otherwise a partially staged file would show the same
        // combined diff for both of its rows.
        var arguments = [
            "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--find-renames", "-U3"
        ]
        if change.staged {
            arguments.append("--cached")
            if hasCommits { arguments.append("HEAD") }
        }
        arguments += ["--"] + change.affectedPaths

        let result = try await run(arguments, in: root, allowFailure: true)
        guard result.succeeded || result.exitCode == 1 else {
            throw GitError.commandFailed(command: "git diff", message: result.failureMessage)
        }

        var parsed = DiffParser.parse(result.stdout)
        if parsed.isEmpty {
            parsed = [FileDiff.empty(path: change.path, note: "No textual changes to display.")]
        }
        return parsed.map { $0.replacingPath(change.path) }
    }

    // MARK: - Staging

    func stage(paths: [String], at root: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(["add", "--all", "--"] + paths, in: root)
    }

    func unstage(paths: [String], at root: URL, hasCommits: Bool) async throws {
        guard !paths.isEmpty else { return }
        if hasCommits {
            _ = try await run(["restore", "--staged", "--"] + paths, in: root)
        } else {
            _ = try await run(
                ["rm", "--cached", "-r", "--force", "--ignore-unmatch", "--"] + paths,
                in: root,
                allowFailure: true
            )
        }
    }

    func discard(changes: [FileChange], at root: URL, hasCommits: Bool) async throws {
        for change in changes {
            for path in change.affectedPaths {
                if change.isUntracked {
                    _ = try await run(["clean", "-f", "-d", "--", path], in: root)
                } else if change.isAdded {
                    // New relative to HEAD: drop it from the index and delete the file.
                    _ = try await run(
                        ["rm", "--cached", "-r", "--force", "--ignore-unmatch", "--", path],
                        in: root,
                        allowFailure: true
                    )
                    let fileURL = root.appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                } else if hasCommits && (change.staged || change.isConflicted) {
                    _ = try await run(
                        ["restore", "--source=HEAD", "--staged", "--worktree", "--", path],
                        in: root
                    )
                } else if hasCommits {
                    // Only the working-tree side of a partly staged file: keep
                    // whatever the user already staged in the index.
                    _ = try await run(["restore", "--worktree", "--", path], in: root)
                } else {
                    _ = try await run(
                        ["rm", "--cached", "-r", "--force", "--ignore-unmatch", "--", path],
                        in: root,
                        allowFailure: true
                    )
                }
            }
        }
    }

    // MARK: - Stashes

    func listStashes(at root: URL) async throws -> [StashInfo] {
        let format = ["%gd", "%H", "%at", "%gs"].joined(separator: "%x1f")
        let result = try await run(
            ["stash", "list", "--format=\(format)"],
            in: root
        )
        guard !result.stdout.isEmpty else { return [] }

        return try result.stdout.split(separator: "\n").map { line in
            let fields = line.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4,
                  let timestamp = TimeInterval(fields[2]) else {
                throw GitError.commandFailed(
                    command: "git stash list",
                    message: "Git returned an invalid stash entry."
                )
            }
            return StashInfo(
                reference: String(fields[0]),
                sha: String(fields[1]),
                message: String(fields[3]),
                date: Date(timeIntervalSince1970: timestamp)
            )
        }
    }

    func createStash(message: String?, at root: URL) async throws {
        let previousStashes = try await listStashes(at: root)
        var arguments = ["stash", "push", "--include-untracked"]
        if let message, !message.isEmpty {
            arguments += ["--message", message]
        }
        _ = try await run(arguments, in: root)

        let currentStashes = try await listStashes(at: root)
        guard currentStashes.count > previousStashes.count else {
            throw GitError.invalidInput("There are no local changes to stash.")
        }
    }

    func applyStash(sha: String, at root: URL) async throws {
        _ = try await run(["stash", "apply", sha], in: root)
    }

    func popStash(sha: String, at root: URL) async throws {
        let stashes = try await listStashes(at: root)
        guard let stash = stashes.first(where: { $0.sha == sha }) else {
            throw GitError.invalidInput("This stash no longer exists.")
        }
        _ = try await run(["stash", "pop", stash.reference], in: root)
    }

    func dropStash(sha: String, at root: URL) async throws {
        let stashes = try await listStashes(at: root)
        guard let stash = stashes.first(where: { $0.sha == sha }) else {
            throw GitError.invalidInput("This stash no longer exists.")
        }
        _ = try await run(["stash", "drop", stash.reference], in: root)
    }

    // MARK: - Commit

    func commit(message: String, at root: URL, identity: GitIdentity?) async throws {
        var environment: [String: String] = [:]
        if let identity {
            if !identity.name.isEmpty {
                environment["GIT_AUTHOR_NAME"] = identity.name
                environment["GIT_COMMITTER_NAME"] = identity.name
            }
            if !identity.email.isEmpty {
                environment["GIT_AUTHOR_EMAIL"] = identity.email
                environment["GIT_COMMITTER_EMAIL"] = identity.email
            }
        }

        _ = try await run(
            ["-c", "commit.gpgsign=false", "commit", "--cleanup=whitespace", "-F", "-"],
            in: root,
            allowFailure: false,
            extraEnvironment: environment,
            input: message
        )
    }

    // MARK: - Branches

    func checkout(branch: String, at root: URL) async throws {
        _ = try await run(["switch", branch], in: root)
    }

    func checkoutRemote(fullName: String, localName: String, at root: URL) async throws {
        _ = try await run(["switch", "--track", "-c", localName, fullName], in: root)
    }

    func createBranch(name: String, at root: URL, checkout: Bool) async throws {
        if checkout {
            _ = try await run(["switch", "-c", name], in: root)
        } else {
            _ = try await run(["branch", name], in: root)
        }
    }

    // MARK: - Remotes

    func fetch(at root: URL) async throws {
        _ = try await run(["fetch", "--all", "--prune", "--quiet"], in: root)
    }

    func pull(at root: URL) async throws -> String {
        let result = try await run(["-c", "core.editor=true", "pull", "--no-rebase", "--no-edit"], in: root, allowFailure: true)
        guard result.succeeded else {
            throw GitError.commandFailed(command: "git pull", message: result.failureMessage)
        }
        let output = result.stdoutTrimmed
        if output.contains("Already up to date") || output.contains("Already up-to-date") {
            return "Already up to date"
        }
        return "Pulled changes from remote"
    }

    func push(at root: URL) async throws {
        _ = try await run(["-c", "push.default=simple", "push"], in: root)
    }

    func publish(branch: String, remote: String = "origin", at root: URL) async throws {
        _ = try await run(["push", "--set-upstream", remote, branch], in: root)
    }

    // MARK: - Commits, cloning, creation

    func revert(commit sha: String, at root: URL, identity: GitIdentity?, isMerge: Bool = false) async throws {
        var environment: [String: String] = [:]
        if let identity {
            if !identity.name.isEmpty {
                environment["GIT_AUTHOR_NAME"] = identity.name
                environment["GIT_COMMITTER_NAME"] = identity.name
            }
            if !identity.email.isEmpty {
                environment["GIT_AUTHOR_EMAIL"] = identity.email
                environment["GIT_COMMITTER_EMAIL"] = identity.email
            }
        }
        // Reverting a merge needs to know which parent is the mainline.
        var arguments = ["-c", "commit.gpgsign=false", "revert", "--no-edit"]
        if isMerge { arguments += ["-m", "1"] }
        arguments.append(sha)
        _ = try await run(arguments, in: root, extraEnvironment: environment)
    }

    func clone(remote: String, to destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try await run(["clone", "--progress", "--", remote, destination.path], in: nil)
    }

    func createRepository(at url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try await run(["init", "-b", "main", url.path], in: nil)
    }

    // MARK: - Helpers

    private func detectOperation(in root: URL) async -> RepoOperation? {
        let gitDirResult = try? await run(["rev-parse", "--absolute-git-dir"], in: root)
        let gitDir = URL(fileURLWithPath: gitDirResult?.stdoutTrimmed ?? root.appendingPathComponent(".git").path)

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: gitDir.appendingPathComponent(name).path)
        }

        if exists("MERGE_HEAD") { return .merge }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }

    @discardableResult
    private func run(
        _ arguments: [String],
        in directory: URL? = nil,
        allowFailure: Bool = false,
        extraEnvironment: [String: String] = [:],
        input: String? = nil
    ) async throws -> CommandResult {
        guard isGitAvailable else { throw GitError.gitNotFound }

        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: directory,
            environment: extraEnvironment,
            standardInput: input
        )

        if !allowFailure && !result.succeeded {
            throw GitError.commandFailed(
                command: "git " + arguments.joined(separator: " "),
                message: result.failureMessage
            )
        }

        return result
    }
}
