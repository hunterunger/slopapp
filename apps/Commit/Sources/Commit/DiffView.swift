import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// The detail column in Changes: a header for the file and its diff.
struct DiffPane: View {
    @Bindable var model: RepoModel

    var body: some View {
        DiffContainer(model: model, state: model.diff, editable: model.diff.isEditable)
    }
}

/// Header + diff body or a placeholder, for any diff source.
struct DiffContainer: View {
    @Bindable var model: RepoModel
    let state: DiffState
    let editable: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let header = headerInfo {
                DiffHeader(info: header, state: state, model: model, editable: editable)
                DiffNotes(state: state, ignoringWhitespace: model.ignoreWhitespace)
                Hairline()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch state.source {
        case .none:
            ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Select a file to see its changes."))
        case .multiple(let n):
            ContentUnavailableView {
                Label("\(n) Files Selected", systemImage: "doc.on.doc")
            } description: {
                Text("Press Space to stage or unstage them together.")
            } actions: {
                Button(model.stageToggleTitle) { model.toggleSelection() }
            }
        default:
            if let error = state.error {
                ContentUnavailableView("Couldn't Show the Diff", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let result = state.result {
                body(for: result)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func body(for result: DiffResult) -> some View {
        if result.isFolder {
            ContentUnavailableView("New Folder", systemImage: "folder.badge.plus",
                                   description: Text("Its files are new. Stage the folder to add them all."))
        } else if let file = result.file {
            if file.isBinary {
                ContentUnavailableView("Binary File", systemImage: "doc.zipper", description: Text(binaryDescription(result)))
            } else if file.hunks.isEmpty {
                ContentUnavailableView(file.isModeChangeOnly ? "Permissions Changed" : "No Text Changes", systemImage: "doc",
                                       description: Text(file.isModeChangeOnly ? "\(file.oldMode ?? "") → \(file.newMode ?? "")" : "The file's contents are the same."))
            } else if file.changedLineCount > DiffContainer.largeDiffLimit && !state.showsFull {
                ContentUnavailableView {
                    Label("Large Diff", systemImage: "doc.text")
                } description: {
                    Text("\(file.changedLineCount.formatted()) changed lines. Showing them all may take a moment.")
                } actions: {
                    Button("Show Full Diff") { showFull() }
                }
            } else {
                DiffTable(file: file, state: state, editable: editable, model: model)
            }
        } else {
            ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("Nothing differs in this file."))
        }
    }

    static let largeDiffLimit = 10_000

    private func showFull() {
        if model.diff.source == state.source { model.diff.showsFull = true }
    }

    private func binaryDescription(_ result: DiffResult) -> String {
        switch (result.oldSize, result.newSize) {
        case (let old?, let new?): "\(ByteSize.string(old)) → \(ByteSize.string(new))"
        case (nil, let new?): "New, \(ByteSize.string(new))"
        case (let old?, nil): "Deleted, was \(ByteSize.string(old))"
        default: "Its contents can't be shown as text."
        }
    }

    private var headerInfo: (path: String, original: String?, side: String?)? {
        switch state.source {
        case .workingCopy(let entry, let staged):
            return (entry.path, staged ? entry.originalPath : nil, staged ? "Staged" : entry.isUntracked ? "New file" : "Not staged")
        case .commit(_, let file), .stash(_, let file):
            return (file.path, file.originalPath, nil)
        default:
            return nil
        }
    }
}

struct DiffHeader: View {
    let info: (path: String, original: String?, side: String?)
    let state: DiffState
    let model: RepoModel
    let editable: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            let parts = StatusEntry.split(info.path)
            Text(parts.name).font(.headline).lineLimit(1).truncationMode(.middle)
            if let original = info.original {
                Text("renamed from \(original)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            } else if !parts.folder.isEmpty {
                Text(parts.folder).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: Spacing.s)
            if let file = state.result?.file, !file.hunks.isEmpty {
                Text("+\(file.additions)").font(.callout).monospacedDigit().foregroundStyle(.textGreen)
                    .accessibilityLabel("\(file.additions) lines added")
                Text("−\(file.deletions)").font(.callout).monospacedDigit().foregroundStyle(.textRed)
                    .accessibilityLabel("\(file.deletions) lines removed")
            }
            if case .workingCopy(let entry, _) = state.source, entry.isConflicted {
                Button("Open in Editor") { model.openInEditor(entry) }
                    .controlSize(.small)
                Button("Mark Resolved") { model.markResolved([entry]) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            } else if let side = info.side {
                Text(side)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}

/// Notes under the header (fallback algorithm, whitespace hidden).
struct DiffNotes: View {
    let state: DiffState
    let ignoringWhitespace: Bool

    var body: some View {
        if state.result?.usedFallback == true || ignoringWhitespace {
            VStack(alignment: .leading, spacing: 2) {
                if state.result?.usedFallback == true {
                    Label("Shown with the Myers algorithm: your configured diff algorithm took too long on this file.",
                          systemImage: "info.circle")
                }
                if ignoringWhitespace {
                    Label("Whitespace changes are hidden. Show them to stage single lines.", systemImage: "info.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Table

/// A row of the diff table.
enum DiffRow: Equatable {
    case gap(Int)
    case hunk(Int)
    case line(hunk: Int, line: Int)
}

/// The diff as an NSTableView: virtualised rows (200,000 lines stay smooth), and the table's
/// own selection gives click, shift-click, ⌘-click, drag and arrow-key line selection.
struct DiffTable: NSViewRepresentable {
    let file: FileDiff
    let state: DiffState
    let editable: Bool
    /// nil for a read-only diff outside a repository window (file history).
    let model: RepoModel?

    func makeCoordinator() -> DiffTableCoordinator { DiffTableCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = DiffNSTableView()
        table.headerView = nil
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.backgroundColor = .textBackgroundColor
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.gridStyleMask = []
        table.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.resizingMask = []
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.setAccessibilityLabel("Diff")
        context.coordinator.table = table
        table.coordinator = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.editable = editable
        coordinator.isStagedSide = state.isStagedSide
        coordinator.isUntracked = {
            if case .workingCopy(let entry, _) = state.source { return entry.isUntracked }
            return false
        }()
        coordinator.update(file: file, selection: state.lineSelection)
        if state.scrollRequest != coordinator.lastScrollRequest, let hunk = state.scrollToHunk {
            coordinator.lastScrollRequest = state.scrollRequest
            coordinator.scroll(toHunk: hunk)
        }
    }
}

@MainActor
final class DiffTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var table: DiffNSTableView?
    weak var model: RepoModel?
    var file = FileDiff()
    var rows: [DiffRow] = []
    var editable = false
    var isStagedSide = false
    var isUntracked = false
    var lastScrollRequest = 0
    private var applyingSelection = false
    private var hunkSelectionCounts: [Int: Int] = [:]

    static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }
    static var numberFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
    }

    func update(file newFile: FileDiff, selection: Set<LineRef>) {
        guard let table else { return }
        if newFile != file {
            file = newFile
            rows = Self.rows(for: newFile)
            table.reloadData()
            sizeColumn()
        }
        let indexes = IndexSet(rows.enumerated().compactMap { index, row in
            if case .line(let h, let l) = row, selection.contains(LineRef(hunk: h, line: l)) { return index }
            return nil
        })
        if table.selectedRowIndexes != indexes {
            applyingSelection = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            applyingSelection = false
        }
        updateHunkCounts(selection)
    }

    static func rows(for file: FileDiff) -> [DiffRow] {
        var rows: [DiffRow] = []
        rows.reserveCapacity(file.lineCount + file.hunks.count * 2)
        var previousEnd = 1
        for (h, hunk) in file.hunks.enumerated() {
            let start = hunk.oldCount == 0 ? hunk.oldStart + 1 : hunk.oldStart
            if start - previousEnd > 0 { rows.append(.gap(start - previousEnd)) }
            rows.append(.hunk(h))
            for l in hunk.lines.indices { rows.append(.line(hunk: h, line: l)) }
            previousEnd = hunk.oldStart + hunk.oldCount + (hunk.oldCount == 0 ? 1 : 0)
        }
        return rows
    }

    private func sizeColumn() {
        guard let table, let column = table.tableColumns.first else { return }
        var longest = 0
        for hunk in file.hunks {
            for line in hunk.lines where Int(line.length) > longest { longest = Int(line.length) }
        }
        let advance = ("0" as NSString).size(withAttributes: [.font: Self.font]).width
        let width = DiffLineRowView.textStart + CGFloat(min(longest, 2000)) * advance + Spacing.xl
        column.width = max(width, table.enclosingScrollView?.contentSize.width ?? 600)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .hunk: 30
        case .gap: 24
        case .line: ceil(Self.font.ascender - Self.font.descender + Self.font.leading) + 4
        }
    }

    /// Line rows get a transparent cell that carries the spoken text ("Added line 12: …");
    /// the row view does the drawing.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard case .line(let h, let l) = rows[row] else { return nil }
        let cell = tableView.makeView(withIdentifier: DiffLineCell.identifier, owner: nil) as? DiffLineCell ?? DiffLineCell()
        cell.configure(file: file, line: file.hunks[h].lines[l])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        switch rows[row] {
        case .gap(let count):
            let view = tableView.makeView(withIdentifier: GapRowView.identifier, owner: nil) as? GapRowView ?? GapRowView()
            view.configure(count: count)
            return view
        case .hunk(let h):
            let view = tableView.makeView(withIdentifier: HunkRowView.identifier, owner: nil) as? HunkRowView ?? HunkRowView()
            view.configure(hunk: file.hunks[h], index: h, editable: editable, stagedSide: isStagedSide, untracked: isUntracked,
                           selectedCount: hunkSelectionCounts[h] ?? 0, coordinator: self)
            return view
        case .line(let h, let l):
            let view = tableView.makeView(withIdentifier: DiffLineRowView.identifier, owner: nil) as? DiffLineRowView ?? DiffLineRowView()
            view.configure(file: file, line: file.hunks[h].lines[l])
            return view
        }
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        guard editable else { return [] }
        return proposed.filteredIndexSet { index in
            if case .line(let h, let l) = rows[index] { return file.hunks[h].lines[l].isChange }
            return false
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection, let table, let model else { return }
        var selection = Set<LineRef>()
        for index in table.selectedRowIndexes {
            if case .line(let h, let l) = rows[index] { selection.insert(LineRef(hunk: h, line: l)) }
        }
        updateHunkCounts(selection)
        if model.diff.lineSelection != selection { model.diff.lineSelection = selection }
    }

    private func updateHunkCounts(_ selection: Set<LineRef>) {
        var counts: [Int: Int] = [:]
        for ref in selection { counts[ref.hunk, default: 0] += 1 }
        guard counts != hunkSelectionCounts, let table else {
            return
        }
        let changed = Set(counts.keys).union(hunkSelectionCounts.keys)
        hunkSelectionCounts = counts
        for (index, row) in rows.enumerated() {
            if case .hunk(let h) = row, changed.contains(h), let view = table.rowView(atRow: index, makeIfNecessary: false) as? HunkRowView {
                view.updateButtons(selectedCount: counts[h] ?? 0)
            }
        }
    }

    func scroll(toHunk hunk: Int) {
        guard let table, let index = rows.firstIndex(of: .hunk(hunk)) else { return }
        let rect = table.rect(ofRow: index)
        table.scroll(NSPoint(x: 0, y: max(0, rect.minY - 4)))
        table.window?.makeFirstResponder(table)
    }

    // Actions from rows and keys.
    func stageHunk(_ index: Int) { model?.applyHunk(index, discard: false) }
    func discardHunk(_ index: Int) { model?.applyHunk(index, discard: true) }
    func toggleSelectedLines() { model?.toggleSelection() }
    func clearSelection() { model?.diff.lineSelection = [] }

    /// Where the change after (or before) the current selection starts, for the arrow keys.
    func line(after row: Int, forward: Bool) -> Int? {
        var index = row + (forward ? 1 : -1)
        while index >= 0 && index < rows.count {
            if case .line(let h, let l) = rows[index], file.hunks[h].lines[l].isChange { return index }
            index += forward ? 1 : -1
        }
        return nil
    }
}

/// Keys: Space/Return stage the selection (or the hunk), Esc clears it, ↑/↓ move between
/// changed lines.
final class DiffNSTableView: NSTableView {
    weak var coordinator: DiffTableCoordinator?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isSpaceOrReturn = [49, 36, 76].contains(event.keyCode) // space, return, enter
        if isSpaceOrReturn && modifiers.isEmpty && !selectedRowIndexes.isEmpty {
            coordinator?.toggleSelectedLines()
            return
        }
        if event.keyCode == 53 && !selectedRowIndexes.isEmpty { // esc
            coordinator?.clearSelection()
            return
        }
        // ↑/↓ move between changed lines (context, headers and gaps aren't selectable);
        // with ⇧ they extend the selection. ⌘↑/⌘↓ are Previous/Next Change in the menu.
        if (event.keyCode == 125 || event.keyCode == 126) && !modifiers.contains(.command), let coordinator {
            let forward = event.keyCode == 125
            let anchor = forward ? (selectedRowIndexes.last ?? -1) : (selectedRowIndexes.first ?? numberOfRows)
            guard let next = coordinator.line(after: anchor, forward: forward) else { NSSound.beep(); return }
            selectRowIndexes([next], byExtendingSelection: modifiers.contains(.shift))
            scrollRowToVisible(next)
            return
        }
        super.keyDown(with: event)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        clipRect.fill()
    }
}

/// One line of code: old and new line numbers, a +/− marker, the text; tinted by kind.
final class DiffLineRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("DiffLine")
    static let numberWidth: CGFloat = 44
    static var textStart: CGFloat { numberWidth * 2 + 20 }

    private var kind: DiffLine.Kind = .context
    private var oldNumber: Int32 = 0
    private var newNumber: Int32 = 0
    private var text = ""
    private var crlf = false

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
    }

    func configure(file: FileDiff, line: DiffLine) {
        kind = line.kind
        oldNumber = line.oldNumber
        newNumber = line.newNumber
        text = file.text(of: line).replacingOccurrences(of: "\t", with: "    ")
        crlf = file.hasCarriageReturn(line)
        let what: String
        switch kind {
        case .added: what = "Added line \(newNumber)"
        case .removed: what = "Removed line \(oldNumber)"
        case .context: what = "Line \(newNumber)"
        }
        setAccessibilityLabel("\(what): \(text)")
        setAccessibilityRole(.row)
        needsDisplay = true
    }

    override var isEmphasized: Bool {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        switch kind {
        case .added: NSColor.systemGreen.withAlphaComponent(0.13).setFill()
        case .removed: NSColor.systemRed.withAlphaComponent(0.12).setFill()
        case .context: NSColor.textBackgroundColor.setFill()
        }
        bounds.fill()
        // Gutter.
        NSColor.labelColor.withAlphaComponent(0.03).setFill()
        NSRect(x: 0, y: 0, width: Self.numberWidth * 2 + 6, height: bounds.height).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let color: NSColor = isEmphasized ? .selectedContentBackgroundColor.withAlphaComponent(0.3) : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        bounds.fill()
        // A bar in the gutter marks selected lines without relying on colour alone.
        (isEmphasized ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = DiffTableCoordinator.font
        let numberFont = DiffTableCoordinator.numberFont
        let numberColor: NSColor
        let markerColor: NSColor
        switch kind {
        case .added:
            numberColor = .readable(.systemGreen, on: .textBackgroundColor, target: ReadableColor.statusTarget)
            markerColor = numberColor
        case .removed:
            numberColor = .readable(.systemRed, on: .textBackgroundColor, target: ReadableColor.statusTarget)
            markerColor = numberColor
        case .context:
            numberColor = .secondaryLabelColor
            markerColor = .secondaryLabelColor
        }
        let textHeight = ceil(font.ascender - font.descender)
        let y = floor((bounds.height - textHeight) / 2)
        let numberAttributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
        func drawNumber(_ n: Int32, right: CGFloat) {
            guard n > 0 else { return }
            let s = "\(n)" as NSString
            let size = s.size(withAttributes: numberAttributes)
            s.draw(at: NSPoint(x: right - size.width, y: y + (textHeight - size.height) / 2), withAttributes: numberAttributes)
        }
        drawNumber(oldNumber, right: Self.numberWidth - 4)
        drawNumber(newNumber, right: Self.numberWidth * 2 - 4)
        let marker: String = kind == .added ? "+" : kind == .removed ? "−" : ""
        (marker as NSString).draw(at: NSPoint(x: Self.numberWidth * 2 + 6, y: y),
                                  withAttributes: [.font: font, .foregroundColor: markerColor])
        (text as NSString).draw(at: NSPoint(x: Self.textStart, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if crlf {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            ("␍" as NSString).draw(at: NSPoint(x: Self.textStart + width + 2, y: y),
                                   withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
        }
    }

    override var isFlipped: Bool { true }
}

/// The accessibility element for one diff line.
final class DiffLineCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("DiffLineCell")

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    func configure(file: FileDiff, line: DiffLine) {
        let text = file.text(of: line)
        switch line.kind {
        case .added: setAccessibilityLabel("Added line \(line.newNumber): \(text)")
        case .removed: setAccessibilityLabel("Removed line \(line.oldNumber): \(text)")
        case .context: setAccessibilityLabel("Line \(line.newNumber): \(text)")
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks go to the row
}

/// "@@ -12,5 +12,6 @@ func name()" with Stage/Unstage Hunk (or "Stage 2 Lines") and Discard.
final class HunkRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("DiffHunk")
    private let label = NSTextField(labelWithString: "")
    private let primary = NSButton(title: "Stage Hunk", target: nil, action: nil)
    private let discard = NSButton(title: "Discard", target: nil, action: nil)
    private weak var coordinator: DiffTableCoordinator?
    private var index = 0
    private var stagedSide = false

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        label.font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        for button in [primary, discard] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = NSFont.preferredFont(forTextStyle: .caption1)
            button.target = self
        }
        primary.action = #selector(primaryPressed)
        discard.action = #selector(discardPressed)
        // Buttons first, so they stay in view when a long line scrolls the diff sideways.
        let stack = NSStackView(views: [primary, discard, label])
        stack.orientation = .horizontal
        stack.spacing = Spacing.s
        stack.edgeInsets = NSEdgeInsets(top: 0, left: Spacing.s, bottom: 0, right: Spacing.m)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Keep the buttons visible when the diff scrolls sideways: pin to the visible width.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(hunk: DiffHunk, index: Int, editable: Bool, stagedSide: Bool, untracked: Bool, selectedCount: Int,
                   coordinator: DiffTableCoordinator) {
        self.coordinator = coordinator
        self.index = index
        self.stagedSide = stagedSide
        label.stringValue = hunk.headerText
        label.setAccessibilityLabel("Change \(index + 1): \(hunk.headerText)")
        primary.isHidden = !editable
        discard.isHidden = !editable || stagedSide || untracked
        updateButtons(selectedCount: selectedCount)
    }

    func updateButtons(selectedCount: Int) {
        let verb = stagedSide ? "Unstage" : "Stage"
        let noun = selectedCount == 1 ? "Line" : "\(selectedCount) Lines"
        primary.title = selectedCount > 0 ? "\(verb) \(noun)" : "\(verb) Hunk"
        discard.title = selectedCount > 0 ? "Discard \(noun)" : "Discard Hunk"
        primary.setAccessibilityLabel("\(primary.title), change \(index + 1)")
        discard.setAccessibilityLabel("\(discard.title), change \(index + 1)")
    }

    @objc private func primaryPressed() { coordinator?.stageHunk(index) }
    @objc private func discardPressed() { coordinator?.discardHunk(index) }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        let pixel = 1 / max(window?.backingScaleFactor ?? 2, 1)
        NSRect(x: 0, y: 0, width: bounds.width, height: pixel).fill()
        NSRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel).fill()
    }

    override var isFlipped: Bool { true }
}

/// "42 unchanged lines" between hunks.
final class GapRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("DiffGap")
    private let label = NSTextField(labelWithString: "")

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        label.font = NSFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DiffLineRowView.textStart),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(count: Int) {
        label.stringValue = count == 1 ? "1 unchanged line" : "\(count.formatted()) unchanged lines"
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
    }
}
