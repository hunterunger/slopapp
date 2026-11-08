import Darwin
import Foundation
import UniformTypeIdentifiers

/// How a map scan walks.
public struct MapScanOptions: Sendable {
    /// The folder walked (the Data volume for the startup disk).
    public var root: String
    /// Folders not entered (protected ones without Full Disk Access, the Trash in test mode).
    /// They're listed as locked, partial rows so the totals explain themselves.
    public var excluded: Set<String>
    /// Folders skipped without a trace, like mount points (other disks' stand-ins in test
    /// mode).
    public var skipped: Set<String>
    /// Worker threads.
    public var threads: Int
    /// Each folder lists at most this many files on its own...
    public var keptFiles: Int
    /// ...and only files at least this big. The rest go into the folder's smaller-items total.
    public var minimumListedSize: Int64

    public init(root: String, excluded: Set<String> = [], skipped: Set<String> = [],
                threads: Int = MapScanOptions.defaultThreads, keptFiles: Int = 64, minimumListedSize: Int64 = 1_000_000) {
        self.root = Self.normalized(root)
        self.excluded = Set(excluded.map(Self.normalized))
        self.skipped = Set(skipped.map(Self.normalized))
        self.threads = max(1, threads)
        self.keptFiles = keptFiles
        self.minimumListedSize = minimumListedSize
    }

