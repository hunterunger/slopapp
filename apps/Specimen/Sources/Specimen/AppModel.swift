import AppKit
import CoreText
import Observation
import SlopKit
import SpecimenCore

enum Screen: Equatable {
    case grid
    case detail(family: String)
    case compare
}

/// A refusal or failure, shown as an alert.
struct Notice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// A choice the user must make before fonts change.
enum PendingActivation: Identifiable {
    case swap(ActivationPlan)
    case bulk(ActivationPlan)

    var id: String {
        switch self {
        case .swap: "swap"
        case .bulk: "bulk"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let environment: SpecimenEnvironment
    @ObservationIgnored let system: any FontSystem = CoreTextFontSystem()
    @ObservationIgnored private let favoritesStore: FavoritesStore
    @ObservationIgnored private let overridesStore: CategoryOverridesStore
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Saves a preference. Benchmarks change size and text a lot; they never save.
    private func persist(_ value: Any, _ key: String) {
        guard environment.benchmark == nil else { return }
        defaults.set(value, forKey: key)
    }
    /// SwiftUI's environment undo manager isn't the one Edit ▸ Undo uses; the window's is.
    @ObservationIgnored weak var fallbackUndoManager: UndoManager?
    var undoManager: UndoManager? {
        (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain })?.undoManager ?? fallbackUndoManager
    }
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var fontObserver: NSObjectProtocol?
    @ObservationIgnored private var testFontURLs: [URL] = []

    // Library
    private(set) var faces: [FontFace] = []
    private(set) var families: [FontFamily] = []
    private(set) var items: [GridEntry] = []
    /// Bumped whenever `items` changes, so the grid knows to reload.
    private(set) var itemsVersion = 0
    private(set) var counts: [SidebarItem: Int] = [:]
    private(set) var hasLoaded = false
    private(set) var isIndexing = false
    private(set) var indexProgress: Double?
    private(set) var isChangingFonts = false

    // Filters (persisted)
    var sidebar: SidebarItem = .all {
        didSet { guard sidebar != oldValue else { return }; persist(sidebar.storageKey, "sidebar"); refreshItems() }
    }
    var search = "" {
        didSet { guard search != oldValue else { return }; refreshItems() }
    }
    var showSystemFonts = true {
        didSet { guard showSystemFonts != oldValue else { return }; persist(showSystemFonts, "showSystemFonts"); refreshItems(counts: true) }
    }
    var groupByFamily = true {
        didSet { guard groupByFamily != oldValue else { return }; persist(groupByFamily, "groupByFamily"); refreshItems() }
    }

    // Preview (persisted)
    var previewText = "" {
        didSet { persist(previewText, "previewText") }
    }
    var previewSize: Double = PreviewSize.standard {
        didSet {
            let clamped = PreviewSize.clamp(previewSize.rounded())
            if clamped != previewSize { previewSize = clamped; return }
            persist(previewSize, "previewSize")
        }
    }

    // User data
    private(set) var favorites: Set<String> = []
    private(set) var categoryOverrides: [String: FontCategory] = [:]

    // Selection and navigation
    var selection: Set<String> = []
    var screen: Screen = .grid
    /// Faces in the compare view, in order.
    var compareFaceIDs: [String] = []
    /// The style picked in the detail view (for info and waterfall).
    var detailFaceID: String?

    // Prompts
    var notice: Notice?
    var pending: PendingActivation?
    /// Incremented to ask the toolbar's preview field to take focus (⌘L).
    var focusPreviewRequest = 0
    /// Incremented to ask the grid to take keyboard focus.
    var focusGridRequest = 0

    init(environment: SpecimenEnvironment = SpecimenEnvironment(
        environment: ProcessInfo.processInfo.environment,
        defaultDataDirectory: { (try? AppPaths.applicationSupport) ?? FileManager.default.temporaryDirectory.appendingPathComponent("Specimen") }
    )) {
        self.environment = environment
        favoritesStore = FavoritesStore(directory: environment.dataDirectory)
        overridesStore = CategoryOverridesStore(directory: environment.dataDirectory)
        sidebar = defaults.string(forKey: "sidebar").flatMap(SidebarItem.init(storageKey:)) ?? .all
        showSystemFonts = defaults.object(forKey: "showSystemFonts") as? Bool ?? true
        groupByFamily = defaults.object(forKey: "groupByFamily") as? Bool ?? true
        previewText = defaults.string(forKey: "previewText") ?? ""
        previewSize = PreviewSize.clamp(defaults.object(forKey: "previewSize") as? Double ?? PreviewSize.standard)
        favorites = favoritesStore.load()
        categoryOverrides = overridesStore.load()
    }

    // MARK: Loading

    func start() {
        let cacheURL = environment.indexCacheURL
        let testDirectory = environment.testFontsDirectory
        isIndexing = true
        indexTask = Task {
            // Test mode: register the test fonts for this session before listing.
            if let testDirectory {
                testFontURLs = TestFonts.fontFiles(in: testDirectory)
                let urls = testFontURLs
                let errors = await Task.detached { TestFonts.register(urls) }.value
                if !errors.isEmpty { NSLog("Specimen test fonts: %@", errors.joined(separator: "; ")) }
            }
            let cache = await Task.detached(priority: .userInitiated) { IndexCache.load(from: cacheURL) }.value
            if !cache.faces.isEmpty, faces.isEmpty {
                apply(faces: cache.faces)
            }
            await rebuildIndex(cache: cache)
        }
        fontObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    /// Test mode: turn the test fonts back on and unregister them, so nothing is left behind.
    func cleanUpTestFonts() {
        guard !testFontURLs.isEmpty else { return }
        TestFonts.cleanUp(testFontURLs)
        testFontURLs = []
    }

    private func rebuildIndex(cache: IndexCache) async {
        isIndexing = true
        let system = system
        let cacheURL = environment.indexCacheURL
        let result = await Task.detached(priority: .userInitiated) { [weak self] in
            FontIndexer(system: system).build(cache: cache) { done, total in
                Task { @MainActor in self?.indexProgress = Double(done) / Double(max(total, 1)) }
            }
        }.value
        guard !Task.isCancelled else { return }
        apply(faces: result.faces)
        isIndexing = false
        indexProgress = nil
        if result.freshlyRead > 0 || result.cache.faces != cache.faces {
            Task.detached(priority: .utility) { try? result.cache.save(to: cacheURL) }
        }
    }

    private func apply(faces newFaces: [FontFace]) {
        faces = newFaces
        let shown = FontIndexer.stressCopies(newFaces, copies: environment.stressCopies)
        families = FontFamily.group(shown, overrides: categoryOverrides)
        hasLoaded = true
        refreshItems(counts: true)
        // Forget selections and screens whose fonts went away.
        if case .detail(let family) = screen, !families.contains(where: { $0.name == family }) { screen = .grid }
        let faceIDs = Set(newFaces.map(\.id))
        compareFaceIDs.removeAll { !faceIDs.contains($0) }
        if screen == .compare, compareFaceIDs.isEmpty { screen = .grid }
    }

    /// Font Book (or anything else) changed the registry: debounce, then update.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshFromSystem()
        }
    }

