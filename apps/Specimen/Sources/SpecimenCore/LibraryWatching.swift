import CoreServices
import Foundation

/// The real file system: FileManager for listing, CoreText for reading faces (in parallel).
public struct LocalLibraryFileSystem: LibraryFileSystem {
    public init() {}

    public func fontFiles(under root: String) -> [FileStamp] {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [FileStamp] = []
        let base = LibraryPaths.trimmed(root)
        // The enumerator hands back resolved paths (/private/tmp for /tmp). Rebuild each one
        // from the root as given, so it matches registrations and events.
        let prefixes = [Self.realPath(base), rootURL.path, base]
        for case let url as URL in enumerator {
            guard LibraryPaths.isFontFile(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let prefix = prefixes.first(where: { LibraryPaths.isInside(url.path, folder: $0) }) else { continue }
            let path = base + url.path.dropFirst(prefix.count)
            result.append(FileStamp(path: path, modified: values.contentModificationDate, size: Int64(values.fileSize ?? 0)))
        }
        return result
    }

    public func stamp(of path: String) -> FileStamp? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        return FileStamp(path: path, modified: modified, size: Int64(info.st_size))
    }

    public func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func readFaces(_ paths: [String]) -> [String: [SystemFace]] {
        let box = ResultBox(count: paths.count)
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let faces = autoreleasepool { CoreTextFontSystem.faces(inFile: paths[index]) }
            box.set(index, faces)
        }
        var result: [String: [SystemFace]] = [:]
        for (index, path) in paths.enumerated() { result[path] = box.value(index) }
        return result
    }

    /// The folder's path with symlinks resolved (FSEvents reports these).
    public static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[SystemFace]]
    init(count: Int) { values = Array(repeating: [], count: count) }
    func set(_ index: Int, _ faces: [SystemFace]) { lock.withLock { values[index] = faces } }
    func value(_ index: Int) -> [SystemFace] { lock.withLock { values[index] } }
}

/// Watches folders for changes. `FSEventsWatcher` in the app; a fake (or nothing) in tests.
public protocol FolderWatching: AnyObject, Sendable {
    /// Replaces whatever was watched. `handler` gets events with paths in the form `roots`
    /// were given in, on a background queue.
    func watch(_ roots: [String], handler: @escaping @Sendable ([FolderEvent]) -> Void)
    func stop()
}

/// FSEvents, one stream for every library folder, with file-level events.
public final class FSEventsWatcher: FolderWatching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.slopapp.specimen.fsevents")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var handler: (@Sendable ([FolderEvent]) -> Void)?
    /// (real path, path as added) per watched folder.
    private var roots: [(real: String, root: String)] = []
    /// Seconds FSEvents waits to coalesce events.
    private let latency: CFTimeInterval

    public init(latency: CFTimeInterval = 0.25) {
        self.latency = latency
    }

    deinit { stop() }

    public func watch(_ roots: [String], handler: @escaping @Sendable ([FolderEvent]) -> Void) {
        stop()
        guard !roots.isEmpty else { return }
        lock.withLock {
            self.handler = handler
            self.roots = roots.map { (LocalLibraryFileSystem.realPath($0), $0) }
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            var events: [FolderEvent] = []
            for index in 0..<count {
                guard let path = array[index] as? String else { continue }
                events.append(FolderEvent(path: path, flags: FSEventsWatcher.flags(flags[index])))
            }
            watcher.deliver(events)
        }
        let watched = self.roots.map(\.real) as CFArray
        guard let stream = FSEventStreamCreate(nil, callback, &context, watched,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.withLock { self.stream = stream }
    }

    public func stop() {
        let old = lock.withLock { () -> FSEventStreamRef? in
            let old = stream
            stream = nil
            handler = nil
            return old
        }
        guard let old else { return }
        FSEventStreamStop(old)
        FSEventStreamInvalidate(old)
        FSEventStreamRelease(old)
    }

    private func deliver(_ events: [FolderEvent]) {
        let (handler, roots) = lock.withLock { (self.handler, self.roots) }
        guard let handler else { return }
        let mapped = events.compactMap { event -> FolderEvent? in
            for root in roots {
                if let path = LibraryPaths.rebase(event.path, real: root.real, root: root.root) {
                    return FolderEvent(path: path, flags: event.flags)
                }
            }
            return nil
        }
        if !mapped.isEmpty { handler(mapped) }
    }

    static func flags(_ raw: FSEventStreamEventFlags) -> FolderEvent.Flags {
        var flags: FolderEvent.Flags = []
        let value = Int(raw)
        if value & kFSEventStreamEventFlagItemCreated != 0 { flags.insert(.created) }
        if value & kFSEventStreamEventFlagItemRemoved != 0 { flags.insert(.removed) }
        if value & kFSEventStreamEventFlagItemRenamed != 0 { flags.insert(.renamed) }
        if value & (kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod) != 0 { flags.insert(.modified) }
        if value & kFSEventStreamEventFlagItemIsFile != 0 { flags.insert(.isFile) }
        if value & kFSEventStreamEventFlagItemIsDir != 0 { flags.insert(.isDirectory) }
        if value & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 {
            flags.insert(.mustRescan)
        }
        if value & kFSEventStreamEventFlagRootChanged != 0 { flags.insert(.rootChanged) }
        return flags
    }
}