    /// 3–6 by core count: past that the threads mostly wait on each other.
    public static var defaultThreads: Int {
        min(6, max(3, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    static func normalized(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}

public enum MapScanOutcome: Sendable, Equatable {
    case finished
    /// Stopped before the end: what was counted is kept, unfinished folders aren't final.
    case stopped
}

public enum MapScanError: Error, Equatable, Sendable {
    case notFound
    case notAFolder
    case unreadable(DirectoryReadError)
}

/// Keys for counting hard links and clones once, with the folder that counted them (so a
/// rescan of that folder can count them again).
struct LinkKey: Hashable {
    var device: Int32
    var fileID: UInt64
}

final class SeenTable: @unchecked Sendable {
    let lock = UnfairLock()
    var links: [LinkKey: UInt32] = [:]
    var clones: [UInt64: UInt32] = [:]

    /// True if this is the first time the hard-linked file is seen.
    func firstLink(_ key: LinkKey, owner: UInt32) -> Bool {
        lock.withLock {
            guard links[key] == nil else { return false }
            links[key] = owner
            return true
        }
    }

    func firstClone(_ id: UInt64, owner: UInt32) -> Bool {
        lock.withLock {
            guard clones[id] == nil else { return false }
            clones[id] = owner
            return true
        }
    }

    func forget(where inside: (UInt32) -> Bool) {
        lock.withLock {
            links = links.filter { !inside($0.value) }
            clones = clones.filter { !inside($0.value) }
        }
    }
}

/// A folder waiting to be read.
struct WorkItem {
    /// The node it belongs to (the folder itself, or the package it's inside).
    var node: UInt32
    var path: String
    /// Create nodes for what's inside (false inside packages: their contents only add up).
    var createsNodes: Bool
    /// Nodes created below get `.insidePackage` (Show Package Contents).
    var marksInsidePackage: Bool
}

/// The parallel space-map walk: several dedicated threads, each reading whole folders with
/// one bulk call at a time and committing each folder to the shared store in one step.
///
/// - Totals roll up as each folder is read, so the map can draw while it scans; a folder is
///   final once its own read and every folder inside it are done.
/// - Hard links and full clones count once (first one reached); later ones are listed with
///   their size greyed.
/// - Cloud placeholders are never downloaded: the threads turn that off for themselves
///   (`DirectoryReader.prepareThread`).
/// - It never leaves the volume it started on and never follows symlinks.
public final class MapScanner<Reader: DirectoryReader>: @unchecked Sendable {
    public let store: MapStore
    public let options: MapScanOptions
    let reader: Reader
    let seen: SeenTable

    private let condition = NSCondition()
    private var stack: [WorkItem] = []
    private var outstanding = 0
    private var cancelled = false
    private var runningThreads = 0
    private var outcome: MapScanOutcome?
    private var onFinish: (@Sendable (MapScanOutcome) -> Void)?
    private let stopFlag = StopFlag()

    /// Starts a new map of `options.root`.
    public init(reader: Reader, options: MapScanOptions) throws(MapScanError) {
        guard let info = reader.info(options.root) else { throw .notFound }
        guard info.kind == .directory else { throw .notAFolder }
        self.reader = reader
        self.options = options
        let name = options.root == "/" ? "/" : (options.root as NSString).lastPathComponent
        store = MapStore(rootName: name, device: info.device, fileID: info.fileID)
        seen = SeenTable()
        stack = [WorkItem(node: MapStore.root, path: options.root, createsNodes: true, marksInsidePackage: false)]
        outstanding = 1
    }

    /// Re-walks one folder of an existing map and splices the result in (Rescan This
    /// Folder), or lists a package's contents (`showPackageContents`, read-only). The old
    /// totals come out of every folder above it first.
    public init(rescanning node: UInt32, at path: String, in store: MapStore, seen previous: MapScanner?,
                reader: Reader, options: MapScanOptions, showPackageContents: Bool = false) {
        self.reader = reader
        self.options = options
        self.store = store
        seen = previous?.seen ?? SeenTable()
        store.lock.withLock {
            let old = store.nodes[Int(node)]
            store.subtractUp(from: old.parent, size: old.size, logical: old.logical, items: old.itemCount)
            if let tally = store.cloud[node] {
                var i = old.parent
                while i != MapNode.none {
                    store.cloud[i]?.count -= tally.count
                    store.cloud[i]?.bytes -= tally.bytes
                    i = store.nodes[Int(i)].parent
                }
            }
            if let count = store.unreadable[node] {
                var i = old.parent
                while i != MapNode.none {
                    store.unreadable[i] = (store.unreadable[i] ?? count) - count
                    i = store.nodes[Int(i)].parent
                }
            }
            store.cloud = store.cloud.filter { !store.isInsideLocked($0.key, node) }
            store.unreadable = store.unreadable.filter { !store.isInsideLocked($0.key, node) }
            // Folders above that were final wait for this one again.
            if old.isFinal {
                var i = old.parent
                while i != MapNode.none {
                    let wasFinal = store.nodes[Int(i)].isFinal
                    store.nodes[Int(i)].pending += 1
                    store.nodes[Int(i)].flags.remove(.final)
                    guard wasFinal else { break }
                    i = store.nodes[Int(i)].parent
                }
            }
            var fresh = old
            fresh.size = 0
            fresh.logical = 0
            fresh.aux = 0
            fresh.childCount = 0
            fresh.otherCount = 0
            fresh.itemCount = 0
            fresh.pending = 1
            fresh.flags.subtract([.final, .partial, .unreadable, .removed])
            store.nodes[Int(node)] = fresh
            store.bump()
        }
        seen.forget { store.isInside($0, node) }
        let insidePackage = showPackageContents || store.node(node).flags.contains(.insidePackage)
        let createsNodes = showPackageContents || !store.node(node).flags.contains(.package)
        stack = [WorkItem(node: node, path: MapScanOptions.normalized(path), createsNodes: createsNodes,
                          marksInsidePackage: insidePackage)]
        outstanding = 1
    }

    /// Starts the threads. `onFinish` runs once, on a scanner thread, when the walk ends or
    /// has stopped.
    public func start(onFinish: (@Sendable (MapScanOutcome) -> Void)? = nil) {
        condition.lock()
        self.onFinish = onFinish
        runningThreads = options.threads
        condition.unlock()
        for index in 0..<options.threads {
            let thread = Thread { [self] in work() }
            thread.name = "Tidy map scanner \(index + 1)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// Stops soon (within one bulk read per thread). What was counted stays in the store.
    public func cancel() {
        stopFlag.set()
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks until the threads are done. For the command line tool and tests.
    @discardableResult
    public func wait() -> MapScanOutcome {
        condition.lock()
        while outcome == nil { condition.wait() }
        let result = outcome!
        condition.unlock()
        return result
    }

    public var isRunning: Bool {
        condition.lock()
        defer { condition.unlock() }
        return outcome == nil
    }

    // MARK: Workers

    private func work() {
        reader.prepareThread()
        var context = WorkerContext(options: options)
        while true {
            condition.lock()
            while stack.isEmpty && outstanding > 0 && !cancelled { condition.wait() }
            if cancelled || stack.isEmpty {
                finishThread()
                return
            }
            let item = stack.removeLast()
            condition.unlock()

            let spawned = process(item, &context)

            condition.lock()
            stack.append(contentsOf: spawned)
            outstanding += spawned.count - 1
            if !spawned.isEmpty || outstanding == 0 { condition.broadcast() }
            condition.unlock()
        }
    }

    /// Called with the condition locked; unlocks it.
    private func finishThread() {
        runningThreads -= 1
        condition.broadcast()
        guard runningThreads == 0 else {
            condition.unlock()
            return
        }
        let result: MapScanOutcome = cancelled && outstanding > 0 ? .stopped : .finished
        outcome = result
        let finish = onFinish
        onFinish = nil
        condition.broadcast()
        condition.unlock()
        store.trim()
        store.lock.withLock { store.bump() }
        finish?(result)
    }

    /// A file that might be listed on its own. Its name is a range of the worker's pool, so
    /// no per-file allocation (the walk sees millions of files).
    struct Candidate {
        var name: Range<Int>
        var node: MapNode
        var linkCount: UInt32
    }

    struct Subfolder {
        var name: Range<Int>
        var node: MapNode
        var read: Bool
    }

    struct WorkerContext {
        let options: MapScanOptions
        var packageExtensions: [String: Bool] = [:]
        // Reused per folder.
        var candidates: [Candidate] = []
        var folders: [Subfolder] = []
        var pool: [UInt8] = []

        init(options: MapScanOptions) { self.options = options }

        mutating func keep(_ name: UnsafeBufferPointer<UInt8>) -> Range<Int> {
            let start = pool.count
            pool.append(contentsOf: name)
            return start..<pool.count
        }

        /// Swapped-out candidates leave their names behind; squeeze them out now and then.
        mutating func compactPool() {
            guard pool.count > 1 << 16 else { return }
            var fresh: [UInt8] = []
            fresh.reserveCapacity(pool.count / 2)
            for i in folders.indices {
                let start = fresh.count
                fresh.append(contentsOf: pool[folders[i].name])
                folders[i].name = start..<fresh.count
            }
            for i in candidates.indices {
                let start = fresh.count
                fresh.append(contentsOf: pool[candidates[i].name])
                candidates[i].name = start..<fresh.count
            }
            pool = fresh
        }

        mutating func isPackage(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
            guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0, dot < name.count - 1 else { return false }
            let ext = String(decoding: UnsafeBufferPointer(rebasing: name[(dot + 1)...]), as: UTF8.self).lowercased()
            if let known = packageExtensions[ext] { return known }
            let type = UTType(filenameExtension: ext, conformingTo: .directory)
            let value = type.map { $0.conforms(to: .package) || $0.conforms(to: .bundle) } ?? false
            packageExtensions[ext] = value
            return value
        }
    }

    private func process(_ item: WorkItem, _ context: inout WorkerContext) -> [WorkItem] {
        context.candidates.removeAll(keepingCapacity: true)
        context.folders.removeAll(keepingCapacity: true)
        context.pool.removeAll(keepingCapacity: context.pool.capacity <= 1 << 16)
        let device = store.device
        let account = item.node
        let keep = item.createsNodes ? options.keptFiles : 0
        let minimum = options.minimumListedSize
        var bytes: Int64 = 0
        var logical: Int64 = 0
        var files: UInt32 = 0
        var visited = 0
        var otherSize: Int64 = 0
        var otherCount: UInt32 = 0
        var cloud = CloudTally()
        var unreadableEntries: UInt32 = 0
        var internalFolders: [String] = []
        // The smallest kept candidate, for the top-K test (candidates stay unsorted).
        var smallestKept = Int64.max
        let parentPath = item.path == "/" ? "" : item.path
        let inheritedFlags: MapFlags = item.marksInsidePackage ? [.insidePackage] : []

        let failure = reader.read(item.path, shouldStop: { stopFlag.isSet }) { entry in
            visited += 1
            if entry.error != 0 {
                if entry.error == EACCES || entry.error == EPERM { unreadableEntries += 1 }
                return
            }
            if entry.kind == .directory {
                // Never cross into another volume (mount points, disk images mounted inside).
                if entry.isMountPoint || entry.device != device { return }
                let path = parentPath + "/" + String(decoding: entry.name, as: UTF8.self)
                if !options.skipped.isEmpty, options.skipped.contains(path) { return }
                bytes += entry.allocated
                if !item.createsNodes {
                    if entry.isDataless { cloud.count += 1 } else { internalFolders.append(path) }
                    return
                }
                var node = MapNode()
                node.flags = inheritedFlags.union(.directory)
                node.fileID = entry.fileID
                node.parent = account
                var read = true
                if entry.isDataless {
                    node.flags.formUnion([.dataless, .final])
                    cloud.count += 1
                    read = false
                } else if options.excluded.contains(path) {
                    node.flags.formUnion([.excluded, .partial, .final])
                    read = false
                } else {
                    if !item.marksInsidePackage, context.isPackage(entry.name) { node.flags.insert(.package) }
                    node.pending = 1
                }
                context.folders.append(Subfolder(name: context.keep(entry.name), node: node, read: read))
                return
            }

            // Files, symlinks and anything else.
            var counted = entry.allocated
            var flags = inheritedFlags
            if entry.kind == .symlink { flags.insert(.symlink) }
            if entry.kind == .file {
                if entry.linkCount > 1 {
                    flags.insert(.hardLinked)
                    if !seen.firstLink(LinkKey(device: entry.device, fileID: entry.fileID), owner: account) {
                        counted = 0
                        flags.insert(.countedElsewhere)
                    }
                }
                if entry.sharesAllBlocks, entry.cloneID != 0 {
                    flags.insert(.clone)
                    if counted > 0, !seen.firstClone(entry.cloneID, owner: account) {
                        counted = 0
                        flags.insert(.countedElsewhere)
                    }
                } else if entry.maySharePartly {
                    flags.insert(.partialClone)
                }
                if entry.isDataless {
                    flags.insert(.dataless)
                    cloud.count += 1
                    cloud.bytes += entry.logical
                }
                if entry.isPurgeable { flags.insert(.purgeable) }
                if entry.isSparse { flags.insert(.sparse) }
                if entry.isCompressed { flags.insert(.compressed) }
            }
            bytes += counted
            logical += entry.logical
            files += 1

            guard keep > 0, entry.allocated >= minimum else {
                otherSize += counted
                otherCount += 1
                return
            }
            var node = MapNode()
            node.size = counted
            node.logical = entry.logical
            node.aux = entry.allocated
            node.fileID = entry.fileID
            node.parent = account
            node.itemCount = 1
            node.flags = flags.union(.final)
            if context.candidates.count < keep {
                context.candidates.append(Candidate(name: context.keep(entry.name), node: node, linkCount: entry.linkCount))
                smallestKept = min(smallestKept, entry.allocated)
            } else if entry.allocated > smallestKept {
                context.compactPool()
                let candidate = Candidate(name: context.keep(entry.name), node: node, linkCount: entry.linkCount)
                // Swap out the smallest kept one; it joins the folded total.
                let index = context.candidates.indices.min { context.candidates[$0].node.aux < context.candidates[$1].node.aux }!
                otherSize += context.candidates[index].node.size
                otherCount += 1
                context.candidates[index] = candidate
                smallestKept = context.candidates.map(\.node.aux).min() ?? Int64.max
            } else {
                otherSize += counted
                otherCount += 1
            }
        }

        // Stopped during (or right after) this read: keep what was counted, but the folder
        // isn't complete, so it never becomes final and nothing below it is queued.
        let interrupted = stopFlag.isSet
        var spawned: [WorkItem] = []
        store.lock.withLock {
            store.visited += visited
            if item.createsNodes {
                let start = UInt32(store.nodes.count)
                for folder in context.folders {
                    let index = context.pool.withUnsafeBufferPointer {
                        store.appendNode(folder.node, name: UnsafeBufferPointer(rebasing: $0[folder.name]))
                    }
                    if folder.node.flags.contains(.excluded) {
                        store.markPartialUp(from: account)
                    }
                    if folder.read {
                        let name = String(decoding: context.pool[folder.name], as: UTF8.self)
                        spawned.append(WorkItem(node: index, path: parentPath + "/" + name,
                                                createsNodes: !folder.node.flags.contains(.package) || item.marksInsidePackage,
                                                marksInsidePackage: item.marksInsidePackage))
                    }
                }
                for candidate in context.candidates {
                    let index = context.pool.withUnsafeBufferPointer {
                        store.appendNode(candidate.node, name: UnsafeBufferPointer(rebasing: $0[candidate.name]))
                    }
                    if candidate.linkCount > 1 { store.linkCounts[index] = candidate.linkCount }
                }
                let added = UInt32(store.nodes.count) - start
                // A folder is read once; on a rescan its old children are simply left behind.
                store.nodes[Int(account)].childStart = start
                store.nodes[Int(account)].childCount = added
                store.nodes[Int(account)].aux += otherSize
                store.nodes[Int(account)].otherCount += otherCount
                // Kept files' sizes are added with the rest below; their nodes start final.
                store.nodes[Int(account)].pending += UInt32(spawned.count)
            } else {
                for path in internalFolders {
                    spawned.append(WorkItem(node: account, path: path, createsNodes: false, marksInsidePackage: false))
                }
                store.nodes[Int(account)].pending += UInt32(spawned.count)
            }
            store.addUp(from: account, size: bytes, logical: logical, items: files)
            store.addCloudUp(from: account, cloud)
            if let failure {
                switch failure {
                case .dataless:
                    store.nodes[Int(account)].flags.insert(.dataless)
                    store.addCloudUp(from: account, CloudTally(count: 1, bytes: 0))
                case .vanished:
                    break
                default:
                    if item.node == account { store.nodes[Int(account)].flags.insert(.unreadable) }
                    store.markPartialUp(from: account)
                    store.addUnreadableUp(from: account, 1)
                }
            }
            if unreadableEntries > 0 { store.markPartialUp(from: account) }
            if !interrupted { store.settle(account) }
            store.bump()
        }
        return interrupted ? [] : spawned
    }
}

/// A flag the reader polls between bulk reads.
final class StopFlag: @unchecked Sendable {
    private let lock = UnfairLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
