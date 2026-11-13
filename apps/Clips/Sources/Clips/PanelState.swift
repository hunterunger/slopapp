import AppKit
import ClipsCore
import Observation

/// What the panel shows. Updated in place, so the panel is built once and stays warm.
@MainActor
@Observable
final class PanelState {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            let started = Diagnostics.now()
            // Typing always goes back to the search.
            if cardsFocused { cardsFocused = false }
            refresh(resetSelection: true)
            Diagnostics.recordWhenIdle("panel search settled results=\(results.count)", since: started)
        }
    }

    var filter: ClipFilter = .all {
        didSet { if filter != oldValue { refresh(resetSelection: true) } }
    }

    /// All, each board, then the kinds.
    var tabs: [ClipFilter] { ClipFilter.tabs(boards: model.boards.all) }

    private(set) var results: [Clip] = []
    /// Bumped whenever `results` is recomputed (cheaper to compare than the array).
    private(set) var resultsVersion = 0
    /// The history revision `results` was computed from.
    @ObservationIgnored private var resultsRevision = -1

    /// The selected cards. One, usually; several after ⇧/⌘-click, ⇧-arrows or ⌘A.
    private(set) var selection = StripSelection()

    /// The card the keyboard is on. Setting it selects just that card.
    var selectedID: UUID? {
        get { selection.cursor }
        set {
            guard newValue != selection.cursor || selection.isMultiple else { return }
            selection.select(newValue)
            selectionChanged()
        }
    }

    /// Selected clips waiting for a second ⌘⌫ (some are pinned).
    var pendingDelete: Set<UUID>?
    /// A board with clips on it, waiting for "Delete Board" in the notice.
    var pendingBoardDelete: UUID?
    /// A board tab showing its name field (a new board, or Rename).
    var renaming: BoardRename?
    /// The clip being edited in the preview (⌘E, ⌘R).
    var editor: ClipEditSession?
    /// The tab a dragged card is over.
    var dropTarget: ClipFilter?
    /// Where each tab is, in the panel's top-left coordinates (for dropping cards on them).
    @ObservationIgnored var tabFrames: [String: CGRect] = [:]

    /// Bumped when the selection moves by keyboard, so the strip scrolls to it.
    private(set) var scrollRequest = 0
    /// Bumped on every show, so the search field takes focus again.
    private(set) var focusRequest = 0
    /// ⌘ is held: the first nine cards show their number.
    var commandHeld = false
    /// Tab moved the keyboard to the cards (Space previews; typing goes back to search).
    var cardsFocused = false {
        didSet { if cardsFocused != oldValue { onCardsFocusChange?(cardsFocused) } }
    }
    @ObservationIgnored var onCardsFocusChange: ((Bool) -> Void)?
    var quickLookOpen = false
    /// Whole cards visible at once (the strip reports it), for Page Up / Page Down.
    @ObservationIgnored var pageSize = 5
    /// The app Return pastes into.
    @ObservationIgnored var target: NSRunningApplication?
    private(set) var targetName: String?
    /// "Now" for relative times, fixed while the panel is open.
    private(set) var now = Date()

    @ObservationIgnored private let model: AppModel

    struct BoardRename: Equatable {
        var id: UUID
        /// Just made with + or ⇧⌘N: Esc removes it again.
        var isNew: Bool
        var draft: String
    }

    init(model: AppModel) {
        self.model = model
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return results.firstIndex { $0.id == selectedID }
    }

    var selected: Clip? {
        selectedIndex.map { results[$0] }
    }

    /// Every selected clip, in strip order (newest first). Just the cursor's clip, usually.
    var selectedClips: [Clip] {
        guard selection.isMultiple else { return selected.map { [$0] } ?? [] }
        return results.filter { selection.contains($0.id) }
    }

    var isMultipleSelection: Bool { selection.isMultiple }

    private var order: [UUID] { results.map(\.id) }

    /// Resets to "newest clip selected, no search". Only touches what changed: every
    /// assignment to observed state costs a redraw, and this runs on the hot path.
    func prepareForShow(target: NSRunningApplication?) {
        self.target = target
        let name = target?.localizedName
        if targetName != name { targetName = name }
        if Date().timeIntervalSince(now) > 30 { now = Date() }
        if !query.isEmpty { query = "" }
        if filter != .all { filter = .all }
        if pendingDelete != nil { pendingDelete = nil }
        if pendingBoardDelete != nil { pendingBoardDelete = nil }
        if renaming != nil { renaming = nil }
        if editor != nil { editor = nil }
        if dropTarget != nil { dropTarget = nil }
        if cardsFocused { cardsFocused = false }
        if commandHeld { commandHeld = false }
        if quickLookOpen { quickLookOpen = false }
        if resultsRevision != model.revision { refresh() }
        if selectedID != results.first?.id || selectedIndex != 0 || selection.isMultiple {
            selectedID = results.first?.id
            scrollRequest &+= 1
        }
        focusRequest &+= 1
    }

    /// Re-runs the search. Keeps the selection if it's still listed.
    func refresh(resetSelection: Bool = false) {
        let started = Diagnostics.now()
        // A deleted board's tab falls back to All.
        if let board = filter.boardID, model.boards.board(id: board) == nil { filter = .all; return }
        results = ClipSearch.run(model.history.clips, query: query, filter: filter)
        resultsRevision = model.revision
        resultsVersion &+= 1
        if resetSelection {
            if selectedID != results.first?.id || selection.isMultiple { selectedID = results.first?.id }
            scrollRequest &+= 1
        } else if selection.isMultiple {
            var reconciled = selection
            reconciled.reconcile(with: order, fallback: results.first?.id)
            if reconciled != selection { selection = reconciled }
            if selectedIndex == nil { scrollRequest &+= 1 }
        } else if selectedIndex == nil {
            if selectedID != results.first?.id { selectedID = results.first?.id }
            scrollRequest &+= 1
        }
        if Diagnostics.isLogging, !query.isEmpty {
            Diagnostics.record("search results=\(results.count) of=\(model.history.clips.count) ms=\(Diagnostics.milliseconds(since: started))")
        }
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? 0
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].id
        scrollRequest &+= 1
    }

    func select(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedID = results[index].id
        scrollRequest &+= 1
    }

    // MARK: - Several cards

    /// A click on a card: ⌘ adds or removes it, ⇧ selects the range to it, else just it.
    func click(_ id: UUID, command: Bool, shift: Bool) {
        if shift {
            selection.extend(to: id, in: order)
        } else if command {
            selection.toggle(id, in: order)
        } else {
            selectedID = id
            return
        }
        selectionChanged()
    }

    func extendSelection(by delta: Int) {
        selection.extend(by: delta, in: order)
        selectionChanged()
        scrollRequest &+= 1
    }

    func extendSelection(toEnd last: Bool) {
        selection.extend(toEdge: last, in: order)
        selectionChanged()
        scrollRequest &+= 1
    }

    func selectAll() {
        selection.selectAll(in: order)
        selectionChanged()
    }

    /// Several selected → just the cursor. Returns false if there was only one.
    @discardableResult
    func collapseSelection() -> Bool {
        guard selection.isMultiple else { return false }
        selection.collapse()
        selectionChanged()
        return true
    }

    /// Test hooks: select cards by index the way clicks would.
    func testSelect(indexes: [Int], adding: Bool) {
        let ids = indexes.compactMap { results.indices.contains($0) ? results[$0].id : nil }
        guard let first = ids.first else { return }
        if !adding { selectedID = first }
        for id in ids.dropFirst(adding ? 0 : 1) where !selection.contains(id) { selection.toggle(id, in: order) }
        selectionChanged()
    }

    private func selectionChanged() {
        if pendingDelete != nil { pendingDelete = nil }
    }

    // MARK: - Tabs

    func cycleFilter(by delta: Int) {
        let all = tabs
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + delta + all.count) % all.count]
    }

    /// Shows a board's name field. `isNew`: Esc deletes the board again.
    func beginRenaming(_ board: Board, isNew: Bool) {
        renaming = BoardRename(id: board.id, isNew: isNew, draft: board.name)
    }

    func commitRename() {
        guard let renaming else { return }
        self.renaming = nil
        model.renameBoard(renaming.id, to: renaming.draft)
        focusRequest &+= 1
    }

    func cancelRename() {
        guard let renaming else { return }
        self.renaming = nil
        if renaming.isNew {
            if filter == .board(renaming.id) { filter = .all }
            model.deleteBoard(renaming.id)
        }
        focusRequest &+= 1
    }
}
