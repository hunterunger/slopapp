import AppKit
import SlopKit
import TidyCore
import UniformTypeIdentifiers

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case uninstall, leftovers, junk, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uninstall: "Uninstall"
        case .leftovers: "Leftovers"
        case .junk: "Junk"
        case .large: "Large & Old"
        }
    }

    var systemImage: String {
        switch self {
        case .uninstall: "trash.square"
        case .leftovers: "questionmark.folder"
        case .junk: "sparkles"
        case .large: "doc.badge.clock"
        }
    }

    var searchPrompt: String {
        switch self {
        case .uninstall: "Search apps"
        case .leftovers, .junk: "Search items"
        case .large: "Search files"
        }
    }
}

enum AppSort: String, CaseIterable, Identifiable {
    case name, size, lastOpened
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .size: "App Size"
        case .lastOpened: "Last Opened"
        }
    }
}

enum ScanPhase: Equatable {
    case idle
    case scanning(String)
    case done
    case stopped
}

/// What the last Move to Trash did, shown under the list with Put Back.
struct ActionResult: Identifiable {
    var id = UUID()
    var section: SidebarSection
    var moved: [TrashedItem]
    var failures: [TrashFailure]
    /// Set when an app itself was moved.
    var appName: String?
    var keptAppName: String?
    var isPutBack = false
    /// Items found but not moved (protected or needing an administrator).
    var leftInPlace: [Leftover] = []
    var date = Date()
    /// This move was undone (Put Back) since.
    var wasPutBack = false
    /// Some items were put back, the rest (still in `moved`) are still in the Trash.
    var partlyPutBack = false
    /// Put back summaries: how many couldn't be put back.
    var stillInTrash = 0

    var bytes: Int64 { moved.reduce(0) { $0 + $1.bytes } }

    var logEntry: TrashLogEntry {
        TrashLogEntry(id: id, date: date, section: section.rawValue, moved: moved, appName: appName,
                      keptAppName: keptAppName, wasPutBack: wasPutBack, partlyPutBack: partlyPutBack)
    }

    init(section: SidebarSection, moved: [TrashedItem], failures: [TrashFailure], appName: String? = nil,
         keptAppName: String? = nil, isPutBack: Bool = false, leftInPlace: [Leftover] = []) {
        self.section = section
        self.moved = moved
        self.failures = failures
        self.appName = appName
        self.keptAppName = keptAppName
        self.isPutBack = isPutBack
        self.leftInPlace = leftInPlace
    }

    init(_ entry: TrashLogEntry) {
        self.init(section: SidebarSection(rawValue: entry.section) ?? .junk, moved: entry.moved, failures: [],
                  appName: entry.appName, keptAppName: entry.keptAppName)
        id = entry.id
        date = entry.date
        partlyPutBack = entry.partlyPutBack ?? false
    }

    var summary: String {
        let count = moved.count
        let items = count == 1 ? "1 item" : "\(count.formatted()) items"
        if isPutBack {
            let left = stillInTrash == 0 ? "" : " \(stillInTrash == 1 ? "1 item is" : "\(stillInTrash) items are") still in the Trash."
            return count == 0 ? "Nothing was put back.\(left)" : "Put back \(items).\(left)"
        }
        if let appName {
            let others = count - 1
            return others > 0 ? "Moved \(appName) and \(others == 1 ? "1 item" : "\(others.formatted()) items") to the Trash."
                : "Moved \(appName) to the Trash."
        }
        if let keptAppName { return "Moved \(items) to the Trash. \(keptAppName) is still installed." }
        return "Moved \(items) to the Trash."
    }

    var leftInPlaceNote: String? {
        guard !leftInPlace.isEmpty, !isPutBack else { return nil }
        let count = leftInPlace.count
        return (count == 1 ? "1 item needs" : "\(count) items need")
            + " an administrator or Full Disk Access, so Tidy left \(count == 1 ? "it" : "them") in place."
    }
}

