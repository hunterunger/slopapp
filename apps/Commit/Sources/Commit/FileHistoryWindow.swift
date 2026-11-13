import AppKit
import CommitCore
import Observation
import SlopKit
import SwiftUI

/// Which file a File History window shows (restored on relaunch).
struct FileHistoryTarget: Codable, Hashable {
    var root: String
    var path: String
    /// Open on Blame rather than Changes.
    var blame: Bool
    /// The commit to select first (hex), else the newest version.
    var revision: String?
}

/// One version in the list: the working copy, or a commit that changed the file.
enum FileVersion: Hashable {
    case workingCopy
    case commit(ObjectID)
}

/// A file's commits (following renames), each one's diff, and blame at any of them.
@MainActor
@Observable
final class FileHistoryModel {
    enum Mode: String, CaseIterable, Identifiable {
        case changes, blame
        var id: String { rawValue }
        var title: String { self == .changes ? "Changes" : "Blame" }
    }

    let target: FileHistoryTarget
    private(set) var repository: Repository?
    private(set) var entries: [FileHistoryEntry] = []
    private(set) var hasWorkingChanges = false
    private(set) var isLoading = true
    private(set) var loadError: String?

    var selection: FileVersion? { didSet { if oldValue != selection { selectedLine = nil; loadContent() } } }
    var mode: Mode { didSet { if oldValue != mode { loadContent() } } }

    private(set) var blame: Blame?
    private(set) var diff: DiffResult?
    private(set) var contentLoading = false
    private(set) var contentError: String?
    /// Selected line in Blame (index into `blame.lines`).
    var selectedLine: Int?

    @ObservationIgnored private var contentTask: Task<Void, Never>?

    init(target: FileHistoryTarget) {
        self.target = target
        self.mode = target.blame ? .blame : .changes
    }

    var fileName: String { (target.path as NSString).lastPathComponent }

    func load() async {
        let app = AppModel.shared
        await app.waitUntilReady()
        guard let runner = app.runner else {
            loadError = "Git isn't available. Check Commit's Settings."
            isLoading = false
            return
        }
        do {
            let location = try await Repository.locate(URL(fileURLWithPath: target.root, isDirectory: true), runner: runner)
            let repository = Repository(location: location, runner: runner)
            self.repository = repository
            async let history = repository.fileHistory(target.path)
            async let changed = repository.hasUncommittedChanges(target.path)
            entries = try await history
            hasWorkingChanges = await changed
            let exists = FileManager.default.fileExists(atPath: location.root.appendingPathComponent(target.path).path)
            isLoading = false
            if let hex = target.revision, let id = ObjectID(hex: hex), entries.contains(where: { $0.id == id }) {
                selection = .commit(id)
            } else if hasWorkingChanges && exists {
                selection = .workingCopy
            } else {
                selection = entries.first.map { .commit($0.id) }
            }
            if entries.isEmpty && !hasWorkingChanges { loadError = "“\(fileName)” has no commits yet." }
        } catch let problem as OpenProblem {
            loadError = problem.message
            isLoading = false
        } catch {
            loadError = (error as? GitFailure)?.output ?? String(describing: error)
            isLoading = false
        }
    }

    /// The versions in list order, newest first.
    var versions: [FileVersion] {
        (hasWorkingChanges ? [.workingCopy] : []) + entries.map { .commit($0.id) }
    }

    func entry(_ id: ObjectID) -> FileHistoryEntry? { entries.first { $0.id == id } }

    var selectedEntry: FileHistoryEntry? {
        if case .commit(let id) = selection { return entry(id) }
        return nil
    }

    /// The file's path in the selected version (renames).
    var selectedPath: String { selectedEntry?.path ?? target.path }

    var canGoOlder: Bool { index(of: selection).map { $0 < versions.count - 1 } ?? false }
    var canGoNewer: Bool { index(of: selection).map { $0 > 0 } ?? false }

