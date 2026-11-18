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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repoURL
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(message)")
        }
    }
}
