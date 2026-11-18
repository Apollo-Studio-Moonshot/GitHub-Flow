import Foundation
import XCTest

@testable import GitHubFlow

final class FlowAnalyzerTests: XCTestCase {
    func testNumstatParsingGroupsAndFlags() {
        let output = """
        10\t2\tsrc/App.swift
        5\t0\tTests/AppTests.swift
        -\t-\tAssets/logo.png
        3\t1\tdocs/README.md
        4\t0\tmigrations/001_initial.sql
        2\t1\t.env
        """

        let files = FlowAnalyzer.parseNumstat(output)
        XCTAssertEqual(files.count, 6)

        let app = files.first { $0.path == "src/App.swift" }
        XCTAssertEqual(app?.category, .code)
        XCTAssertEqual(app?.changes, 12)

        XCTAssertEqual(files.first { $0.path == "Tests/AppTests.swift" }?.category, .tests)
        XCTAssertEqual(files.first { $0.path == "docs/README.md" }?.category, .docs)
        XCTAssertEqual(files.first { $0.path == "migrations/001_initial.sql" }?.category, .migrations)
        XCTAssertTrue(files.first { $0.path == "migrations/001_initial.sql" }?.flags.contains("Migration") == true)

        let binary = files.first { $0.path == "Assets/logo.png" }
        XCTAssertEqual(binary?.category, .assets)
        XCTAssertTrue(binary?.flags.contains("Binary") == true)

        let env = files.first { $0.path == ".env" }
        XCTAssertTrue(env?.flags.contains("Possible secret") == true)

        let groups = FlowAnalyzer.groups(from: files)
        XCTAssertEqual(groups.map(\.category), [.code, .tests, .docs, .config, .migrations, .assets])
    }

    func testChecksAndScore() {
        let checks = FlowAnalyzer.checks(
            isOnBase: false,
            ahead: 2,
            behind: 0,
            hasUpstream: true,
            uncommittedCount: 0,
            conflictRisk: false,
            branchAgeDays: 2,
            filesChanged: 3,
            additions: 40,
            deletions: 5
        )

        XCTAssertEqual(checks.filter { $0.level == .pass }.count, checks.filter { $0.level != .info }.count)

        let summary = FlowSummary(
            branch: "feature",
            base: "main",
            baseIsAuto: true,
            isOnBase: false,
            ahead: 2,
            behind: 0,
            commitCount: 2,
            branchAgeDays: 2,
            lastCommitDate: Date(),
            additions: 40,
            deletions: 5,
            filesChanged: 3,
            hasUpstream: true,
            uncommittedCount: 0,
            conflictRisk: false,
            checks: checks,
            groups: [],
            commitSubjects: ["A", "B"],
            prTitle: "Feature",
            prBody: "",
            compareURL: nil
        )
        XCTAssertEqual(summary.score, 100)
    }

    func testPullRequestCopyAndCompareURL() {
        let files = FlowAnalyzer.parseNumstat("4\t1\tsrc/Feature.swift\n2\t0\tTests/FeatureTests.swift\n")
        let groups = FlowAnalyzer.groups(from: files)
        let body = FlowAnalyzer.prBody(
            branch: "feature/login",
            base: "origin/main",
            ahead: 2,
            behind: 1,
            groups: groups,
            subjects: ["Add login", "Add tests"],
            riskFlags: ["Dependency change"],
            additions: 6,
            deletions: 1,
            filesChanged: 2
        )

        XCTAssertTrue(body.contains("## Summary"))
        XCTAssertTrue(body.contains("## Changes"))
        XCTAssertTrue(body.contains("## Impact"))
        XCTAssertTrue(body.contains("## Risk"))
        XCTAssertTrue(body.contains("## Testing"))
        XCTAssertTrue(body.contains("Add login"))

        let url = FlowAnalyzer.compareURL(
            remoteURL: "git@github.com:owner/repo.git",
            baseRef: "origin/main",
            branch: "feature/login"
        )
        XCTAssertEqual(url, "https://github.com/owner/repo/compare/main...feature/login?expand=1")

        XCTAssertEqual(FlowAnalyzer.shortBaseName("origin/main"), "main")
        XCTAssertEqual(FlowAnalyzer.humanizedBranchName("feature/login-form"), "Login form")
    }

    func testRemoteParsing() {
        XCTAssertEqual(FlowAnalyzer.parseRemote("git@github.com:owner/repo.git")?.host, "github.com")
        XCTAssertEqual(FlowAnalyzer.parseRemote("git@github.com:owner/repo.git")?.path, "owner/repo")
        XCTAssertEqual(FlowAnalyzer.parseRemote("https://gitlab.com/group/repo.git")?.path, "group/repo")
    }
}

final class FeatureIntegrationTests: XCTestCase {
    private var repoURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubflow-feature-tests-\(UUID().uuidString)", isDirectory: true)
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

