import AppKit
import SpecimenCore
import UniformTypeIdentifiers

// Library folders (fonts managed where they are, watched with FSEvents), documents (the
// fonts a file uses), and temporary activation. The pure logic lives in SpecimenCore.

extension AppModel {
    var libraryCacheURL: URL { environment.dataDirectory.appendingPathComponent("Cache/library.plist") }

    /// Library folders that are there right now.
    var onlineFolderPaths: [String] { folders.map(\.path).filter { !offlineFolders.contains($0) } }

    func loadLibraryState() {
        var loaded = foldersStore.load()
        // A folder moved or renamed while Specimen was closed: follow its bookmark.
        var moved = false
        for index in loaded.indices where !FileManager.default.fileExists(atPath: loaded[index].path) {
            if let resolved = Self.resolve(loaded[index].bookmark), resolved != loaded[index].path {
                loaded[index].path = resolved
                moved = true
            }
        }
        setFolders(loaded)
        if moved { saveFolders() }
        setDocuments(documentsStore.load())
    }

    static func resolve(_ bookmark: Data?) -> String? {
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return LibraryPaths.trimmed(url.path)
    }

    func saveFolders() {
        do {
            try foldersStore.save(folders)
        } catch {
            notice = Notice(title: "Couldn't save library folders", message: "\(error.localizedDescription) Check that \(environment.dataDirectory.path) is writable.")
        }
    }

    // MARK: Temporary activations

    /// Ends temporary activations a previous run left behind (it crashed, or was killed).
    func endLeftoverTemporaryActivations() async {
        let leftover = temporaryStore.load()
        guard !leftover.isEmpty else { return }
        let registrar = registrar
        await Task.detached {
            let stillTemporary = leftover.filter { registrar.scope(of: $0) == .session }
            _ = registrar.unregister(Array(stillTemporary))
        }.value
        temporaryStore.save([])
        setTemporaryPaths([])
    }

    // MARK: Scanning and watching

    /// Shows the cached scan of every folder (no disk access beyond the cache).
    func loadFolders() async {
        guard !folders.isEmpty else { return }
        await folderLibrary.load(from: libraryCacheURL)
        let snapshot = await folderLibrary.cached(roots: folders.map(\.path))
        await apply(snapshot, reindex: false)
    }

    /// Brings every folder up to date with the disk, then watches them.
    func syncFolders() async {
        guard !folders.isEmpty else {
            watcher.stop()
            return
        }
        setScanningFolders(true)
        let snapshot = await folderLibrary.sync(roots: folders.map(\.path))
        setScanningFolders(false)
        await apply(snapshot)
        startWatching()
    }

    func startWatching() {
        let roots = onlineFolderPaths
        guard !roots.isEmpty else {
            watcher.stop()
            return
        }
        watcher.watch(roots) { [weak self] events in
            Task { @MainActor in self?.enqueue(events) }
        }
    }

