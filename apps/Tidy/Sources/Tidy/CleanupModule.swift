import SlopKit
import SwiftUI
import TidyCore

/// The parts of Cleanup, shown as tiles and as categories in its review.
enum CleanupPane: String, CaseIterable, Identifiable, Hashable {
    case systemJunk, mailDownloads, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemJunk: "System Junk"
        case .mailDownloads: "Mail Downloads"
        case .trash: "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .systemJunk: "internaldrive"
        case .mailDownloads: "paperclip"
        case .trash: "trash"
        }
    }

    var detail: String {
        switch self {
        case .systemJunk: "Caches, logs, crash reports and developer files that apps and tools make again when they need them."
        case .mailDownloads: JunkCategory.mailDownloads.detail
        case .trash: "What's in your Trash still takes up space until it's erased."
        }
    }

    func contains(_ category: JunkCategory) -> Bool {
        switch self {
        case .systemJunk: category != .mailDownloads
        case .mailDownloads: category == .mailDownloads
        case .trash: false
        }
    }
}

/// Cleanup's own state: the Trash's contents and which review category is showing.
@MainActor
@Observable
final class CleanupState {
    var pane: CleanupPane = .systemJunk
    var trashItems: [TrashBinItem] = []
    /// The Trash couldn't be read (no Full Disk Access on a real Mac).
    var trashUnreadable = false
    var trashPhase: ScanPhase = .idle
    var trashChecked: Set<String> = []
    var trashSelection: Set<String> = []
    /// What the last clean did, for the completion screen.
    var doneLines: [DoneLine] = []
    var doneMovedSomething = false
    @ObservationIgnored var task: Task<Void, Never>?
}

/// Emptying the Trash erases for good, so it always asks.
struct ErasePlan: Identifiable {
    enum Context { case cleanup, smartScan }
    let id = UUID()
    var urls: [URL]
    var bytes: Int64
    /// Every item in the Trash (Empty Trash) or only some (Erase).
    var isEverything: Bool
    var context: Context

    var title: String {
        isEverything ? "Empty the Trash?"
            : "Erase \(urls.count == 1 ? "1 item" : "\(urls.count) items") in the Trash?"
    }

    var message: String {
        "This permanently erases \(urls.count == 1 ? "1 item" : "\(urls.count.formatted()) items")"
            + (bytes > 0 ? " (\(ByteFormat.string(bytes)))" : "") + ". You can't undo this or put them back."
    }

    var buttonTitle: String { isEverything ? "Empty Trash" : "Erase" }
}

extension AppModel {
    // MARK: Cleanup scan

    func startCleanupScan() {
        cleanup.task?.cancel()
        setStage(.scanning, for: .junk)
        cleanup.task = Task {
            scanJunk()
            async let trash: Void = refreshTrashBins()
            await junkTask?.value
            await trash
            guard !Task.isCancelled else { return }
            setStage(.results, for: .junk)
        }
    }

    func stopCleanupScan() {
        cleanup.task?.cancel()
        stopJunk()
        setStage(junkItems.isEmpty && cleanup.trashItems.isEmpty ? .intro : .results, for: .junk)
    }

    var cleanupScanDetail: String {
        if case .scanning(let text) = junkPhase { return text }
        if case .scanning(let text) = cleanup.trashPhase { return text }
        return "Looking for caches, logs and developer files…"
    }

    func reviewCleanup(_ pane: CleanupPane) {
        cleanup.pane = pane
        query = ""
        setStage(.review, for: .junk)
    }

    // MARK: Trash bins

    func scanTrashBins() {
        Task { await refreshTrashBins() }
    }

    /// Lists the Trash and measures what's in it.
    func refreshTrashBins() async {
        cleanup.trashPhase = .scanning("Checking the Trash…")
        let scanner = TrashBinScanner(environment: environment)
        let scan = await Task.detached(priority: .userInitiated) { scanner.scan() }.value
        let previous = Set(cleanup.trashItems.map(\.id))
        cleanup.trashItems = scan.items
        cleanup.trashUnreadable = !scan.unreadable.isEmpty
        let ids = Set(scan.items.map(\.id))
        // Everything in the Trash starts checked; later rescans keep what was unchecked.
        cleanup.trashChecked = cleanup.trashChecked.intersection(ids).union(ids.subtracting(previous))
        cleanup.trashSelection.formIntersection(ids)
        sizes.request(scan.items.map(\.url))
        while scan.items.contains(where: { sizes.isMeasuring($0.url) }) {
            try? await Task.sleep(for: .milliseconds(120))
        }
        cleanup.trashPhase = .done
    }