    func goOlder() { move(by: 1) }
    func goNewer() { move(by: -1) }

    private func index(of version: FileVersion?) -> Int? {
        guard let version else { return nil }
        return versions.firstIndex(of: version)
    }

    private func move(by offset: Int) {
        guard let i = index(of: selection), versions.indices.contains(i + offset) else { NSSound.beep(); return }
        selection = versions[i + offset]
    }

    /// Blame the version before the change that last touched a line: the next older entry.
    func blameBefore(_ commit: ObjectID) {
        guard let i = entries.firstIndex(where: { $0.id == commit }) else {
            HUD.show("That change is older than this file's history here.", systemImage: "exclamationmark.triangle")
            return
        }
        guard entries.indices.contains(i + 1) else {
            HUD.show("That's the commit that added the file.", systemImage: "info.circle")
            return
        }
        mode = .blame
        selection = .commit(entries[i + 1].id)
    }

    func showChanges(of commit: ObjectID) {
        guard entry(commit) != nil else { return }
        selection = .commit(commit)
        mode = .changes
    }

    func reload() {
        Task {
            guard let repository else { return }
            entries = (try? await repository.fileHistory(target.path)) ?? entries
            hasWorkingChanges = await repository.hasUncommittedChanges(target.path)
            loadContent()
        }
    }

    private func loadContent() {
        guard let repository, let selection else { blame = nil; diff = nil; return }
        contentTask?.cancel()
        contentLoading = true
        contentError = nil
        let mode = mode
        let path = selectedPath
        contentTask = Task {
            do {
                switch (mode, selection) {
                case (.blame, .workingCopy):
                    let b = try await repository.blame(target.path, at: nil)
                    guard !Task.isCancelled else { return }
                    blame = b
                case (.blame, .commit(let id)):
                    if entry(id)?.change == .deleted {
                        throw OpenProblem.git("This commit deleted the file, so there are no lines to blame. Choose an older version.")
                    }
                    let b = try await repository.blame(path, at: id)
                    guard !Task.isCancelled else { return }
                    blame = b
                case (.changes, .workingCopy):
                    let d = try await repository.diffAgainstHead(target.path)
                    guard !Task.isCancelled else { return }
                    diff = d
                case (.changes, .commit(let id)):
                    guard let e = entry(id) else { return }
                    let d = try await repository.diff(of: e.changedFile, in: id, parent: e.parents.first)
                    guard !Task.isCancelled else { return }
                    diff = d
                }
                contentLoading = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                contentLoading = false
                contentError = (error as? GitFailure)?.output ?? (error as? OpenProblem)?.message ?? String(describing: error)
            }
        }
    }

    func copyHash(_ id: ObjectID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id.hex, forType: .string)
        HUD.show("Copied \(id.short)", systemImage: "doc.on.doc")
    }
}

/// The focused File History window, for menu commands.
struct FileHistoryModelKey: FocusedValueKey {
    typealias Value = FileHistoryModel
}

extension FocusedValues {
    var fileHistoryModel: FileHistoryModel? {
        get { self[FileHistoryModelKey.self] }
        set { self[FileHistoryModelKey.self] = newValue }
    }
}

struct FileHistoryWindow: View {
    @State private var model: FileHistoryModel

    init(target: FileHistoryTarget) {
        _model = State(initialValue: FileHistoryModel(target: target))
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading the history of \(model.fileName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.loadError, model.versions.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text(error))
            } else {
                NavigationSplitView {
                    FileVersionList(model: model)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
                } detail: {
                    FileVersionDetail(model: model)
                }
            }
        }
        .navigationTitle("History of \(model.fileName)")
        .navigationSubtitle(model.target.path)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("View", selection: $model.mode) {
                    ForEach(FileHistoryModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Changes in each commit, or who changed each line")
                .disabled(model.isLoading)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.goNewer() } label: { Label("Newer Version", systemImage: "chevron.up") }
                    .help("Newer version (⌘])")
                    .disabled(!model.canGoNewer)
                Button { model.goOlder() } label: { Label("Older Version", systemImage: "chevron.down") }
                    .help("Older version (⌘[)")
                    .disabled(!model.canGoOlder)
            }
        }
        .focusedSceneValue(\.fileHistoryModel, model)
        .task { await model.load() }
        .frame(minWidth: 720, minHeight: 420)
    }
}

