import Foundation

// MARK: - Flow Center

enum FlowCheckLevel: String, Hashable, Sendable {
    case pass
    case warn
    case fail
    case info
}

struct FlowCheck: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let level: FlowCheckLevel
}

enum ImpactCategory: String, CaseIterable, Hashable, Sendable {
    case code
    case tests
    case docs
    case config
    case dependencies
    case migrations
    case ci
    case assets
    case other

    var title: String {
        switch self {
        case .code: "Code"
        case .tests: "Tests"
        case .docs: "Docs"
        case .config: "Configuration"
        case .dependencies: "Dependencies"
        case .migrations: "Migrations"
        case .ci: "CI"
        case .assets: "Assets"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .tests: "checkmark.seal"
        case .docs: "doc.text"
        case .config: "slider.horizontal.3"
        case .dependencies: "shippingbox"
        case .migrations: "cylinder.split.1x2"
        case .ci: "gearshape.2"
        case .assets: "photo"
        case .other: "folder"
        }
    }
}

struct ImpactFile: Identifiable, Hashable, Sendable {
    let path: String
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let category: ImpactCategory
    let flags: [String]

    var id: String { path }
    var changes: Int { additions + deletions }
    var displayName: String { (path as NSString).lastPathComponent }
    var directoryPath: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }
}

struct ImpactGroup: Identifiable, Hashable, Sendable {
    let category: ImpactCategory
    let files: [ImpactFile]

    var id: String { category.rawValue }
    var title: String { category.title }
    var symbol: String { category.symbol }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    var changes: Int { additions + deletions }
}

struct FlowSummary: Hashable, Sendable {
    let branch: String
    let base: String?
    let baseIsAuto: Bool
    let isOnBase: Bool
    let ahead: Int
    let behind: Int
    let commitCount: Int
    let branchAgeDays: Int?
    let lastCommitDate: Date?
    let additions: Int
    let deletions: Int
    let filesChanged: Int
    let hasUpstream: Bool
    let uncommittedCount: Int
    let conflictRisk: Bool?
    let checks: [FlowCheck]
    let groups: [ImpactGroup]
    let commitSubjects: [String]
    let prTitle: String
    let prBody: String
    let compareURL: String?

    var changes: Int { additions + deletions }

    var riskFlags: [String] {
        Array(Set(groups.flatMap { $0.files.flatMap(\.flags) })).sorted()
    }

    /// 0…100, based on the readiness checks. Informational checks are ignored.
    var score: Int {
        let scored = checks.filter { $0.level != .info }
        guard !scored.isEmpty else { return 0 }
        let total = scored.reduce(0.0) { partial, check in
            switch check.level {
            case .pass: partial + 1
            case .warn: partial + 0.5
            case .fail, .info: partial
            }
        }
        return Int((total / Double(scored.count) * 100).rounded())
    }

    var passedCount: Int { checks.filter { $0.level == .pass }.count }

    static let empty = FlowSummary(
        branch: "",
        base: nil,
        baseIsAuto: true,
        isOnBase: false,
        ahead: 0,
        behind: 0,
        commitCount: 0,
        branchAgeDays: nil,
        lastCommitDate: nil,
        additions: 0,
        deletions: 0,
        filesChanged: 0,
        hasUpstream: false,
        uncommittedCount: 0,
        conflictRisk: nil,
        checks: [],
        groups: [],
        commitSubjects: [],
        prTitle: "",
        prBody: "",
        compareURL: nil
    )
}

// MARK: - Safety Net

struct RecoverySnapshot: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case workingTree
        case commit
        case branch

        var title: String {
            switch self {
            case .workingTree: "Working tree"
            case .commit: "Commit"
            case .branch: "Branch"
            }
        }

        var symbol: String {
            switch self {
            case .workingTree: "doc.on.doc"
            case .commit: "clock.arrow.circlepath"
            case .branch: "arrow.triangle.branch"
            }
        }
    }

    let ref: String
    let sha: String
    let date: Date
    let message: String
    let kind: Kind
    let branchName: String?

    var id: String { ref }
    var shortSHA: String { String(sha.prefix(7)) }
}

// MARK: - Standup digest

enum StandupRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        }
    }
}

struct StandupCommit: Identifiable, Hashable, Sendable {
    let sha: String
    let shortSHA: String
    let repository: String
    let author: String
    let subject: String
    let date: Date

    var id: String { repository + "|" + sha }
}

struct StandupDigest: Hashable, Sendable {
    let range: StandupRange
    let generatedAt: Date
    let commits: [StandupCommit]
    let markdown: String

    var repositories: [String] {
        Array(Set(commits.map(\.repository))).sorted()
    }

    func commits(in repository: String) -> [StandupCommit] {
        commits.filter { $0.repository == repository }
    }
}

// MARK: - Repository janitor

struct StaleBranch: Identifiable, Hashable, Sendable {
    let name: String
    let sha: String
    let subject: String
    let date: Date
    let isMerged: Bool
    let reason: String

    var id: String { name }
}

struct LargeObject: Identifiable, Hashable, Sendable {
    let oid: String
    let path: String
    let size: Int64

    var id: String { oid + "|" + path }
}

struct GitignoreSuggestion: Identifiable, Hashable, Sendable {
    let pattern: String
    let reason: String

    var id: String { pattern }
}

// MARK: - Explanations

struct ChangeExplanation: Hashable, Sendable {
    enum Source: String, Hashable, Sendable {
        case offline
        case onDevice

        var title: String {
            switch self {
            case .offline: "Offline analysis"
            case .onDevice: "On-device model"
            }
        }
    }

    let title: String
    let text: String
    let source: Source
}
