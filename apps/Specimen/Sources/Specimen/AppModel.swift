import AppKit
import CoreText
import Observation
import SlopKit
import SpecimenCore
import UniformTypeIdentifiers

enum Screen: Equatable {
    case grid
    case detail(family: String)
    case compare
}

/// How the library is shown (View ▸ as Grid ⌘1 / as List ⌘2).
enum ViewMode: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// The family page's tabs (⌘1–⌘5 while it's open).
enum DetailTab: String, CaseIterable, Identifiable {
    case styles, characters, text, variables, info
    var id: String { rawValue }
    var title: String {
        switch self {
        case .styles: "Styles"
        case .characters: "Characters"
        case .text: "Text"
        case .variables: "Variables"
        case .info: "Info"
        }
    }
}

/// A sheet over the library window.
enum LibrarySheet: Identifiable, Equatable {
    case tags
    case newTag
    case renameTag(String)
    case smartCollection(SmartCollection, isNew: Bool)
    case install(InstallReport)

    var id: String {
        switch self {
        case .tags: "tags"
        case .newTag: "newTag"
        case .renameTag(let name): "rename.\(name)"
        case .smartCollection(let collection, _): "smart.\(collection.id)"
        case .install: "install"
        }
    }
}

/// What "Add Fonts…" did, for its summary sheet.
struct InstallReport: Equatable {
    var added: [String]
    var problems: [(file: String, reason: String)]
    var folder: String

    static func == (a: InstallReport, b: InstallReport) -> Bool {
        a.added == b.added && a.folder == b.folder && a.problems.map(\.file) == b.problems.map(\.file)
    }
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
    @ObservationIgnored private let collectionsStore: CollectionsStore
    @ObservationIgnored private var coverageTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Saves a preference. Benchmarks change size and text a lot; they never save.
    private func persist(_ value: Any, _ key: String) {
        guard environment.benchmark == nil, !isSnapshotRun else { return }
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
    var sort = LibrarySort() {
        didSet { guard sort != oldValue else { return }; persist(sort.storageKey, "sort"); refreshItems() }
    }
    var viewMode: ViewMode = .grid {
        didSet { guard viewMode != oldValue else { return }; persist(viewMode.rawValue, "viewMode"); if screen != .grid { screen = .grid } }
    }
    /// Hide fonts that can't show every character of the preview text.
    var hideUncovered = false {
        didSet { guard hideUncovered != oldValue else { return }; persist(hideUncovered, "hideUncovered"); updateCoverage() }
    }
    /// Faces hidden by `hideUncovered` for the current text.
    private(set) var hiddenFaceIDs: Set<String> = []
    private(set) var isCheckingCoverage = false

    // Preview (persisted)
    var previewText = "" {
        didSet { guard previewText != oldValue else { return }; persist(previewText, "previewText"); if hideUncovered { updateCoverage() } }
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
    private(set) var tags = TagLibrary()
    private(set) var smartCollections: [SmartCollection] = []
    /// The compare tray: a shortlist that survives clicks and relaunches.
    private(set) var tray = CompareTray()

    // Selection and navigation
    var selection: Set<String> = []
    var screen: Screen = .grid
    /// The style picked in the detail view (for every tab).
    var detailFaceID: String?
    var detailTab: DetailTab = .styles {
        didSet { persist(detailTab.rawValue, "detailTab") }
    }
    var sheet: LibrarySheet?

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
        collectionsStore = CollectionsStore(directory: environment.dataDirectory)
        isSnapshotRun = ProcessInfo.processInfo.environment["SPECIMEN_SNAPSHOT_DIR"] != nil
        sidebar = defaults.string(forKey: "sidebar").flatMap(SidebarItem.init(storageKey:)) ?? .all
        showSystemFonts = defaults.object(forKey: "showSystemFonts") as? Bool ?? true
        groupByFamily = defaults.object(forKey: "groupByFamily") as? Bool ?? true
        previewText = defaults.string(forKey: "previewText") ?? ""
        previewSize = PreviewSize.clamp(defaults.object(forKey: "previewSize") as? Double ?? PreviewSize.standard)
        favorites = favoritesStore.load()
        categoryOverrides = overridesStore.load()
        let collections = collectionsStore.load()
        tags = collections.tagLibrary
        smartCollections = collections.smartCollections
        sort = defaults.string(forKey: "sort").flatMap(LibrarySort.init(storageKey:)) ?? LibrarySort()
        viewMode = defaults.string(forKey: "viewMode").flatMap(ViewMode.init(rawValue:)) ?? .grid
        hideUncovered = defaults.object(forKey: "hideUncovered") as? Bool ?? false
        detailTab = defaults.string(forKey: "detailTab").flatMap(DetailTab.init(rawValue:)) ?? .styles
        tray = CompareTray(faceIDs: defaults.stringArray(forKey: "compareTray") ?? [])
    }

    /// `SPECIMEN_SNAPSHOT_DIR` renders the windows offscreen and quits; it never saves preferences.
    @ObservationIgnored let isSnapshotRun: Bool

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
        isIndexing = false
        indexProgress = nil
        apply(faces: result.faces)
        if result.freshlyRead > 0 || result.cache.faces != cache.faces {
            Task.detached(priority: .utility) { try? result.cache.save(to: cacheURL) }
        }
    }

