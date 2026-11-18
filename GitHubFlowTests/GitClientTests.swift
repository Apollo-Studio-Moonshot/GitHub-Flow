import Foundation
import XCTest

@testable import GitHubFlow

final class GitClientTests: XCTestCase {
    private var repoURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubflow-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Test Runner"])
        try git(["config", "user.email", "tests@example.com"])
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        repoURL = nil
        try super.tearDownWithError()
    }

    func testSnapshotAndStagingFlow() async throws {
        let client = GitClient()

        try write("one\ntwo\n", to: "hello.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.hasCommits)
        XCTAssertFalse(snapshot.hasChanges)
        XCTAssertEqual(snapshot.localBranches.count, 1)

        try write("one\nTWO\n", to: "hello.txt")
        try write("brand new\n", to: "untracked.txt")

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.changes.count, 2)
        XCTAssertTrue(snapshot.changes.contains { $0.path == "untracked.txt" && $0.kind == .untracked })
        XCTAssertTrue(snapshot.changes.contains { $0.path == "hello.txt" && !$0.staged })

        // Diff of the untracked file should be a pure addition.
        let untrackedChange = try XCTUnwrap(snapshot.changes.first { $0.path == "untracked.txt" })
        let untrackedDiff = try await client.workingDiff(
            at: repoURL,
            change: untrackedChange,
            hasCommits: true
        )
        XCTAssertEqual(untrackedDiff.first?.additions, 1)

        // Stage everything and verify the index side shows up.
        try await client.stage(paths: ["hello.txt", "untracked.txt"], at: repoURL)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.stagedChanges.count, 2)
        XCTAssertTrue(snapshot.unstagedChanges.isEmpty)

        // Commit and inspect history + commit detail.
        try await client.commit(message: "Update files", at: repoURL, identity: nil)

        let history = try await client.history(at: repoURL)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].subject, "Update files")

        let detail = try await client.commitDetail(at: repoURL, commit: history[0])
        XCTAssertEqual(detail.files.count, 2)
        XCTAssertEqual(detail.body, "")

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.hasChanges)
    }

    func testUnstageAndDiscard() async throws {
        let client = GitClient()

        try write("a\n", to: "tracked.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("b\n", to: "tracked.txt")
        try write("new\n", to: "scratch.txt")
        try git(["add", "--all"])

        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.stagedChanges.count, 2)

        try await client.unstage(paths: ["tracked.txt", "scratch.txt"], at: repoURL, hasCommits: true)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertTrue(snapshot.stagedChanges.isEmpty)
        XCTAssertEqual(snapshot.unstagedChanges.count, 2)

        try await client.discard(
            changes: [try XCTUnwrap(snapshot.changes.first { $0.path == "scratch.txt" })],
            at: repoURL,
            hasCommits: true
        )

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.changes.contains { $0.path == "scratch.txt" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("scratch.txt").path))
    }

    func testDiscardStagedNewFile() async throws {
        let client = GitClient()

        try write("a\n", to: "keep.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("new\n", to: "added.txt")
        try git(["add", "--all"])

        var snapshot = try await client.snapshot(at: repoURL)
        let added = try XCTUnwrap(snapshot.changes.first { $0.path == "added.txt" })
        XCTAssertEqual(added.kind, .added)
        XCTAssertTrue(added.staged)

        try await client.discard(changes: [added], at: repoURL, hasCommits: true)

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.changes.contains { $0.path == "added.txt" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("added.txt").path))
    }

    func testWorkingDiffSeparatesStagedAndUnstagedChanges() async throws {
        let client = GitClient()

        try write("one\ntwo\nthree\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("one\nTWO\nthree\n", to: "file.txt")
        try git(["add", "file.txt"])
        try write("one\nTWO\nTHREE\n", to: "file.txt")

        let snapshot = try await client.snapshot(at: repoURL)
        let staged = try XCTUnwrap(snapshot.stagedChanges.first { $0.path == "file.txt" })
        let unstaged = try XCTUnwrap(snapshot.unstagedChanges.first { $0.path == "file.txt" })

        let stagedDiffs = try await client.workingDiff(at: repoURL, change: staged, hasCommits: true)
        let unstagedDiffs = try await client.workingDiff(at: repoURL, change: unstaged, hasCommits: true)
        let stagedDiff = try XCTUnwrap(stagedDiffs.first)
        let unstagedDiff = try XCTUnwrap(unstagedDiffs.first)

        let stagedText = stagedDiff.hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")
        let unstagedText = unstagedDiff.hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")
        let unstagedAdditions = unstagedDiff.hunks.flatMap(\.lines).filter { $0.kind == .addition }.map(\.text)
        let unstagedDeletions = unstagedDiff.hunks.flatMap(\.lines).filter { $0.kind == .deletion }.map(\.text)

        XCTAssertEqual(stagedDiff.additions, 1)
        XCTAssertEqual(stagedDiff.deletions, 1)
        XCTAssertTrue(stagedText.contains("TWO"))
        XCTAssertFalse(stagedText.contains("THREE"))

        XCTAssertEqual(unstagedDiff.additions, 1)
        XCTAssertEqual(unstagedDiff.deletions, 1)
        XCTAssertTrue(unstagedText.contains("THREE"))
        XCTAssertEqual(unstagedAdditions, ["THREE"])
        XCTAssertEqual(unstagedDeletions, ["three"])
    }

    func testDiscardUnstagedChangeKeepsStagedChange() async throws {
        let client = GitClient()

        try write("a\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("staged\n", to: "file.txt")
        try git(["add", "file.txt"])
        try write("unstaged\n", to: "file.txt")

        var snapshot = try await client.snapshot(at: repoURL)
        let unstaged = try XCTUnwrap(snapshot.unstagedChanges.first { $0.path == "file.txt" })

        try await client.discard(changes: [unstaged], at: repoURL, hasCommits: true)

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.stagedChanges.count, 1)
        XCTAssertTrue(snapshot.unstagedChanges.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repoURL.appendingPathComponent("file.txt"), encoding: .utf8),
            "staged\n"
        )
    }

    func testMergeCommitDetailIncludesFiles() async throws {
        let client = GitClient()

        try write("base\n", to: "base.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Base"])

        try git(["checkout", "-q", "-b", "feature"])
        try write("feature\n", to: "feature.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Feature"])

        try git(["checkout", "-q", "main"])
        try write("main\n", to: "main.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Main"])

        try git(["merge", "-q", "--no-ff", "-m", "Merge feature", "feature"])

        let history = try await client.history(at: repoURL)
        let mergeCommit = try XCTUnwrap(history.first)
        XCTAssertTrue(mergeCommit.isMerge)

        let detail = try await client.commitDetail(at: repoURL, commit: mergeCommit)
        XCTAssertEqual(detail.files.map(\.path), ["feature.txt"])
    }

    func testPublishToNonOriginRemote() async throws {
        let client = GitClient()
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubflow-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: bareURL) }

        try runGit(["init", "-q", "--bare", bareURL.path], in: FileManager.default.temporaryDirectory)

        try write("a\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])
        try git(["remote", "add", "upstream", bareURL.path])

        try await client.publish(branch: "main", remote: "upstream", at: repoURL)

        let output = try runGit(
            ["--git-dir", bareURL.path, "rev-parse", "--verify", "refs/heads/main"],
            in: FileManager.default.temporaryDirectory
        )
        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testEmptyRepositorySnapshot() async throws {
        let client = GitClient()
        let snapshot = try await client.snapshot(at: repoURL)

        XCTAssertFalse(snapshot.hasCommits)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.changes.isEmpty)

        let history = try await client.history(at: repoURL)
        XCTAssertTrue(history.isEmpty)
    }

    func testCommitIdentityOverride() async throws {
        let client = GitClient()

        try write("a\n", to: "file.txt")
        try await client.stage(paths: ["file.txt"], at: repoURL)
        try await client.commit(
            message: "Authored by app identity",
            at: repoURL,
            identity: GitIdentity(name: "App User", email: "app@example.com")
        )

        let history = try await client.history(at: repoURL)
        XCTAssertEqual(history.first?.author, "App User")
        XCTAssertEqual(history.first?.email, "app@example.com")
    }

    func testBranchCreationAndCheckout() async throws {
        let client = GitClient()

        try write("a\n", to: "file.txt")
        try await client.stage(paths: ["file.txt"], at: repoURL)
        try await client.commit(message: "Initial", at: repoURL, identity: nil)

        try await client.createBranch(name: "feature", at: repoURL, checkout: true)
        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.branch, "feature")

        try await client.checkout(branch: "main", at: repoURL)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.branch, "main")
    }

    func testStashManagementIncludesUntrackedAndSupportsApplyPopAndDrop() async throws {
        let client = GitClient()

        try write("original\n", to: "tracked.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("updated\n", to: "tracked.txt")
        try write("new\n", to: "untracked.txt")
        try await client.createStash(message: "Saved work", at: repoURL)

        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertTrue(snapshot.changes.isEmpty)
        XCTAssertEqual(snapshot.stashes.count, 1)
        let stash = try XCTUnwrap(snapshot.stashes.first)
        XCTAssertTrue(stash.message.contains("Saved work"))
        XCTAssertEqual(stash.reference, "stash@{0}")

        try await client.applyStash(sha: stash.sha, at: repoURL)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(Set(snapshot.changes.map(\.path)), ["tracked.txt", "untracked.txt"])
        XCTAssertEqual(snapshot.stashes.count, 1)

        try git(["reset", "--hard", "HEAD"])
        try git(["clean", "-fd"])
        try await client.popStash(sha: stash.sha, at: repoURL)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(Set(snapshot.changes.map(\.path)), ["tracked.txt", "untracked.txt"])
        XCTAssertTrue(snapshot.stashes.isEmpty)

        try await client.createStash(message: nil, at: repoURL)
        let remainingStashes = try await client.listStashes(at: repoURL)
        let droppedStash = try XCTUnwrap(remainingStashes.first)
        try await client.dropStash(sha: droppedStash.sha, at: repoURL)

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertTrue(snapshot.stashes.isEmpty)
        XCTAssertTrue(snapshot.changes.isEmpty)
    }

    func testBranchRenameDeleteAndMerge() async throws {
        let client = GitClient()

        try write("base\n", to: "base.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Base"])

        try await client.createBranch(name: "feature", at: repoURL, checkout: true)
        try write("feature\n", to: "feature.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Feature"])

        try await client.checkout(branch: "main", at: repoURL)
        try write("main\n", to: "main.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Main"])

        let cleanMerge = try await client.merge(branch: "feature", at: repoURL, identity: nil)
        XCTAssertTrue(cleanMerge)

        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.hasChanges)
        XCTAssertNil(snapshot.operation)

        try await client.createBranch(name: "temp", at: repoURL, checkout: false)
        try await client.renameBranch(from: "temp", to: "renamed", at: repoURL)

        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertTrue(snapshot.localBranches.contains { $0.name == "renamed" })
        XCTAssertFalse(snapshot.localBranches.contains { $0.name == "temp" })

        try await client.deleteBranch("renamed", at: repoURL, force: true)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.localBranches.contains { $0.name == "renamed" })
    }

    func testMergeConflictReportsOperation() async throws {
        let client = GitClient()

        try write("base\n", to: "shared.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Base"])

        try git(["checkout", "-q", "-b", "feature"])
        try write("feature\n", to: "shared.txt")
        try git(["commit", "-q", "-am", "Feature edit"])

        try git(["checkout", "-q", "main"])
        try write("main\n", to: "shared.txt")
        try git(["commit", "-q", "-am", "Main edit"])

        let cleanMerge = try await client.merge(branch: "feature", at: repoURL, identity: nil)
        XCTAssertFalse(cleanMerge)

        let snapshot = try await client.snapshot(at: repoURL)
        XCTAssertEqual(snapshot.operation, .merge)
        XCTAssertTrue(snapshot.changes.contains { $0.kind == .conflicted })
    }

    func testAmendAndUndoLastCommit() async throws {
        let client = GitClient()

        try write("one\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial"])

        try write("two\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Second"])

        try await client.amendCommit(message: "Second, amended", at: repoURL, identity: nil)
        var history = try await client.history(at: repoURL)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.subject, "Second, amended")

        try await client.undoLastCommit(at: repoURL)
        history = try await client.history(at: repoURL)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.subject, "Initial")

        var snapshot = try await client.snapshot(at: repoURL)
        XCTAssertTrue(snapshot.stagedChanges.contains { $0.path == "file.txt" })

        // Undoing the root commit leaves an unborn branch with staged changes.
        try await client.undoLastCommit(at: repoURL)
        history = try await client.history(at: repoURL)
        XCTAssertTrue(history.isEmpty)
        snapshot = try await client.snapshot(at: repoURL)
        XCTAssertFalse(snapshot.hasCommits)
    }

    func testCherryPickCommit() async throws {
        let client = GitClient()

        try write("base\n", to: "base.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Base"])

        try git(["checkout", "-q", "-b", "feature"])
        try write("picked\n", to: "picked.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Pick me"])
        let featureSHA = try runGit(["rev-parse", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try git(["checkout", "-q", "main"])
        try write("main\n", to: "main.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Main"])

        let cleanPick = try await client.cherryPick(commit: featureSHA, at: repoURL, identity: nil)
        XCTAssertTrue(cleanPick)

        let history = try await client.history(at: repoURL)
        XCTAssertEqual(history.first?.subject, "Pick me")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("picked.txt").path))
    }

    func testRemoteManagement() async throws {
        let client = GitClient()

        try await client.addRemote(name: "origin", url: "https://example.com/first.git", at: repoURL)
        var remotes = try await client.remotes(at: repoURL)
        XCTAssertEqual(remotes, [GitRemote(name: "origin", url: "https://example.com/first.git")])

        try await client.setRemoteURL(name: "origin", url: "https://example.com/second.git", at: repoURL)
        remotes = try await client.remotes(at: repoURL)
        XCTAssertEqual(remotes.first?.url, "https://example.com/second.git")

        try await client.removeRemote(name: "origin", at: repoURL)
        remotes = try await client.remotes(at: repoURL)
        XCTAssertTrue(remotes.isEmpty)
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = repoURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: [String]) throws {
        _ = try runGit(arguments, in: repoURL)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(message)")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