    func refreshFromSystem() async {
        let system = system
        let listed = await Task.detached(priority: .userInitiated) { system.listFaces() }.value
        if let updated = FontIndexer.applyStates(listed, to: faces) {
            if updated != faces { apply(faces: updated) }
        } else {
            await rebuildIndex(cache: IndexCache.load(from: environment.indexCacheURL))
        }
    }

    // MARK: Filtering

    var query: LibraryQuery {
        LibraryQuery(sidebar: sidebar, search: search, showSystemFonts: showSystemFonts,
                     groupByFamily: groupByFamily, favorites: favorites)
    }

    private func refreshItems(counts recount: Bool = false) {
        items = LibraryFilter.items(in: families, query: query)
        itemsVersion += 1
        let visible = Set(items.map(\.id))
        if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
        if recount { counts = LibraryFilter.counts(in: families, query: query) }
    }

    var selectedItems: [GridEntry] { items.filter { selection.contains($0.id) } }

    /// The faces an action applies to: the detail's family, or the grid selection.
    var actionFaces: [FontFace] {
        switch screen {
        case .detail(let name): return families.first { $0.name == name }?.faces ?? []
        case .compare: return compareFaceIDs.compactMap { id in faces.first { $0.id == id } }
        case .grid:
            // A selected family card acts on the whole family; an ungrouped card on its face.
            return selectedItems.flatMap { groupByFamily ? $0.family.faces : $0.faces }
        }
    }