    private func apply(faces newFaces: [FontFace]) {
        faces = newFaces
        let shown = FontIndexer.stressCopies(newFaces, copies: environment.stressCopies)
        families = FontFamily.group(shown, overrides: categoryOverrides)
        familyIndex = Dictionary(families.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        faceIndex = Dictionary(families.flatMap(\.faces).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        hasLoaded = true
        refreshItems(counts: true)
        // Forget selections and screens whose fonts went away.
        if case .detail(let family) = screen, !families.contains(where: { $0.name == family }) { screen = .grid }
        // Keep tray entries for fonts that are only offline for a moment (indexing): prune
        // only against a complete index.
        if !isIndexing {
            var pruned = tray
            pruned.prune(existing: Set(families.flatMap(\.faces).map(\.id)))
            if pruned != tray { setTray(pruned) }
        }
        if screen == .compare, tray.isEmpty { screen = .grid }
        if hideUncovered { updateCoverage() }
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
                     groupByFamily: groupByFamily, favorites: favorites, tags: tags,
                     smartCollections: smartCollections, sort: sort,
                     hiddenFaceIDs: hideUncovered ? hiddenFaceIDs : [])
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
        case .compare: return trayFaces
        case .grid:
            // A selected family card acts on the whole family; an ungrouped card on its face.
            return selectedItems.flatMap { groupByFamily ? $0.family.faces : $0.faces }
        }
    }

    var actionFamilies: [String] {
        switch screen {
        case .detail(let name): return [name]
        case .compare: return Array(NSOrderedSet(array: trayFaces.map(\.familyName))) as? [String] ?? []
        case .grid: return Array(NSOrderedSet(array: selectedItems.map(\.family.name))) as? [String] ?? []
        }
    }

    func family(named name: String) -> FontFamily? { familyIndex[name] }
    func face(id: String) -> FontFace? { faceIndex[id] }
    @ObservationIgnored private var familyIndex: [String: FontFamily] = [:]
    @ObservationIgnored private var faceIndex: [String: FontFace] = [:]

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

    /// Opens a family's page from compare (or anywhere a face is known).
    func openDetail(face: FontFace) {
        detailFaceID = face.id
        screen = .detail(family: face.familyName)
    }

    /// ⌘K: add the selection to the tray (if any) and show the tray side by side.
    func openCompare() {
        if screen == .grid, !selectedItems.isEmpty {
            var updated = tray
            for item in selectedItems where !updated.containsAny(cardFaceIDs(item)) { updated.add(item.representative.id) }
            if updated != tray { setTray(updated, actionName: "Add to Compare") }
        }
        guard !tray.isEmpty else { return }
        screen = .compare
    }

