import AppKit
import Observation
import os
import SlopappCore
import SlopKit

/// What's happening to one app right now.
enum Operation: Equatable {
    case queued
    case downloading(Double)
    case verifying
    case quitting
    case installing
    case removing

    var label: String {
        switch self {
        case .queued: "Waiting…"
        case .downloading(let p): p > 0 ? "Downloading \(Int(p * 100))%" : "Downloading…"
        case .verifying: "Verifying…"
        case .quitting: "Quitting…"
        case .installing: "Installing…"
        case .removing: "Moving to Trash…"
        }
    }

    var canCancel: Bool {
        switch self {
        case .queued, .downloading, .verifying: true
        default: false
        }
    }
}

/// Apps that must quit before an update or uninstall can go ahead.
struct QuitRequest: Identifiable, Equatable {
    var items: [CatalogItem]
    var id: String { items.map(\.id).joined(separator: ",") }

    var names: String { ListFormat.and(items.map(\.app.name)) }
    var title: String {
        items.count == 1 ? "\(names) is open. Quit it to update?" : "\(names) are open. Quit them to update?"
    }
    var message: String {
        items.count == 1 ? "Slopapp reopens it when the update is done. Save any open work first."
            : "Slopapp reopens them when the updates are done. Save any open work first."
    }
}

/// A failure shown under an app's button. Only failed installs/updates turn the button into Retry.
struct AppError: Equatable {
    var message: String
    var isInstallFailure: Bool
    /// Caused by the network (offline, server error): cleared once the catalog loads again.
    var isNetwork = false
}

/// An update that went through, for the Updates page's "Recently Updated" list.
struct RecentUpdate: Codable, Equatable, Identifiable {
    var slug: String
    var name: String
    var from: String
    var to: String
    var date: Date
    var id: String { "\(slug)-\(to)" }
}

/// The last uninstall, for Undo.
struct TrashedApp: Equatable {
    var name: String
    var result: Uninstaller.Result
    var removedData: Bool { result.moved.count > 1 }
    /// Where the app was; if a copy is back there, Undo has nothing to do.
    var appURL: URL? { result.moved.first?.from }
}