    var trashTotal: (bytes: Int64, isComplete: Bool) { sizes.total(cleanup.trashItems.map(\.url)) }

    var checkedTrashItems: [TrashBinItem] {
        let visible = visibleTrashItems.map(\.id)
        let ids = Set(ReviewRules.actionable(checked: cleanup.trashChecked, visible: visible))
        return visibleTrashItems.filter { ids.contains($0.id) }
    }

    var visibleTrashItems: [TrashBinItem] {
        guard !query.isEmpty, section == .junk, cleanup.pane == .trash else { return cleanup.trashItems }
        return cleanup.trashItems.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Asks before erasing `items` (all of the Trash when nil).
    func confirmErase(_ items: [TrashBinItem]? = nil, context: ErasePlan.Context = .cleanup) {
        let list = items ?? cleanup.trashItems
        guard !list.isEmpty else { return }
        pendingErase = ErasePlan(urls: list.map(\.url), bytes: sizes.total(list.map(\.url)).bytes,
                                 isEverything: Set(list.map(\.id)) == Set(cleanup.trashItems.map(\.id)), context: context)
    }

    /// Erases for good. Only things directly inside the Trash (`TrashBinService.check`).
    @discardableResult
    func performErase(_ plan: ErasePlan) async -> EraseResult {
        let service = TrashBinService(environment: environment)
        let items = plan.urls.map { (url: $0, bytes: sizes.size($0)?.bytes ?? 0) }
        let result = await Task.detached(priority: .userInitiated) { service.erase(items) }.value
        sizes.forget(result.erased)
        pruneHistory()
        await refreshTrashBins()
        if !result.failures.isEmpty {
            failureReport = FailureReport(title: "Some items weren't erased", failures: result.failures, offersReveal: false)
        }
        return result
    }

    /// Drops history entries whose items are no longer in the Trash (it was emptied).
    func pruneHistory() {
        let fm = FileManager.default
        let pruned = history.compactMap { entry -> ActionResult? in
            if entry.wasPutBack { return entry }
            var entry = entry
            entry.moved = entry.moved.filter { fm.fileExists(atPath: $0.trashed.path) || (try? $0.trashed.checkResourceIsReachable()) == true }
            return entry.moved.isEmpty ? nil : entry
        }
        if pruned.map(\.id) != history.map(\.id) || pruned.map(\.moved.count) != history.map(\.moved.count) {
            history = pruned
        }
    }

    // MARK: Cleaning from tiles

    func junkItems(in pane: CleanupPane) -> [JunkItem] { junkItems.filter { pane.contains($0.category) } }

    func checkedJunk(in pane: CleanupPane) -> [JunkItem] {
        junkItems(in: pane).filter { junkChecked.contains($0.id) }
    }

    /// Clean on a tile: moves the checked items of that category to the Trash, then shows
    /// the completion screen.
    func cleanFromTile(_ pane: CleanupPane) {
        let items = checkedJunk(in: pane)
        guard !items.isEmpty else { return }
        setStage(.running, for: .junk)
        Task {
            let result = await performMove(items.map(\.url), section: .junk)
            cleanup.doneLines = Self.doneLines(moved: result, label: pane.title)
            cleanup.doneMovedSomething = !(result?.moved.isEmpty ?? true)
            setStage(.done, for: .junk)
        }
    }

    func finishErase(_ plan: ErasePlan) {
        pendingErase = nil
        switch plan.context {
        case .cleanup:
            setStage(.running, for: .junk)
            Task {
                let result = await performErase(plan)
                cleanup.doneLines = [Self.eraseLine(result)]
                cleanup.doneMovedSomething = false
                setStage(.done, for: .junk)
            }
        case .smartScan:
            runSmartScan(erasing: plan)
        }
    }

    static func doneLines(moved result: ActionResult?, label: String) -> [DoneLine] {
        guard let result else { return [] }
        var lines: [DoneLine] = []
        if !result.moved.isEmpty {
            lines.append(DoneLine(systemImage: "checkmark.circle.fill", title: "\(ByteFormat.string(result.bytes)) of \(label)",
                                  subtitle: "Moved to the Trash. Empty the Trash to free the space, or put it back (⌘Z)."))
        }
        if !result.failures.isEmpty {
            lines.append(DoneLine(systemImage: "exclamationmark.triangle.fill",
                                  title: "\(result.failures.count == 1 ? "1 item wasn't" : "\(result.failures.count) items weren't") moved",
                                  subtitle: result.failures.first?.message ?? "", isFailure: true))
        }
        return lines
    }

    static func eraseLine(_ result: EraseResult) -> DoneLine {
        if result.erased.isEmpty {
            return DoneLine(systemImage: "exclamationmark.triangle.fill", title: "Nothing was erased",
                            subtitle: result.failures.first?.message ?? "", isFailure: true)
        }
        return DoneLine(systemImage: "trash.slash.fill", title: "\(ByteFormat.string(result.bytes)) erased from the Trash",
                        subtitle: "\(result.erased.count == 1 ? "1 item" : "\(result.erased.count) items") erased for good."
                            + (result.failures.isEmpty ? "" : " \(result.failures.count) couldn't be erased."))
    }
}

// MARK: Views

struct CleanupModuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.stage(.junk) {
        case .intro:
            ModuleIntro(systemImage: SidebarSection.junk.systemImage, title: "Cleanup",
                        subtitle: "Clear caches, logs and developer files, copies of Mail attachments, and the Trash.",
                        features: CleanupPane.allCases.map { ModuleFeature(systemImage: $0.systemImage, title: $0.title) },
                        buttonHelp: "Look for junk (⌘R)", action: model.startCleanupScan) { EmptyView() }
        case .scanning:
            ModuleScanning(systemImage: SidebarSection.junk.systemImage, title: "Looking for junk…",
                           detail: model.cleanupScanDetail, onStop: model.stopCleanupScan)
        case .results:
            results
        case .review:
            CleanupReview(model: model)
        case .running:
            ModuleScanning(systemImage: SidebarSection.junk.systemImage, title: "Cleaning…")
        case .done:
            ModuleDone(systemImage: "checkmark", title: "Cleanup Complete", lines: model.cleanup.doneLines) {
                if model.cleanup.doneMovedSomething {
                    Button("Recently Moved to Trash…") { model.showingHistory = true }
                }
                Spacer()
                Button("Review Remaining Items") { model.reviewCleanup(model.cleanup.pane) }
                Button("Done") { model.setStage(.results, for: .junk) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var results: some View {
        let junk = model.sizes.total(model.junkItems(in: .systemJunk).map(\.url))
        let mail = model.sizes.total(model.junkItems(in: .mailDownloads).map(\.url))
        let trash = model.trashTotal
        let total = junk.bytes + mail.bytes + trash.bytes
        return ModuleResults(headline: total > 0 ? "There's \(ByteFormat.string(total)) you can clear." : "Nothing to clear right now.",
                             reviewAllTitle: "Review All Junk", onReviewAll: { model.reviewCleanup(.systemJunk) },
                             tiles: tiles(junk: junk.bytes, mail: mail.bytes, trash: trash.bytes)) {
            EmptyView()
        }
    }

    private func tiles(junk: Int64, mail: Int64, trash: Int64) -> [TileModel] {
        let checkedJunk = model.checkedJunk(in: .systemJunk)
        let checkedMail = model.checkedJunk(in: .mailDownloads)
        var tiles = [
            TileModel(id: "junk", systemImage: CleanupPane.systemJunk.systemImage, label: "System Junk",
                      value: "\(ByteFormat.string(junk)) found",
                      caption: checkedJunk.isEmpty ? "nothing checked" : "\(ByteFormat.string(model.sizes.total(checkedJunk.map(\.url)).bytes)) checked to clean",
                      detail: CleanupPane.systemJunk.detail,
                      actions: [TileAction(title: "Review", help: "See every item (and change what's checked)") { model.reviewCleanup(.systemJunk) },
                                TileAction(title: "Clean", isProminent: true, isEnabled: !checkedJunk.isEmpty && !model.isMoving,
                                           help: "Move the checked items to the Trash. You can put them back.") { model.cleanFromTile(.systemJunk) }],
                      isQuiet: junk == 0),
        ]
        if model.hasFullDiskAccess {
            tiles.append(TileModel(id: "mail", systemImage: CleanupPane.mailDownloads.systemImage, label: "Mail Downloads",
                                   value: "\(ByteFormat.string(mail)) found",
                                   caption: model.junkItems(in: .mailDownloads).isEmpty ? "nothing to clean"
                                       : checkedMail.isEmpty ? "nothing checked"
                                       : "\(ByteFormat.string(model.sizes.total(checkedMail.map(\.url)).bytes)) checked to clean",
                                   actions: [TileAction(title: "Review") { model.reviewCleanup(.mailDownloads) },
                                             TileAction(title: "Clean", isEnabled: !checkedMail.isEmpty && !model.isMoving) { model.cleanFromTile(.mailDownloads) }],
                                   isQuiet: mail == 0))
        } else {
            tiles.append(TileModel(id: "mail", systemImage: CleanupPane.mailDownloads.systemImage, label: "Mail Downloads",
                                   value: "Needs access", caption: "Mail keeps these in a protected folder.",
                                   actions: [TileAction(title: "Allow…", help: "Full Disk Access") { model.showingAccessSheet = true }],
                                   isQuiet: true))
        }
        if model.cleanup.trashUnreadable {
            tiles.append(TileModel(id: "trash", systemImage: CleanupPane.trash.systemImage, label: "Trash",
                                   value: "Needs access", caption: "macOS protects the Trash.",
                                   actions: [TileAction(title: "Allow…", help: "Full Disk Access") { model.showingAccessSheet = true }],
                                   isQuiet: true))
        } else {
            tiles.append(TileModel(id: "trash", systemImage: CleanupPane.trash.systemImage, label: "Trash",
                                   value: "\(ByteFormat.string(trash)) in the Trash",
                                   caption: model.cleanup.trashItems.isEmpty ? "already empty" : "to empty",
                                   actions: [TileAction(title: "Review") { model.reviewCleanup(.trash) },
                                             TileAction(title: "Empty…", isEnabled: !model.cleanup.trashItems.isEmpty,
                                                        help: "Erase everything in the Trash for good (asks first)") { model.confirmErase() }],
                                   isQuiet: model.cleanup.trashItems.isEmpty))
        }
        return tiles
    }
}

/// Cleanup's review: categories on the left, the checkable list on the right.
struct CleanupReview: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { model.cleanup.pane }, set: { if let pane = $0 { model.cleanup.pane = pane; model.query = "" } })) {
                ForEach(CleanupPane.allCases) { pane in
                    HStack {
                        Label(pane.title, systemImage: pane.systemImage)
                        Spacer()
                        Text(size(pane)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Categories")
            .reviewCategoryColumn()
            Hairline(axis: .vertical)
            VStack(spacing: 0) {
                PaneHeader(title: model.cleanup.pane.title, detail: model.cleanup.pane.detail)
                Hairline()
                switch model.cleanup.pane {
                case .systemJunk, .mailDownloads: JunkPane(model: model, pane: model.cleanup.pane)
                case .trash: TrashPane(model: model)
                }
            }
        }
    }

    private func size(_ pane: CleanupPane) -> String {
        let urls = pane == .trash ? model.cleanup.trashItems.map(\.url) : model.junkItems(in: pane).map(\.url)
        if pane == .mailDownloads && !model.hasFullDiskAccess { return "—" }
        if pane == .trash && model.cleanup.trashUnreadable { return "—" }
        return ByteFormat.string(model.sizes.total(urls).bytes)
    }
}

struct PaneHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// System Junk or Mail Downloads, grouped by kind, with Move to Trash below.
struct JunkPane: View {
    @Bindable var model: AppModel
    let pane: CleanupPane

