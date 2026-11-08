import AppKit
import SlopKit
import TidyCore

/// What the map shows: the home folder, any folder, or a whole disk.
enum MapScope: Hashable {
    case home
    case folder(URL)
    case volume(MapVolume)

    var isDisk: Bool { if case .volume = self { true } else { false } }
}

enum MapStatus: Equatable {
    case idle, scanning, stopped, finished
    case failed(String)
    /// The disk went away; the map stays, read-only.
    case disconnected
}

/// Where in the map you are: a folder, or the smaller items of a folder.
enum MapPlace: Hashable {
    case folder(String)
    case smaller(String)

    var folderID: String {
        switch self {
        case .folder(let id), .smaller(let id): id
        }
    }
}

/// Asks before the map moves anything to the Trash (it can be big and personal).
struct SpaceMovePlan: Identifiable {
    let id = UUID()
    var items: [CheckedItem]
    var otherVolume: Bool

    var urls: [URL] { items.map { URL(fileURLWithPath: $0.path) } }
    var bytes: Int64 { items.reduce(0) { $0 + $1.freeable } }

    var title: String {
        items.count == 1 ? "Move “\(items[0].name)” to the Trash?" : "Move \(items.count) items to the Trash?"
    }

    var message: String {
        let names = items.prefix(5).map(\.name).joined(separator: ", ") + (items.count > 5 ? ", and \(items.count - 5) more" : "")
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        let shared = items.filter(\.mayFreeNothing).count
        var text = items.count == 1 ? "" : names + ".\n\n"
        text += "\(count), up to \(ByteFormat.string(bytes)), will be moved to the Trash. "
        text += otherVolume ? "The space comes back when you empty the Trash while the disk is connected. "
            : "The space comes back when you empty the Trash. "
        if shared > 0 {
            text += shared == 1 ? "One of them is a hard link or clone, so moving it may free nothing. "
                : "\(shared) of them are hard links or clones, so moving them may free nothing. "
        }
        return text + "You can put them back (⌘Z)."
    }
}

@MainActor
@Observable
final class SpaceState {
    var scope: MapScope = .home
    private(set) var volumes: [MapVolume] = []
    private(set) var recents: [URL] = []
    private(set) var status: MapStatus = .idle
    /// What the current map shows (the scope it was scanned with).
    private(set) var mapped: MapScope?
    private(set) var paths: MapPaths?
    private(set) var volume: MapVolume?
    private(set) var figures: VolumeFigures?
    private(set) var progressItems = 0
    private(set) var progressBytes: Int64 = 0
    /// Protected folders were left out (no Full Disk Access).
    private(set) var skippedProtected = false
    private(set) var place: MapPlace = .folder("")
    private(set) var backStack: [MapPlace] = []
    private(set) var forwardStack: [MapPlace] = []
    private(set) var snapshot: MapFolderSnapshot?
    /// The open "smaller items" folder's files (nil while it's being read).
    private(set) var smallItems: [SmallItem]?
    var selection: Set<String> = []
    var hovered: String?
    private(set) var tray = CheckTray()
    /// Why the last check didn't happen, shown in the bottom bar.
    var note: String?
    var showingTray = false
    var inspected: MapItem?
    var inspectedFacts: ItemFacts?
    /// Bumped to re-run the drill animation.
    private(set) var placeChanges = 0

    @ObservationIgnored private(set) var store: MapStore?
    @ObservationIgnored private var scanner: MapScanner<BulkDirectoryReader>?
    /// A Rescan This Folder or Show Package Contents walk in progress.
    @ObservationIgnored private var rescanner: MapScanner<BulkDirectoryReader>?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var scanToken = 0
    @ObservationIgnored private var scanStart = Date()
    @ObservationIgnored private var loggedFirstMap = false
    @ObservationIgnored private var movedSmall: [String: (folder: UInt32, size: Int64)] = [:]
    @ObservationIgnored private(set) var safety: MapSafety?
    @ObservationIgnored private(set) var trash: TrashService?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var environment: TidyEnvironment?

    static let recentsKey = "mapRecents"