/// Failures to show in an alert.
struct FailureReport: Identifiable {
    let id = UUID()
    var title: String
    var failures: [TrashFailure]
    /// Show in Finder helps for permission problems, not for "that isn't an app".
    var offersReveal = true
    /// Offer to open Recently Moved to Trash (to keep both or find what's left).
    var offersHistory = false
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let environment: TidyEnvironment
    let trash: TrashService
    let sizes = SizeStore()
    let running: RunningApps
    var section: SidebarSection = .uninstall
    var query = "" {
        didSet { if query != oldValue { reconcileSelections() } }
    }
    var hasFullDiskAccess: Bool
    var showingAccessSheet = false
    var failureReport: FailureReport?
    var previewURL: URL?
    var isMoving = false
    var results: [SidebarSection: ActionResult] = [:]
    /// Every move to the Trash that can still be put back (this session and earlier ones
    /// whose items are still in the Trash), oldest first. Undo walks it backwards.
    var history: [ActionResult] = [] {
        didSet { saveHistory() }
    }
    /// Put Back failures to show inside the history sheet while it's open.
    var historyFailures: [TrashFailure] = []
    /// Moves that were undone, for Redo.
    private var redoStack: [ActionResult] = []
    var showingHistory = false {
        didSet { if !showingHistory { historyFailures = [] } }
    }
    /// A text field (search) is being edited: text editing owns Undo, ⌘⌫, ⌘A...
    var isEditingText = false
    @ObservationIgnored private var editingObservers: [NSObjectProtocol] = []

    /// A sheet or alert is up: menu commands that change what's behind it are off.
    var isModalUp: Bool {
        showingHistory || showingAccessSheet || quitRequest != nil || pendingUninstall != nil || failureReport != nil
    }
    /// Waiting for the user to confirm an uninstall started from a menu or shortcut.
    var pendingUninstall: UninstallPlan?

    // Uninstall
    var apps: [InstalledApp] = []
    var appsLoaded = false
    var lastOpened: [String: Date] = [:]
    var appSort: AppSort = AppSort(rawValue: Keys.defaults.string(forKey: Keys.appSort) ?? "") ?? .name {
        didSet {
            Keys.defaults.set(appSort.rawValue, forKey: Keys.appSort)
            if appSort == .size { sizes.request(apps.map(\.url)) }
            if appSort == .lastOpened { loadAllLastOpened() }
        }
    }
    var selectedAppID: String? {
        didSet {
            guard oldValue != selectedAppID else { return }
            // Picking another app clears the last result; the app disappearing doesn't.
            if selectedAppID != nil { results[.uninstall] = nil }
            selectedAppChanged()
        }
    }
    /// An app chosen from outside the Applications folders.
    var externalApp: InstalledApp?
    private(set) var index: LibraryIndex?
    private(set) var finder: LeftoverFinder?
    var leftovers: [Leftover] = []
    var appChecked: Set<String> = []
    var appSelection: Set<String> = []
    var quitRequest: InstalledApp?

    // Leftovers of deleted apps
    var orphanGroups: [OrphanGroup] = []
    var orphanPhase: ScanPhase = .idle
    var orphanChecked: Set<String> = []
    var orphanSelection: Set<String> = []
    /// The leftover count from the last scan, shown in the sidebar until a new one finishes.
    var cachedOrphanCount: Int? = Keys.defaults.object(forKey: "orphanCount") as? Int {
        didSet { Keys.defaults.set(cachedOrphanCount, forKey: "orphanCount") }
    }

    // Junk
    var junkItems: [JunkItem] = []
    var junkPhase: ScanPhase = .idle
    var junkChecked: Set<String> = []
    var junkSelection: Set<String> = []
    @ObservationIgnored private var junkTask: Task<Void, Never>?

    // Large & Old
    var largeFiles: [LargeFile] = []
    var largePhase: ScanPhase = .idle
    var largeChecked: Set<String> = []
    var largeSelection: Set<String> = []
    var largeFilter = Keys.savedLargeFilter() {
        didSet { Keys.save(largeFilter) }
    }
    var largeRoot: URL
    /// Desktop, Documents and Downloads were left out (no Full Disk Access).
    var largeSkippedProtected = false
    var largeChoice: LargeScanChoice? = Keys.defaults.bool(forKey: Keys.skipProtected) ? .withoutProtectedFolders : nil {
        didSet { Keys.defaults.set(largeChoice != nil, forKey: Keys.skipProtected) }
    }
    @ObservationIgnored private var largeTask: Task<Void, Never>?

    enum LargeScanChoice { case withoutProtectedFolders }