    var body: some View {
        VStack(spacing: 0) {
            if pane == .mailDownloads && !model.hasFullDiskAccess {
                PermissionPrompt(permission: .fullDiskAccess, reason: """
                Mail keeps copies of opened attachments in a folder macOS protects. With Full Disk \
                Access, Tidy can list them.
                """)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleJunkItems.isEmpty {
                if !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .scanning = model.junkPhase {
                    ProgressView("Looking for junk…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(pane == .mailDownloads ? "No Mail Downloads" : "No Junk Found", systemImage: "checkmark.circle")
                    } description: {
                        Text(pane == .mailDownloads ? "Mail hasn't kept any copies of attachments."
                             : "There are no caches, logs or developer files to clear right now.")
                    } actions: {
                        Button("Scan Again") { model.startCleanupScan() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ReviewList(sections: sections, checked: $model.junkChecked, selection: $model.junkSelection,
                           sizes: model.sizes, home: model.environment.home)
            }
            // Nothing can be checked behind the permission prompt, so no bar under it.
            if !(pane == .mailDownloads && !model.hasFullDiskAccess) {
                ActionBar(model: model, section: .junk, checkedURLs: model.actionableJunk.map(\.url))
            }
        }
    }

    private var sections: [ReviewSection] {
        let home = model.environment.home
        let grouped = Dictionary(grouping: model.visibleJunkItems, by: \.category)
        return JunkCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return ReviewSection(id: category.rawValue, title: category.title, systemImage: category.systemImage,
                                 detail: category.detail,
                                 items: items.sorted { (model.sizes.size($0.url)?.bytes ?? 0) > (model.sizes.size($1.url)?.bytes ?? 0) }
                                    .map { item in
                                        // The real folder name, with the friendly name (app, project) after the path.
                                        if item.category == .mailDownloads {
                                            return ReviewItem(url: item.url, title: item.name, subtitle: "In Mail Downloads",
                                                              note: item.note, help: item.url.path)
                                        }
                                        let friendly = item.name == item.url.lastPathComponent ? "" : " · \(item.name)"
                                        return ReviewItem(url: item.url, title: item.url.lastPathComponent,
                                                          subtitle: PathDisplay.parent(item.url, home: home) + friendly,
                                                          note: item.note)
                                    })
        }
    }
}

/// What's in the Trash, all checked; Empty Trash (or Erase for some) asks first.
struct TrashPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.cleanup.trashUnreadable {
                ContentUnavailableView {
                    Label("Tidy Can't See Inside the Trash", systemImage: "lock.shield")
                } description: {
                    Text("macOS protects the Trash. Allow Full Disk Access, or open the Trash in Finder and empty it there.")
                } actions: {
                    Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                    Button("Open Trash") { NSWorkspace.shared.open(model.environment.trashBins[0]) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleTrashItems.isEmpty {
                if !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("The Trash Is Empty", systemImage: "trash")
                    } description: {
                        Text("Things you move to the Trash show up here until it's emptied.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ReviewList(sections: [section], checked: Binding(get: { model.cleanup.trashChecked }, set: { model.cleanup.trashChecked = $0 }),
                           selection: Binding(get: { model.cleanup.trashSelection }, set: { model.cleanup.trashSelection = $0 }),
                           sizes: model.sizes, home: model.environment.home)
            }
            TrashBar(model: model)
        }
    }

    private var section: ReviewSection {
        ReviewSection(id: "trash", title: "In the Trash", systemImage: "trash", detail: nil,
                      items: model.visibleTrashItems
                        .sorted { (model.sizes.size($0.url)?.bytes ?? 0) > (model.sizes.size($1.url)?.bytes ?? 0) }
                        .map { item in
                            ReviewItem(url: item.url, title: item.name,
                                       subtitle: item.dateTrashed.map { "Moved to the Trash \($0.formatted(.relative(presentation: .named)))" } ?? "In the Trash")
                        })
    }
}

struct TrashBar: View {
    var model: AppModel

    var body: some View {
        let checked = model.checkedTrashItems
        let total = model.sizes.total(checked.map(\.url))
        BottomBar {
            Text(checked.isEmpty ? "Nothing checked"
                 : "\(checked.count == 1 ? "1 item" : "\(checked.count.formatted()) items") checked, \(total.isComplete ? "" : "at least ")\(ByteFormat.string(total.bytes))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Open Trash") { NSWorkspace.shared.open(model.environment.trashBins[0]) }
                .help("Show the Trash in Finder")
            let everything = !checked.isEmpty && checked.count == model.cleanup.trashItems.count
            Button(everything ? "Empty Trash…" : "Erase…") { model.confirmErase(checked) }
                .buttonStyle(.borderedProminent)
                .disabled(checked.isEmpty || model.cleanup.trashUnreadable)
                .help("Erase the checked items for good. Tidy asks first; this can't be undone.")
        }
    }
}

extension AppModel {
    /// File ▸ Empty Trash… (⇧⌘⌫): looks in the Trash, then asks.
    func emptyTrashCommand() {
        Task {
            await refreshTrashBins()
            if cleanup.trashUnreadable {
                failureReport = FailureReport(title: "Tidy can't see inside the Trash", failures: [
                    TrashFailure(url: environment.trashBins[0], message: "macOS protects the Trash. Allow Full Disk Access, or empty it in Finder."),
                ], offersReveal: false)
            } else if cleanup.trashItems.isEmpty {
                failureReport = FailureReport(title: "The Trash is already empty", failures: [], offersReveal: false)
            } else {
                confirmErase()
            }
        }
    }
}
