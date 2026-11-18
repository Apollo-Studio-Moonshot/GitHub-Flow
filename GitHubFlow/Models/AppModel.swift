import AppKit
import Foundation
import Observation

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case changes
    case flow
    case history
    case stashes
    case safety

    var id: String { rawValue }
    var title: String {
        switch self {
        case .changes: "Changes"
        case .flow: "Flow"
        case .history: "History"
        case .stashes: "Stashes"
        case .safety: "Safety"
        }
    }

    var symbol: String {
        switch self {
        case .changes: "square.stack.3d.up"
        case .flow: "point.3.connected.trianglepath.dotted"
        case .history: "clock.arrow.circlepath"
        case .stashes: "archivebox"
        case .safety: "shield.lefthalf.filled"
        }
    }
}

enum SheetRoute: String, Identifiable, Hashable {
    case clone
    case create
    case newBranch
    case manageBranches
    case manageRemotes
    case standup
    case janitor

    var id: String { rawValue }
}

/// Single source of truth for the app. Owns the repository list, the loaded
/// snapshot for the selected repository, and every git interaction.
@MainActor
@Observable
final class AppModel {
    private let git = GitClient.shared

    // MARK: - Persisted state

    private(set) var repositories: [RepositoryRef]
    private(set) var loadedRepositoryID: RepositoryRef.ID?

    var selectedRepositoryID: RepositoryRef.ID? {
        didSet {
            guard oldValue != selectedRepositoryID,
                  let id = selectedRepositoryID,
                  let index = repositories.firstIndex(where: { $0.id == id }) else { return }
            repositories[index].lastOpened = .now
            persistRepositories()
        }
    }

    var settings: AppSettings {
        didSet { Persistence.saveSettings(settings) }
    }

    // MARK: - Selected repository state

    private(set) var snapshot: RepoSnapshot?
    private(set) var commits: [CommitInfo] = []
    private(set) var commitDetail: CommitDetail?
    private(set) var workingDiffs: [FileDiff] = []
    private(set) var isLoading = false

    var tab: MainTab = .changes
    var changesSearch = ""
    var historySearch = ""

    var commitSummary = ""
    var commitDescription = ""
    var isDescriptionExpanded = false
    var stashMessage = ""

    var selectedChangeID: FileChange.ID? {
        didSet {
            guard oldValue != selectedChangeID else { return }
            Task { await self.loadWorkingDiff() }
        }
    }

    var selectedCommitSHA: String? {
        didSet {
            guard oldValue != selectedCommitSHA else { return }
            commitDetail = nil
            selectedCommitFileID = nil
            Task { await self.loadCommitDetail() }
        }
    }

    var selectedCommitFileID: String?

    // MARK: - Presentation

    private(set) var busyCount = 0
    private(set) var activityLabel: String?
    private(set) var gitVersion: String?

    var alert: AppAlert?
    var toast: ToastMessage?
    var sheet: SheetRoute?
    var pendingRevert: CommitInfo?
    var pendingDiscard: FileChange?
    var pendingStashDrop: StashInfo?
    var pendingUndoLastCommit = false
    var pendingBranchRename: BranchInfo?
    var pendingBranchDelete: BranchInfo?
    var showsDiscardAllConfirmation = false

    /// When true the commit composer edits the latest commit instead of
    /// creating a new one.
    var isAmendingLastCommit = false

    private(set) var remotes: [GitRemote] = []

    // MARK: - Flow Center

    private(set) var flowSummary: FlowSummary?
    private(set) var isLoadingFlow = false
    var flowBase: String?

    // MARK: - Safety Net

    private(set) var recoverySnapshots: [RecoverySnapshot] = []
    var pendingSnapshotRestore: RecoverySnapshot?
    var pendingSnapshotDelete: RecoverySnapshot?

    // MARK: - Standup

    private(set) var standup: StandupDigest?
    private(set) var isLoadingStandup = false
    var standupRange: StandupRange = .today

    // MARK: - Repository janitor

    private(set) var staleBranches: [StaleBranch] = []
    private(set) var largeObjects: [LargeObject] = []
    private(set) var ignoreSuggestions: [GitignoreSuggestion] = []
    private(set) var isScanningJanitor = false
    private(set) var hasScannedLargeObjects = false

    // MARK: - Command palette & explanations

    var showsCommandPalette = false
    var showsExplanation = false
    private(set) var explanation: ChangeExplanation?
    private(set) var isExplaining = false
    private var explanationPrompt: String?

    // MARK: - Generation tokens

    private var diffGeneration = 0
    private var detailGeneration = 0
    private var flowGeneration = 0
    private var flowHeadSHA: String?
    private var flowWorktreeSignature: String?
    private var standupGeneration = 0
    private var janitorGeneration = 0

    // MARK: - Init

    init() {
        settings = Persistence.loadSettings()
        let stored = Persistence.loadRepositories()
        repositories = stored

        // Restore the most recently used repository.
        selectedRepositoryID = stored.max(by: { $0.lastOpened < $1.lastOpened })?.id
    }

    // MARK: - Derived state

    var isBusy: Bool { busyCount > 0 }

    var isGitAvailable: Bool { git.isGitAvailable }

    var gitPath: String { git.executable.path }

    var selectedRepository: RepositoryRef? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    var repoURL: URL? { selectedRepository?.url }