    init() {
        let environment = TidyEnvironment.current
        self.environment = environment
        trash = TrashService(environment: environment)
        running = RunningApps(environment: environment)
        hasFullDiskAccess = FullDiskAccess.isGranted(environment: environment)
        largeRoot = environment.home
        history = TrashLog.load(from: historyFile).map(ActionResult.init)
        let center = NotificationCenter.default
        for (name, editing) in [(NSControl.textDidBeginEditingNotification, true), (NSControl.textDidEndEditingNotification, false)] {
            editingObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isEditingText = editing }
            })
        }
        let cache = appSizeCache
        sizes.onMeasured = { [weak self] path, usage in
            guard let self, self.apps.contains(where: { $0.id == path }) else { return }
            cache.remember(path, usage)
        }
    }

    @ObservationIgnored private let appSizeCache = AppSizeCache()

    var policy: TrashPolicy { trash.policy }

    /// Where the move log lives: next to the fixture in test mode, else Application Support.
    var historyFile: URL {
        if environment.isTestMode, let trash = environment.trashDirectory {
            return trash.deletingLastPathComponent().appendingPathComponent("tidy-history.json")
        }
        let support = (try? AppPaths.applicationSupport) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("trash-log.json")
    }

    private func saveHistory() {
        try? TrashLog.save(history.map(\.logEntry), to: historyFile)
    }

    // MARK: Lifecycle

    func start() {
        loadApps()
    }

    func refreshAccess() {
        let granted = FullDiskAccess.isGranted(environment: environment)
        guard granted != hasFullDiskAccess else { return }
        hasFullDiskAccess = granted
        if granted {
            requestLeftoverSizes()
            if section == .leftovers { requestOrphanSizes() }
            if largeSkippedProtected { scanLarge() }
        }
    }

    // MARK: Apps

    func loadApps(keepSelection: Bool = true) {
        let environment = self.environment
        Task {
            let (apps, index) = await Task.detached(priority: .userInitiated) {
                (AppCatalog.scan(environment.applicationDirectories), LibraryIndex.build(environment))
            }.value
            self.apps = apps
            appSizeCache.apply(to: apps, sizes: sizes)
            self.index = index
            self.finder = LeftoverFinder(apps: apps, index: index)
            self.appsLoaded = true
            if !keepSelection || (selectedAppID != nil && currentApp == nil) { selectedAppID = nil }
            selectedAppChanged()
            // App sizes are measured as rows appear (and all at once when sorting by size), so
            // launching doesn't walk every app on the Mac.
            if appSort == .size { sizes.request(apps.map(\.url)) }
            // The sidebar shows last time's leftover count at once; a fresh count is made in
            // the background a little later (it asks LaunchServices about every candidate, so
            // it waits until launch has settled), or right away when the section opens.
            if orphanPhase == .idle {
                Task {
                    try? await Task.sleep(for: .seconds(30))
                    if orphanPhase == .idle { findOrphans() }
                }
            } else {
                findOrphans()
            }
            if appSort == .lastOpened { loadAllLastOpened() }
        }
    }

    @ObservationIgnored private var lastOpenedQueue: Set<URL> = []
    @ObservationIgnored private var lastOpenedAsked: Set<String> = []
    @ObservationIgnored private var lastOpenedScheduled = false

    /// Asks Spotlight when an app was last opened, for rows as they appear (batched), so
    /// launching doesn't query every app.
    func requestLastOpened(_ app: InstalledApp) {
        guard !environment.isTestMode, lastOpenedAsked.insert(app.id).inserted else { return }
        lastOpenedQueue.insert(app.url)
        guard !lastOpenedScheduled else { return }
        lastOpenedScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            let urls = lastOpenedQueue
            lastOpenedQueue = []
            lastOpenedScheduled = false
            let dates = await Task.detached(priority: .utility) {
                var result: [String: Date] = [:]
                for url in urls { if let date = SystemLookup.lastOpened(url) { result[url.path] = date } }
                return result
            }.value
            lastOpened.merge(dates) { _, new in new }
        }
    }

    private func loadAllLastOpened() {
        for app in apps { requestLastOpened(app) }
    }

    var currentApp: InstalledApp? {
        if let externalApp, externalApp.id == selectedAppID { return externalApp }
        return apps.first { $0.id == selectedAppID }
    }

    var sortedApps: [InstalledApp] {
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
        switch appSort {
        case .name:
            return filtered
        case .size:
            return filtered.sorted { (sizes.size($0.url)?.bytes ?? -1) > (sizes.size($1.url)?.bytes ?? -1) }
        case .lastOpened:
            guard canSortByLastOpened else { return filtered }
            return filtered.sorted { (lastOpened[$0.id] ?? .distantPast) < (lastOpened[$1.id] ?? .distantPast) }
        }
    }

    /// Spotlight knows when apps were last opened (not in test mode, and not always).
    var canSortByLastOpened: Bool { !lastOpened.isEmpty }

    /// Ids of the apps the list shows, the chosen outside app first.
    var visibleAppIDs: [String] { [externalApp?.id].compactMap { $0 } + sortedApps.map(\.id) }

    /// Keeps selections pointing only at things that are on screen, so no action can reach
    /// something search has hidden.
    func reconcileSelections() {
        let selected = ReviewRules.reconcile(selection: selectedAppID, visible: visibleAppIDs)
        if selected != selectedAppID { selectedAppID = selected }
        orphanSelection = ReviewRules.reconcile(selection: orphanSelection, visible: visibleOrphanGroups.flatMap(\.items).map(\.id))
        junkSelection = ReviewRules.reconcile(selection: junkSelection, visible: visibleJunkItems.map(\.id))
        largeSelection = ReviewRules.reconcile(selection: largeSelection, visible: visibleLargeFiles.map(\.id))
    }

    private func selectedAppChanged() {
        appSelection = []
        guard let app = currentApp, let finder else {
            leftovers = []
            appChecked = []
            return
        }
        leftovers = finder.leftovers(for: app)
        // Possible matches (common or shared names) are never checked for you.
        appChecked = Set(leftovers.filter { isRemovable($0) && !$0.reason.isPossibleMatch }.map(\.id))
        if !canRemove(app) { appChecked = [] }
        requestLeftoverSizes()
    }

    private func requestLeftoverSizes() {
        sizes.request(leftovers.filter { hasFullDiskAccess || !$0.needsFullDiskAccess }.map(\.url))
    }

    func isRemovable(_ item: Leftover) -> Bool { item.isRemovable(hasFullDiskAccess: hasFullDiskAccess) }

    /// Why the app can't be removed, if it can't.
    func refusal(for app: InstalledApp) -> String? {
        if app.isApple { return "\(app.name) is part of macOS, so Tidy doesn't remove it." }
        if app.url.path == Bundle.main.bundleURL.path { return "Tidy can't remove itself. Quit it and drag it to the Trash." }
        if !policy.allows(app.url) {
            return environment.isTestMode
                ? "In test mode, Tidy only removes apps from \(environment.applicationDirectories.map(\.path).joined(separator: ", "))."
                : "Tidy removes apps from your Applications folders and home folder only."
        }
        return nil
    }

    func canRemove(_ app: InstalledApp) -> Bool { refusal(for: app) == nil }

    /// Picks an app given as a file (dropped, chosen or opened).
    func open(appAt url: URL) {
        section = .uninstall
        query = ""
        guard let app = AppCatalog.read(url) else {
            failureReport = FailureReport(title: "Tidy only uninstalls apps", failures: [
                TrashFailure(url: url, message: "It isn't an app, so Tidy ignored it. To clear out files, use Junk or Large & Old."),
            ], offersReveal: false)
            return
        }
        if let known = apps.first(where: { $0.url.path == app.url.path }) {
            selectedAppID = known.id
        } else {
            externalApp = app
            selectedAppID = app.id
        }
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = environment.applicationDirectories.first
        panel.prompt = "Choose"
        panel.message = "Choose an app to see everything it keeps on your Mac."
        if panel.runModal() == .OK, let url = panel.url { open(appAt: url) }
    }

    // MARK: Moving to the Trash

    /// Move to Trash for whatever section is showing. Only checked items that are visible
    /// right now are moved; an uninstall started from a menu or shortcut asks first.
    func moveCheckedToTrash(_ trigger: MoveTrigger) {
        switch section {
        case .uninstall: uninstallChecked(trigger)
        case .leftovers: move(actionableOrphans.map(\.url), section: .leftovers)
        case .junk: move(actionableJunk.map(\.url), section: .junk)
        case .large: move(actionableLarge.map(\.url), section: .large)
        }
    }

    var canMoveToTrash: Bool {
        guard !isMoving else { return false }
        switch section {
        case .uninstall: return currentApp.map(canRemove) == true && !checkedLeftovers.isEmpty
        case .leftovers: return !actionableOrphans.isEmpty
        case .junk: return !actionableJunk.isEmpty
        case .large: return !actionableLarge.isEmpty
        }
    }

    /// The selected app's checked, movable items (only when the app is visible in the list).
    var checkedLeftovers: [Leftover] {
        guard let app = currentApp, visibleAppIDs.contains(app.id) else { return [] }
        let ids = Set(ReviewRules.actionable(checked: appChecked, visible: leftovers.map(\.id)))
        return leftovers.filter { ids.contains($0.id) && isRemovable($0) }
    }

    var visibleOrphanGroups: [OrphanGroup] {
        guard !query.isEmpty else { return orphanGroups }
        return orphanGroups.compactMap { group in
            var group = group
            group.items = group.items.filter {
                group.bundleID.localizedCaseInsensitiveContains(query) || group.displayName.localizedCaseInsensitiveContains(query)
                    || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
            }
            return group.items.isEmpty ? nil : group
        }
    }

    var actionableOrphans: [Leftover] {
        let items = visibleOrphanGroups.flatMap(\.items)
        let ids = Set(ReviewRules.actionable(checked: orphanChecked, visible: items.map(\.id)))
        return items.filter { ids.contains($0.id) && isRemovable($0) }
    }

    var visibleJunkItems: [JunkItem] {
        guard !query.isEmpty else { return junkItems }
        return junkItems.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    var actionableJunk: [JunkItem] {
        let ids = Set(ReviewRules.actionable(checked: junkChecked, visible: visibleJunkItems.map(\.id)))
        return visibleJunkItems.filter { ids.contains($0.id) }
    }

    var actionableLarge: [LargeFile] {
        let ids = Set(ReviewRules.actionable(checked: largeChecked, visible: visibleLargeFiles.map(\.id)))
        return visibleLargeFiles.filter { ids.contains($0.id) }
    }

    func uninstallChecked(_ trigger: MoveTrigger) {
        guard let app = currentApp, canRemove(app) else { return }
        let items = checkedLeftovers
        guard !items.isEmpty else { return }
        let includesApp = items.first?.kind == .application
        let plan = UninstallPlan(appName: app.name, includesApp: includesApp, itemCount: items.count - (includesApp ? 1 : 0),
                                 bytes: sizes.total(items.map(\.url)).bytes)
        if plan.needsConfirmation(trigger) {
            pendingUninstall = plan
            return
        }
        if running.isRunning(app) {
            quitRequest = app
            return
        }
        move(items.map(\.url), section: .uninstall, stopIfFirstFails: includesApp,
             appName: includesApp ? app.name : nil, keptAppName: includesApp ? nil : app.name,
             leftInPlace: leftovers.filter { !isRemovable($0) && !$0.reason.isPossibleMatch })
    }

    /// After the quit sheet: wait for the app to quit, then carry on.
    func quitAndContinue(_ app: InstalledApp, force: Bool) {
        running.quit(app, force: force)
        Task {
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                running.refresh()
                if !running.isRunning(app) {
                    quitRequest = nil
                    uninstallChecked(.reviewButton)
                    return
                }
            }
        }
    }

    private func move(_ urls: [URL], section: SidebarSection, stopIfFirstFails: Bool = false,
                      appName: String? = nil, keptAppName: String? = nil, leftInPlace: [Leftover] = [],
                      clearsRedo: Bool = true) {
        guard !urls.isEmpty, !isMoving else { return }
        isMoving = true
        let items = urls.map { (url: $0, bytes: sizes.size($0)?.bytes ?? junkSize($0) ?? largeSize($0) ?? 0) }
        let trash = self.trash
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                trash.moveToTrash(items, stopIfFirstFails: stopIfFirstFails)
            }.value
            isMoving = false
            let movedApp = appName != nil && result.moved.first?.original == urls.first
            let outcome = ActionResult(section: section, moved: result.moved, failures: result.failures,
                                       appName: movedApp ? appName : nil, keptAppName: keptAppName, leftInPlace: leftInPlace)
            if !result.moved.isEmpty {
                results[section] = outcome
                history.append(outcome)
                if clearsRedo { redoStack.removeAll() }
            }
            if !result.failures.isEmpty {
                failureReport = FailureReport(
                    title: result.stoppedEarly ? "Nothing was moved" : "Some items weren't moved",
                    failures: result.failures)
            }
            afterChange(movedPaths: Set(result.moved.map(\.original.path)), section: section)
        }
    }

    /// Puts back the latest move shown in `section`.
    func putBack(_ section: SidebarSection) {
        guard let result = results[section], !result.isPutBack else { return }
        putBack(entry: result.id)
    }

    /// Puts back one move from this session's history.
    /// Puts back one move from the history. Items whose place is taken stay in the Trash
    /// (the entry is then "partly put back"), unless `keepBoth` restores them next to the
    /// new item as "Name (restored)".
    func putBack(entry id: UUID, keepBoth: Bool = false) {
        guard let index = history.firstIndex(where: { $0.id == id }), !history[index].wasPutBack else { return }
        let entry = history[index]
        history[index].wasPutBack = true   // no double put-backs while this runs
        let trash = self.trash
        Task {
            let (restored, failures) = await Task.detached { trash.putBack(entry.moved, keepBoth: keepBoth) }.value
            let restoredFrom = Set(restored.map(\.trashed.path))
            let remaining = entry.moved.filter { !restoredFrom.contains($0.trashed.path) }
            if let i = history.firstIndex(where: { $0.id == id }) {
                if remaining.isEmpty {
                    history[i].wasPutBack = true
                } else {
                    history[i].wasPutBack = false
                    history[i].moved = remaining
                    history[i].partlyPutBack = history[i].partlyPutBack || !restored.isEmpty
                }
            }
            var summary = ActionResult(section: entry.section, moved: restored, failures: failures, isPutBack: true)
            summary.stillInTrash = remaining.count
            results[entry.section] = summary
            if !failures.isEmpty {
                // Shown inside the history sheet when it's open, else as an alert that leads there.
                if showingHistory {
                    historyFailures = failures
                } else {
                    failureReport = FailureReport(title: "Some items are still in the Trash", failures: failures,
                                                  offersReveal: false, offersHistory: true)
                }
            }
            if !restored.isEmpty {
                var redo = entry
                redo.moved = restored
                redoStack.append(redo)
            }
            afterChange(movedPaths: Set(restored.map(\.original.path)), section: entry.section, restoredApp: true)
        }
    }

    /// The most recent move that can still be put back (Edit ▸ Undo).
    var undoableEntry: ActionResult? { history.last { !$0.wasPutBack && !$0.partlyPutBack } }
    var redoableEntry: ActionResult? { redoStack.last }

    func undo() {
        guard let entry = undoableEntry else { return }
        section = entry.section
        putBack(entry: entry.id)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        section = entry.section
        move(entry.moved.map(\.original), section: entry.section, appName: entry.appName, keptAppName: entry.keptAppName,
             leftInPlace: entry.leftInPlace, clearsRedo: false)
    }

    /// Refreshes every list that may show the moved paths.
    private func afterChange(movedPaths: Set<String>, section: SidebarSection, restoredApp: Bool = false) {
        guard !movedPaths.isEmpty else { return }
        sizes.forget(movedPaths.map { URL(fileURLWithPath: $0) })
        appChecked.subtract(movedPaths)
        orphanChecked.subtract(movedPaths)
        junkChecked.subtract(movedPaths)
        largeChecked.subtract(movedPaths)
        let exists = { (path: String) in FileManager.default.fileExists(atPath: path) }
        junkItems.removeAll { movedPaths.contains($0.id) && !exists($0.id) }
        largeFiles.removeAll { movedPaths.contains($0.id) && !exists($0.id) }
        if restoredApp {
            if section == .junk { scanJunk() }
            if section == .large { scanLarge() }
        }
        if let external = externalApp, movedPaths.contains(external.id) { externalApp = nil }
        loadApps()
    }

    private func junkSize(_ url: URL) -> Int64? { sizes.size(url)?.bytes }
    private func largeSize(_ url: URL) -> Int64? { largeFiles.first { $0.url == url }?.size }

    // MARK: Leftovers of deleted apps

    func findOrphans() {
        guard let finder else { orphanPhase = .scanning("Looking for leftovers…"); return }
        orphanPhase = .scanning("Looking for leftovers…")
        let running = self.running.bundleIDs
        let usesLS = environment.usesLaunchServices
        // Apps in the Trash keep their leftovers findable by name too (not just by id).
        let trashFolder = environment.trashDirectory ?? environment.home.appendingPathComponent(".Trash")
        Task {
            let groups = await Task.detached(priority: .userInitiated) {
                OrphanFinder(finder: finder, runningBundleIDs: running, trashedApps: AppCatalog.scan([trashFolder])) { id in
                    usesLS && SystemLookup.isAppInstalled(bundleID: id)
                }.find()
            }.value
            orphanGroups = groups
            cachedOrphanCount = groups.count
            orphanChecked.formIntersection(Set(groups.flatMap(\.items).filter { isRemovable($0) }.map(\.id)))
            orphanPhase = .done
            // Measured only once the section is open (the launch-time pass just counts groups).
            if section == .leftovers { requestOrphanSizes() }
        }
    }

    func requestOrphanSizes() {
        sizes.request(orphanGroups.flatMap(\.items).filter { hasFullDiskAccess || !$0.needsFullDiskAccess }.map(\.url))
    }

    // MARK: Junk

    func scanJunk() {
        junkTask?.cancel()
        junkPhase = .scanning("Looking for junk…")
        results[.junk] = nil
        let scanner = JunkScanner(environment: environment, runningBundleIDs: running.bundleIDs,
                                  appNames: Dictionary(apps.compactMap { app in app.bundleID.map { ($0, app.name) } },
                                                       uniquingKeysWith: { a, _ in a }))
        junkTask = Task {
            let items = await Task.detached(priority: .userInitiated) { scanner.scan() }.value
            guard !Task.isCancelled else { return }
            junkItems = items
            junkChecked = Set(items.filter(\.isRecommended).map(\.id))
            sizes.forget(items.map(\.url))
            sizes.request(items.map(\.url))
            junkPhase = .scanning("Measuring…")
            while !Task.isCancelled, items.contains(where: { sizes.isMeasuring($0.url) }) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            if !Task.isCancelled { junkPhase = .done }
        }
    }

    func stopJunk() {
        junkTask?.cancel()
        sizes.reset()
        junkPhase = .stopped
    }

    // MARK: Large & Old

    /// Without Full Disk Access, walking Desktop, Documents and Downloads makes macOS ask
    /// about each folder; Tidy asks first.
    var largeNeedsChoice: Bool {
        // Test mode asks too (the fixture isn't protected, but the flow should match a real Mac).
        !hasFullDiskAccess && largeRoot == environment.home && largeChoice == nil
    }

    func scanLarge() {
        largeTask?.cancel()
        results[.large] = nil
        let root = largeRoot
        var scanner = root == environment.home
            ? LargeFileScanner.forHome(environment, minimumSize: 10_000_000)
            : LargeFileScanner(root: root, minimumSize: 10_000_000,
                               excluded: [environment.library] + [environment.trashDirectory].compactMap { $0 })
        let skipProtected = !hasFullDiskAccess && root == environment.home
        if skipProtected {
            scanner.excluded += ["Desktop", "Documents", "Downloads"].map { environment.home.appendingPathComponent($0) }
        }
        largeSkippedProtected = skipProtected
        largePhase = .scanning("Looking for large files…")
        let useSpotlight = !environment.isTestMode
        let finalScanner = scanner
        largeTask = Task {
            let progress = ScanCounter()
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    let count = progress.value
                    if count > 0, case .scanning = largePhase {
                        largePhase = .scanning("Looked at \(count.formatted()) items…")
                    }
                }
            }
            let work = Task.detached(priority: .userInitiated) { () -> [LargeFile]? in
                guard var files = finalScanner.scan(progress: { progress.set($0) }) else { return nil }
                if useSpotlight {
                    for i in files.indices {
                        if Task.isCancelled { return nil }
                        files[i].lastOpened = SystemLookup.lastOpened(files[i].url)
                    }
                }
                return files
            }
            let files = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            poll.cancel()
            guard !Task.isCancelled else { return }
            if let files {
                largeFiles = files
                largeChecked.formIntersection(Set(files.map(\.id)))
                largePhase = .done
            } else {
                largePhase = .stopped
            }
        }
    }

    func stopLarge() {
        largeTask?.cancel()
        largeTask = nil
        largePhase = .stopped
    }

    var visibleLargeFiles: [LargeFile] {
        let filtered = largeFilter.apply(largeFiles, now: Date())
        guard !query.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func chooseLargeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = largeRoot
        panel.prompt = "Scan"
        panel.message = "Choose a folder in your home folder to look for large files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = environment.home.standardizedFileURL.resolvingSymlinksInPath().path
        guard path == home || path.hasPrefix(home + "/") else {
            failureReport = FailureReport(title: "Choose a folder in your home folder", failures: [
                TrashFailure(url: url, message: "Tidy looks for large files in \(environment.home.path) and the folders inside it."),
            ], offersReveal: false)
            return
        }
        section = .large
        largeRoot = url.standardizedFileURL
        largeChoice = .withoutProtectedFolders
        scanLarge()
    }

    func resetLargeRoot() {
        largeRoot = environment.home
        scanLarge()
    }

    // MARK: Section-independent actions

    var selectedURLs: [URL] {
        switch section {
        case .uninstall:
            return appSelection.isEmpty ? currentApp.map { [$0.url] } ?? [] : appSelection.map { URL(fileURLWithPath: $0) }
        case .leftovers: return orphanSelection.map { URL(fileURLWithPath: $0) }
        case .junk: return junkSelection.map { URL(fileURLWithPath: $0) }
        case .large: return largeSelection.map { URL(fileURLWithPath: $0) }
        }
    }

    func revealSelection() { Finder.reveal(selectedURLs) }

    func quickLookSelection() {
        if previewURL != nil { previewURL = nil; return }
        previewURL = selectedURLs.sorted { $0.path < $1.path }.first
    }

    func rescan() {
        switch section {
        case .uninstall:
            sizes.reset()
            loadApps()
        case .leftovers:
            sizes.reset()
            loadApps()
            findOrphans()
        case .junk: scanJunk()
        case .large: scanLarge()
        }
    }

    func sectionAppeared(_ section: SidebarSection) {
        switch section {
        case .uninstall: break
        case .leftovers: if orphanPhase == .idle { findOrphans() } else { requestOrphanSizes() }
        case .junk: if junkPhase == .idle { scanJunk() }
        case .large: if largePhase == .idle && !largeNeedsChoice { scanLarge() }
        }
    }
}