/// The launcher's state: the feed, what's installed, and every install/update/uninstall.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    let config: Config
    private(set) var feed: Feed?
    private(set) var items: [CatalogItem] = []
    /// A newer Slopapp (the hub's own feed entry), if any.
    private(set) var hubUpdate: FeedApp?
    private(set) var lastCheck: Date?
    private(set) var isChecking = false
    /// The last catalog fetch failed; the lists show the cached feed if there is one.
    private(set) var feedError: String?
    private(set) var hasScanned = false
    var operations: [String: Operation] = [:]
    /// Last failure per app, shown under its button until the next attempt.
    var errors: [String: AppError] = [:]
    /// Updates done in the last 7 days, newest first.
    private(set) var recentUpdates: [RecentUpdate] = []
    /// A short note under an app's button after it changed ("Reinstalled version 1.1.0."), for a few seconds.
    private(set) var notices: [String: String] = [:]
    var quitRequest: QuitRequest?
    var uninstallRequest: CatalogItem?
    private(set) var lastTrashed: TrashedApp?
    /// Starred apps (Favorites page, heart on app pages). Kept per feed, like Recently Updated.
    private(set) var favorites = FavoriteList()
    let icons: Icons

    @ObservationIgnored private var tasks: [String: Task<RecentUpdate?, Never>] = [:]
    @ObservationIgnored private let network = Network()
    @ObservationIgnored private let locator = LocalAppLocator()
    @ObservationIgnored private let schedule = UpdateSchedule()
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private let logger = Logger(subsystem: "app.slopapp.slopapp", category: "store")
    @ObservationIgnored private var scanGeneration = 0

    @ObservationIgnored private var appliedScanGeneration = 0
    @ObservationIgnored private lazy var watcher = FolderWatcher { [weak self] in self?.rescan() }

    var updates: [CatalogItem] { CatalogBuilder.updates(in: items) }
    var installed: [CatalogItem] { CatalogBuilder.installed(in: items) }
    /// Discover's first section: apps you can get, plus ones already here that the catalog
    /// can't offer right now.
    var available: [CatalogItem] { items.filter { $0.app.isInstallable || $0.isInstalled } }
    var comingSoon: [CatalogItem] { items.filter { !$0.app.isInstallable && !$0.isInstalled } }
    /// Sidebar categories with at least one app, in order.
    var categories: [String] { Categories.ordered(in: items) }
    var favoriteItems: [CatalogItem] { favorites.items(in: items) }
    var isBusy: Bool { !operations.isEmpty }

    func item(_ slug: String) -> CatalogItem? { items.first { $0.id == slug } }

    init(config: Config = .load()) {
        self.config = config
        let caches = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("app.slopapp.slopapp/icons", isDirectory: true)
        icons = Icons(fetcher: network, urlPolicy: config.urlPolicy, cacheDirectory: caches)
        lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let saved = try? JSONDecoder().decode([RecentUpdate].self, from: data) {
            recentUpdates = saved.filter { $0.date > Date().addingTimeInterval(-7 * 86400) }
        }
        favorites = FavoriteList(slugs: UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    private var recentKey: String { config.isDeveloperFeed ? "recentUpdates:dev" : "recentUpdates" }
    private var favoritesKey: String { config.isDeveloperFeed ? "favorites:dev" : "favorites" }

    func isFavorite(_ item: CatalogItem) -> Bool { favorites.contains(item.id) }

    func toggleFavorite(_ item: CatalogItem) {
        favorites.toggle(item.id)
        UserDefaults.standard.set(favorites.slugs, forKey: favoritesKey)
    }

    /// Favorites page "Install All": every starred app that isn't on this Mac yet, in a row.
    func installFavorites() {
        update(favorites.installable(in: items))
    }

    private func recordUpdate(_ update: RecentUpdate) {
        recentUpdates.removeAll { $0.slug == update.slug }
        recentUpdates.insert(update, at: 0)
        recentUpdates = Array(recentUpdates.prefix(10))
        if let data = try? JSONEncoder().encode(recentUpdates) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }

    // MARK: - Feed

    private var lastCheckKey: String { "lastCheck:\(config.feedURL.absoluteString)" }

    private var cacheFile: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        // Test feeds get their own cache so they never mix with the real catalog.
        let name = config.isDeveloperFeed ? "feed-cache-dev-\(Self.stableKey(config.feedURL.absoluteString)).json" : "feed-cache.json"
        return support.appendingPathComponent("app.slopapp.slopapp", isDirectory: true).appendingPathComponent(name)
    }

    private static func stableKey(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    /// Launch: show the cached catalog at once, then fetch a fresh one (opening the app is a
    /// person asking for it; the 6-hour limit is for checks nobody asked for).
    func start() {
        if let cacheFile, let data = try? Data(contentsOf: cacheFile),
           let cached = try? FeedParser.parse(data, baseURL: config.feedURL) {
            apply(cached)
        } else {
            rescan()
        }
        if config.allowsNetwork {
            Task { await refresh() }
        }
        startBackgroundChecks()
    }

    /// Fetches the feed now (Check for Updates, Try Again).
    func refresh() async {
        // What's on disk can change without the catalog changing (apps deleted in Finder).
        rescan()
        guard config.allowsNetwork, !isChecking else { return }
        guard config.urlPolicy.allows(config.feedURL) else {
            feedError = "The catalog address isn't secure (HTTPS), so Slopapp won't use it."
            return
        }
        isChecking = true
        defer { isChecking = false }
        logger.debug("refresh")
        do {
            let data = try await network.data(from: config.feedURL)
            let parsed = try FeedParser.parse(data, baseURL: config.feedURL)
            if let cacheFile {
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheFile, options: .atomic)
            }
            feedError = nil
            // The network is back: drop download errors it caused.
            for (slug, error) in errors where error.isNetwork { errors[slug] = nil }
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: lastCheckKey)
            apply(parsed)
        } catch let error as FeedError {
            feedError = error.message
        } catch NetworkError.offline {
            feedError = "Can't reach the Slopapp catalog. Check your internet connection and try again."
        } catch {
            feedError = "The Slopapp catalog isn't available right now. Try again later."
            logger.error("feed: \(String(describing: error), privacy: .public)")
        }
    }

    func checkIfDue() async {
        guard schedule.isDue(lastCheck: lastCheck, now: Date()) else { return }
        await refresh()
    }

    /// At most every 6 hours, scheduled by the system (coalesced, power-friendly; no polling).
    private func startBackgroundChecks() {
        guard config.allowsNetwork, scheduler == nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "app.slopapp.slopapp.update-check")
        scheduler.repeats = true
        scheduler.interval = schedule.interval
        scheduler.tolerance = 30 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await Store.shared.checkIfDue()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    private func apply(_ feed: Feed) {
        self.feed = feed
        hubUpdate = feed.apps.first { app in
            guard app.isHub, app.isInstallable, let version = app.version else { return false }
            let mine = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                                  build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            return AppVersion(version, build: app.build ?? 0) > mine
        }
        rescan()
    }

    // MARK: - What's installed

    /// Looks for every catalog app on disk, off the main thread (signature checks take a few ms each).
    func rescan() {
        Task { await scanInventory() }
    }

    /// `rescan`, finishing once the result is on screen. Install and Move to Trash wait for it
    /// before they drop their progress, so the button goes straight from progress to its new
    /// state (no flash of the old one in between).
    func scanInventory() async {
        let feed = feed ?? Feed(apps: [])
        let roots = config.roots
        let locator = locator
        scanGeneration += 1
        let generation = scanGeneration
        let items = await Task.detached(priority: .userInitiated) {
            CatalogBuilder.items(feed: feed) { app in
                Inventory.copies(of: app.bundleId ?? "", appName: app.name, roots: roots, locator: locator)
            }
        }.value
        // A newer scan's result wins; an older one still counts until the newer one lands
        // (both started after whatever changed, so the caller waiting here sees it).
        guard generation > appliedScanGeneration else { return }
        appliedScanGeneration = generation
        // Assign only real changes, so a folder event doesn't redraw every view.
        if self.items != items { self.items = items }
        if !self.hasScanned { self.hasScanned = true }
        self.logger.debug("rescan \(generation)")
        // An app put back in place by a reinstall: the Trash banner's Undo has nothing to do.
        if let trashed = self.lastTrashed, let url = trashed.appURL,
           FileManager.default.fileExists(atPath: url.path) {
            self.lastTrashed = nil
            self.mainWindowUndoManager?.removeAllActions(withTarget: self)
        }
        // "It's no longer at …" and similar notes go away once the app is back.
        for item in items where item.isInstalled && self.errors[item.id]?.isInstallFailure == false {
            self.errors[item.id] = nil
        }
        self.icons.load(items)
        // Folders that exist now (the install folder appears with the first install).
        self.watcher.watch([roots.installDirectory] + roots.managedDirectories + roots.applicationsDirectories)
    }

    // MARK: - Actions

    func open(_ item: CatalogItem) {
        guard let url = item.primary?.url else { return }
        // It may have been deleted or moved outside Slopapp since the last scan.
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path) else {
            errors[item.id] = AppError(
                message: "\(item.app.name) is no longer at \(displayPath(url)). It may have been moved or deleted." +
                    (item.app.isInstallable ? " Install it again from here." : ""),
                isInstallFailure: false)
            rescan()
            return
        }
        errors[item.id] = nil
        Task {
            do { try await RunningApps.open(url) } catch {
                errors[item.id] = AppError(message: "Couldn't open \(item.app.name). Use Reinstall in the ⋯ menu to repair it.",
                                           isInstallFailure: false)
            }
        }
    }

    /// Downloads the catalog's version again over the copy that's there (repair).
    func reinstall(_ item: CatalogItem) {
        update([item])
    }

    func reveal(_ item: CatalogItem) {
        guard let url = item.primary?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Install, Update, or Retry: whatever the item's state calls for.
    func installOrUpdate(_ item: CatalogItem) {
        update([item])
    }

    /// Updates (or installs) these apps one after another, asking first if any are running.
    func update(_ items: [CatalogItem], confirmedQuit: Bool = false) {
        let items = items.filter { operations[$0.id] == nil && $0.app.isInstallable }
        guard !items.isEmpty else { return }
        let running = items.filter { item in
            guard let copy = item.primary, copy.location.canModify else { return false }
            return RunningApps.isRunning(at: copy.url)
        }
        if !running.isEmpty, !confirmedQuit {
            quitRequest = QuitRequest(items: running)
            pendingAfterQuit = items
            return
        }
        for item in items {
            operations[item.id] = .queued
            errors[item.id] = nil
        }
        let slugs = items.map(\.id)
        // One after another; each app gets its own task so Cancel stops only that app.
        Task {
            var updated: [RecentUpdate] = []
            for slug in slugs {
                guard operations[slug] == .queued, let item = self.item(slug) else { continue }
                let task = Task { await self.perform(item, mayQuit: confirmedQuit) }
                tasks[slug] = task
                if let done = await task.value { updated.append(done) }
            }
            // Say what changed (a short HUD, design system: no alerts for confirmations).
            if updated.count == 1, let one = updated.first {
                HUD.show(one.from == one.to ? "Reinstalled \(one.name) \(one.to)" : "Updated \(one.name) to \(one.to)")
            } else if updated.count > 1 {
                HUD.show("Updated \(updated.count) apps")
            }
        }
    }

    @ObservationIgnored private var pendingAfterQuit: [CatalogItem] = []

    func confirmQuitAndUpdate() {
        let items = pendingAfterQuit
        quitRequest = nil
        pendingAfterQuit = []
        update(items, confirmedQuit: true)
    }

    func cancelQuitRequest() {
        quitRequest = nil
        pendingAfterQuit = []
    }

    func updateAll() {
        update(updates)
    }

    func cancel(_ item: CatalogItem) {
        guard operations[item.id]?.canCancel == true else { return }
        if operations[item.id] == .queued {
            operations[item.id] = nil
            return
        }
        tasks[item.id]?.cancel()
    }

    /// Installs or updates one app. Returns what changed when it replaced an existing copy.
    private func perform(_ item: CatalogItem, mayQuit: Bool) async -> RecentUpdate? {
        let slug = item.id
        let request = InstallRequest.plan(for: item, roots: config.roots)
        let wasRunning = item.primary.map { $0.location.canModify && RunningApps.isRunning(at: $0.url) } ?? false
        let isFreshInstall = request.replacing == nil
        let installer = Installer(
            downloader: network, unarchiver: DittoUnarchiver(), files: LocalFiles(trashDirectory: config.trashDirectory),
            signatures: locator, policy: config.signaturePolicy, urlPolicy: config.urlPolicy
        )
        operations[slug] = .downloading(0)
        let destination = request.destination
        var done: RecentUpdate?
        do {
            let result = try await installer.install(request, beforeReplace: { @Sendable in
                try await Store.shared.quitIfRunning(slug: slug, at: destination, mayQuit: mayQuit)
            }, progress: { @Sendable phase in
                Task { @MainActor in Store.shared.progress(slug, phase) }
            })
            // The new copy is in place: show it before the progress goes away.
            await scanInventory()
            operations[slug] = nil
            tasks[slug] = nil
            logger.info("installed \(slug, privacy: .public) \(result.info.version, privacy: .public) verdict \(String(describing: result.verdict), privacy: .public)")
            if let old = request.replacing {
                let update = RecentUpdate(slug: slug, name: item.app.name, from: old.info.version, to: result.info.version, date: Date())
                recordUpdate(update)
                done = update
                showNotice(slug, old.info.version == result.info.version
                           ? "Reinstalled version \(result.info.version)." : "Updated to version \(result.info.version).")
            } else {
                showNotice(slug, "Installed version \(result.info.version).")
            }
            let openAfter = isFreshInstall && UserDefaults.standard.object(forKey: "openAfterInstall") as? Bool ?? true
            if wasRunning || openAfter {
                try? await RunningApps.open(result.url)
            }
            // Menu bar apps open without a window: say where to find them.
            if openAfter, item.app.menuBarOnly == true {
                HUD.show("Opened \(item.app.name). It's in your menu bar.", systemImage: "menubar.arrow.up.rectangle", duration: .seconds(3))
            }
        } catch is CancellationError {
            operations[slug] = nil
            tasks[slug] = nil
        } catch let error as InstallError {
            operations[slug] = nil
            tasks[slug] = nil
            errors[slug] = AppError(message: error.message(appName: item.app.name), isInstallFailure: true,
                                    isNetwork: [.offline, .notFound].contains(error) || { if case .downloadFailed = error { true } else { false } }())
            logger.error("install \(slug, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            // The catalog may be out of date (a newer release replaced the file): reload it so
            // Retry uses the current entry.
            switch error {
            case .checksumMismatch, .notFound, .versionMismatch, .bundleMismatch, .unexpectedContents:
                Task { await refresh() }
            default:
                break
            }
        } catch {
            operations[slug] = nil
            tasks[slug] = nil
            errors[slug] = AppError(message: "Couldn't install \(item.app.name). Try again.", isInstallFailure: true)
        }
        rescan()
        return done
    }

    private func showNotice(_ slug: String, _ text: String) {
        notices[slug] = text
        Task {
            try? await Task.sleep(for: .seconds(6))
            if notices[slug] == text { notices[slug] = nil }
        }
    }

    /// Right before the swap: the copy being replaced must not be running.
    private func quitIfRunning(slug: String, at url: URL, mayQuit: Bool) async throws {
        guard RunningApps.isRunning(at: url) else { return }
        guard mayQuit else { throw InstallError.appWouldNotQuit }
        operations[slug] = .quitting
        guard await RunningApps.quit(at: url) else { throw InstallError.appWouldNotQuit }
        operations[slug] = .installing
    }

    private func progress(_ slug: String, _ phase: InstallPhase) {
        guard let current = operations[slug], current != .quitting else { return }
        let next: Operation = switch phase {
        case .downloading(let p): .downloading(p)
        case .verifying: .verifying
        case .installing: .installing
        }
        // Progress callbacks hop here asynchronously; never step backwards.
        if case .downloading(let old) = current, case .downloading(let new) = next, new - old < 0.01, new < 1 { return }
        if current == .installing, next != .installing { return }
        if current == .verifying, case .downloading = next { return }
        operations[slug] = next
    }

    // MARK: - Uninstall

    func requestUninstall(_ item: CatalogItem) {
        guard item.primary?.location.canModify == true, operations[item.id] == nil else { return }
        uninstallRequest = item
    }

    func uninstall(_ item: CatalogItem, removeData: Bool) async {
        uninstallRequest = nil
        guard let copy = item.primary, copy.location.canModify else { return }
        let slug = item.id
        operations[slug] = .removing
        errors[slug] = nil
        if RunningApps.isRunning(at: copy.url) {
            guard await RunningApps.quit(at: copy.url) else {
                errors[slug] = AppError(message: InstallError.appWouldNotQuit.message(appName: item.app.name), isInstallFailure: false)
                operations[slug] = nil
                return
            }
        }
        let uninstaller = Uninstaller(files: LocalFiles(trashDirectory: config.trashDirectory), library: config.library)
        do {
            let result = try uninstaller.uninstall(copy, removeData: removeData)
            if result.removedPreferences, !config.isTestingLibrary {
                // The preferences daemon caches settings; tell it they're gone.
                _ = try? await ProcessRunner.run("/usr/bin/defaults", ["delete", copy.info.bundleID])
            }
            lastTrashed = TrashedApp(name: item.app.name, result: result)
            // Edit > Undo (⌘Z) in the library window.
            if let undo = mainWindowUndoManager {
                undo.removeAllActions(withTarget: self)
                undo.registerUndo(withTarget: self) { $0.undoUninstall() }
                undo.setActionName("Move to Trash")
            }
        } catch {
            errors[slug] = AppError(message: "Couldn't move \(item.app.name) to the Trash. Check the folder's permissions, then try again.",
                                    isInstallFailure: false)
        }
        // Straight from "Moving to Trash…" to Install, without the old Open in between.
        await scanInventory()
        operations[slug] = nil
    }

    /// Puts the last uninstalled app (and its data) back.
    func undoUninstall() {
        guard let trashed = lastTrashed else { return }
        lastTrashed = nil
        mainWindowUndoManager?.removeAllActions(withTarget: self)
        if let url = trashed.appURL, FileManager.default.fileExists(atPath: url.path) {
            HUD.show("\(trashed.name) is already installed again.", systemImage: "info.circle")
            return
        }
        let uninstaller = Uninstaller(files: LocalFiles(trashDirectory: config.trashDirectory), library: config.library)
        do {
            try uninstaller.putBack(trashed.result)
        } catch {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
        }
        rescan()
    }

    func dismissTrashed() { lastTrashed = nil }

    private var mainWindowUndoManager: UndoManager? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }?.undoManager
    }
}