    /// FSEvents batches arrive every quarter second at most; gather a little more, then apply.
    private func enqueue(_ events: [FolderEvent]) {
        pendingEvents += events
        guard eventTask == nil else { return }
        eventTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            let batch = pendingEvents
            pendingEvents = []
            eventTask = nil
            await handle(batch)
        }
    }

    private func handle(_ events: [FolderEvent]) async {
        guard !events.isEmpty else { return }
        // A library folder itself moved, renamed or went away.
        if events.contains(where: { $0.flags.contains(.rootChanged) }) {
            followMovedFolders()
            await syncFolders()
            return
        }
        let snapshot = await folderLibrary.apply(events, roots: folders.map(\.path))
        await apply(snapshot)
    }

    /// Folders whose path is gone but whose bookmark resolves elsewhere: follow them, and move
    /// their registrations along so active fonts stay active.
    private func followMovedFolders() {
        var updated = folders
        var moves: [(from: String, to: String)] = []
        for index in updated.indices where !FileManager.default.fileExists(atPath: updated[index].path) {
            guard let resolved = Self.resolve(updated[index].bookmark), resolved != updated[index].path else { continue }
            moves.append((updated[index].path, resolved))
            updated[index].path = resolved
        }
        guard !moves.isEmpty else { return }
        setFolders(updated)
        saveFolders()
        var carried: [RegistrationCarryOver.Move] = []
        for move in moves {
            for path in registeredPaths where LibraryPaths.isInside(path, folder: move.from) {
                carried.append(RegistrationCarryOver.Move(from: path, to: move.to + path.dropFirst(move.from.count)))
            }
        }
        carryRegistrations(carried)
        if case .folder(let path) = sidebar, let move = moves.first(where: { LibraryPaths.isInside(path, folder: $0.from, orEqual: true) }) {
            sidebar = .folder(move.to + path.dropFirst(move.from.count))
        }
    }

    /// Re-registers moved files at their new paths with the same scope.
    private func carryRegistrations(_ moves: [RegistrationCarryOver.Move]) {
        guard !moves.isEmpty else { return }
        let registrar = registrar
        var temporary = temporaryPaths
        var persistent: [String] = [], session: [String] = []
        for move in moves {
            if temporary.remove(move.from) != nil {
                temporary.insert(move.to)
                session.append(move.to)
            } else {
                persistent.append(move.to)
            }
        }
        setTemporaryPaths(temporary)
        temporaryStore.save(temporary)
        let old = moves.map(\.from)
        Task.detached {
            _ = registrar.unregister(old)
            _ = registrar.register(persistent, scope: .persistent)
            _ = registrar.register(session, scope: .session)
        }
    }

    /// Applies a scan: the sidebar trees, the faces, and registrations of files that moved
    /// (carried over) or were deleted (unregistered, so they don't linger as missing fonts).
    func apply(_ snapshot: FolderLibrary.Snapshot, reindex: Bool = true) async {
        setFolderState(trees: snapshot.trees, offline: snapshot.offline, unreadable: snapshot.unreadable)
        libraryFaces = snapshot.faces
        let change = snapshot.change
        var relist = false
        if !change.removed.isEmpty {
            let moves = RegistrationCarryOver.moves(in: change, registered: registeredPaths)
            let moved = Set(moves.map(\.from))
            // Only files whose folder is still there were really deleted.
            let deleted = change.removed.keys.filter { path in
                registeredPaths.contains(path) && !moved.contains(path)
                    && folders.contains { $0.contains(path) && !snapshot.offline.contains($0.path) }
            }
            if !deleted.isEmpty {
                let registrar = registrar
                let paths = Array(deleted)
                await Task.detached { _ = registrar.unregister(paths) }.value
                var temporary = temporaryPaths
                temporary.subtract(paths)
                setTemporaryPaths(temporary)
                temporaryStore.save(temporary)
            }
            carryRegistrations(moves)
            relist = !deleted.isEmpty || !moves.isEmpty
        }
        if case .folder(let path) = sidebar, !folderNodePaths.contains(path) { sidebar = .all }
        if reindex, !change.isEmpty {
            await rebuildIndex(relist: relist)
        } else {
            refreshItems(counts: true)
        }
        let library = folderLibrary, url = libraryCacheURL
        Task.detached(priority: .utility) { await library.saveIfNeeded(to: url) }
    }

    /// Disks come and go: folders on them go offline and come back.
    func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.folders.isEmpty else { return }
                    Task { await self.syncFolders() }
                }
            })
        }
    }

    // MARK: Adding and removing folders

    func chooseFolderToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        panel.message = "Choose folders of fonts. Specimen shows their fonts and activates them where they are; nothing is copied."
        if let test = environment.testFontsDirectory { panel.directoryURL = test }
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func addFolders(_ urls: [URL]) {
        var updated = folders
        var select: SidebarItem?
        for url in urls {
            let path = LibraryPaths.trimmed(url.standardizedFileURL.path)
            if let test = environment.testFontsDirectory, !LibraryPaths.isInside(path, folder: test.path, orEqual: true),
               !LibraryPaths.isInside(path, folder: LocalLibraryFileSystem.realPath(test.path), orEqual: true) {
                notice = Notice(title: "Not in the test folder", message: "In test mode, Specimen only adds folders inside \(test.path).")
                continue
            }
            switch FolderAddition.plan(path, existing: updated) {
            case .add(let path, let replacing):
                updated.removeAll { replacing.contains($0.id) }
                updated.append(LibraryFolder(path: path, bookmark: try? url.bookmarkData()))
                select = .folder(path)
            case .alreadyIncluded:
                select = .folder(path)
            case .installedFonts:
                notice = Notice(title: "These fonts are already installed",
                                message: "Fonts in macOS’s Fonts folders are already in Specimen. Add folders where you keep other fonts, like a project’s Fonts folder.")
            }
        }
        guard updated != folders || select != nil else { return }
        updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let changed = updated != folders
        setFolders(updated)
        if changed { saveFolders() }
        Task {
            if changed { await syncFolders() }
            if let select { sidebar = folderNodePaths.contains(select.folderPath ?? "") ? select : (updated.first.map { .folder($0.path) } ?? .all) }
            screen = .grid
        }
    }

    /// Faces in a folder that are on (registered from there by Specimen or anything else).
    func activeFaces(inFolder path: String) -> [FontFace] {
        faces.filter { $0.isEnabled && $0.path.map { LibraryPaths.isInside($0, folder: path) } == true }
    }

    func facesIn(folder path: String) -> [FontFace] {
        faces.filter { $0.path.map { LibraryPaths.isInside($0, folder: path) } == true }
    }

    /// Asks first when the folder has active fonts (they're turned off with it).
    func requestRemove(_ folder: LibraryFolder) {
        if activeFaces(inFolder: folder.path).isEmpty {
            remove(folder)
        } else {
            pendingFolderRemoval = folder
        }
    }

    /// Removes a folder from the library (the files stay where they are) and turns off its
    /// fonts that are on from there.
    func remove(_ folder: LibraryFolder) {
        pendingFolderRemoval = nil
        let active = activeFaces(inFolder: folder.path).filter(isInPlace).compactMap(\.path)
        let remaining = folders.filter { $0.id != folder.id }
        if case .folder(let path) = sidebar, LibraryPaths.isInside(path, folder: folder.path, orEqual: true) { sidebar = .all }
        Task {
            if !active.isEmpty {
                let registrar = registrar
                let paths = Array(Set(active))
                await Task.detached { _ = registrar.unregister(paths) }.value
                var temporary = temporaryPaths
                temporary.subtract(paths)
                setTemporaryPaths(temporary)
                temporaryStore.save(temporary)
            }
            setFolders(remaining)
            saveFolders()
            let snapshot = await folderLibrary.remove(folder.path, roots: remaining.map(\.path))
            await apply(snapshot, reindex: false)
            await rebuildIndex(relist: true)
            startWatching()
        }
    }

    func folder(forPath path: String) -> LibraryFolder? {
        folders.first { $0.path == path || $0.contains(path) }
    }

    /// The library folder a face is in, if any (for Info and the list's Location column).
    func libraryFolder(of face: FontFace) -> LibraryFolder? {
        guard let path = face.path else { return nil }
        return folders.first { $0.contains(path) }
    }

    // MARK: Documents

    func chooseDocumentToOpen() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = DocumentKind.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Show Fonts"
        panel.message = "Choose a PDF, Illustrator, EPS, SVG, HTML, CSS or RTF file to see the fonts it uses."
        if let test = environment.testFontsDirectory { panel.directoryURL = test }
        guard panel.runModal() == .OK else { return }
        openDocuments(panel.urls)
    }

    func openDocuments(_ urls: [URL]) {
        var list = documents
        var last: UUID?
        for url in urls where DocumentKind(pathExtension: url.pathExtension) != nil {
            let result = DocumentsStore.adding(url.standardizedFileURL.path, to: list, bookmark: try? url.bookmarkData())
            list = result.documents
            last = result.id
        }
        guard let last else { return }
        setDocuments(list)
        try? documentsStore.save(list)
        refreshDocuments(only: Set(urls.compactMap { url in list.first { $0.path == url.standardizedFileURL.path }?.id }))
        sidebar = .document(last)
        screen = .grid
    }

    func removeDocument(_ id: UUID) {
        if sidebar == .document(id) { sidebar = .all }
        let list = documents.filter { $0.id != id }
        setDocuments(list)
        try? documentsStore.save(list)
        documentReferences[id] = nil
        rematchDocuments()
        refreshItems(counts: true)
    }

    /// Reads documents' font names in the background (all of them, or `only` these).
    func refreshDocuments(only: Set<UUID>? = nil) {
        let targets = documents.filter { only?.contains($0.id) ?? true }
        guard !targets.isEmpty else { return }
        Task {
            let results = await Task.detached(priority: .userInitiated) { () -> [(UUID, Result<[FontReference], Error>)] in
                targets.map { document in
                    var path = document.path
                    if !FileManager.default.fileExists(atPath: path), let moved = AppModel.resolveFile(document.bookmark) { path = moved }
                    return (document.id, Result { try DocumentFontReader.references(in: URL(fileURLWithPath: path)) })
                }
            }.value
            var problems = documentProblems
            for (id, result) in results {
                switch result {
                case .success(let references):
                    documentReferences[id] = references
                    problems[id] = nil
                case .failure(let error):
                    documentReferences[id] = []
                    problems[id] = Self.describe(error, document: documents.first { $0.id == id })
                }
            }
            setDocumentState(matches: documentMatches, problems: problems)
            rematchDocuments()
            refreshItems(counts: true)
        }
    }

    nonisolated static func resolveFile(_ bookmark: Data?) -> String? {
        guard let bookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale))?.path
    }

    static func describe(_ error: Error, document: OpenedDocument?) -> String {
        if let failure = error as? DocumentFontReader.Failure {
            switch failure {
            case .unsupported: return "Specimen can’t read fonts from this kind of file."
            case .tooLarge: return "The file is too large to read."
            case .unreadable:
                if let document, !FileManager.default.fileExists(atPath: document.path) { return "The file was moved or deleted." }
                return "Specimen couldn’t read the file. It may be damaged."
            }
        }
        return error.localizedDescription
    }

    /// Matches every document's fonts against the current library (one index for all).
    func rematchDocuments() {
        guard !documents.isEmpty else {
            if !documentMatches.isEmpty { setDocumentState(matches: [:], problems: documentProblems) }
            return
        }
        let index = DocumentFontMatcher.Index(faces)
        var matches: [UUID: [DocumentFontMatch]] = [:]
        for document in documents {
            guard let references = documentReferences[document.id] else { continue }
            matches[document.id] = DocumentFontMatcher.match(references, in: index, documentPath: document.path)
        }
        setDocumentState(matches: matches, problems: documentProblems)
    }

    var documentFaceIDs: [UUID: Set<String>] {
        documentMatches.mapValues { Set($0.flatMap { $0.faces.map(\.id) }) }
    }

    func document(_ id: UUID) -> OpenedDocument? { documents.first { $0.id == id } }

    /// Faces a document uses that are off (what its Activate button turns on).
    func inactiveFaces(inDocument id: UUID) -> [FontFace] {
        var seen = Set<String>()
        return (documentMatches[id] ?? []).flatMap(\.inactiveFaces).filter { seen.insert($0.id).inserted }
    }

    // MARK: Collections

    /// Every face a sidebar item holds (folder, document, tag, smart collection…), for
    /// activating a whole collection at once.
    func faces(in item: SidebarItem) -> [FontFace] {
        var query = query
        query.sidebar = item
        query.search = ""
        query.hiddenFaceIDs = []
        query.groupByFamily = true
        return LibraryFilter.items(in: families, query: query).flatMap(\.faces)
    }

    // MARK: Drops and Open

    /// Folders join the library; documents show their fonts; font files are installed.
    func handleDrop(_ urls: [URL]) -> Bool {
        let fileManager = FileManager.default
        var folders: [URL] = [], documents: [URL] = [], fonts: [URL] = []
        for url in urls where url.isFileURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue { folders.append(url) }
            else if DocumentKind(pathExtension: url.pathExtension) != nil { documents.append(url) }
            else if InstallPlan.fontExtensions.contains(url.pathExtension.lowercased()) { fonts.append(url) }
        }
        if !folders.isEmpty { addFolders(folders) }
        if !documents.isEmpty { openDocuments(documents) }
        if !fonts.isEmpty { addFonts(fonts) }
        return !(folders.isEmpty && documents.isEmpty && fonts.isEmpty)
    }
}

extension SidebarItem {
    var folderPath: String? {
        if case .folder(let path) = self { return path }
        return nil
    }
}