    var actionFamilies: [String] {
        switch screen {
        case .detail(let name): return [name]
        case .compare: return Array(NSOrderedSet(array: compareFaceIDs.compactMap { id in faces.first { $0.id == id }?.familyName })) as? [String] ?? []
        case .grid: return Array(NSOrderedSet(array: selectedItems.map(\.family.name))) as? [String] ?? []
        }
    }

    func family(named name: String) -> FontFamily? { families.first { $0.name == name } }
    func face(id: String) -> FontFace? { faces.first { $0.id == id } }

    func lockReason(for face: FontFace) -> LockReason? {
        ActivationPlanner.lockReason(for: face, testRoot: environment.testFontsDirectory,
                                     fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// One lock that applies to every face of a family, if any.
    func lockReason(for family: FontFamily) -> LockReason? {
        let reasons = family.faces.map(lockReason(for:))
        guard let first = reasons.first, let reason = first, reasons.allSatisfy({ $0 == reason }) else { return nil }
        return reason
    }

    // MARK: Navigation

    func openDetail(_ item: GridEntry? = nil) {
        guard let item = item ?? selectedItems.first else { return }
        detailFaceID = item.representative.id
        screen = .detail(family: item.family.name)
    }

    func openCompare() {
        let chosen = selectedItems.prefix(8).map(\.representative.id)
        guard chosen.count >= 2 else { return }
        compareFaceIDs = chosen
        screen = .compare
    }

    var canCompare: Bool { screen == .grid && selection.count >= 2 }
    var compareIsCapped: Bool { selection.count > 8 }

    func goBack() {
        screen = .grid
        focusGridRequest += 1
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    // MARK: Preview

    func biggerPreview() { previewSize = PreviewSize.bigger(previewSize) }
    func smallerPreview() { previewSize = PreviewSize.smaller(previewSize) }
    func actualSizePreview() { previewSize = PreviewSize.standard }

    // MARK: Favorites

    var allActionFamiliesAreFavorites: Bool {
        let names = actionFamilies
        return !names.isEmpty && names.allSatisfy(favorites.contains)
    }

    func toggleFavorite() {
        let names = actionFamilies
        guard !names.isEmpty else { return }
        setFavorite(!allActionFamiliesAreFavorites, families: names)
    }

    func setFavorite(_ on: Bool, families names: [String]) {
        let before = favorites
        var after = favorites
        if on { after.formUnion(names) } else { after.subtract(names) }
        guard after != before else { return }
        updateFavorites(after, undoTo: before, actionName: on ? "Add to Favorites" : "Remove from Favorites")
    }

    private func updateFavorites(_ value: Set<String>, undoTo previous: Set<String>, actionName: String) {
        favorites = value
        do {
            try favoritesStore.save(value)
        } catch {
            notice = Notice(title: "Couldn't save favorites", message: "\(error.localizedDescription) Check that \(environment.dataDirectory.path) is writable.")
        }
        refreshItems(counts: true)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.updateFavorites(previous, undoTo: value, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
    }

    // MARK: Categories

    func setCategory(_ category: FontCategory?, families names: [String]) {
        let before = categoryOverrides
        var after = categoryOverrides
        for name in names { after[name] = category }
        guard after != before else { return }
        updateOverrides(after, undoTo: before)
    }

    func category(ofFamily name: String) -> FontCategory? { family(named: name)?.category }
    func hasCategoryOverride(_ name: String) -> Bool { categoryOverrides[name] != nil }

    private func updateOverrides(_ value: [String: FontCategory], undoTo previous: [String: FontCategory]) {
        categoryOverrides = value
        try? overridesStore.save(value)
        apply(faces: faces)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.updateOverrides(previous, undoTo: value) }
        }
        undoManager?.setActionName("Change Category")
    }

    // MARK: Activation

    func activate(_ enable: Bool) { request(enable, faces: actionFaces) }

    func request(_ enable: Bool, faces targets: [FontFace]) {
        guard environment.stressCopies == 1 else {
            notice = Notice(title: "Fonts can't change in stress mode", message: "Quit and open Specimen without SPECIMEN_STRESS to turn fonts on or off.")
            return
        }
        let plan = ActivationPlanner.plan(targets: targets, enable: enable, library: faces,
                                          testRoot: environment.testFontsDirectory)
        if plan.isEmpty {
            if !plan.lockReasons.isEmpty {
                let what = enable ? "turned on" : "turned off"
                notice = Notice(title: plan.locked.count == 1 ? "This font can't be \(what)" : "These fonts can't be \(what)",
                                message: plan.lockReasons.map(\.explanation).joined(separator: " "))
            }
            return
        }
        if !plan.conflicts.isEmpty {
            pending = .swap(plan)
        } else if plan.needsConfirmation {
            pending = .bulk(plan)
        } else {
            perform(on: enable ? plan.changes : [], off: enable ? [] : plan.changes, actionName: enable ? "Activate" : "Deactivate")
        }
    }

    /// Carries out a confirmed plan. `swap`: turn off the clashing copies too.
    func confirm(_ plan: ActivationPlan, swap: Bool) {
        pending = nil
        let on = plan.enable ? plan.changes + (swap ? plan.swapOns : []) : []
        let off = plan.enable ? (swap ? plan.swapOffs : []) : plan.changes
        guard !on.isEmpty || !off.isEmpty else { return }
        perform(on: on, off: off, actionName: plan.enable ? "Activate" : "Deactivate")
    }

    /// Turns faces on and off off the main actor, verifies, and registers one undo step.
    /// The undo step is registered right away (not after the async work) so that, during an
    /// undo, it becomes the redo step.
    func perform(on: [FontFace], off: [FontFace], actionName: String) {
        let system = system
        isChangingFonts = true
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    let current = { (f: FontFace) in model.face(id: f.id) ?? f }
                    model.perform(on: off.map(current), off: on.map(current), actionName: actionName)
                }
            }
            undoManager.setActionName(actionName)
        }
        Task {
            await Task.detached(priority: .userInitiated) {
                if !off.isEmpty { system.setEnabled(off, enabled: false) }
                if !on.isEmpty { system.setEnabled(on, enabled: true) }
            }.value
            refreshTask?.cancel()
            await refreshFromSystem()
            isChangingFonts = false
            let failed = ActivationPlanner.failures(requested: on, enable: true, after: faces)
                + ActivationPlanner.failures(requested: off, enable: false, after: faces)
            if !failed.isEmpty {
                let names = failed.prefix(5).map(\.fullName).joined(separator: ", ") + (failed.count > 5 ? ", and \(failed.count - 5) more" : "")
                notice = Notice(title: failed.count == 1 ? "A font didn't change" : "\(failed.count) fonts didn't change",
                                message: "macOS didn't change \(names). Try again, or use Font Book.")
            }
        }
    }

    /// Whether Activate / Deactivate make sense for the current target.
    var canActivate: Bool { actionFaces.contains { !$0.isEnabled } }
    var canDeactivate: Bool { actionFaces.contains { $0.isEnabled } }

    // MARK: Copy and reveal

    func copyNames(postScript: Bool) {
        let names: [String]
        if postScript {
            switch screen {
            case .detail: names = detailFaceID.flatMap(face(id:)).map { [$0.postScriptName] } ?? []
            default: names = actionFaces.isEmpty ? [] : (screen == .grid ? selectedItems.map(\.representative.postScriptName) : actionFaces.map(\.postScriptName))
            }
        } else {
            names = actionFamilies
        }
        guard !names.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
    }

    var revealableURLs: [URL] {
        let targets: [FontFace]
        if case .detail = screen, let face = detailFaceID.flatMap(face(id:)) { targets = [face] } else { targets = actionFaces }
        let paths = targets.compactMap(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        return Array(Set(paths)).sorted().map { URL(fileURLWithPath: $0) }
    }

    func revealInFinder() {
        let urls = revealableURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