/// A counter shared between a scan and the UI polling it.
final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func set(_ value: Int) { lock.withLock { count = value } }
}

/// Remembered choices (UserDefaults keys).
enum Keys {
    /// Test mode keeps its choices apart, so trying Tidy on fixtures never changes the real
    /// app's preferences.
    static var defaults: UserDefaults {
        TidyEnvironment.current.isTestMode ? UserDefaults(suiteName: "app.slopapp.tidy.testmode") ?? .standard : .standard
    }

    static let appSort = "appSort"
    static let largeThreshold = "largeThreshold"
    static let largeAge = "largeOlderThan"
    static let largeKind = "largeKind"
    static let skipProtected = "largeSkipProtectedFolders"

    static func savedLargeFilter() -> LargeFileFilter {
        let defaults = Keys.defaults
        let age = defaults.object(forKey: largeAge) as? Double
        return LargeFileFilter(
            minimumSize: Int64(defaults.object(forKey: largeThreshold) as? Int ?? 50_000_000),
            olderThan: age.flatMap { $0 > 0 ? $0 : nil },
            kind: defaults.string(forKey: largeKind).flatMap(FileKind.init(rawValue:)))
    }

    static func save(_ filter: LargeFileFilter) {
        let defaults = Keys.defaults
        defaults.set(Int(filter.minimumSize), forKey: largeThreshold)
        defaults.set(filter.olderThan ?? 0, forKey: largeAge)
        defaults.set(filter.kind?.rawValue ?? "", forKey: largeKind)
    }
}

