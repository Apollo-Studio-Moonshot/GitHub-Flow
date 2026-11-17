import Foundation

// MARK: - Repository

/// A repository the app knows about, persisted between launches.
struct RepositoryRef: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var lastOpened: Date = .now

    var url: URL { URL(fileURLWithPath: path) }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Changes

enum ChangeKind: String, Codable, Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
    case typeChanged

    var letter: String {
        switch self {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "U"
        case .conflicted: "!"
        case .typeChanged: "T"
        }
    }

    var label: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .untracked: "Untracked"
        case .conflicted: "Conflicted"
        case .typeChanged: "Type changed"
        }
    }

    var symbolName: String {
        switch self {
        case .added, .untracked: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .copied: "doc.on.doc.fill"
        case .conflicted: "exclamationmark.triangle.fill"
        case .typeChanged: "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

/// One change in the working tree or the index. A file that is partly staged
/// produces two entries: one for the index side and one for the worktree side.
struct FileChange: Identifiable, Hashable, Sendable {
    let path: String
    var originalPath: String?
    let kind: ChangeKind
    let staged: Bool

    var id: String { path + (staged ? "|index" : "|worktree") }

    var displayName: String { (path as NSString).lastPathComponent }

    var directoryPath: String {
        (path as NSString).deletingLastPathComponent
    }

    var isUntracked: Bool { kind == .untracked }
    var isConflicted: Bool { kind == .conflicted }
    var isAdded: Bool { kind == .added }
    var isDeleted: Bool { kind == .deleted }

    /// Paths that must be touched to stage or unstage this change. Renames
    /// include both the new and the original path.
    var affectedPaths: [String] {
        if let originalPath, originalPath != path {
            return [path, originalPath]
        }
        return [path]
    }
}

// MARK: - Branches

struct BranchInfo: Identifiable, Hashable, Sendable {
    let name: String          // e.g. "main" or "origin/main"
    let sha: String
    let upstream: String?
    let isCurrent: Bool
    let isRemote: Bool
    let lastCommitDate: Date
    let subject: String

    var id: String { (isRemote ? "r:" : "l:") + name }

    /// "origin/feature" -> "feature"
    var displayName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

// MARK: - Commits

struct CommitInfo: Identifiable, Hashable, Sendable {
    let sha: String
    let shortSHA: String
    let author: String
    let email: String
    let date: Date
    let parents: [String]
    let decorations: String
    let subject: String

    var id: String { sha }
    var isMerge: Bool { parents.count > 1 }

    var refs: [String] {
        decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var initials: String {
        let parts = author.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

struct CommitDetail: Sendable, Hashable {
    let commit: CommitInfo
    let body: String
    let files: [FileDiff]
}

// MARK: - Diff model

struct DiffLine: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case context
        case addition
        case deletion
        case meta
    }

    let kind: Kind
    let text: String
    let oldLine: Int?
    let newLine: Int?
}

struct DiffHunk: Identifiable, Hashable, Sendable {
    let id: Int
    let header: String
    let lines: [DiffLine]

    var additions: Int { lines.reduce(0) { $0 + ($1.kind == .addition ? 1 : 0) } }
    var deletions: Int { lines.reduce(0) { $0 + ($1.kind == .deletion ? 1 : 0) } }
}

struct FileDiff: Identifiable, Hashable, Sendable {
    let oldPath: String
    let newPath: String
    let isBinary: Bool
    let isNew: Bool
    let isDeleted: Bool
    let hunks: [DiffHunk]
    let additions: Int
    let deletions: Int
    let note: String?

    var id: String { newPath }

    var path: String { newPath }

    var displayName: String { (newPath as NSString).lastPathComponent }

    var isEmpty: Bool { !isBinary && hunks.isEmpty }

    static func empty(path: String, note: String? = nil) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            isBinary: false,
            isNew: false,
            isDeleted: false,
            hunks: [],
            additions: 0,
            deletions: 0,
            note: note
        )
    }

    func replacingPath(_ path: String) -> FileDiff {
        FileDiff(
            oldPath: path,
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
}

// MARK: - Repository snapshot

enum RepoOperation: String, Sendable, Hashable {
    case merge
    case rebase
    case cherryPick
    case revert

    var title: String {
        switch self {
        case .merge: "Merge in progress"
        case .rebase: "Rebase in progress"
        case .cherryPick: "Cherry-pick in progress"
        case .revert: "Revert in progress"
        }
    }
}

struct RepoSnapshot: Sendable, Equatable {
    var rootPath: String
    var branch: String
    var isDetached: Bool
    var hasCommits: Bool
    var ahead: Int
    var behind: Int
    var hasRemote: Bool
    var remoteName: String?
    var hasUpstream: Bool
    var changes: [FileChange]
    var branches: [BranchInfo]
    var operation: RepoOperation?

    static let empty = RepoSnapshot(
        rootPath: "",
        branch: "",
        isDetached: false,
        hasCommits: false,
        ahead: 0,
        behind: 0,
        hasRemote: false,
        remoteName: nil,
        hasUpstream: false,
        changes: [],
        branches: [],
        operation: nil
    )

    var branchDisplayName: String {
        isDetached ? "Detached HEAD" : (branch.isEmpty ? "No commits yet" : branch)
    }

    var localBranches: [BranchInfo] { branches.filter { !$0.isRemote } }
    var remoteBranches: [BranchInfo] { branches.filter(\.isRemote) }

    var currentBranch: BranchInfo? { branches.first { $0.isCurrent && !$0.isRemote } }

    var stagedChanges: [FileChange] { changes.filter(\.staged) }
    var unstagedChanges: [FileChange] { changes.filter { !$0.staged } }

    var hasChanges: Bool { !changes.isEmpty }

    var remoteOrDefaultName: String { remoteName ?? "origin" }
}