/// The library folders' scan, serialised: loads the cache, brings folders up to date, applies
/// FSEvents batches. Everything slow happens here, off the main actor.
public actor FolderLibrary {
    private var scan: LibraryScan
    private let fileSystem: any LibraryFileSystem
    private var dirty = false

    public init(scan: LibraryScan = LibraryScan(), fileSystem: any LibraryFileSystem = LocalLibraryFileSystem()) {
        self.scan = scan
        self.fileSystem = fileSystem
    }

    public struct Snapshot: Sendable {
        /// Faces in the folders that are online.
        public var faces: [SystemFace]
        /// Library folder path → its sidebar tree (online folders only).
        public var trees: [String: FolderNode]
        public var offline: Set<String>
        public var unreadable: [String: Int]
        public var change: LibraryChange
    }

    public func load(from url: URL) {
        scan = LibraryScan.load(from: url)
    }

    /// Cached faces, before anything is checked (shown at launch).
    public func cached(roots: [String]) -> Snapshot {
        snapshot(roots: roots, change: LibraryChange())
    }

    /// Checks every folder against the disk (a stat per file; only changed files are read).
    public func sync(roots: [String]) -> Snapshot {
        var change = LibraryChange()
        for root in roots where fileSystem.directoryExists(root) {
            change.merge(scan.rescan(root, fileSystem: fileSystem))
        }
        if !change.isEmpty { dirty = true }
        return snapshot(roots: roots, change: change)
    }

    public func apply(_ events: [FolderEvent], roots: [String]) -> Snapshot {
        let change = scan.apply(events, roots: roots, fileSystem: fileSystem)
        if !change.isEmpty { dirty = true }
        return snapshot(roots: roots, change: change)
    }

    public func remove(_ root: String, roots: [String]) -> Snapshot {
        let change = scan.remove(root)
        if !change.isEmpty { dirty = true }
        return snapshot(roots: roots, change: change)
    }

    /// Writes the cache if anything changed since the last save.
    public func saveIfNeeded(to url: URL) {
        guard dirty else { return }
        dirty = false
        try? scan.save(to: url)
    }

    private func snapshot(roots: [String], change: LibraryChange) -> Snapshot {
        let online = roots.filter { fileSystem.directoryExists($0) }
        var trees: [String: FolderNode] = [:]
        var unreadable: [String: Int] = [:]
        for root in online {
            let paths = scan.paths(in: root)
            trees[root] = FolderNode.tree(root: root, files: paths)
            unreadable[root] = scan.unreadableCount(in: root)
        }
        return Snapshot(faces: scan.faces(in: online), trees: trees, offline: Set(roots).subtracting(online),
                        unreadable: unreadable, change: change)
    }
}