/// App bundle sizes remembered between launches, so the list shows sizes at once without
/// walking every app again. An entry is used only while the bundle and its Info.plist are
/// unchanged (updates change them).
@MainActor
final class AppSizeCache {
    private var entries: [String: [Double]]   // path → [stamp, bytes, files]
    private var saveScheduled = false
    private static let key = "appSizeCache"

    init() {
        entries = Keys.defaults.dictionary(forKey: Self.key) as? [String: [Double]] ?? [:]
    }

    static func stamp(_ path: String) -> Double {
        let fm = FileManager.default
        let dates = [path, path + "/Contents/Info.plist"].compactMap {
            (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
        }
        return dates.map(\.timeIntervalSince1970).reduce(0, +)
    }

    func apply(to apps: [InstalledApp], sizes: SizeStore) {
        for app in apps {
            guard let entry = entries[app.id], entry.count == 3, entry[0] == Self.stamp(app.id) else { continue }
            sizes.preset(app.id, DiskUsage(bytes: Int64(entry[1]), files: Int(entry[2])))
        }
    }

    func remember(_ path: String, _ usage: DiskUsage) {
        guard !usage.isPartial else { return }
        entries[path] = [Self.stamp(path), Double(usage.bytes), Double(usage.files)]
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            saveScheduled = false
            Keys.defaults.set(entries, forKey: Self.key)
        }
    }
}