    var repositoryName: String { selectedRepository?.name ?? "" }

    var currentBranchName: String { snapshot?.branchDisplayName ?? "" }

    var stagedChanges: [FileChange] { snapshot?.stagedChanges ?? [] }
    var unstagedChanges: [FileChange] { snapshot?.unstagedChanges ?? [] }
    var allChanges: [FileChange] { snapshot?.changes ?? [] }
    var stashes: [StashInfo] { snapshot?.stashes ?? [] }

    var filteredStagedChanges: [FileChange] { filterChanges(stagedChanges) }
    var filteredUnstagedChanges: [FileChange] { filterChanges(unstagedChanges) }

    var filteredCommits: [CommitInfo] {
        let query = historySearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return commits }
        return commits.filter { commit in
            commit.subject.localizedCaseInsensitiveContains(query)
                || commit.author.localizedCaseInsensitiveContains(query)
                || commit.shortSHA.localizedCaseInsensitiveContains(query)
        }
    }

    var canCommit: Bool {
        selectedRepository != nil
            && (isAmendingLastCommit || !stagedChanges.isEmpty)
            && !commitSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    var selectedCommit: CommitInfo? {
        commits.first { $0.sha == selectedCommitSHA }
    }

    var selectedCommitFile: FileDiff? {
        commitDetail?.files.first { $0.id == selectedCommitFileID }
    }

    var workingDiff: FileDiff? { workingDiffs.first }

    var selectedChange: FileChange? {
        allChanges.first { $0.id == selectedChangeID }
    }

    private func filterChanges(_ changes: [FileChange]) -> [FileChange] {
        let query = changesSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return changes }
        return changes.filter {
            $0.path.localizedCaseInsensitiveContains(query)
                || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await loadGitVersion()
    }

    func loadGitVersion() async {
        guard gitVersion == nil else { return }
        gitVersion = await git.version()
    }

    private func resetRepositoryState() {
        snapshot = nil
        commits = []
        commitDetail = nil
        workingDiffs = []
        selectedChangeID = nil
        selectedCommitSHA = nil
        selectedCommitFileID = nil
        commitSummary = ""
        commitDescription = ""
        isDescriptionExpanded = false
        stashMessage = ""
        changesSearch = ""
        historySearch = ""
        isAmendingLastCommit = false
        remotes = []
        flowSummary = nil
        flowBase = nil
        flowHeadSHA = nil
        flowWorktreeSignature = nil
        recoverySnapshots = []
        pendingSnapshotRestore = nil
        pendingSnapshotDelete = nil
        staleBranches = []
        largeObjects = []
        ignoreSuggestions = []
        hasScannedLargeObjects = false
        explanation = nil
        explanationPrompt = nil
        showsExplanation = false
        pendingBranchRename = nil
        pendingBranchDelete = nil
        isLoading = true
        diffGeneration += 1
        detailGeneration += 1
        flowGeneration += 1
        janitorGeneration += 1
    }

    /// Called when the selected repository's view appears or the selection changes.
    func loadSelectedRepository() async {
        guard selectedRepository != nil else { return }
        if loadedRepositoryID != selectedRepositoryID {
            loadedRepositoryID = selectedRepositoryID
            resetRepositoryState()
        }
        await refresh()
        await loadSnapshots()
    }

    // MARK: - Loading

    func refresh(showSpinner: Bool = true) async {
        guard let repository = selectedRepository else { return }
        let url = repository.url
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }

        do {
            let newSnapshot = try await git.snapshot(at: url)
            let newHistory = try await git.history(at: url)
            guard selectedRepository?.id == repository.id else { return }
            apply(snapshot: newSnapshot, history: newHistory)
            if tab == .flow { await loadFlow(force: true) }
        } catch {
            guard selectedRepository?.id == repository.id else { return }
            // A repository that moved on disk is reported inline in the UI;
            // don't spam the user with an alert at launch.
            if repository.existsOnDisk { present(error) }
        }
    }

    /// Lightweight background refresh; only does real work when something changed.
    func autoRefresh() async {
        guard !isBusy, !isLoading,
              let repository = selectedRepository,
              repository.existsOnDisk else { return }

        guard let newSnapshot = try? await git.snapshot(at: repository.url) else { return }
        guard selectedRepository?.id == repository.id else { return }
        guard newSnapshot != snapshot else {
            // The status can be identical while a file's *contents* changed
            // (e.g. an external editor saved an already-modified file), so keep
            // the visible diff in sync too.
            if tab == .changes, selectedChange != nil { await loadWorkingDiff() }
            return
        }

        let newHistory = (try? await git.history(at: repository.url)) ?? commits
        guard selectedRepository?.id == repository.id else { return }
        apply(snapshot: newSnapshot, history: newHistory)
    }

    private func apply(snapshot newSnapshot: RepoSnapshot, history newHistory: [CommitInfo]) {
        let previousSnapshot = snapshot
        let historyChanged = commits.map(\.sha) != newHistory.map(\.sha)

        snapshot = newSnapshot
        commits = newHistory

        if let id = selectedRepositoryID, let index = repositories.firstIndex(where: { $0.id == id }) {
            let rootName = (newSnapshot.rootPath as NSString).lastPathComponent
            if !rootName.isEmpty {
                repositories[index].name = rootName
            }
            repositories[index].lastOpened = .now
            persistRepositories()
        }

        if selectedChange == nil {
            // Keep the current file selected across staging/unstaging by matching
            // on its path, then fall back to the first changed file.
            let previousPath = previousSnapshot?.changes.first { $0.id == selectedChangeID }?.path
            if let previousPath,
               let match = newSnapshot.changes.first(where: { $0.path == previousPath }) {
                selectedChangeID = match.id
            } else {
                selectedChangeID = newSnapshot.changes.first?.id
            }
        } else if previousSnapshot != newSnapshot {
            Task { await self.loadWorkingDiff() }
        }

        if selectedCommitSHA == nil || !newHistory.contains(where: { $0.sha == selectedCommitSHA }) {
            selectedCommitSHA = newHistory.first?.sha
        } else if historyChanged {
            Task { await self.loadCommitDetail() }
        } else if commitDetail == nil {
            Task { await self.loadCommitDetail() }
        }
    }

    private func loadWorkingDiff() async {
        guard let repository = selectedRepository,
              let change = allChanges.first(where: { $0.id == selectedChangeID }) else {
            workingDiffs = []
            return
        }

        diffGeneration += 1
        let generation = diffGeneration
        let hasCommits = snapshot?.hasCommits ?? false

        do {
            let diffs = try await git.workingDiff(
                at: repository.url,
                change: change,
                hasCommits: hasCommits
            )
            guard generation == diffGeneration else { return }
            workingDiffs = diffs
        } catch {
            guard generation == diffGeneration else { return }
            workingDiffs = [FileDiff.empty(path: change.path, note: error.localizedDescription)]
        }
    }

    private func loadCommitDetail() async {
        guard let repository = selectedRepository,
              let commit = commits.first(where: { $0.sha == selectedCommitSHA }) else {
            commitDetail = nil
            return
        }

        detailGeneration += 1
        let generation = detailGeneration

        do {
            let detail = try await git.commitDetail(at: repository.url, commit: commit)
            guard generation == detailGeneration else { return }
            commitDetail = detail
            if let firstFile = detail.files.first,
               !detail.files.contains(where: { $0.id == selectedCommitFileID }) {
                selectedCommitFileID = firstFile.id
            }
        } catch {
            guard generation == detailGeneration else { return }
            commitDetail = nil
            present(error)
        }
    }

    // MARK: - Flow Center

    var flowBaseOptions: [String] {
        guard let snapshot else { return [] }
        return snapshot.branches
            .filter { !$0.isCurrent }
            .map(\.name)
            .sorted { lhs, rhs in
                let preferred = ["origin/main", "origin/master", "origin/develop", "main", "master", "develop", "trunk"]
                let lhsRank = preferred.firstIndex(of: lhs) ?? preferred.count
                let rhsRank = preferred.firstIndex(of: rhs) ?? preferred.count
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    func setFlowBase(_ base: String?) {
        flowBase = base
        flowSummary = nil
        flowHeadSHA = nil
        flowWorktreeSignature = nil
    }

    func loadFlow(force: Bool = false) async {
        guard let repository = selectedRepository else {
            flowSummary = nil
            return
        }
        let headSHA = commits.first?.sha
        let worktree = worktreeSignature
        if !force,
           flowSummary != nil,
           flowSummary?.branch == snapshot?.branch,
           flowHeadSHA == headSHA,
           flowWorktreeSignature == worktree {
            return
        }

        flowGeneration += 1
        let generation = flowGeneration
        isLoadingFlow = true
        defer { if generation == flowGeneration { isLoadingFlow = false } }

        do {
            let summary = try await git.flowSummary(at: repository.url, base: flowBase)
            guard generation == flowGeneration else { return }
            flowSummary = summary
            flowHeadSHA = headSHA
            flowWorktreeSignature = worktree
        } catch {
            guard generation == flowGeneration else { return }
            flowSummary = nil
            present(error)
        }
    }

    private var worktreeSignature: String {
        (snapshot?.changes ?? []).map(\.id).sorted().joined(separator: "|")
    }

    func openFlowCompare() {
        guard let link = flowSummary?.compareURL, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyFlowPRBody() {
        guard let summary = flowSummary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.prBody, forType: .string)
        showToast("Copied pull request description")
    }

    func explainBranch() async {
        guard let summary = flowSummary else { return }
        let files = summary.groups.flatMap(\.files)
        explanation = ChangeExplainer.explain(
            title: "This branch",
            subjects: summary.commitSubjects,
            files: files
        )
        explanationPrompt = ChangeExplainer.prompt(
            title: "Branch \(summary.branch) vs \(summary.base ?? "base")",
            subjects: summary.commitSubjects,
            files: files,
            diff: nil
        )
        showsExplanation = true
    }

    func explainSelectedCommit() async {
        guard let commit = selectedCommit else { return }
        isExplaining = true
        defer { isExplaining = false }

        if commitDetail == nil || commitDetail?.commit.sha != commit.sha {
            await loadCommitDetail()
        }
        guard let detail = commitDetail, detail.commit.sha == commit.sha else {
            present(title: "Couldn’t load commit", message: "The commit details are not available right now.")
            return
        }

        let files = detail.files.map {
            FlowAnalyzer.impactFile(
                path: $0.path,
                additions: $0.additions,
                deletions: $0.deletions,
                isBinary: $0.isBinary
            )
        }
        explanation = ChangeExplainer.explain(
            title: commit.subject,
            subjects: [commit.subject],
            files: files
        )
        explanationPrompt = ChangeExplainer.prompt(
            title: commit.subject,
            subjects: [commit.subject],
            files: files,
            diff: Self.diffExcerpt(detail.files)
        )
        showsExplanation = true
    }

    func refineExplanationWithOnDevice() async {
        guard let prompt = explanationPrompt else { return }
        isExplaining = true
        defer { isExplaining = false }

        if let text = await OnDeviceExplainer.explain(prompt: prompt) {
            explanation = ChangeExplanation(
                title: explanation?.title ?? "Explanation",
                text: text,
                source: .onDevice
            )
            showToast("Refined with the on-device model")
        } else {
            present(
                title: "On-device model unavailable",
                message: "This Mac can’t run the system language model, or the model isn’t ready yet."
            )
        }
    }

    private static func diffExcerpt(_ files: [FileDiff]) -> String {
        files.prefix(10).map { file in
            var lines = ["--- \(file.path)"]
            for hunk in file.hunks {
                lines.append(hunk.header)
                lines.append(contentsOf: hunk.lines.map { line in
                    switch line.kind {
                    case .addition: "+" + line.text
                    case .deletion: "-" + line.text
                    case .context: " " + line.text
                    case .meta: line.text
                    }
                })
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Safety Net

    func loadSnapshots() async {
        guard let repository = selectedRepository else {
            recoverySnapshots = []
            return
        }
        recoverySnapshots = (try? await git.recoverySnapshots(at: repository.url)) ?? []
    }

    func captureSnapshot(label: String = "Manual snapshot") async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Capturing snapshot…") { () -> Bool in
            _ = try await self.git.createWorktreeSnapshot(
                label: label,
                at: repository.url,
                hasCommits: self.snapshot?.hasCommits ?? false,
                identity: self.settings.identity
            )
            return true
        }
        if succeeded == true {
            await loadSnapshots()
            showToast("Captured a safety snapshot")
        }
    }

    func restoreSnapshot(_ snapshot: RecoverySnapshot) async {
        guard let repository = selectedRepository else { return }

        // Make even a restore reversible by capturing the current state first.
        if snapshot.kind != .commit, self.snapshot?.hasChanges == true {
            _ = try? await git.createWorktreeSnapshot(
                label: "Before restoring a snapshot",
                at: repository.url,
                hasCommits: self.snapshot?.hasCommits ?? false,
                identity: settings.identity
            )
        }

        let succeeded = await withActivity("Restoring snapshot…") { () -> Bool in
            switch snapshot.kind {
            case .workingTree:
                try await self.git.restoreWorktreeSnapshot(sha: snapshot.sha, at: repository.url)
            case .commit:
                try await self.git.restoreCommitSnapshot(sha: snapshot.sha, at: repository.url)
            case .branch:
                guard let name = snapshot.branchName else {
                    throw GitError.invalidInput("This snapshot doesn’t name a branch.")
                }
                try await self.git.restoreBranchSnapshot(name: name, sha: snapshot.sha, at: repository.url)
            }
            return true
        }

        if succeeded == true {
            showToast("Restored snapshot")
            await loadSnapshots()
            await refresh(showSpinner: false)
        }
    }

    func deleteSnapshot(_ snapshot: RecoverySnapshot) async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Deleting snapshot…") { () -> Bool in
            try await self.git.deleteSnapshot(ref: snapshot.ref, at: repository.url)
            return true
        }
        if succeeded == true {
            await loadSnapshots()
            showToast("Deleted snapshot")
        }
    }

    private func captureWorkingTreeBefore(_ label: String) async {
        guard let repository = selectedRepository, snapshot?.hasChanges == true else { return }
        _ = try? await git.createWorktreeSnapshot(
            label: label,
            at: repository.url,
            hasCommits: snapshot?.hasCommits ?? false,
            identity: settings.identity
        )
        await loadSnapshots()
    }

    private func captureCommitBefore() async {
        guard let repository = selectedRepository, snapshot?.hasCommits == true else { return }
        _ = try? await git.createCommitSnapshot(at: repository.url)
        await loadSnapshots()
    }

    private func captureBranchBefore(_ branch: BranchInfo) async {
        guard let repository = selectedRepository else { return }
        _ = try? await git.createBranchSnapshot(
            branch: branch.name,
            at: repository.url,
            identity: settings.identity
        )
        await loadSnapshots()
    }

    // MARK: - Standup digest

    func loadStandup(range: StandupRange? = nil) async {
        let selectedRange = range ?? standupRange
        standupRange = selectedRange

        standupGeneration += 1
        let generation = standupGeneration
        isLoadingStandup = true
        defer { if generation == standupGeneration { isLoadingStandup = false } }

        let calendar = Calendar.current
        let since: Date
        switch selectedRange {
        case .today:
            since = calendar.startOfDay(for: Date())
        case .week:
            since = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
        }

        let author = settings.identity?.email
        var commits: [StandupCommit] = []
        for repository in repositories where repository.existsOnDisk {
            let recent = (try? await git.recentCommits(at: repository.url, since: since, author: author)) ?? []
            for commit in recent {
                commits.append(
                    StandupCommit(
                        sha: commit.sha,
                        shortSHA: commit.shortSHA,
                        repository: repository.name,
                        author: commit.author,
                        subject: commit.subject,
                        date: commit.date
                    )
                )
            }
        }

        guard generation == standupGeneration else { return }
        commits.sort { $0.date > $1.date }
        let markdown = Self.standupMarkdown(range: selectedRange, commits: commits)
        standup = StandupDigest(
            range: selectedRange,
            generatedAt: .now,
            commits: commits,
            markdown: markdown
        )
    }

    func copyStandup() {
        guard let markdown = standup?.markdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        showToast("Copied standup digest")
    }

    private static func standupMarkdown(range: StandupRange, commits: [StandupCommit]) -> String {
        var lines: [String] = [
            "# Standup — \(range.title)",
            "",
            "_Generated \(Date().formatted(date: .abbreviated, time: .shortened))_",
            ""
        ]

        guard !commits.isEmpty else {
            lines.append("No commits in this range.")
            return lines.joined(separator: "\n")
        }

        let grouped = Dictionary(grouping: commits, by: \.repository)
        for repository in grouped.keys.sorted() {
            lines.append("## \(repository)")
            for commit in grouped[repository] ?? [] {
                lines.append(
                    "- \(commit.subject) (`\(commit.shortSHA)`) — \(commit.author), \(commit.date.relativeDescription)"
                )
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Repository janitor

    func loadJanitor() async {
        guard let repository = selectedRepository else {
            resetJanitor()
            return
        }

        janitorGeneration += 1
        let generation = janitorGeneration
        isScanningJanitor = true
        defer { if generation == janitorGeneration { isScanningJanitor = false } }

        let base = flowSummary?.base ?? snapshot?.currentBranch?.name
        let branches = (try? await git.staleBranches(at: repository.url, base: base)) ?? []
        let ignores = (try? await git.ignoreSuggestions(at: repository.url)) ?? []

        guard generation == janitorGeneration else { return }
        staleBranches = branches
        ignoreSuggestions = ignores
    }

    func scanLargeObjects() async {
        guard let repository = selectedRepository else { return }
        janitorGeneration += 1
        let generation = janitorGeneration
        isScanningJanitor = true
        defer { if generation == janitorGeneration { isScanningJanitor = false } }

        let objects = (try? await git.largeObjects(at: repository.url)) ?? []
        guard generation == janitorGeneration else { return }
        largeObjects = objects
        hasScannedLargeObjects = true
    }

    func deleteStaleBranches(_ branches: [StaleBranch]) async {
        guard let repository = selectedRepository, !branches.isEmpty else { return }
        let succeeded = await withActivity("Deleting branches…") { () -> Bool in
            for branch in branches {
                _ = try? await self.git.createBranchSnapshot(
                    branch: branch.name,
                    at: repository.url,
                    identity: self.settings.identity
                )
                try await self.git.deleteBranch(branch.name, at: repository.url, force: true)
            }
            return true
        }
        if succeeded == true {
            showToast("Deleted \(branches.count) branch\(branches.count == 1 ? "" : "es")")
            await loadJanitor()
            await refresh(showSpinner: false)
        }
    }

    func applyIgnoreSuggestions(_ suggestions: [GitignoreSuggestion]) async {
        guard let repository = selectedRepository, !suggestions.isEmpty else { return }
        let succeeded = await withActivity("Updating .gitignore…") { () -> Bool in
            try await self.git.appendGitignore(suggestions.map(\.pattern), at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Updated .gitignore")
            await loadJanitor()
            await refresh(showSpinner: false)
        }
    }

    private func resetJanitor() {
        staleBranches = []
        largeObjects = []
        ignoreSuggestions = []
        hasScannedLargeObjects = false
        isScanningJanitor = false
        janitorGeneration += 1
    }

    // MARK: - Staging

    func toggleStaging(_ change: FileChange) async {
        guard let repository = selectedRepository else { return }

        await withActivity(change.staged ? "Unstaging…" : "Staging…") {
            if change.staged {
                try await self.git.unstage(
                    paths: change.affectedPaths,
                    at: repository.url,
                    hasCommits: self.snapshot?.hasCommits ?? false
                )
            } else {
                try await self.git.stage(paths: change.affectedPaths, at: repository.url)
            }
        }
        await refresh(showSpinner: false)
    }

    func stageAll() async {
        guard let repository = selectedRepository else { return }
        let paths = unstagedChanges.flatMap(\.affectedPaths)
        guard !paths.isEmpty else { return }

        await withActivity("Staging all…") {
            try await self.git.stage(paths: paths, at: repository.url)
        }
        await refresh(showSpinner: false)
    }

    func unstageAll() async {
        guard let repository = selectedRepository else { return }
        let paths = stagedChanges.flatMap(\.affectedPaths)
        guard !paths.isEmpty else { return }

        await withActivity("Unstaging all…") {
            try await self.git.unstage(
                paths: paths,
                at: repository.url,
                hasCommits: self.snapshot?.hasCommits ?? false
            )
        }
        await refresh(showSpinner: false)
    }

    func discard(_ change: FileChange) async {
        guard let repository = selectedRepository else { return }
        await captureWorkingTreeBefore("Before discarding \(change.displayName)")

        await withActivity("Discarding changes…") {
            try await self.git.discard(
                changes: [change],
                at: repository.url,
                hasCommits: self.snapshot?.hasCommits ?? false
            )
        }
        await refresh(showSpinner: false)
    }

    func discardAllChanges() async {
        guard let repository = selectedRepository else { return }
        let changes = allChanges
        guard !changes.isEmpty else { return }
        await captureWorkingTreeBefore("Before discarding all changes")

        await withActivity("Discarding all changes…") {
            try await self.git.discard(
                changes: changes,
                at: repository.url,
                hasCommits: self.snapshot?.hasCommits ?? false
            )
        }
        await refresh(showSpinner: false)
    }

    // MARK: - Stashes

    func saveStash() async {
        guard let repository = selectedRepository else { return }
        guard !allChanges.isEmpty else {
            present(title: "Nothing to stash", message: "There are no local changes to save.")
            return
        }

        let message = stashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded = await withActivity("Saving stash…") { () -> Bool in
            try await self.git.createStash(
                message: message.isEmpty ? nil : message,
                at: repository.url
            )
            return true
        }
        if succeeded == true {
            stashMessage = ""
            showToast("Saved changes to a stash")
        }
        await refresh(showSpinner: false)
    }

    func applyStash(_ stash: StashInfo) async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Applying stash…") { () -> Bool in
            try await self.git.applyStash(sha: stash.sha, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Applied “\(stash.message)”") }
        await refresh(showSpinner: false)
    }

    func popStash(_ stash: StashInfo) async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Popping stash…") { () -> Bool in
            try await self.git.popStash(sha: stash.sha, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Applied and removed “\(stash.message)”") }
        await refresh(showSpinner: false)
    }

    func dropStash(_ stash: StashInfo) async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Dropping stash…") { () -> Bool in
            try await self.git.dropStash(sha: stash.sha, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Dropped “\(stash.message)”") }
        await refresh(showSpinner: false)
    }

    // MARK: - Commit

    func commit() async {
        guard let repository = selectedRepository else { return }
        let amending = isAmendingLastCommit
        let staged = stagedChanges
        if !amending {
            guard !staged.isEmpty else {
                present(title: "Nothing staged", message: "Select the files you want to include in this commit.")
                return
            }
        }

        let summary = commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            present(title: "Add a summary", message: "A commit needs a short summary.")
            return
        }

        let description = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = description.isEmpty ? summary : summary + "\n\n" + description
        let identity = settings.identity
        let count = staged.count

        let succeeded = await withActivity(amending ? "Amending…" : "Committing…") { () -> Bool in
            if amending {
                try await self.git.amendCommit(message: message, at: repository.url, identity: identity)
            } else {
                try await self.git.commit(message: message, at: repository.url, identity: identity)
            }
            return true
        }

        if succeeded == true {
            commitSummary = ""
            commitDescription = ""
            isDescriptionExpanded = false
            isAmendingLastCommit = false
            if amending {
                showToast("Amended the last commit")
            } else {
                showToast("Committed \(count) change\(count == 1 ? "" : "s")")
            }
        }
        await refresh(showSpinner: false)
    }

    // MARK: - Amending & undo

    var canAmendLastCommit: Bool {
        selectedRepository != nil && !isBusy && !commits.isEmpty
    }

    func beginAmendLastCommit() async {
        guard let repository = selectedRepository, let latest = commits.first else { return }
        await captureCommitBefore()

        let body: String
        if let detail = commitDetail, detail.commit.sha == latest.sha {
            body = detail.body
        } else {
            body = (try? await git.commitDetail(at: repository.url, commit: latest))?.body ?? ""
        }

        commitSummary = latest.subject
        commitDescription = body
        isDescriptionExpanded = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isAmendingLastCommit = true
        tab = .changes
    }

    func cancelAmendLastCommit() {
        isAmendingLastCommit = false
        commitSummary = ""
        commitDescription = ""
        isDescriptionExpanded = false
    }

    func undoLastCommit() async {
        guard let repository = selectedRepository, !commits.isEmpty else { return }
        await captureCommitBefore()
        let succeeded = await withActivity("Undoing last commit…") { () -> Bool in
            try await self.git.undoLastCommit(at: repository.url)
            return true
        }
        if succeeded == true {
            isAmendingLastCommit = false
            commitSummary = ""
            commitDescription = ""
            isDescriptionExpanded = false
            showToast("Undid the last commit")
        }
        await refresh(showSpinner: false)
    }

    // MARK: - Remotes

    func fetch() async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Fetching…") { () -> Bool in
            try await self.git.fetch(at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Fetched from \(snapshot?.remoteOrDefaultName ?? "origin")")
        }
        await refresh(showSpinner: false)
    }

    func pull() async {
        guard let repository = selectedRepository else { return }
        var message = "Pulled changes"
        let succeeded = await withActivity("Pulling…") { () -> Bool in
            message = try await self.git.pull(at: repository.url)
            return true
        }
        if succeeded == true { showToast(message) }
        await refresh(showSpinner: false)
    }

    func push() async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Pushing…") { () -> Bool in
            try await self.git.push(at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Pushed to \(snapshot?.remoteOrDefaultName ?? "origin")")
        }
        await refresh(showSpinner: false)
    }

    func publishBranch() async {
        guard let repository = selectedRepository,
              let snapshot,
              snapshot.hasCommits,
              !snapshot.branch.isEmpty,
              snapshot.hasRemote else { return }
        let branch = snapshot.branch
        let remote = snapshot.remoteOrDefaultName
        let succeeded = await withActivity("Publishing…") { () -> Bool in
            try await self.git.publish(branch: branch, remote: remote, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Published “\(branch)”") }
        await refresh(showSpinner: false)
    }

    // MARK: - Remotes management

    func loadRemotes() async {
        guard let repository = selectedRepository else {
            remotes = []
            return
        }
        remotes = (try? await git.remotes(at: repository.url)) ?? []
    }

    @discardableResult
    func addRemote(name rawName: String, url rawURL: String) async -> Bool {
        guard let repository = selectedRepository else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !url.isEmpty else {
            present(title: "Remote details required", message: "Enter both a remote name and a URL.")
            return false
        }
        guard !name.contains(" "), !name.contains("/") else {
            present(title: "Invalid remote name", message: "Remote names can’t contain spaces or slashes.")
            return false
        }

        let succeeded = await withActivity("Adding remote…") { () -> Bool in
            try await self.git.addRemote(name: name, url: url, at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Added remote “\(name)”")
            await loadRemotes()
            await refresh(showSpinner: false)
        }
        return succeeded == true
    }

    @discardableResult
    func updateRemoteURL(_ remote: GitRemote, url rawURL: String) async -> Bool {
        guard let repository = selectedRepository else { return false }
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            present(title: "URL required", message: "Enter a URL for this remote.")
            return false
        }

        let succeeded = await withActivity("Updating remote…") { () -> Bool in
            try await self.git.setRemoteURL(name: remote.name, url: url, at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Updated remote “\(remote.name)”")
            await loadRemotes()
            await refresh(showSpinner: false)
        }
        return succeeded == true
    }

    func removeRemote(_ remote: GitRemote) async {
        guard let repository = selectedRepository else { return }
        let succeeded = await withActivity("Removing remote…") { () -> Bool in
            try await self.git.removeRemote(name: remote.name, at: repository.url)
            return true
        }
        if succeeded == true {
            showToast("Removed remote “\(remote.name)”")
            await loadRemotes()
            await refresh(showSpinner: false)
        }
    }

    // MARK: - Branches

    func switchBranch(_ branch: BranchInfo) async {
        guard let repository = selectedRepository, !branch.isCurrent else { return }

        // Prefer an existing local branch when the user picks a remote one,
        // otherwise `--track -c` would fail for an already-existing name.
        let localMatch = branch.isRemote
            ? snapshot?.localBranches.first { $0.name == branch.displayName }
            : nil
        if let localMatch, localMatch.isCurrent { return }

        let succeeded = await withActivity("Switching to \(branch.displayName)…") { () -> Bool in
            if let localMatch {
                try await self.git.checkout(branch: localMatch.name, at: repository.url)
            } else if branch.isRemote {
                try await self.git.checkoutRemote(
                    fullName: branch.name,
                    localName: branch.displayName,
                    at: repository.url
                )
            } else {
                try await self.git.checkout(branch: branch.name, at: repository.url)
            }
            return true
        }

        if succeeded == true { showToast("Checked out “\(branch.displayName)”") }
        await refresh(showSpinner: false)
    }

    @discardableResult
    func createBranch(named rawName: String, checkout: Bool) async -> Bool {
        guard let repository = selectedRepository else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            present(title: "Name required", message: "Enter a name for the new branch.")
            return false
        }
        guard !name.contains(" "), !name.hasPrefix("-"), !name.hasSuffix(".") else {
            present(title: "Invalid branch name", message: "Branch names can't contain spaces or start with “-”.")
            return false
        }

        let succeeded = await withActivity("Creating branch…") { () -> Bool in
            try await self.git.createBranch(name: name, at: repository.url, checkout: checkout)
            return true
        }

        if succeeded == true {
            showToast(checkout ? "Created and switched to “\(name)”" : "Created branch “\(name)”")
        }
        await refresh(showSpinner: false)
        return succeeded == true
    }

    func merge(_ branch: BranchInfo) async {
        guard let repository = selectedRepository, !branch.isCurrent, !branch.isRemote else { return }
        await captureWorkingTreeBefore("Before merging \(branch.name)")

        let conflicted = await withActivity("Merging \(branch.name)…") { () -> Bool in
            let clean = try await self.git.merge(
                branch: branch.name,
                at: repository.url,
                identity: self.settings.identity
            )
            return !clean
        }

        if conflicted == true {
            showToast("Merge has conflicts to resolve")
            tab = .changes
        } else if conflicted == false {
            showToast("Merged “\(branch.name)”")
        }
        await refresh(showSpinner: false)
    }

    @discardableResult
    func renameBranch(_ branch: BranchInfo, to rawName: String) async -> Bool {
        guard let repository = selectedRepository, !branch.isRemote else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            present(title: "Name required", message: "Enter a new name for the branch.")
            return false
        }
        guard name != branch.name else { return true }
        guard !name.contains(" "), !name.hasPrefix("-"), !name.hasSuffix(".") else {
            present(title: "Invalid branch name", message: "Branch names can't contain spaces or start/end with punctuation.")
            return false
        }

        let succeeded = await withActivity("Renaming branch…") { () -> Bool in
            try await self.git.renameBranch(from: branch.name, to: name, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Renamed “\(branch.name)” to “\(name)”") }
        await refresh(showSpinner: false)
        return succeeded == true
    }

    func deleteBranch(_ branch: BranchInfo) async {
        guard let repository = selectedRepository, !branch.isCurrent, !branch.isRemote else { return }
        await captureBranchBefore(branch)
        let succeeded = await withActivity("Deleting branch…") { () -> Bool in
            // The user already confirmed, so use the force flag: unmerged
            // branches should still be deletable from the manager.
            try await self.git.deleteBranch(branch.name, at: repository.url, force: true)
            return true
        }
        if succeeded == true { showToast("Deleted “\(branch.name)”") }
        await refresh(showSpinner: false)
    }

    // MARK: - History actions

    func cherryPick(_ commit: CommitInfo) async {
        guard let repository = selectedRepository else { return }
        await captureWorkingTreeBefore("Before cherry-picking \(commit.shortSHA)")

        let conflicted = await withActivity("Cherry-picking \(commit.shortSHA)…") { () -> Bool in
            let clean = try await self.git.cherryPick(
                commit: commit.sha,
                at: repository.url,
                identity: self.settings.identity
            )
            return !clean
        }

        if conflicted == true {
            showToast("Cherry-pick has conflicts to resolve")
            tab = .changes
        } else if conflicted == false {
            showToast("Cherry-picked \(commit.shortSHA)")
        }
        await refresh(showSpinner: false)
    }

    func revert(_ commit: CommitInfo) async {
        guard let repository = selectedRepository else { return }
        await captureCommitBefore()
        let identity = settings.identity
        let succeeded = await withActivity("Reverting \(commit.shortSHA)…") { () -> Bool in
            try await self.git.revert(
                commit: commit.sha,
                at: repository.url,
                identity: identity,
                isMerge: commit.isMerge
            )
            return true
        }
        if succeeded == true { showToast("Reverted “\(commit.subject)”") }
        await refresh(showSpinner: false)
    }

    func copySHA(_ commit: CommitInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.sha, forType: .string)
        showToast("Copied commit SHA")
    }

    // MARK: - Repositories

    @discardableResult
    func addExistingRepository(at url: URL) async -> Bool {
        guard await git.isRepository(url) else {
            present(
                title: "Not a Git repository",
                message: "“\(url.lastPathComponent)” doesn’t contain a Git repository."
            )
            return false
        }

        let rootPath = (try? await git.snapshot(at: url).rootPath) ?? url.path
        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL

        if let existing = repositories.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL == standardizedRoot
        }) {
            selectedRepositoryID = existing.id
            return true
        }

        let reference = RepositoryRef(name: (rootPath as NSString).lastPathComponent, path: rootPath)
        repositories.append(reference)
        persistRepositories()
        selectedRepositoryID = reference.id
        return true
    }

    func cloneRepository(remote: String, into parent: URL, name: String) async throws -> RepositoryRef {
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitError.invalidInput("A folder named “\(name)” already exists in that location.")
        }

        try await git.clone(remote: remote, to: destination)
        return addRepositoryReference(named: name, path: destination.path)
    }

    func createRepository(named name: String, in parent: URL) async throws -> RepositoryRef {
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitError.invalidInput("A folder named “\(name)” already exists in that location.")
        }

        try await git.createRepository(at: destination)
        return addRepositoryReference(named: name, path: destination.path)
    }

    func removeRepository(_ reference: RepositoryRef) {
        repositories.removeAll { $0.id == reference.id }
        if selectedRepositoryID == reference.id {
            selectedRepositoryID = repositories.max(by: { $0.lastOpened < $1.lastOpened })?.id
        }
        persistRepositories()
    }

    func revealInFinder(_ reference: RepositoryRef) {
        NSWorkspace.shared.activateFileViewerSelecting([reference.url])
    }

    func openInTerminal(_ reference: RepositoryRef) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([reference.url], withApplicationAt: terminal, configuration: configuration)
    }

    private func addRepositoryReference(named name: String, path: String) -> RepositoryRef {
        let reference = RepositoryRef(name: name, path: path)
        repositories.append(reference)
        persistRepositories()
        selectedRepositoryID = reference.id
        return reference
    }

    private func persistRepositories() {
        Persistence.saveRepositories(repositories)
    }

    // MARK: - Alerts & toasts

    func present(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    func present(_ error: Error) {
        if let gitError = error as? GitError {
            var message = gitError.errorDescription ?? "The git command failed."
            if let suggestion = gitError.recoverySuggestion {
                message += "\n\n" + suggestion
            }
            alert = AppAlert(title: "Git error", message: message)
        } else {
            alert = AppAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func showToast(_ text: String) {
        let message = ToastMessage(text: text)
        toast = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.toast?.id == message.id else { return }
            self.toast = nil
        }
    }

    // MARK: - Busy tracking

    @discardableResult
    private func withActivity<T>(_ label: String, _ operation: () async throws -> T) async -> T? {
        busyCount += 1
        activityLabel = label
        defer {
            busyCount = max(0, busyCount - 1)
            if busyCount == 0 { activityLabel = nil }
        }

        do {
            return try await operation()
        } catch {
            present(error)
            return nil
        }
    }
}
