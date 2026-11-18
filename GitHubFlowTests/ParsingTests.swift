import Foundation
import XCTest

@testable import GitHubFlow

final class ParsingTests: XCTestCase {
    func testStatusParsing() {
        let output = "R  new.txt\u{0}old.txt\u{0} M uni-é.txt\u{0}?? untracked.txt\u{0}"
        let changes = GitParsing.parseStatus(output)

        XCTAssertEqual(changes.count, 3)

        let renamed = changes.first { $0.path == "new.txt" }
        XCTAssertEqual(renamed?.kind, .renamed)
        XCTAssertEqual(renamed?.staged, true)
        XCTAssertEqual(renamed?.originalPath, "old.txt")

        let modified = changes.first { $0.path == "uni-é.txt" }
        XCTAssertEqual(modified?.kind, .modified)
        XCTAssertEqual(modified?.staged, false)

        let untracked = changes.first { $0.path == "untracked.txt" }
        XCTAssertEqual(untracked?.kind, .untracked)
        XCTAssertEqual(untracked?.isUntracked, true)
    }

    func testPartiallyStagedFileProducesTwoEntries() {
        let output = "MM both.txt\u{0}"
        let changes = GitParsing.parseStatus(output)

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.filter(\.staged).count, 1)
        XCTAssertEqual(changes.filter { !$0.staged }.count, 1)
    }

    func testConflictParsing() {
        let output = "UU conflict.txt\u{0}"
        let changes = GitParsing.parseStatus(output)

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .conflicted)
        XCTAssertEqual(changes.first?.isConflicted, true)
    }

    func testCommitLogParsing() {
        let record1 = ["abc123", "abc", "Ada Lovelace", "ada@example.com", "1700000000", "parent1 parent2", "HEAD -> main, origin/main", "Merge it"]
            .joined(separator: "\u{1F}")
        let record2 = ["def456", "def", "Alan Turing", "alan@example.com", "1700000100", "abc123", "", "Second commit"]
            .joined(separator: "\u{1F}")

        let commits = GitParsing.parseCommits(record1 + "\u{0}" + record2 + "\u{0}")

        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].sha, "abc123")
        XCTAssertTrue(commits[0].isMerge)
        XCTAssertEqual(commits[0].refs, ["HEAD -> main", "origin/main"])
        XCTAssertEqual(commits[1].subject, "Second commit")
        XCTAssertEqual(commits[1].initials, "AT")
    }

    func testDiffParsing() {
        let patch = """
        diff --git a/hello.txt b/hello.txt
        index 1234567..89abcde 100644
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,4 @@
         one
        -two
        +TWO
        +three
         four
        """

        let diffs = DiffParser.parse(patch)

        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].path, "hello.txt")
        XCTAssertEqual(diffs[0].additions, 2)
        XCTAssertEqual(diffs[0].deletions, 1)
        XCTAssertEqual(diffs[0].hunks.count, 1)

        let lines = diffs[0].hunks[0].lines
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0].kind, .context)
        XCTAssertEqual(lines[1].oldLine, 2)
        XCTAssertEqual(lines[1].newLine, nil)
        XCTAssertEqual(lines[2].kind, .addition)
        XCTAssertEqual(lines[2].newLine, 2)
        XCTAssertEqual(lines[4].oldLine, 3)
        XCTAssertEqual(lines[4].newLine, 4)
    }

    func testNewFileDiffParsing() {
        let patch = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..1111111
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +a
        +b
        """

        let diffs = DiffParser.parse(patch)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertTrue(diffs[0].isNew)
        XCTAssertEqual(diffs[0].additions, 2)
        XCTAssertEqual(diffs[0].deletions, 0)
    }

    func testRenamedFileDiffParsing() {
        let patch = """
        diff --git a/old.txt b/new.txt
        similarity index 100%
        rename from old.txt
        rename to new.txt
        """

        let diffs = DiffParser.parse(patch)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].oldPath, "old.txt")
        XCTAssertEqual(diffs[0].newPath, "new.txt")
        XCTAssertEqual(diffs[0].note, "Renamed without content changes.")
    }

    func testBinaryDiffParsing() {
        let patch = """
        diff --git a/image.png b/image.png
        index 1111111..2222222 100644
        Binary files a/image.png and b/image.png differ
        """

        let diffs = DiffParser.parse(patch)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertTrue(diffs[0].isBinary)
    }
}