    func testFlowSummaryForFeatureBranch() async throws {
        let client = GitClient()

        try write("root\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        try git(["switch", "-q", "-c", "feature/login"])
        try write("hello\n", to: "src/Feature.swift")
        try write("root\nmore\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Add login"])

        let summary = try await client.flowSummary(at: repoURL)

        XCTAssertEqual(summary.branch, "feature/login")
        XCTAssertEqual(summary.base, "main")
        XCTAssertEqual(summary.ahead, 1)
        XCTAssertEqual(summary.behind, 0)
        XCTAssertEqual(summary.filesChanged, 2)
        XCTAssertEqual(summary.additions, 2)
        XCTAssertFalse(summary.isOnBase)
        XCTAssertEqual(summary.conflictRisk, false)
        XCTAssertEqual(summary.prTitle, "Add login")
        XCTAssertTrue(summary.prBody.contains("## Summary"))
        XCTAssertFalse(summary.checks.isEmpty)
    }

    func testFlowSummaryDetectsConflicts() async throws {
        let client = GitClient()

        try write("base\n", to: "shared.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        try git(["switch", "-q", "-c", "feature"])
        try write("feature\n", to: "shared.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Feature change"])

        try git(["switch", "-q", "main"])
        try write("main\n", to: "shared.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Main change"])
        try git(["switch", "-q", "feature"])

        let summary = try await client.flowSummary(at: repoURL)
        XCTAssertEqual(summary.base, "main")
        XCTAssertEqual(summary.ahead, 1)
        XCTAssertEqual(summary.behind, 1)
        XCTAssertEqual(summary.conflictRisk, true)
    }

    func testWorkingTreeSnapshotRestoresDiscardedChanges() async throws {
        let client = GitClient()

        try write("line1\n", to: "file.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        try write("line1 changed\n", to: "file.txt")
        try write("brand new\n", to: "new.txt")

        let snapshot = try await client.createWorktreeSnapshot(
            label: "Before discard",
            at: repoURL,
            hasCommits: true,
            identity: nil
        )

        try git(["restore", "--", "file.txt"])
        try git(["clean", "-f", "-d"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("new.txt").path)
        )

        try await client.restoreWorktreeSnapshot(sha: snapshot.sha, at: repoURL)

        let restored = try String(contentsOf: repoURL.appendingPathComponent("file.txt"), encoding: .utf8)
        XCTAssertEqual(restored, "line1 changed\n")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("new.txt").path)
        )

        let snapshots = try await client.recoverySnapshots(at: repoURL)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.kind, .workingTree)
        XCTAssertEqual(snapshots.first?.message, "Working tree snapshot · Before discard")
    }

    func testBranchSnapshotRecreatesDeletedBranch() async throws {
        let client = GitClient()

        try write("root\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        try git(["switch", "-q", "-c", "cleanup"])
        try write("work\n", to: "work.txt")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Work on cleanup"])
        let tip = try runGit(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

        let snapshot = try await client.createBranchSnapshot(
            branch: "cleanup",
            at: repoURL,
            identity: nil
        )
        XCTAssertEqual(snapshot.sha, tip)

        try git(["switch", "-q", "main"])
        try git(["branch", "-D", "cleanup"])

        try await client.restoreBranchSnapshot(name: "cleanup", sha: snapshot.sha, at: repoURL)
        let restored = try runGit(["rev-parse", "cleanup"]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(restored, tip)

        let snapshots = try await client.recoverySnapshots(at: repoURL)
        XCTAssertEqual(snapshots.first?.kind, .branch)
        XCTAssertEqual(snapshots.first?.branchName, "cleanup")
    }

    func testRecentCommitsExcludeRecoverySnapshots() async throws {
        let client = GitClient()

        try write("root\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])

        try write("change\n", to: "README.md")
        _ = try await client.createWorktreeSnapshot(
            label: "Snapshot",
            at: repoURL,
            hasCommits: true,
            identity: nil
        )

        let commits = try await client.recentCommits(
            at: repoURL,
            since: Date().addingTimeInterval(-3_600),
            author: nil
        )
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.subject, "Initial commit")
    }

    func testStaleBranchDetection() async throws {
        let client = GitClient()

        try write("root\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])
        try git(["branch", "old-work"])

        let stale = try await client.staleBranches(at: repoURL, base: "main")
        XCTAssertTrue(stale.contains { $0.name == "old-work" && $0.isMerged })
    }

    func testIgnoreSuggestionsAndAppend() async throws {
        let client = GitClient()

        try write("root\n", to: "README.md")
        try git(["add", "--all"])
        try git(["commit", "-q", "-m", "Initial commit"])
        try write("metadata\n", to: ".DS_Store")

        let suggestions = try await client.ignoreSuggestions(at: repoURL)
        XCTAssertTrue(suggestions.contains { $0.pattern == ".DS_Store" })

        try await client.appendGitignore([".DS_Store"], at: repoURL)

        let after = try await client.ignoreSuggestions(at: repoURL)
        XCTAssertFalse(after.contains { $0.pattern == ".DS_Store" })

        let contents = try String(
            contentsOf: repoURL.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("# Added by GitHub Flow"))
        XCTAssertTrue(contents.contains(".DS_Store"))
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
    private func runGit(_ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? repoURL
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
