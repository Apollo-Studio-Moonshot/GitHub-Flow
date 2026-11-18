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
    case history
    case stashes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .stashes: "Stashes"
        }
    }

    var symbol: String {
        switch self {
        case .changes: "square.stack.3d.up"
        case .history: "clock.arrow.circlepath"
        case .stashes: "archivebox"
        }
    }
}

enum SheetRoute: String, Identifiable, Hashable {
    case clone
    case create
    case newBranch

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
    var showsDiscardAllConfirmation = false

    // MARK: - Generation tokens

    private var diffGeneration = 0
    private var detailGeneration = 0

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
            && !stagedChanges.isEmpty
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
        isLoading = true
        diffGeneration += 1
        detailGeneration += 1
    }

    /// Called when the selected repository's view appears or the selection changes.
    func loadSelectedRepository() async {
        guard selectedRepository != nil else { return }
        if loadedRepositoryID != selectedRepositoryID {
            loadedRepositoryID = selectedRepositoryID
            resetRepositoryState()
        }
        await refresh()
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
        guard newSnapshot != snapshot else { return }

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
        let staged = stagedChanges
        guard !staged.isEmpty else {
            present(title: "Nothing staged", message: "Select the files you want to include in this commit.")
            return
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

        let succeeded = await withActivity("Committing…") { () -> Bool in
            try await self.git.commit(message: message, at: repository.url, identity: identity)
            return true
        }

        if succeeded == true {
            commitSummary = ""
            commitDescription = ""
            isDescriptionExpanded = false
            showToast("Committed \(count) change\(count == 1 ? "" : "s")")
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
        guard let repository = selectedRepository, let snapshot, !snapshot.branch.isEmpty else { return }
        let branch = snapshot.branch
        let succeeded = await withActivity("Publishing…") { () -> Bool in
            try await self.git.publish(branch: branch, at: repository.url)
            return true
        }
        if succeeded == true { showToast("Published “\(branch)”") }
        await refresh(showSpinner: false)
    }

    // MARK: - Branches

    func switchBranch(_ branch: BranchInfo) async {
        guard let repository = selectedRepository, !branch.isCurrent else { return }

        let succeeded = await withActivity("Switching to \(branch.displayName)…") { () -> Bool in
            if branch.isRemote {
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

    // MARK: - History actions

    func revert(_ commit: CommitInfo) async {
        guard let repository = selectedRepository else { return }
        let identity = settings.identity
        let succeeded = await withActivity("Reverting \(commit.shortSHA)…") { () -> Bool in
            try await self.git.revert(commit: commit.sha, at: repository.url, identity: identity)
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