    init() {
        recents = (Keys.defaults.stringArray(forKey: Self.recentsKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.volumesChanged() }
            })
        }
    }

    // MARK: Scope

    func loadVolumes(_ environment: TidyEnvironment) {
        self.environment = environment
        let source = environment.volumeSource
        Task {
            let list = await Task.detached(priority: .userInitiated) { source.volumes() }.value
            volumes = list
            if case .volume(let chosen) = scope, let fresh = list.first(where: { $0.id == chosen.id }) { scope = .volume(fresh) }
        }
    }

    private func volumesChanged() {
        guard let environment else { return }
        loadVolumes(environment)
        if let volume, status != .idle, !FileManager.default.fileExists(atPath: volume.root.path) {
            scanner?.cancel()
            status = .disconnected
        }
    }

    var startupVolume: MapVolume? { volumes.first { $0.kind == .startup } }
    var otherVolumes: [MapVolume] { volumes.filter { $0.kind != .startup } }

    func scopeTitle(_ home: URL) -> String {
        switch scope {
        case .home: "Home Folder"
        case .folder(let url): url.lastPathComponent
        case .volume(let volume): volume.name
        }
    }

    func remember(_ url: URL) {
        var list = recents.filter { $0.path != url.path }
        list.insert(url, at: 0)
        recents = Array(list.prefix(5))
        Keys.defaults.set(recents.map(\.path), forKey: Self.recentsKey)
    }

    func clearRecents() {
        recents = []
        Keys.defaults.removeObject(forKey: Self.recentsKey)
    }

    // MARK: Scanning

    var isScanning: Bool { status == .scanning }
    var hasMap: Bool { store != nil }

    func scan(environment: TidyEnvironment, hasFullDiskAccess: Bool) {
        self.environment = environment
        stopTimers()
        scanner?.cancel()
        let scope = self.scope
        let sameScope = mapped == scope
        let fm = FileManager.default
        var excluded: Set<String> = []
        var skipped: Set<String> = []
        var allowedVolumes: [URL] = []
        var scopeKind: MapScopeKind = .home
        let walkRoot: URL
        var firmlinks: Firmlinks?
        let protected = hasFullDiskAccess ? [] : SpaceScanner.protectedFolders(in: environment.home)
        var skippedProtected = false
        switch scope {
        case .home:
            walkRoot = environment.home
            excluded = Set(protected.map(\.path))
            skippedProtected = !protected.isEmpty
        case .folder(let url):
            walkRoot = url
            scopeKind = .folder
            let inside = protected.filter { $0.path.hasPrefix(url.path + "/") || $0.path == url.path }
            excluded = Set(inside.map(\.path))
            skippedProtected = !inside.isEmpty
        case .volume(let volume):
            walkRoot = volume.walkRoot
            if volume.kind == .startup {
                scopeKind = .startupDisk
                if walkRoot.path == "/System/Volumes/Data" { firmlinks = Firmlinks.system }
                let mapper = MapPaths(walkRoot: walkRoot.path, firmlinks: firmlinks)
                // Protected folders, as walk paths on the Data volume.
                excluded = Set(protected.compactMap { mapper.id(for: $0.path).map(mapper.walkPath) })
                skippedProtected = !excluded.isEmpty
                // Other disks' stand-ins inside the startup stand-in are mount points.
                skipped = Set(volumes.filter { $0.kind != .startup }.map(\.root.path))
            } else {
                scopeKind = .volume(isReadOnly: volume.isReadOnly)
                allowedVolumes = [volume.root]
            }
        }
        if let trashFolder = environment.trashDirectory { excluded.insert(trashFolder.path) }

        let options = MapScanOptions(root: walkRoot.path, excluded: excluded, skipped: skipped)
        let scanner: MapScanner<BulkDirectoryReader>
        do {
            scanner = try MapScanner(reader: BulkDirectoryReader(), options: options)
        } catch {
            status = .failed(Self.message(for: error, at: walkRoot, isDisk: scope.isDisk))
            AppModel.shared.setStage(.results, for: .spaceLens)
            return
        }
        let policy = TrashPolicy(environment: environment, allowedVolumeRoots: allowedVolumes)
        safety = MapSafety(policy: policy, scope: scopeKind, syncedFolders: Self.syncedFolders(home: environment.home, fm: fm))
        trash = TrashService(environment: environment, allowedVolumeRoots: allowedVolumes)
        self.scanner = scanner
        store = scanner.store
        paths = MapPaths(walkRoot: walkRoot.path, firmlinks: firmlinks)
        if case .volume(let volume) = scope { self.volume = volume } else { volume = nil }
        figures = nil
        mapped = scope
        self.skippedProtected = skippedProtected
        status = .scanning
        place = .folder("")
        backStack = []
        forwardStack = []
        selection = []
        hovered = nil
        smallItems = nil
        snapshot = nil
        items = []
        note = nil
        movedSmall = [:]
        if !sameScope { tray = CheckTray() }
        progressItems = 0
        progressBytes = 0
        scanStart = Date()
        loggedFirstMap = false
        scanToken += 1
        let token = scanToken
        AppModel.shared.setStage(.results, for: .spaceLens)
        scanner.start { outcome in
            Task { @MainActor [weak self] in self?.scanEnded(outcome, token: token) }
        }
        startPolling(token: token)
        // Checks kept from the last map of this scope: only those still there.
        if sameScope {
            tray.removeAll { !fm.fileExists(atPath: $0.path) }
        }
    }

    static func syncedFolders(home: URL, fm: FileManager) -> [(URL, String)] {
        var list: [(URL, String)] = []
        for (name, service) in MapSafety.classicSyncFolders {
            let url = home.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { list.append((url, service)) }
        }
        // Desktop and Documents in iCloud: synced (and protected).
        for name in ["Desktop", "Documents"] {
            let url = home.appendingPathComponent(name)
            if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
                list.append((url, "iCloud Drive"))
            }
        }
        return list
    }

    static func message(for error: Error, at url: URL, isDisk: Bool) -> String {
        switch error as? MapScanError {
        case .notFound?: isDisk ? "The disk isn't connected any more." : "\(url.lastPathComponent) isn't there any more."
        case .notAFolder?: "\(url.lastPathComponent) isn't a folder."
        default: isDisk
            ? "Tidy can't read this disk. Allow it in System Settings ▸ Privacy & Security ▸ Files and Folders."
            : "Tidy can't read \(url.lastPathComponent)."
        }
    }

    private func startPolling(token: Int) {
        poll?.cancel()
        poll = Task { [weak self] in
            // The first map within a fraction of a second, then up to 4 updates a second.
            try? await Task.sleep(for: .milliseconds(120))
            while !Task.isCancelled {
                guard let self, self.scanToken == token, self.status == .scanning else { return }
                self.refresh()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTimers() {
        poll?.cancel()
        poll = nil
    }

    private func scanEnded(_ outcome: MapScanOutcome, token: Int) {
        guard token == scanToken else { return }
        stopTimers()
        if status == .scanning { status = outcome == .finished ? .finished : .stopped }
        refresh(force: true)
        logTiming("scan \(outcome == .finished ? "finished" : "stopped") after \(Int(Date().timeIntervalSince(scanStart) * 1000)) ms, \(progressItems) items")
    }

    /// Stop: keeps what was counted.
    func stop() {
        guard status == .scanning else { return }
        scanner?.cancel()
        rescanner?.cancel()
        status = .stopped
    }

    /// Start Over: drops the map and its memory.
    func reset() {
        stopTimers()
        scanner?.cancel()
        scanner = nil
        store = nil
        snapshot = nil
        smallItems = nil
        figures = nil
        mapped = nil
        paths = nil
        status = .idle
        tray = CheckTray()
        selection = []
        hovered = nil
        backStack = []
        forwardStack = []
        place = .folder("")
    }

    /// Re-walks the folder shown and splices it in (or lists a package's contents).
    func rescanCurrentFolder(showPackageContents package: MapItem? = nil) {
        guard let store, let scanner, let paths, status != .scanning, status != .disconnected else { return }
        let id = package?.id ?? place.folderID
        guard let node = store.find(id: id) else { return }
        let options = scanner.options
        let rescan = MapScanner(rescanning: node, at: paths.walkPath(id), in: store, seen: scanner, reader: BulkDirectoryReader(),
                                options: options, showPackageContents: package != nil)
        status = .scanning
        scanToken += 1
        let token = scanToken
        if package != nil {
            go(to: .folder(id))
        }
        rescanner = rescan
        rescan.start { outcome in
            Task { @MainActor [weak self] in
                guard let self, token == self.scanToken else { return }
                self.rescanner = nil
                self.stopTimers()
                self.status = outcome == .finished ? .finished : .stopped
                self.refresh(force: true)
            }
        }
        startPolling(token: token)
    }

    /// Copies what's needed for the folder shown out of the store.
    func refresh(force: Bool = false) {
        guard let store, paths != nil else { return }
        let progress = store.progress
        progressItems = progress.items
        progressBytes = progress.bytes
        let id = place.folderID
        guard let node = store.find(id: id) else {
            place = .folder("")
            refresh(force: true)
            return
        }
        let version = store.version
        if force || snapshot?.version != version || snapshot?.folder.id != id {
            snapshot = store.snapshot(of: node, id: id)
            if !loggedFirstMap, !(snapshot?.items.isEmpty ?? true) {
                loggedFirstMap = true
                logTiming("first map after \(Int(Date().timeIntervalSince(scanStart) * 1000)) ms, \(snapshot?.items.count ?? 0) items")
            }
        }
        if let volume {
            let fresh = VolumeFigures(volume: volume, mapped: store.node(MapStore.root).size)
            if fresh != figures { figures = fresh }
        }
        rebuildItems()
        if let hovered, !visibleIDs.contains(hovered), item(hovered) == nil { self.hovered = nil }
    }

    /// Test mode only: timings and counts (never paths) next to the fixture.
    private func logTiming(_ line: String) {
        guard let environment, environment.isTestMode, let trash = environment.trashDirectory else { return }
        let file = trash.deletingLastPathComponent().appendingPathComponent("tidy-map-timing.txt")
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }

    // MARK: What's shown

    var folder: MapItem? { snapshot?.folder }

    /// The rows and tiles of the place shown, biggest first (virtual items included).
    private(set) var items: [MapItem] = []

    private func rebuildItems() {
        let list = buildItems()
        if list != items { items = list }
    }

    private func buildItems() -> [MapItem] {
        guard let snapshot else { return [] }
        if case .smaller(let id) = place {
            return (smallItems ?? []).map { small in
                MapItem(id: id.isEmpty ? small.name : id + "/" + small.name, name: small.name,
                        kind: small.flags.contains(.symlink) ? .symlink : .file, size: small.size, logical: small.logical,
                        flags: small.flags, itemCount: 1, fileID: small.fileID)
            }
        }
        var list = snapshot.items
        if snapshot.folder.otherCount > 0 {
            list.append(MapItem(id: "#smaller:" + snapshot.folder.id, name: smallerTitle(snapshot.folder.otherCount),
                                kind: .smaller, size: snapshot.folder.otherSize, flags: [.final],
                                otherSize: snapshot.folder.otherSize, otherCount: snapshot.folder.otherCount))
        }
        if snapshot.folder.id.isEmpty, let figures {
            if figures.system > 0 {
                list.append(MapItem(id: "#system", name: "macOS", kind: .system, size: figures.system, flags: [.final]))
            }
            if figures.notMapped > 0 {
                list.append(MapItem(id: "#notmapped", name: "Not mapped", kind: .notMapped, size: figures.notMapped, flags: [.final]))
            }
        }
        return list.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
    }

    var visibleIDs: Set<String> { Set(items.map(\.id)) }

    func smallerTitle(_ count: Int) -> String {
        count == 1 ? "1 smaller item" : "\(count.formatted()) smaller items"
    }

    /// The total for the place shown (the root of a disk includes the system and unmapped space).
    var total: Int64 {
        guard let folder else { return 0 }
        if case .smaller = place { return folder.otherSize }
        if folder.id.isEmpty, let figures { return folder.size + figures.system + figures.notMapped }
        return folder.size
    }

    /// Nested items (the map's second level) of an item shown.
    func nested(_ item: MapItem) -> [MapItem] { snapshot?.nested[item.id] ?? [] }

    func item(_ id: String) -> MapItem? {
        if let found = items.first(where: { $0.id == id }) { return found }
        for (_, list) in snapshot?.nested ?? [:] {
            if let found = list.first(where: { $0.id == id }) { return found }
        }
        return nil
    }

    func path(of item: MapItem) -> String? {
        guard !item.isVirtual, let paths else { return nil }
        return paths.path(item.id)
    }

    func url(of item: MapItem) -> URL? { path(of: item).map { URL(fileURLWithPath: $0) } }

    func url(forID id: String) -> URL? {
        guard !id.hasPrefix("#"), let paths else { return nil }
        return URL(fileURLWithPath: paths.path(id))
    }

    /// Why it can't be checked, if it can't.
    func lock(_ item: MapItem) -> MapLock? {
        if status == .disconnected { return .disconnected }
        guard let safety else { return .virtualItem }
        guard let path = path(of: item) else { return .virtualItem }
        return safety.lock(path: path, kind: item.kind, flags: item.flags)
    }

    /// Breadcrumbs: (title, place) from the root to where you are.
    func breadcrumbs(home: URL) -> [(title: String, place: MapPlace)] {
        var crumbs: [(String, MapPlace)] = [(rootTitle(home: home), .folder(""))]
        let parts = place.folderID.split(separator: "/").map(String.init)
        for i in parts.indices {
            crumbs.append((parts[i], .folder(parts[0...i].joined(separator: "/"))))
        }
        if case .smaller(let id) = place, let folder = snapshot?.folder, folder.id == id {
            crumbs.append((smallerTitle(folder.otherCount), place))
        }
        return crumbs
    }

    func rootTitle(home: URL) -> String {
        switch mapped {
        case .home?, nil: "Home Folder"
        case .folder(let url)?: url.path == home.path ? "Home Folder" : url.lastPathComponent
        case .volume(let volume)?: volume.name
        }
    }

    // MARK: Navigation

    private func go(to newPlace: MapPlace, record: Bool = true) {
        guard newPlace != place else { return }
        if record {
            backStack.append(place)
            forwardStack = []
        }
        place = newPlace
        selection = []
        hovered = nil
        placeChanges += 1
        if case .smaller(let id) = newPlace { loadSmallItems(id) } else { smallItems = nil }
        refresh(force: true)
    }

    func navigate(to place: MapPlace) { go(to: place) }

    /// Opens a folder, a package listed with its contents, or a folder's smaller items.
    func open(_ item: MapItem) {
        guard item.canOpen else { return }
        if item.kind == .smaller {
            go(to: .smaller(String(item.id.dropFirst("#smaller:".count))))
        } else {
            go(to: .folder(item.id))
        }
    }

    var canGoUp: Bool { place != .folder("") }

    func goUp() {
        switch place {
        case .smaller(let id): go(to: .folder(id))
        case .folder(let id):
            guard !id.isEmpty else { return }
            go(to: .folder((id as NSString).deletingLastPathComponent))
        }
    }

    func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(place)
        go(to: previous, record: false)
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(place)
        go(to: next, record: false)
    }

    private func loadSmallItems(_ folderID: String) {
        smallItems = nil
        guard let paths, let store, let node = store.find(id: folderID) else { return }
        let listed = Set(store.children(node).map { store.name($0) })
        let path = paths.walkPath(folderID)
        let reader = BulkDirectoryReader()
        Task {
            let result = await ScannerThread.run(reader: reader) {
                SmallItemsReader.read(path, excluding: listed, reader: reader)
            }
            guard self.place == .smaller(folderID) else { return }
            switch result {
            case .success(let items): smallItems = items
            case .failure: smallItems = []
            }
            rebuildItems()
        }
    }

    // MARK: Checking

    func isChecked(_ item: MapItem) -> Bool {
        guard let path = path(of: item) else { return false }
        return tray.contains(path)
    }

    /// A checked folder that contains it.
    func coveringCheck(_ item: MapItem) -> CheckedItem? {
        guard let path = path(of: item) else { return nil }
        return tray.covering(path)
    }

    func checkable(_ item: MapItem) -> Bool { lock(item) == nil && coveringCheck(item) == nil }

    func setChecked(_ item: MapItem, _ on: Bool) {
        guard let path = path(of: item) else { return }
        if !on {
            tray.uncheck(path)
            note = nil
            return
        }
        if let lock = lock(item) {
            note = "\(item.name): \(lock.reason)"
            return
        }
        let parent = (path as NSString).deletingLastPathComponent
        let checked = CheckedItem(
            path: path, name: item.name, size: item.size, isDirectory: item.isFolderLike, device: store?.device ?? 0,
            fileID: item.fileID,
            mayFreeNothing: item.flags.contains(.hardLinked) || item.flags.contains(.clone) || item.flags.contains(.countedElsewhere),
            folderName: (parent as NSString).lastPathComponent, resolvedParent: PathResolution.resolvedParent(parent))
        switch tray.check(checked) {
        case .insideChecked(let outer): note = "“\(outer)” is checked, and \(item.name) is inside it."
        case .checked(let absorbed) where absorbed > 0:
            note = absorbed == 1 ? "1 checked item inside \(item.name) is now part of it."
                : "\(absorbed) checked items inside \(item.name) are now part of it."
        default: note = nil
        }
    }

    /// Space on rows or tiles: checks them, or unchecks them if they're all checked.
    func toggle(_ ids: Set<String>) {
        let targets = ids.compactMap(item)
        guard !targets.isEmpty else { return }
        let allChecked = targets.allSatisfy(isChecked)
        for item in targets { setChecked(item, !allChecked) }
    }

    func uncheck(path: String) { tray.uncheck(path) }

    func size(of url: URL) -> Int64? { tray.items.first { $0.path == url.path }?.size }

    /// After a move or Put Back: sizes update in place, without a rescan.
    func noteChanged(_ changed: Set<String>, restored: Bool) {
        guard let store, let paths else { return }
        for path in changed {
            guard let id = paths.id(for: path) else { continue }
            if let node = store.find(id: id) {
                if restored { store.restore(node) } else { store.markRemoved(node) }
            } else if restored, let small = movedSmall.removeValue(forKey: path) {
                store.adjustSmallItems(in: small.folder, size: small.size, logical: small.size, count: 1, restoring: true)
            } else if !restored, let folder = store.find(id: (id as NSString).deletingLastPathComponent) {
                let size = tray.items.first { $0.path == path }?.size
                    ?? smallItems?.first { $0.name == (path as NSString).lastPathComponent }?.size ?? 0
                movedSmall[path] = (folder, size)
                store.adjustSmallItems(in: folder, size: size, logical: size, count: 1, restoring: false)
            }
        }
        if !restored {
            tray.remove(paths: changed)
            selection = selection.filter { id in !changed.contains(paths.path(id)) }
        }
        if case .smaller(let id) = place { loadSmallItems(id) }
        refresh(force: true)
    }

    // MARK: Moving

    /// The last check before moving: refusals become failures, the rest is moved.
    func verifiedForMove() -> (items: [CheckedItem], refused: [TrashFailure]) {
        guard let safety else { return ([], []) }
        let reader = BulkDirectoryReader()
        var ok: [CheckedItem] = []
        var refused: [TrashFailure] = []
        for item in tray.items {
            let id = paths?.id(for: item.path)
            let found = id.flatMap { store?.find(id: $0) }.flatMap { store?.node($0) }
            let kind: MapItem.Kind = item.isDirectory
                ? ((found?.flags.contains(.package) ?? false) ? .package : .folder) : .file
            if let refusal = safety.verify(item, kind: kind, flags: found?.flags ?? [], info: reader.info,
                                           resolveParent: PathResolution.resolvedParent) {
                refused.append(TrashFailure(url: URL(fileURLWithPath: item.path), message: refusal.description))
            } else {
                ok.append(item)
            }
        }
        return (ok, refused)
    }

    /// Items on another disk go to that disk's Trash.
    var isOtherVolume: Bool {
        if case .volume(let volume)? = mapped { return volume.kind != .startup }
        return false
    }

    // MARK: Details

    func inspect(_ item: MapItem) {
        inspected = item
        inspectedFacts = nil
        guard let path = path(of: item) else { return }
        let wantsPrivate = item.flags.contains(.partialClone)
        let reader = BulkDirectoryReader()
        Task {
            let facts = await ScannerThread.run(reader: reader) { ItemFacts.read(path, wantsPrivateSize: wantsPrivate) }
            if inspected?.id == item.id { inspectedFacts = facts }
        }
    }

    func cloudTally(_ item: MapItem) -> CloudTally? { item.node.flatMap { store?.cloudTally($0) } }
    func unreadableCount(_ item: MapItem) -> Int { item.node.map { store?.unreadableCount($0) ?? 0 } ?? 0 }
    func linkCount(_ item: MapItem) -> UInt32? { item.node.flatMap { store?.linkCount($0) } }
}

extension MapPaths {
    /// The path the scanner walks for an id (the Data volume path on the startup disk).
    func walkPath(_ id: String) -> String {
        guard !id.isEmpty else { return walkRoot }
        return walkRoot == "/" ? "/" + id : walkRoot + "/" + id
    }
}