/// Newest first: the working copy (if changed), then every commit that touched the file.
struct FileVersionList: View {
    @Bindable var model: FileHistoryModel
    private let now = Date()

    var body: some View {
        List(selection: $model.selection) {
            if model.hasWorkingChanges {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Version").italic()
                    Text("Not committed yet").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(FileVersion.workingCopy)
            }
            ForEach(model.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.subject.isEmpty ? "(no message)" : entry.subject)
                        .lineLimit(2)
                    Text("\(entry.authorName) · \(RelativeDate.string(for: entry.date, now: now)) · \(entry.id.short)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let original = entry.originalPath {
                        Text("Renamed from \(original)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if entry.change == .added || entry.change == .deleted {
                        Text(entry.change == .added ? "Added" : "Deleted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .help("\(entry.subject)\n\(entry.authorName) <\(entry.authorEmail)>, \(entry.date.formatted(date: .complete, time: .shortened))\n\(entry.id.hex)")
                .tag(FileVersion.commit(entry.id))
                .contextMenu {
                    Button("Copy Hash") { model.copyHash(entry.id) }
                }
            }
        }
        .accessibilityLabel("Versions, newest first")
    }
}

struct FileVersionDetail: View {
    @Bindable var model: FileHistoryModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            Group {
                if let error = model.contentError {
                    ContentUnavailableView(model.mode == .blame ? "Couldn't Show Blame" : "Couldn't Show the Changes",
                                           systemImage: "exclamationmark.triangle", description: Text(error))
                } else if model.mode == .blame {
                    if let blame = model.blame, !model.contentLoading {
                        if blame.lines.isEmpty {
                            ContentUnavailableView("Empty File", systemImage: "doc", description: Text("This version has no lines."))
                        } else {
                            BlameTable(model: model, blame: blame)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let diff = model.diff, !model.contentLoading {
                    ReadOnlyDiff(result: diff, source: model.selectedEntry.map { .commit($0.id, $0.changedFile) } ?? .none)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.mode == .blame, let blame = model.blame, let index = model.selectedLine, blame.lines.indices.contains(index) {
                Hairline()
                BlameLineBar(model: model, commit: blame.commit(of: blame.lines[index]))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            switch model.selection {
            case .workingCopy:
                Text("Current Version").font(.headline)
                Text(model.mode == .blame ? "Uncommitted lines are marked." : "Against the last commit")
                    .font(.callout).foregroundStyle(.secondary)
            case .commit(let id):
                let entry = model.entry(id)
                Text(entry?.subject ?? id.short).font(.headline).lineLimit(1).truncationMode(.tail)
                Text(id.short).font(.callout.monospaced()).foregroundStyle(.secondary)
            case nil:
                Text("No Version Selected").font(.headline)
            }
            Spacer(minLength: Spacing.s)
            if let diff = model.diff?.file, model.mode == .changes, !diff.hunks.isEmpty {
                Text("+\(diff.additions)").font(.callout).monospacedDigit().foregroundStyle(.textGreen)
                    .accessibilityLabel("\(diff.additions) lines added")
                Text("−\(diff.deletions)").font(.callout).monospacedDigit().foregroundStyle(.textRed)
                    .accessibilityLabel("\(diff.deletions) lines removed")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}

/// A diff with no staging: binary, empty and huge cases handled like the main window.
struct ReadOnlyDiff: View {
    let result: DiffResult
    let source: DiffState.Source

    var body: some View {
        if let file = result.file {
            if file.isBinary {
                ContentUnavailableView("Binary File", systemImage: "doc.zipper", description: Text("Its contents can't be shown as text."))
            } else if file.hunks.isEmpty {
                ContentUnavailableView("No Text Changes", systemImage: "doc", description: Text("Only the file's name or mode changed."))
            } else {
                DiffTable(file: file, state: DiffState(source: source, result: result), editable: false, model: nil)
            }
        } else {
            ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("This version matches the one before."))
        }
    }
}

/// The selected blame line's commit, with ways to move through history from it.
struct BlameLineBar: View {
    let model: FileHistoryModel
    let commit: Blame.Commit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if commit.isUncommitted {
                Text("Not committed yet").font(.callout)
                Spacer()
            } else {
                Text(commit.id.short).font(.callout.monospaced()).foregroundStyle(.secondary)
                Text(commit.summary).font(.callout).lineLimit(1).truncationMode(.tail)
                Text("\(commit.authorName), \(commit.authorTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: Spacing.s)
                Button("Show Changes") { model.showChanges(of: commit.id) }
                    .disabled(model.entry(commit.id) == nil)
                    .help("This commit's changes to the file")
                Button("Blame Before This Change") { model.blameBefore(commit.id) }
                    .disabled(commit.isBoundary && commit.previous == nil)
                    .help("Who changed these lines before this commit")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}

// MARK: - Blame table

/// Every line with who last changed it. A run of lines from one commit shows the commit once.
struct BlameTable: NSViewRepresentable {
    let model: FileHistoryModel
    let blame: Blame

    func makeCoordinator() -> BlameCoordinator { BlameCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.allowsMultipleSelection = false
        table.intercellSpacing = .zero
        table.backgroundColor = .textBackgroundColor
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.gridStyleMask = []
        table.rowHeight = ceil(BlameCoordinator.font.boundingRectForFont.height) + 2
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("blame"))
        column.resizingMask = []
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(BlameCoordinator.doubleClicked(_:))
        table.setAccessibilityLabel("Blame")
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.update(blame)
    }
}

@MainActor
final class BlameCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var table: NSTableView?
    var model: FileHistoryModel
    private var blame = Blame()
    private var runIndex: [Int] = []
    private let now = Date()

    static let gutterWidth: CGFloat = 230
    static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }
    static var smallFont: NSFont { NSFont.preferredFont(forTextStyle: .callout) }

    init(model: FileHistoryModel) {
        self.model = model
    }

    func update(_ new: Blame) {
        guard let table, new != blame else { return }
        blame = new
        var runs: [Int] = []
        var run = -1
        for i in new.lines.indices {
            if new.startsRun(i) { run += 1 }
            runs.append(run)
        }
        runIndex = runs
        table.reloadData()
        // Wide enough for the longest line.
        let longest = new.lines.map(\.text.count).max() ?? 0
        let charWidth = ("0" as NSString).size(withAttributes: [.font: Self.font]).width
        let width = Self.gutterWidth + numberWidth + Spacing.s * 2 + CGFloat(longest) * charWidth + Spacing.l
        table.tableColumns.first?.width = max(width, table.enclosingScrollView?.contentSize.width ?? 600)
        table.scrollRowToVisible(0)
    }

    var numberWidth: CGFloat {
        let digits = max(3, String(blame.lines.count).count)
        return CGFloat(digits) * ("0" as NSString).size(withAttributes: [.font: Self.font]).width
    }

    func numberOfRows(in tableView: NSTableView) -> Int { blame.lines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: BlameLineView.identifier, owner: nil) as? BlameLineView ?? BlameLineView()
        let line = blame.lines[row]
        let commit = blame.commit(of: line)
        let gutter: String?
        if blame.startsRun(row) {
            gutter = commit.isUncommitted
                ? "Not committed yet"
                : "\(commit.id.short) \(commit.authorName), \(RelativeDate.string(for: commit.authorTime, now: now))"
        } else {
            gutter = nil
        }
        cell.configure(gutter: gutter, number: line.line, text: line.text, numberWidth: numberWidth,
                       shaded: runIndex[row] % 2 == 1, uncommitted: commit.isUncommitted)
        cell.setAccessibilityLabel("Line \(line.line): \(line.text). \(commit.isUncommitted ? "Not committed yet" : "\(commit.authorName), \(commit.summary)")")
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table else { return }
        model.selectedLine = table.selectedRow >= 0 ? table.selectedRow : nil
    }

    @objc func doubleClicked(_ sender: Any?) {
        guard let table, table.clickedRow >= 0 else { return }
        let commit = blame.commit(of: blame.lines[table.clickedRow])
        if !commit.isUncommitted { model.showChanges(of: commit.id) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table, table.clickedRow >= 0 else { return }
        let commit = blame.commit(of: blame.lines[table.clickedRow])
        guard !commit.isUncommitted else { return }
        let hex = commit.id.hex
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: enabled ? action : nil, keyEquivalent: "")
            item.representedObject = hex
            item.target = self
            item.isEnabled = enabled
        }
        add("Show Changes in \(commit.id.short)", #selector(showChanges(_:)), enabled: model.entry(commit.id) != nil)
        add("Blame Before This Change", #selector(blameBefore(_:)))
        menu.addItem(.separator())
        add("Copy Hash", #selector(copyHash(_:)))
    }

    @objc private func showChanges(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.showChanges(of: id) }
    }

    @objc private func blameBefore(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.blameBefore(id) }
    }

    @objc private func copyHash(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.copyHash(id) }
    }
}

/// Gutter (commit, author, age at the start of each run), line number, text.
final class BlameLineView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("BlameLine")
    private let gutter = NSTextField(labelWithString: "")
    private let number = NSTextField(labelWithString: "")
    private let text = NSTextField(labelWithString: "")
    private var numberWidthConstraint: NSLayoutConstraint?
    private var shaded = false

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        for field in [gutter, number, text] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.maximumNumberOfLines = 1
            addSubview(field)
        }
        gutter.font = BlameCoordinator.smallFont
        gutter.textColor = .secondaryLabelColor
        gutter.lineBreakMode = .byTruncatingTail
        number.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        text.font = BlameCoordinator.font
        text.lineBreakMode = .byClipping
        let width = number.widthAnchor.constraint(equalToConstant: 30)
        numberWidthConstraint = width
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            gutter.widthAnchor.constraint(equalToConstant: BlameCoordinator.gutterWidth - Spacing.m),
            gutter.centerYAnchor.constraint(equalTo: centerYAnchor),
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BlameCoordinator.gutterWidth),
            width,
            number.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: Spacing.m),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    func configure(gutter gutterText: String?, number n: Int, text line: String, numberWidth: CGFloat, shaded: Bool, uncommitted: Bool) {
        gutter.stringValue = gutterText ?? ""
        gutter.textColor = uncommitted ? NSColor.readable(.systemOrange, on: .textBackgroundColor, target: ReadableColor.textTarget) : .secondaryLabelColor
        number.stringValue = "\(n)"
        numberWidthConstraint?.constant = numberWidth
        text.stringValue = line.replacingOccurrences(of: "\t", with: "    ")
        self.shaded = shaded
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if shaded {
            NSColor.labelColor.withAlphaComponent(0.035).setFill()
            NSRect(x: 0, y: 0, width: BlameCoordinator.gutterWidth - Spacing.xs, height: bounds.height).fill()
        }
        // A hairline between the gutter and the code.
        NSColor.separatorColor.setFill()
        let scale = window?.backingScaleFactor ?? 2
        NSRect(x: BlameCoordinator.gutterWidth - Spacing.xs, y: 0, width: 1 / scale, height: bounds.height).fill()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
