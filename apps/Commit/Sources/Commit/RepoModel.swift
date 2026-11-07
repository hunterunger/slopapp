import AppKit
import CommitCore
import Observation
import SlopKit
import SwiftUI

/// A file row in the Changes column: the same path can be in both sections.
struct FileRowID: Hashable, Sendable {
    enum Area: Hashable, Sendable { case conflicted, staged, unstaged }
    var path: String
    var area: Area
}

enum SidebarItem: Hashable {
    case changes, history, stashes
    /// A branch or tag: its history.
    case ref(String)
}

/// Something running, shown in the toolbar.
struct Activity: Equatable {
    var title: String
    var progress: GitProgress?
    var isCancellable: Bool
}

/// A failure shown in a banner until dismissed.
struct Problem: Identifiable, Equatable {
    let id = UUID()
    var explanation: Explanation
    var command: String
}

/// The sheets a repository window can show.
enum RepoSheet: Identifiable, Equatable {
    case newBranch(from: ObjectID?, fromLabel: String)
    case stash
    case output(title: String, output: String)
    case divergentPull
    case identity

    var id: String {
        switch self {
        case .newBranch: "newBranch"
        case .stash: "stash"
        case .output: "output"
        case .divergentPull: "divergent"
        case .identity: "identity"
        }
    }
}

/// A question the window asks with an alert.
struct Confirmation: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var isDestructive: Bool
    var action: @MainActor () -> Void
}

/// A diff on screen, and what it belongs to.
struct DiffState: Equatable {
    enum Source: Equatable {
        case none
        case workingCopy(entry: StatusEntry, staged: Bool)
        case commit(ObjectID, ChangedFile)
        case stash(ObjectID, ChangedFile)
        case multiple(Int)
    }

    var source: Source = .none
    var result: DiffResult?
    var isLoading = false
    var error: String?
    var lineSelection: Set<LineRef> = []
    /// "Show Full Diff" was pressed for a huge diff.
    var showsFull = false
    /// Bumped to scroll the diff to a hunk.
    var scrollToHunk: Int?
    var scrollRequest = 0

    var isEditable: Bool {
        if case .workingCopy(let entry, _) = source { return !entry.isSubmodule && !entry.isConflicted }
        return false
    }
    var isStagedSide: Bool {
        if case .workingCopy(_, let staged) = source { return staged }
        return false
    }
}

/// A prompt from git waiting in a sheet.
struct PendingPrompt: Identifiable {
    var prompt: AskpassPrompt
    var id: UUID { prompt.id }
    let continuation: CheckedContinuation<String?, Never>
}

/// History rows live outside observation (100,000 of them); `RepoModel.historyRevision`
/// tells views when they changed.
@MainActor
final class HistoryStore {
    var rows: [CommitRow] = []
    var layout = GraphLayout()
    var authors = AuthorTable()
    var scope: HistoryScope?
    var isLoading = false
    var failed: String?
    var task: Task<Void, Never>?
    /// Row indices matching the search, or nil when not searching.
    var filtered: [Int]?

    func reset() {
        task?.cancel()
        task = nil
        rows = []
        layout = GraphLayout()
        authors = AuthorTable()
        filtered = nil
        failed = nil
    }
}

@MainActor
@Observable
final class RepoModel: Identifiable {
    let id = UUID()
    let url: URL
    @ObservationIgnored let app: AppModel

    private(set) var repository: Repository?
    private(set) var openProblem: OpenProblem?
    private(set) var isOpening = true

    // Data
    private(set) var status = WorkingTreeStatus()
    private(set) var refs = RefList()
    private(set) var stashes: [StashEntry] = []
    private(set) var inProgress: InProgressOperation?
    private(set) var hasLoadedStatus = false

    // Navigation
    var sidebarSelection: SidebarItem? = .changes {
        didSet { if oldValue != sidebarSelection { sidebarChanged() } }
    }
    var searchText = "" { didSet { if oldValue != searchText { applySearch() } } }
    var isSearchPresented = false
    var branchFilter = ""
    var showBranchSwitcher = false

    // Changes
    var fileSelection: Set<FileRowID> = [] {
        didSet { if oldValue != fileSelection { fileSelectionChanged() } }
    }
    var diff = DiffState()
    var contextLines = UserDefaults.standard.integer(forKey: Preference.contextLines)
    var ignoreWhitespace = false

    // Composer
    var message = CommitMessage() { didSet { if oldValue != message { scheduleDraftSave() } } }
    var amend = false
    var identity = Repository.Identity()
    var headPushed = false
    var composerFocusRequest = 0
    /// Bumped after a commit: the composer gives up focus, so ⌘Z means "undo the commit".
    var composerResignRequest = 0
    var composerFocused = false
    var branchFilterFocused = false
    /// A text field or editor has focus (the composer, a filter or the search field).
    var isEditingText: Bool { composerFocused || branchFilterFocused || isSearchPresented }

    // History
    @ObservationIgnored let history = HistoryStore()
    private(set) var historyRevision = 0
    var historySelection: ObjectID? { didSet { if oldValue != historySelection { loadCommitDetail() } } }
    /// The "Uncommitted Changes" row is selected.
    var showAllBranches = false
    private(set) var commitDetail: CommitDetail?
    private(set) var commitFiles: [ChangedFile] = []
    var commitFileSelection: ChangedFile.ID? { didSet { if oldValue != commitFileSelection { loadCommitFileDiff() } } }

    // Stashes
    var stashSelection: ObjectID? { didSet { if oldValue != stashSelection { loadStashDetail() } } }
    private(set) var stashFiles: [ChangedFile] = []
    var stashFileSelection: ChangedFile.ID? { didSet { if oldValue != stashFileSelection { loadStashFileDiff() } } }

    // Activity, problems, sheets
    private(set) var activity: Activity?
    var problem: Problem?
    var sheet: RepoSheet?
    var confirmation: Confirmation?
    var prompt: PendingPrompt?
    var undoManager: UndoManager?
    /// The window, for its undo manager (the one Edit › Undo uses).
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private var refreshScheduler: RefreshScheduler?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var needsRefs = true
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var autoFetchTask: Task<Void, Never>?
    @ObservationIgnored private var drafts: DraftStore?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastHead: ObjectID?
    @ObservationIgnored private var lastRefs: RefList?
    @ObservationIgnored private var lastCommit: (head: ObjectID, previous: ObjectID?)?
    @ObservationIgnored private var openedAt = ContinuousClock.now