    var canCompare: Bool { !tray.isEmpty || (screen == .grid && !selection.isEmpty) }

    /// The toolbar's tray button: show the tray, or go back if it's showing.
    func toggleTrayScreen() {
        if screen == .compare { goBack() } else if !tray.isEmpty { screen = .compare }
    }

    func goBack() {
        screen = .grid
        focusGridRequest += 1
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    // MARK: Compare tray

    var trayFaces: [FontFace] { tray.faceIDs.compactMap(face(id:)) }

    /// The faces a card stands for in the tray: the whole family (grouped) or its one face.
    func cardFaceIDs(_ item: GridEntry) -> [String] {
        (groupByFamily ? item.family.faces : item.faces).map(\.id)
    }

    func isInTray(_ item: GridEntry) -> Bool { tray.containsAny(cardFaceIDs(item)) }

    func toggleTray(_ item: GridEntry) {
        var updated = tray
        updated.toggle(cardFaceIDs: cardFaceIDs(item), representative: item.representative.id)
        setTray(updated, actionName: updated.count > tray.count ? "Add to Compare" : "Remove from Compare")
    }

    /// Return in the grid or list: collect the selection (or take it out if it's all in).
    func toggleTraySelection() {
        let cards = selectedItems.map { (faceIDs: cardFaceIDs($0), representative: $0.representative.id) }
        guard !cards.isEmpty else { return }
        var updated = tray
        updated.toggle(cards: cards)
        setTray(updated, actionName: updated.count >= tray.count ? "Add to Compare" : "Remove from Compare")
    }

    var selectionIsInTray: Bool { !selectedItems.isEmpty && selectedItems.allSatisfy(isInTray) }

    func removeFromTray(_ ids: [String]) {
        var updated = tray
        updated.remove(ids)
        setTray(updated, actionName: "Remove from Compare")
    }

    func replaceInTray(_ old: String, with new: String) {
        var updated = tray
        updated.replace(old, with: new)
        setTray(updated, actionName: "Change Style")
    }

    func moveInTray(from source: IndexSet, to destination: Int) {
        var updated = tray
        updated.move(from: source, to: destination)
        setTray(updated, actionName: "Move")
    }

    func clearTray() {
        guard !tray.isEmpty else { return }
        setTray(CompareTray(), actionName: "Clear Compare")
    }

    func setTray(_ value: CompareTray, actionName: String? = nil) {
        let previous = tray
        guard value != previous else { return }
        tray = value
        persist(value.faceIDs, "compareTray")
        if screen == .compare, value.isEmpty { goBack() }
        if let actionName {
            undoManager?.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.setTray(previous, actionName: actionName) }
            }
            undoManager?.setActionName(actionName)
        }
    }

    // MARK: Tags and smart collections

    /// The sidebar title for an item (smart collections have names).
    func title(for item: SidebarItem) -> String {
        if case .smart(let id) = item { return smartCollections.first { $0.id == id }?.name ?? item.title }
        return item.title
    }

    func toggleTag(_ name: String, families names: [String]) {
        guard !names.isEmpty else { return }
        var updated = tags
        if tags.membership(name, families: names) == .all {
            updated.detach(name, from: names)
            updateCollections(tags: updated, actionName: "Remove Tag")
        } else {
            updated.attach(name, to: names)
            updateCollections(tags: updated, actionName: "Add Tag")
        }
    }

    func attachTag(_ name: String, families names: [String]) {
        var updated = tags
        updated.attach(name, to: names)
        updateCollections(tags: updated, actionName: "Add Tag")
    }

    /// New tag, attached to `families` (the selection) if any. Returns the tag's name.
    @discardableResult
    func createTag(_ name: String, families names: [String] = []) -> String? {
        var updated = tags
        guard let tag = updated.create(name) else { return nil }
        if !names.isEmpty { updated.attach(tag, to: names) }
        updateCollections(tags: updated, actionName: "New Tag")
        return tag
    }

    func renameTag(_ old: String, to new: String) -> Bool {
        var updated = tags
        guard updated.rename(old, to: new) else { return false }
        let newName = TagLibrary.normalize(new)
        let smart = smartCollections.map { collection -> SmartCollection in
            var collection = collection
            if collection.rules.tag == old { collection.rules.tag = newName }
            return collection
        }
        updateCollections(tags: updated, smart: smart, actionName: "Rename Tag")
        if sidebar == .tag(old) { sidebar = .tag(newName) }
        return true
    }

    func deleteTag(_ name: String) {
        var updated = tags
        updated.delete(name)
        let smart = smartCollections.map { collection -> SmartCollection in
            var collection = collection
            if collection.rules.tag == name { collection.rules.tag = nil }
            return collection
        }
        if sidebar == .tag(name) { sidebar = .all }
        updateCollections(tags: updated, smart: smart, actionName: "Delete Tag")
    }

    func saveSmartCollection(_ collection: SmartCollection) {
        var updated = smartCollections
        if let index = updated.firstIndex(where: { $0.id == collection.id }) {
            updated[index] = collection
        } else {
            updated.append(collection)
        }
        updateCollections(smart: updated, actionName: "Smart Collection")
        sidebar = .smart(collection.id)
        refreshItems(counts: true)
    }

    func deleteSmartCollection(_ id: UUID) {
        if sidebar == .smart(id) { sidebar = .all }
        updateCollections(smart: smartCollections.filter { $0.id != id }, actionName: "Delete Smart Collection")
    }

    /// A smart collection from the current sidebar item and search (File ▸ New Smart Collection).
    func newSmartCollection() {
        let base = sidebar == .all && search.isEmpty ? "New Smart Collection" : (search.isEmpty ? title(for: sidebar) : "“\(search)”")
        var name = base
        var number = 2
        while smartCollections.contains(where: { $0.name == name }) { name = "\(base) \(number)"; number += 1 }
        sheet = .smartCollection(SmartCollection(name: name, rules: SmartRules(sidebar: sidebar, search: search)), isNew: true)
    }

    /// How many families a set of rules matches (live count in the editor).
    func matchCount(_ rules: SmartRules) -> Int {
        let probe = SmartCollection(name: "", rules: rules)
        var query = query
        query.sidebar = .smart(probe.id)
        query.search = ""
        query.hiddenFaceIDs = []
        query.groupByFamily = true
        query.smartCollections = [probe]
        return LibraryFilter.items(in: families, query: query).count
    }

    private func updateCollections(tags newTags: TagLibrary? = nil, smart newSmart: [SmartCollection]? = nil, actionName: String) {
        let previousTags = tags, previousSmart = smartCollections
        if let newTags { tags = newTags }
        if let newSmart { smartCollections = newSmart }
        guard tags != previousTags || smartCollections != previousSmart else { return }
        do {
            try collectionsStore.save(CollectionsStore.Contents(tags: tags, smartCollections: smartCollections))
        } catch {
            notice = Notice(title: "Couldn't save tags", message: "\(error.localizedDescription) Check that \(environment.dataDirectory.path) is writable.")
        }
        if case .tag(let name) = sidebar, tags.tags[name] == nil { sidebar = .all }
        if case .smart(let id) = sidebar, !smartCollections.contains(where: { $0.id == id }) { sidebar = .all }
        refreshItems(counts: true)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.updateCollections(tags: previousTags, smart: previousSmart, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
    }

    // MARK: Coverage

    /// Recomputes which faces can't show the preview text, in the background.
    func updateCoverage() {
        coverageTask?.cancel()
        guard hideUncovered, let text = PreviewText.coverageText(previewText) else {
            isCheckingCoverage = false
            if !hiddenFaceIDs.isEmpty { hiddenFaceIDs = [] }
            refreshItems()
            return
        }
        let targets = faces.map { (id: $0.id, postScriptName: $0.postScriptName, path: $0.path, isEnabled: $0.isEnabled) }
        let copies = environment.stressCopies
        isCheckingCoverage = true
        coverageTask = Task {
            // Debounce typing.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let hidden = await Task.detached(priority: .userInitiated) { () -> Set<String>? in
                var hidden = Set<String>()
                for target in targets {
                    if Task.isCancelled { return nil }
                    let covered = autoreleasepool { () -> Bool in
                        guard let font = FontLoader.makeFont(postScriptName: target.postScriptName, path: target.path,
                                                             isEnabled: target.isEnabled, size: 12) else { return false }
                        return PreviewText.covers(text) { units in
                            var glyphs = [CGGlyph](repeating: 0, count: units.count)
                            return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
                        }
                    }
                    if !covered {
                        hidden.insert(target.id)
                        for copy in stride(from: 2, through: copies, by: 1) { hidden.insert("\(target.id)#\(copy)") }
                    }
                }
                return hidden
            }.value
            guard let hidden, !Task.isCancelled else { return }
            isCheckingCoverage = false
            hiddenFaceIDs = hidden
            refreshItems()
        }
    }

    // MARK: Adding fonts

    /// Where "Add Fonts…" copies files: `~/Library/Fonts`, or (test mode) a folder inside the
    /// test folder, so tests never install anything for real.
    var installFolder: URL {
        if let override = ProcessInfo.processInfo.environment["SPECIMEN_INSTALL_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let test = environment.testFontsDirectory { return test.appendingPathComponent("Added", isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts", isDirectory: true)
    }

    func chooseFontsToAdd() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.font]
        panel.prompt = "Add"
        panel.message = "Choose font files or folders to add to \(installFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))."
        guard panel.runModal() == .OK else { return }
        addFonts(panel.urls)
    }

    /// Copies fonts into the install folder (skipping exact copies and name clashes), then
    /// selects them. In test mode the copies are registered for the session only.
    func addFonts(_ urls: [URL]) {
        let fileManager = FileManager.default
        let files = InstallPlan.fontFiles(in: urls, isDirectory: { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }, contents: { (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] })
        let folder = installFolder
        guard !files.isEmpty else {
            notice = Notice(title: "No fonts to add", message: "Choose .otf, .ttf, .ttc, .otc or .dfont files, or folders that contain them.")
            return
        }
        let plan = InstallPlan.make(
            files: files, into: folder, installed: Set(faces.filter(\.isEnabled).map(\.postScriptName)),
            names: { url in
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
                let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
                return names.isEmpty ? nil : names
            },
            exists: { fileManager.fileExists(atPath: $0.path) },
            sameFile: { fileManager.contentsEqual(atPath: $0.path, andPath: $1.path) }
        )
        var added: [String] = []
        var copied: [URL] = []
        var problems: [(file: String, reason: String)] = []
        for item in plan.items {
            let name = item.source.lastPathComponent
            switch item.outcome {
            case .copy(let destination):
                do {
                    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: item.source, to: destination)
                    copied.append(destination)
                    added.append(contentsOf: item.postScriptNames)
                } catch {
                    problems.append((name, error.localizedDescription))
                }
            case .alreadyInstalled: problems.append((name, "Already added."))
            case .nameInUse(let postScriptName): problems.append((name, "A font named \(postScriptName) is already installed."))
            case .unreadable: problems.append((name, "Not a font macOS can read. It may be damaged."))
            }
        }
        if environment.isTestMode, !copied.isEmpty {
            testFontURLs.append(contentsOf: copied)
            TestFonts.register(copied)
        }
        let addedNames = Set(added)
        Task {
            // The registry notices new files on its own; re-list now and select them.
            try? await Task.sleep(for: .milliseconds(600))
            await refreshFromSystem()
            if !addedNames.isEmpty {
                sidebar = .all
                search = ""
                let ids = items.filter { $0.faces.contains { addedNames.contains($0.postScriptName) } }.map(\.id)
                selection = Set(ids)
                focusGridRequest += 1
            }
        }
        if !problems.isEmpty || added.isEmpty {
            sheet = .install(InstallReport(added: added, problems: problems, folder: folder.path))
        }
    }

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