    init(url: URL, app: AppModel) {
        self.url = url
        self.app = app
        if contextLines <= 0 { contextLines = 3 }
    }

    // MARK: Opening and closing

    func open() async {
        openedAt = .now
        await app.waitUntilReady()
        guard let runner = app.runner(for: id) else {
            isOpening = false
            return
        }
        do {
            let location = try await Repository.locate(url, runner: runner)
            let repository = Repository(location: location, runner: runner)
            self.repository = repository
            app.register(self)
            app.noteOpened(location.root)
            drafts = (try? AppPaths.applicationSupport).map { DraftStore(directory: $0) }
            if let draft = drafts?.draft(for: location.root.path) { message = draft }
            // Status first, so the file list shows as soon as git has it; branches and stashes
            // (7,000 refs take a while) follow.
            await refresh(includeRefs: false)
            isOpening = false
            Task { await refresh(includeRefs: true) }
            Diagnostics.record("open_to_status_ms=\(Diagnostics.milliseconds(since: openedAt)) repo=\(location.root.lastPathComponent) files=\(status.changedCount)")
            if status.isClean && !status.branch.isUnborn && sidebarSelection == .changes { sidebarSelection = .history }
            switch Diagnostics.section {
            case "history": sidebarSelection = .history
            case "stashes": sidebarSelection = .stashes
            case "changes": sidebarSelection = .changes
            default: break
            }
            if let path = Diagnostics.select, let row = rowIDs().first(where: { $0.path == path && $0.area == .unstaged })
                ?? rowIDs().first(where: { $0.path == path }) {
                fileSelection = [row]
            }
            selectFirstFileIfNeeded()
            startWatching(location)
            scheduleAutoFetch()
            Task { identity = await repository.identity() }
        } catch let problem as OpenProblem {
            openProblem = problem
            isOpening = false
        } catch {
            openProblem = .git(String(describing: error))
            isOpening = false
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        refreshScheduler?.cancel()
        history.reset()
        diffTask?.cancel()
        detailTask?.cancel()
        autoFetchTask?.cancel()
        activityTask?.cancel()
        flushDraft()
        prompt?.continuation.resume(returning: nil)
        prompt = nil
        (window?.undoManager ?? undoManager)?.removeAllActions(withTarget: self)
        confirmation = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        app.unregister(self)
    }

    var title: String { repository?.root.lastPathComponent ?? url.lastPathComponent }

    private func startWatching(_ location: RepositoryLocation) {
        let scheduler = RefreshScheduler { [weak self] in
            guard let self else { return }
            let refs = self.needsRefs
            self.needsRefs = false
            await self.refresh(includeRefs: refs)
        }
        refreshScheduler = scheduler
        let classifier = RepoEventClassifier(root: location.root, gitDirectory: location.gitDirectory)
        var paths = [location.root.path]
        let gitReal = RepoEventClassifier.realPath(location.gitDirectory.path)
        if !gitReal.hasPrefix(RepoEventClassifier.realPath(location.root.path) + "/") { paths.append(location.gitDirectory.path) }
        watcher = FileWatcher(paths: paths) { [weak self] changed in
            var any = false, git = false
            for path in changed {
                switch classifier.classify(path) {
                case .ignore: continue
                case .worktree: any = true
                case .gitState: any = true; git = true
                }
            }
            guard any else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if git { self.needsRefs = true }
                self.refreshScheduler?.signal()
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshNow(full: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .commitSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        })
    }

    /// Window became key: cheap insurance against missed events.
    func windowActivated() {
        guard repository != nil, !isOpening else { return }
        needsRefs = true
        refreshScheduler?.signal()
    }

    func refreshNow(full: Bool) {
        if full { needsRefs = true }
        refreshScheduler?.refreshNow()
    }

    // MARK: Refresh

    /// Status (and branches, stashes, state when `includeRefs`), then whatever is on screen.
    func refresh(includeRefs: Bool) async {
        guard let repository else { return }
        let showUntracked = UserDefaults.standard.bool(forKey: Preference.showUntracked)
        do {
            async let newStatus = repository.status(includeUntracked: showUntracked)
            if includeRefs {
                async let newRefs = repository.refs()
                async let newStashes = repository.stashes()
                let (s, r, st) = try await (newStatus, newRefs, newStashes)
                applyStatus(s)
                refs = r
                stashes = st
            } else {
                applyStatus(try await newStatus)
            }
        } catch {
            if !FileManager.default.fileExists(atPath: repository.root.path) {
                openProblem = .missing(repository.root)
            }
            return
        }
        inProgress = repository.inProgressOperation()
        hasLoadedStatus = true
        // Keep the diff and the history in step.
        if case .workingCopy = diff.source { reloadDiff(keepSelection: false) }
        let head = status.branch.head
        if head != lastHead || (includeRefs && refs != lastRefs) {
            lastHead = head
            lastRefs = refs
            if history.scope != nil { reloadHistory() }
            if amend { Task { headPushed = await repository.isHeadPushed() } }
        }
        if let selection = stashSelection, !stashes.contains(where: { $0.id == selection }) { stashSelection = nil }
    }

    private func applyStatus(_ new: WorkingTreeStatus) {
        let previous = status
        status = new
        // Keep the selection on the same rows; if a selected row went away (its file was
        // staged or unstaged), select the row that took its place so ↓ Space ↓ Space works.
        let valid = Set(rowIDs())
        let kept = fileSelection.filter { valid.contains($0) }
        if kept.count != fileSelection.count {
            if kept.isEmpty, let lost = fileSelection.first {
                fileSelection = replacementSelection(for: lost, previous: previous)
            } else {
                fileSelection = kept
            }
        }
    }

    private func replacementSelection(for lost: FileRowID, previous: WorkingTreeStatus) -> Set<FileRowID> {
        let oldList = rows(in: lost.area, of: previous)
        let newList = rows(in: lost.area, of: status)
        if let index = oldList.firstIndex(where: { $0.path == lost.path }), !newList.isEmpty {
            let target = newList[min(index, newList.count - 1)]
            return [FileRowID(path: target.path, area: lost.area)]
        }
        // The section emptied: follow the file to the other section.
        let other: FileRowID.Area = lost.area == .unstaged ? .staged : .unstaged
        if rows(in: other, of: status).contains(where: { $0.path == lost.path }) { return [FileRowID(path: lost.path, area: other)] }
        if let first = rowIDs().first { return [first] }
        return []
    }

    func rows(in area: FileRowID.Area, of status: WorkingTreeStatus? = nil) -> [StatusEntry] {
        let s = status ?? self.status
        switch area {
        case .conflicted: return s.conflicted
        case .staged: return s.staged
        case .unstaged: return s.unstaged
        }
    }

    /// Rows in display order (conflicts, staged, changes).
    func rowIDs() -> [FileRowID] {
        status.conflicted.map { FileRowID(path: $0.path, area: .conflicted) }
            + status.staged.map { FileRowID(path: $0.path, area: .staged) }
            + status.unstaged.map { FileRowID(path: $0.path, area: .unstaged) }
    }

    func entry(for row: FileRowID) -> StatusEntry? {
        rows(in: row.area).first { $0.path == row.path }
    }

    private func selectFirstFileIfNeeded() {
        guard fileSelection.isEmpty, let first = rowIDs().first else { return }
        fileSelection = [first]
    }

    /// Search filters the Changes lists by path.
    func matchesSearch(_ entry: StatusEntry) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || entry.path.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: Sidebar

    private func sidebarChanged() {
        switch sidebarSelection {
        case .history:
            ensureHistory(scope: currentScope())
        case .ref(let name):
            ensureHistory(scope: .refs([name]))
        case .changes:
            if case .workingCopy = diff.source {} else { fileSelectionChanged() }
            selectFirstFileIfNeeded()
        case .stashes:
            if stashSelection == nil { stashSelection = stashes.first?.id }
        case nil:
            break
        }
        if case .history = sidebarSelection {} else if case .ref = sidebarSelection {} else { applySearch() }
    }

    var isShowingHistory: Bool {
        switch sidebarSelection {
        case .history, .ref: true
        default: false
        }
    }

    // MARK: Diff (Changes)

    private func fileSelectionChanged() {
        guard sidebarSelection == .changes || diffBelongsToChanges else { return }
        reloadDiff(keepSelection: false)
    }

    private var diffBelongsToChanges: Bool {
        if case .workingCopy = diff.source { return true }
        return false
    }

    func reloadDiff(keepSelection: Bool) {
        guard let repository else { return }
        let rows = fileSelection
        guard rows.count == 1, let row = rows.first, let entry = entry(for: row) else {
            diffTask?.cancel()
            diff = DiffState(source: rows.count > 1 ? .multiple(rows.count) : .none)
            return
        }
        let staged = row.area == .staged
        let source = DiffState.Source.workingCopy(entry: entry, staged: staged)
        let sameFile = isSameFile(diff.source, source)
        if !sameFile {
            diff = DiffState(source: source, isLoading: true)
        } else {
            diff.source = source
            if !keepSelection { diff.lineSelection = [] }
        }
        let options = DiffOptions(contextLines: contextLines, ignoreWhitespace: ignoreWhitespace)
        diffTask?.cancel()
        let started = ContinuousClock.now
        diffTask = Task {
            do {
                let result = try await repository.diff(for: entry, staged: staged, options: options)
                guard !Task.isCancelled else { return }
                if diff.result != result || diff.isLoading {
                    var updated = diff
                    updated.result = result
                    updated.isLoading = false
                    updated.error = nil
                    if !keepSelection && updated.result?.file?.hunks != diff.result?.file?.hunks { updated.lineSelection = [] }
                    diff = updated
                }
                Diagnostics.record("diff_ms=\(Diagnostics.milliseconds(since: started)) lines=\(result.file?.lineCount ?? 0)")
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                diff.isLoading = false
                diff.error = (error as? GitFailure)?.output ?? String(describing: error)
            }
        }
    }

    private func isSameFile(_ a: DiffState.Source, _ b: DiffState.Source) -> Bool {
        if case .workingCopy(let e1, let s1) = a, case .workingCopy(let e2, let s2) = b { return e1.path == e2.path && s1 == s2 }
        return false
    }

    func changeContext(by step: Int) {
        let presets = [1, 3, 5, 10, 25, 100]
        let index = presets.firstIndex(where: { $0 >= contextLines }) ?? 1
        contextLines = presets[max(0, min(presets.count - 1, index + step))]
        UserDefaults.standard.set(contextLines, forKey: Preference.contextLines)
        reloadAllDiffs()
    }

    func toggleIgnoreWhitespace() {
        ignoreWhitespace.toggle()
        reloadAllDiffs()
    }

    private func reloadAllDiffs() {
        switch diff.source {
        case .workingCopy: reloadDiff(keepSelection: false)
        case .commit: loadCommitFileDiff()
        case .stash: loadStashFileDiff()
        default: break
        }
    }

    var canMoveBetweenHunks: Bool { (diff.result?.file?.hunks.count ?? 0) > 0 && !isEditingText }

    func moveToHunk(forward: Bool) {
        guard !isEditingText, let hunks = diff.result?.file?.hunks, !hunks.isEmpty else { return }
        let current = diff.scrollToHunk ?? (forward ? -1 : hunks.count)
        let next = max(0, min(hunks.count - 1, current + (forward ? 1 : -1)))
        diff.scrollToHunk = next
        diff.scrollRequest += 1
    }

    // MARK: Staging

    var selectedEntries: [(FileRowID, StatusEntry)] {
        fileSelection.sorted { $0.path < $1.path }.compactMap { row in entry(for: row).map { (row, $0) } }
    }

    var selectedConflicts: [StatusEntry] {
        selectedEntries.filter { $0.0.area == .conflicted }.map(\.1)
    }

    var canToggleSelection: Bool {
        guard sidebarSelection == .changes, !isEditingText else { return false }
        if !diff.lineSelection.isEmpty && diff.isEditable { return true }
        return !selectedEntries.isEmpty
    }

    var stageToggleTitle: String {
        if !diff.lineSelection.isEmpty && diff.isEditable {
            let n = diff.lineSelection.count
            return diff.isStagedSide ? "Unstage \(n == 1 ? "Line" : "\(n) Lines")" : "Stage \(n == 1 ? "Line" : "\(n) Lines")"
        }
        let rows = selectedEntries
        if rows.allSatisfy({ $0.0.area == .staged }) && !rows.isEmpty { return rows.count == 1 ? "Unstage File" : "Unstage \(rows.count) Files" }
        if rows.allSatisfy({ $0.0.area == .conflicted }) && !rows.isEmpty { return "Mark Resolved" }
        if !rows.isEmpty { return rows.count == 1 ? "Stage File" : "Stage \(rows.count) Files" }
        return "Stage or Unstage Selection"
    }

    /// Space / ⇧⌘Space: lines if lines are selected in the diff, else the selected files.
    func toggleSelection() {
        if !diff.lineSelection.isEmpty && diff.isEditable {
            applyLines(diff.lineSelection, discard: false)
            return
        }
        let rows = selectedEntries
        guard !rows.isEmpty else { return }
        let conflicts = rows.filter { $0.0.area == .conflicted }.map(\.1)
        if !conflicts.isEmpty { markResolved(conflicts); return }
        let staged = rows.filter { $0.0.area == .staged }.map(\.1)
        let unstaged = rows.filter { $0.0.area == .unstaged }.map(\.1)
        if !unstaged.isEmpty { stage(unstaged) } else if !staged.isEmpty { unstage(staged) }
    }

    /// The checkbox on a row.
    func setStaged(_ entry: StatusEntry, area: FileRowID.Area, staged: Bool) {
        if area == .conflicted { markResolved([entry]); return }
        staged ? stage([entry]) : unstage([entry])
    }

    func stage(_ entries: [StatusEntry]) {
        guard let repository else { return }
        let paths = entries.map(\.path)
        mutate(.stage, undoName: entries.count == 1 ? "Stage" : "Stage Files") { [weak self] in
            let snapshot = try await repository.snapshotIndex(paths: paths)
            try await repository.stage(paths: paths)
            return { [weak self] in self?.restoreIndex(snapshot, name: "Stage") }
        }
    }

    func unstage(_ entries: [StatusEntry]) {
        guard let repository else { return }
        let paths = entries.map(\.path) + entries.compactMap(\.originalPath)
        let headExists = !status.branch.isUnborn
        mutate(.unstage, undoName: entries.count == 1 ? "Unstage" : "Unstage Files") { [weak self] in
            let snapshot = try await repository.snapshotIndex(paths: paths)
            try await repository.unstage(paths: paths, headExists: headExists)
            return { [weak self] in self?.restoreIndex(snapshot, name: "Unstage") }
        }
    }

    func stageAll() {
        guard let repository else { return }
        mutate(.stage, undoName: "Stage All") { [weak self] in
            let snapshot = try await repository.snapshotWholeIndex()
            try await repository.stageAll()
            guard let snapshot else { return nil }
            return { [weak self] in self?.restoreIndex(snapshot, name: "Stage All") }
        }
    }

    func unstageAll() {
        guard let repository else { return }
        let headExists = !status.branch.isUnborn
        mutate(.unstage, undoName: "Unstage All") { [weak self] in
            let snapshot = try await repository.snapshotWholeIndex()
            try await repository.unstageAll(headExists: headExists)
            guard let snapshot else { return nil }
            return { [weak self] in self?.restoreIndex(snapshot, name: "Unstage All") }
        }
    }

    private func restoreIndex(_ snapshot: IndexSnapshot, name: String) {
        guard let repository else { return }
        mutate(.stage, undoName: name, isUndo: true) {
            try await repository.restoreIndex(snapshot)
            return nil
        }
    }

    /// Stage/unstage (or discard) the chosen lines of the diff on screen.
    func applyLines(_ selection: Set<LineRef>, discard: Bool) {
        guard let repository, case .workingCopy(let entry, let staged) = diff.source, let file = diff.result?.file,
              diff.isEditable, !ignoreWhitespace || discard == false else {
            if ignoreWhitespace { HUD.show("Show whitespace changes to stage lines.", systemImage: "exclamationmark.triangle") }
            return
        }
        if ignoreWhitespace {
            HUD.show("Show whitespace changes to stage lines.", systemImage: "exclamationmark.triangle")
            return
        }
        if discard && (staged || entry.isUntracked) { return }
        let direction: PatchBuilder.Direction = (staged || discard) ? .reverse : .forward
        guard let patch = PatchBuilder.patch(for: file, selecting: selection, direction: direction) else { return }
        let count = selection.filter { ref in file.hunks.indices.contains(ref.hunk) && file.hunks[ref.hunk].lines.indices.contains(ref.line) && file.hunks[ref.hunk].lines[ref.line].isChange }.count
        let noun = count == 1 ? "Line" : "Lines"
        let name = discard ? "Discard \(noun)" : staged ? "Unstage \(noun)" : "Stage \(noun)"
        let cached = !discard
        let reverse = staged || discard
        mutate(discard ? .discard : staged ? .unstage : .stage, undoName: name, failureHint: "The file changed. Try again.") { [weak self] in
            try await repository.apply(patch, cached: cached, reverse: reverse)
            return { [weak self] in
                guard let self, let repository = self.repository else { return }
                self.mutate(discard ? .discard : .stage, undoName: name, isUndo: true) {
                    try await repository.apply(patch, cached: cached, reverse: !reverse)
                    return nil
                }
            }
        }
        diff.lineSelection = []
    }

    func applyHunk(_ index: Int, discard: Bool) {
        guard let file = diff.result?.file else { return }
        let inHunk = diff.lineSelection.filter { $0.hunk == index }
        applyLines(inHunk.isEmpty ? PatchBuilder.changes(inHunk: index, of: file) : inHunk, discard: discard)
    }

    // MARK: Discard

    var discardTitle: String {
        if !diff.lineSelection.isEmpty && diff.isEditable && !diff.isStagedSide { return "Discard Selected Lines" }
        let n = selectedEntries.filter { $0.0.area != .conflicted }.count
        return n > 1 ? "Discard Changes to \(n) Files…" : "Discard Changes…"
    }

    var canDiscardSelection: Bool {
        guard sidebarSelection == .changes, !isEditingText else { return false }
        if !diff.lineSelection.isEmpty && diff.isEditable && !diff.isStagedSide {
            if case .workingCopy(let entry, _) = diff.source { return !entry.isUntracked }
        }
        return selectedEntries.contains { $0.0.area != .conflicted }
    }

    func discardSelection() {
        guard canDiscardSelection else { NSSound.beep(); return }
        if !diff.lineSelection.isEmpty && diff.isEditable && !diff.isStagedSide {
            applyLines(diff.lineSelection, discard: true)
            return
        }
        let rows = selectedEntries.filter { $0.0.area != .conflicted }
        guard !rows.isEmpty else { return }
        discardFiles(rows.map(\.1), keepStaged: rows.allSatisfy { $0.0.area == .unstaged })
    }

    func discardFiles(_ entries: [StatusEntry], keepStaged: Bool) {
        guard let repository else { return }
        let names = entries.count == 1 ? "“\(entries[0].nameAndFolder.name)”" : "\(entries.count) files"
        confirmation = Confirmation(
            title: "Discard changes to \(names)?",
            message: keepStaged
                ? "Your unstaged changes are saved in a stash, so you can undo this or get them back from Stashes."
                : "All changes, staged and unstaged, are saved in a stash, so you can undo this or get them back from Stashes.",
            confirmTitle: "Discard", isDestructive: true
        ) { [weak self] in
            self?.mutate(.discard, undoName: "Discard") {
                let record = try await repository.discard(entries, keepStaged: keepStaged)
                return { [weak self] in self?.undoDiscard(record) }
            }
        }
    }

    func confirmDiscardAll() {
        guard let repository else { return }
        confirmation = Confirmation(
            title: "Discard all changes?",
            message: "Every staged, unstaged and new file goes back to the last commit. The changes are saved in a stash, so you can undo this.",
            confirmTitle: "Discard All", isDestructive: true
        ) { [weak self] in
            self?.mutate(.discard, undoName: "Discard All") {
                let record = try await repository.discardAll()
                return { [weak self] in self?.undoDiscard(record) }
            }
        }
    }

    private func undoDiscard(_ record: DiscardRecord) {
        guard let repository else { return }
        mutate(.discard, undoName: "Discard", isUndo: true) {
            try await repository.undoDiscard(record)
            return nil
        }
    }

    // MARK: Conflicts

    func markSelectedResolved() { markResolved(selectedConflicts) }

    func markResolved(_ entries: [StatusEntry]) {
        guard let repository, !entries.isEmpty else { return }
        let withMarkers = entries.filter { repository.hasConflictMarkers($0.path) }
        let run: @MainActor () -> Void = { [weak self] in
            self?.mutate(.stage, undoName: nil) {
                try await repository.stage(paths: entries.map(\.path))
                return nil
            }
        }
        if withMarkers.isEmpty { run(); return }
        confirmation = Confirmation(
            title: "“\(withMarkers[0].nameAndFolder.name)” still has conflict markers",
            message: "It still contains <<<<<<< and >>>>>>> lines. Mark it resolved anyway?",
            confirmTitle: "Mark Resolved", isDestructive: false, action: run)
    }

    func openInEditor(_ entry: StatusEntry) {
        guard let repository else { return }
        NSWorkspace.shared.open(repository.root.appendingPathComponent(entry.path))
    }

    func revealInFinder(_ path: String) {
        guard let repository else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repository.root.appendingPathComponent(path)])
    }

    func continueOperation() {
        guard let repository, let op = inProgress else { return }
        run(.continueOperation, title: "Continuing \(op.noun)") {
            try await repository.continueOperation(op)
        } success: { HUD.show("\(op.noun) finished", systemImage: "checkmark.circle") }
    }

    func confirmAbort() {
        guard let repository, let op = inProgress else { return }
        confirmation = Confirmation(
            title: "Abort the \(op.noun.lowercased())?",
            message: "Your branch goes back to how it was before the \(op.noun.lowercased()) started. Conflict fixes you made are lost.",
            confirmTitle: "Abort \(op.noun)", isDestructive: true
        ) { [weak self] in
            self?.run(.abortOperation, title: "Aborting \(op.noun)") { try await repository.abortOperation(op) }
        }
    }

    // MARK: Committing

    var stagedCount: Int { status.staged.count }

    var commitButtonTitle: String { CommitButtonTitle.title(stagedFiles: stagedCount, amend: amend) }

    var canCommit: Bool {
        guard repository != nil, activity == nil, status.conflicted.isEmpty else { return false }
        guard !message.subject.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return amend || stagedCount > 0 || inProgress == .merge
    }

    /// Why the commit button is disabled, in a few words.
    var commitHint: String? {
        if !status.conflicted.isEmpty { return "Resolve conflicts first." }
        if !amend && stagedCount == 0 && inProgress != .merge {
            return status.isClean ? "Nothing to commit." : "Stage changes to commit them."
        }
        if message.subject.trimmingCharacters(in: .whitespaces).isEmpty { return "Write a subject." }
        return nil
    }

    func toggleAmend() {
        guard let repository, !status.branch.isUnborn else { return }
        amend.toggle()
        if amend {
            Task {
                if message.isEmpty, let previous = try? await repository.headMessage() { message = CommitMessage(text: previous) }
                headPushed = await repository.isHeadPushed()
            }
        } else {
            headPushed = false
        }
    }

    func focusComposer() {
        sidebarSelection = .changes
        composerFocusRequest += 1
    }

    func commit(thenPush: Bool) {
        guard let repository, canCommit else { return }
        if !identity.isComplete {
            Task {
                identity = await repository.identity()
                if !identity.isComplete { sheet = .identity } else { commit(thenPush: thenPush) }
            }
            return
        }
        let text = message.text
        let amending = amend
        let previous = status.branch.head
        let wasUnborn = status.branch.isUnborn
        activityTask = Task {
            activity = Activity(title: amending ? "Amending" : "Committing", progress: nil, isCancellable: true)
            do {
                let head = try await repository.commit(message: text, amend: amending)
                activity = nil
                lastCommit = (head, previous)
                composerResignRequest += 1
                message = CommitMessage()
                amend = false
                headPushed = false
                flushDraft()
                HUD.show("\(amending ? "Amended" : "Committed") \(head.short)", systemImage: "checkmark.circle")
                registerUndo(amending ? "Amend" : "Commit") {
                    self.undoCommit(head: head, previous: wasUnborn ? nil : previous, message: text)
                }
                await refresh(includeRefs: true)
                if thenPush { push() }
            } catch {
                activity = nil
                show(error, operation: .commit)
                await refresh(includeRefs: false)
            }
        }
    }

    /// Undo Commit: only while it's still the branch tip and not pushed.
    private func undoCommit(head: ObjectID, previous: ObjectID?, message text: String) {
        guard let repository else { return }
        Task {
            guard status.branch.head == head else {
                HUD.show("The branch moved on, so the commit can't be undone here.", systemImage: "exclamationmark.triangle")
                return
            }
            if await repository.isHeadPushed() {
                HUD.show("That commit is already pushed.", systemImage: "exclamationmark.triangle")
                return
            }
            do {
                try await repository.softReset(to: previous)
                message = CommitMessage(text: text)
                HUD.show("Commit undone. Your changes are staged.", systemImage: "arrow.uturn.backward")
                await refresh(includeRefs: true)
            } catch {
                show(error, operation: .commit)
            }
        }
    }

    func saveIdentity(name: String, email: String) {
        guard let repository else { return }
        Task {
            do {
                try await repository.setIdentity(name: name, email: email, global: true)
                identity = await repository.identity()
                sheet = nil
            } catch {
                show(error, operation: .other)
            }
        }
    }

    // MARK: Drafts

    private func scheduleDraftSave() {
        draftTask?.cancel()
        draftTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flushDraft()
        }
    }

    private func flushDraft() {
        guard let root = repository?.root.path else { return }
        drafts?.save(message, for: root)
    }

    // MARK: Branches

    func switchTo(_ ref: GitRef) {
        guard let repository else { return }
        if ref.isHead { return }
        let local = refs.local
        let target = ref.kind == .remote ? (ref.nameOnRemote ?? ref.name) : ref.name
        activityTask = Task {
            activity = Activity(title: "Switching to \(target)", progress: nil, isCancellable: false)
            do {
                if ref.kind == .remote {
                    _ = try await repository.switchToRemote(ref, localBranches: local)
                } else if ref.kind == .tag {
                    throw OpenProblem.git("Tags can't be checked out as a branch. Create a branch from it instead.")
                } else {
                    try await repository.switchBranch(ref.name)
                }
                activity = nil
                HUD.show("Switched to \(target)", systemImage: "arrow.triangle.branch")
            } catch let failure as GitFailure {
                activity = nil
                let explanation = Explanation.explain(failure.output, operation: .switchBranch)
                if explanation.action == .stashAndSwitch {
                    confirmation = Confirmation(
                        title: "Stash your changes and switch to \(target)?",
                        message: "You have changes that would be overwritten by switching to \(target). Commit can stash them, switch, and bring them back.",
                        confirmTitle: "Stash and Switch", isDestructive: false
                    ) { self.stashAndSwitch(ref) }
                } else {
                    problem = Problem(explanation: explanation, command: failure.command.displayString)
                }
            } catch {
                activity = nil
                show(error, operation: .switchBranch)
            }
            await refresh(includeRefs: true)
        }
    }

    private func stashAndSwitch(_ ref: GitRef) {
        guard let repository else { return }
        let local = refs.local
        let target = ref.kind == .remote ? (ref.nameOnRemote ?? ref.name) : ref.name
        activityTask = Task {
            activity = Activity(title: "Switching to \(target)", progress: nil, isCancellable: false)
            do {
                let clean = try await repository.stashAndSwitch(to: target, remote: ref.kind == .remote ? ref : nil, localBranches: local)
                activity = nil
                if clean {
                    HUD.show("Switched to \(target) with your changes", systemImage: "arrow.triangle.branch")
                } else {
                    problem = Problem(explanation: Explanation(
                        cause: .conflicts, title: "Switched to \(target)",
                        message: "Some of your changes conflict with \(target). Those files are marked as conflicted; fix them and mark them resolved. The stash stays in Stashes until you drop it.",
                        action: .none, output: ""), command: "git stash pop")
                }
            } catch {
                activity = nil
                show(error, operation: .switchBranch)
            }
            await refresh(includeRefs: true)
        }
    }

    func showNewBranch(from commit: ObjectID?) {
        let label: String
        if let commit, let row = history.rows.first(where: { $0.id == commit }) {
            label = "\(commit.short) \(row.subject)"
        } else if let commit {
            label = commit.short
        } else {
            label = status.branch.branch ?? status.branch.head?.short ?? "HEAD"
        }
        sheet = .newBranch(from: commit, fromLabel: label)
    }

    func createBranch(_ name: String, from commit: ObjectID?, checkout: Bool) {
        guard let repository else { return }
        run(.createBranch, title: "Creating \(name)") {
            try await repository.createBranch(name, from: commit, checkout: checkout)
        } success: {
            HUD.show(checkout ? "Switched to new branch \(name)" : "Created \(name)", systemImage: "arrow.triangle.branch")
        }
    }

    func confirmDelete(_ ref: GitRef) {
        guard let repository, ref.kind == .local, !ref.isHead else { return }
        confirmation = Confirmation(
            title: "Delete the branch “\(ref.name)”?",
            message: "You can undo this right after. If it has commits that aren't merged anywhere, Commit won't delete it.",
            confirmTitle: "Delete Branch", isDestructive: true
        ) { [weak self] in
            self?.mutate(.deleteBranch, undoName: "Delete Branch") {
                guard let tip = try await repository.deleteBranch(ref, force: false) else { return nil }
                return { [weak self] in
                    guard let repository = self?.repository else { return }
                    self?.mutate(.createBranch, undoName: "Delete Branch", isUndo: true) {
                        try await repository.restoreBranch(ref.name, at: tip)
                        return nil
                    }
                }
            }
        }
    }

    var filteredLocalBranches: [GitRef] { RefList.filter(refs.local, branchFilter) }
    var filteredRemoteBranches: [GitRef] { RefList.filter(refs.remote, branchFilter) }
    var filteredTags: [GitRef] { RefList.filter(refs.tags, branchFilter) }

    // MARK: Sync

    var canSync: Bool { repository != nil && activity == nil && !refs.remoteNames.isEmpty }
    var canPull: Bool { canSync && status.branch.upstream != nil && !status.branch.isDetached }
    var canPush: Bool { repository != nil && activity == nil && !status.branch.isDetached && !status.branch.isUnborn && !refs.remoteNames.isEmpty }

    func fetch() {
        guard let repository, canSync else { return }
        perform(.fetch, title: "Fetching", cancellable: true, progress: true) { progress in
            try await repository.fetch(onProgress: progress)
        } success: {
            HUD.show("Fetched", systemImage: "arrow.down.circle")
        }
    }

    func pull(strategy: PullStrategy = .configured, remember: Bool = false) {
        guard let repository, canPull else { return }
        let dirty = !status.isClean
        perform(.pull, title: "Pulling", cancellable: true, progress: true) { progress in
            if remember { try await repository.rememberPullStrategy(strategy) }
            try await repository.pull(strategy: strategy, autostash: dirty, onProgress: progress)
        } success: {
            HUD.show(dirty ? "Pulled. Your local changes were set aside and put back." : "Pulled", systemImage: "arrow.down.circle")
        }
    }

    func push() {
        guard let repository, canPush, let branch = status.branch.branch else { return }
        let upstream = status.branch.upstream
        let remotes = refs.remoteNames
        let remote = remotes.contains("origin") ? "origin" : remotes.first ?? "origin"
        activityTask = Task {
            activity = Activity(title: "Pushing", progress: nil, isCancellable: true)
            do {
                let outcome = try await repository.push(branch: branch, upstream: upstream, remote: remote) { progress in
                    Task { @MainActor in self.activity?.progress = progress }
                }
                activity = nil
                HUD.show(outcome.setUpstream ? "Pushed \(branch) to \(outcome.remote)" : "Pushed to \(outcome.remote)", systemImage: "arrow.up.circle")
                if let url = outcome.pullRequestURL {
                    problem = Problem(explanation: Explanation(cause: .hookOrOther, title: "Pushed",
                                                               message: "\(outcome.remote.capitalized) suggests opening a pull request for \(branch).",
                                                               action: .none, output: url.absoluteString),
                                      command: "")
                }
            } catch is CancellationError {
                activity = nil
            } catch {
                activity = nil
                show(error, operation: .push, remote: remote)
            }
            await refresh(includeRefs: true)
        }
    }

    func cancelActivity() {
        activityTask?.cancel()
    }

    private func scheduleAutoFetch() {
        autoFetchTask?.cancel()
        let minutes = UserDefaults.standard.integer(forKey: Preference.autoFetchMinutes)
        guard minutes > 0 else { return }
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled, let self, self.activity == nil, self.canSync, let repository = self.repository else { continue }
                try? await repository.fetch()
                self.refreshNow(full: true)
            }
        }
    }

    func settingsChanged() {
        scheduleAutoFetch()
        refreshNow(full: true)
    }

    // MARK: Stashes

    func showStashSheet() { sheet = .stash }

    func stash(message: String, includeUntracked: Bool) {
        guard let repository else { return }
        run(.stash, title: "Stashing") {
            try await repository.stash(message: message, includeUntracked: includeUntracked)
        } success: { HUD.show("Stashed", systemImage: "tray.and.arrow.down") }
    }

    func applyStash(_ entry: StashEntry, pop: Bool) {
        guard let repository else { return }
        run(.applyStash, title: pop ? "Popping stash" : "Applying stash") {
            try await repository.applyStash(entry, pop: pop)
        } success: { HUD.show(pop ? "Stash applied and removed" : "Stash applied", systemImage: "tray.and.arrow.up") }
    }

    func dropStash(_ entry: StashEntry) {
        guard let repository else { return }
        confirmation = Confirmation(
            title: "Drop “\(entry.message)”?",
            message: "You can undo this right after with Edit › Undo.",
            confirmTitle: "Drop Stash", isDestructive: true
        ) { [weak self] in
            self?.mutate(.dropStash, undoName: "Drop Stash") {
                try await repository.dropStash(entry)
                return { [weak self] in
                    guard let repository = self?.repository else { return }
                    self?.mutate(.stash, undoName: "Drop Stash", isUndo: true) {
                        try await repository.restoreStash(entry)
                        return nil
                    }
                }
            }
        }
    }

    private func loadStashDetail() {
        guard let repository, let id = stashSelection, let entry = stashes.first(where: { $0.id == id }) else {
            stashFiles = []
            stashFileSelection = nil
            if case .stash = diff.source { diff = DiffState() }
            return
        }
        detailTask?.cancel()
        detailTask = Task {
            let files = (try? await repository.stashFiles(entry)) ?? []
            guard !Task.isCancelled else { return }
            stashFiles = files
            stashFileSelection = files.first?.id
            if files.isEmpty { diff = DiffState() }
        }
    }

    private func loadStashFileDiff() {
        guard let repository, let id = stashSelection, let entry = stashes.first(where: { $0.id == id }),
              let file = stashFiles.first(where: { $0.id == stashFileSelection }) else { return }
        let options = DiffOptions(contextLines: contextLines, ignoreWhitespace: ignoreWhitespace)
        diff = DiffState(source: .stash(id, file), isLoading: true)
        diffTask?.cancel()
        diffTask = Task {
            do {
                let result = try await repository.stashDiff(entry, file: file, options: options)
                guard !Task.isCancelled else { return }
                diff.result = result
                diff.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                diff.isLoading = false
                diff.error = (error as? GitFailure)?.output ?? String(describing: error)
            }
        }
    }

    // MARK: History

    private func currentScope() -> HistoryScope {
        showAllBranches ? .all : .current(upstream: status.branch.upstream)
    }

    func toggleAllBranches() {
        showAllBranches.toggle()
        if sidebarSelection != .history { sidebarSelection = .history } else { ensureHistory(scope: currentScope()) }
    }

    private func ensureHistory(scope: HistoryScope) {
        guard repository != nil else { return }
        if history.scope == scope, !history.rows.isEmpty || history.isLoading { applySearch(); return }
        history.scope = scope
        reloadHistory()
    }

    func reloadHistory() {
        guard let repository, let scope = history.scope else { return }
        if status.branch.isUnborn, case .current = scope {
            history.reset()
            history.scope = scope
            historyRevision += 1
            return
        }
        history.reset()
        history.scope = scope
        history.isLoading = true
        historyRevision += 1
        let started = ContinuousClock.now
        let stream = repository.history(scope: scope)
        history.task = Task { [weak self] in
            var parser = LogParser()
            var pending: [CommitRow] = []
            var lastFlush = ContinuousClock.now
            var firstPage = false
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled else { return }
                    pending += parser.feed(chunk)
                    // Batch UI updates: the first page right away, then every 100 ms.
                    if (!firstPage && pending.count >= 100) || ContinuousClock.now - lastFlush > .milliseconds(100) {
                        self.appendHistory(pending, authors: parser.authors)
                        pending = []
                        lastFlush = .now
                        if !firstPage {
                            firstPage = true
                            Diagnostics.record("history_first_page_ms=\(Diagnostics.milliseconds(since: started))")
                        }
                    }
                }
                pending += parser.finish()
                guard let self, !Task.isCancelled else { return }
                self.appendHistory(pending, authors: parser.authors)
                self.history.isLoading = false
                self.historyRevision += 1
                Diagnostics.record("history_all_ms=\(Diagnostics.milliseconds(since: started)) rows=\(self.history.rows.count)")
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.history.isLoading = false
                self.history.failed = (error as? GitFailure)?.output ?? String(describing: error)
                self.historyRevision += 1
            }
        }
    }

    private func appendHistory(_ rows: [CommitRow], authors: AuthorTable) {
        guard !rows.isEmpty else { return }
        history.authors = authors
        history.layout.reserve(history.rows.count + rows.count)
        for row in rows { history.layout.append(id: row.id, parents: row.parents) }
        history.rows += rows
        if !searchText.isEmpty { applySearch() }
        historyRevision += 1
        if historySelection == nil, let first = history.rows.first, status.isClean || !showsUncommittedRow {
            historySelection = first.id
        }
    }

    /// The "Uncommitted Changes" row shows on top of the current branch's history.
    var showsUncommittedRow: Bool {
        guard !status.isClean, searchText.isEmpty else { return false }
        if case .current = history.scope { return true }
        if case .all = history.scope { return true }
        return false
    }

    private func applySearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard isShowingHistory else { return }
        if q.isEmpty {
            if history.filtered != nil { history.filtered = nil; historyRevision += 1 }
            return
        }
        let lower = q.lowercased()
        let names = history.authors.names.map { $0.lowercased() }
        var matches: [Int] = []
        for (i, row) in history.rows.enumerated() {
            if row.subject.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || (names.indices.contains(Int(row.author)) && names[Int(row.author)].contains(lower))
                || (lower.count >= 4 && row.id.hex.hasPrefix(lower)) {
                matches.append(i)
            }
        }
        history.filtered = matches
        historyRevision += 1
    }

    private func loadCommitDetail() {
        guard let repository, let id = historySelection else {
            commitDetail = nil
            commitFiles = []
            if case .commit = diff.source { diff = DiffState() }
            return
        }
        detailTask?.cancel()
        detailTask = Task {
            do {
                let detail = try await repository.commitDetail(id)
                let files = try await repository.changedFiles(in: id, parent: detail.parents.first)
                guard !Task.isCancelled else { return }
                commitDetail = detail
                commitFiles = files
                if commitFileSelection == files.first?.id { loadCommitFileDiff() } else { commitFileSelection = files.first?.id }
                if files.isEmpty { diff = DiffState() }
            } catch {
                guard !Task.isCancelled else { return }
                commitDetail = nil
                commitFiles = []
            }
        }
    }

    private func loadCommitFileDiff() {
        guard let repository, let detail = commitDetail, let file = commitFiles.first(where: { $0.id == commitFileSelection }) else { return }
        let options = DiffOptions(contextLines: contextLines, ignoreWhitespace: ignoreWhitespace)
        let id = detail.id, parent = detail.parents.first
        diff = DiffState(source: .commit(id, file), isLoading: true)
        diffTask?.cancel()
        diffTask = Task {
            do {
                let result = try await repository.diff(of: file, in: id, parent: parent, options: options)
                guard !Task.isCancelled else { return }
                diff.result = result
                diff.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                diff.isLoading = false
                diff.error = (error as? GitFailure)?.output ?? String(describing: error)
            }
        }
    }

    func copyHash(_ id: ObjectID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id.hex, forType: .string)
        HUD.show("Copied \(id.short)", systemImage: "doc.on.doc")
    }

    func copySubject(_ id: ObjectID) {
        guard let row = history.rows.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.subject, forType: .string)
        HUD.show("Copied subject", systemImage: "doc.on.doc")
    }

    // MARK: Finder and Terminal

    func showInFinder() {
        guard let root = repository?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func openInTerminal() {
        guard let root = repository?.root,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([root], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Askpass

    func ask(_ prompt: AskpassPrompt) async -> String? {
        await withCheckedContinuation { continuation in
            if let existing = self.prompt { existing.continuation.resume(returning: nil) }
            self.prompt = PendingPrompt(prompt: prompt, continuation: continuation)
        }
    }

    func answerPrompt(_ answer: String?) {
        prompt?.continuation.resume(returning: answer)
        prompt = nil
    }

    // MARK: Running things

    /// Runs a change that can be undone. `body` returns the undo action (or nil).
    private func mutate(_ operation: GitOperation, undoName: String?, isUndo: Bool = false, failureHint: String? = nil,
                        _ body: @escaping @MainActor () async throws -> (@MainActor () -> Void)?) {
        Task {
            do {
                let undo = try await body()
                if let undo, let undoName, !isUndo { registerUndo(undoName, undo) }
            } catch {
                show(error, operation: operation, hint: failureHint)
            }
            await refresh(includeRefs: operation == .dropStash || operation == .stash || operation == .discard
                          || operation == .deleteBranch || operation == .createBranch)
        }
    }

    private func registerUndo(_ name: String, _ action: @escaping @MainActor () -> Void) {
        guard let undoManager = window?.undoManager ?? undoManager else { return }
        undoManager.registerUndo(withTarget: self) { _ in
            MainActor.assumeIsolated { action() }
        }
        undoManager.setActionName(name)
    }

    /// A longer operation with an activity in the toolbar.
    private func perform(_ operation: GitOperation, title: String, cancellable: Bool = false, progress: Bool = false,
                         _ body: @escaping @MainActor (@escaping @Sendable (GitProgress) -> Void) async throws -> Void,
                         success: @escaping @MainActor () -> Void = {}) {
        let remote = refs.remoteNames.contains("origin") ? "origin" : refs.remoteNames.first
        activityTask = Task {
            activity = Activity(title: title, progress: nil, isCancellable: cancellable)
            do {
                try await body { value in
                    guard progress else { return }
                    Task { @MainActor in self.activity?.progress = value }
                }
                activity = nil
                success()
            } catch is CancellationError {
                activity = nil
            } catch {
                activity = nil
                if Task.isCancelled { return }
                show(error, operation: operation, remote: remote)
            }
            await refresh(includeRefs: true)
        }
    }

    private func run(_ operation: GitOperation, title: String, _ body: @escaping @MainActor () async throws -> Void,
                     success: @escaping @MainActor () -> Void = {}) {
        perform(operation, title: title, cancellable: false, progress: false, { _ in try await body() }, success: success)
    }

    func show(_ error: any Error, operation: GitOperation, remote: String? = nil, hint: String? = nil) {
        if let failure = error as? GitFailure {
            var explanation = Explanation.explain(failure.output, operation: operation, remote: remote)
            if let hint, explanation.cause == .hookOrOther { explanation.message = hint }
            if explanation.action == .chooseMergeOrRebase { sheet = .divergentPull; return }
            if explanation.action == .setIdentity { sheet = .identity; return }
            problem = Problem(explanation: explanation, command: failure.command.displayString)
        } else if let open = error as? OpenProblem {
            problem = Problem(explanation: Explanation(cause: .hookOrOther, title: operation == .other ? "Git reported a problem" : Explanation.explain("", operation: operation).title,
                                                       message: open.message, action: .none, output: ""), command: "")
        } else if error is CancellationError {
            return
        } else {
            problem = Problem(explanation: Explanation.explain(String(describing: error), operation: operation), command: "")
        }
    }
}

