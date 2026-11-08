import Darwin
import Foundation
import TidyCore

/// An in-memory folder tree for the map's unit tests. Built with a tiny DSL:
///
///     var fs = FakeFileSystem(root: "/fake")
///     fs.file("Movies/clip.mov", size: 40_000_000)
///     fs.file("a/link1", size: 5_000_000, links: 2, id: 77)   // same id = same file
///     fs.deny("Private")                                       // unreadable folder
///     fs.dataless("iCloud/Book")                                // a cloud folder
///
/// Paths are relative to the root; parent folders are created as needed. Reads are
/// recorded, so tests can check what was (and wasn't) read.
public struct FakeFileSystem: DirectoryReader {
    public struct Item: Sendable {
        public var kind: EntryKind
        public var allocated: Int64 = 0
        public var logical: Int64 = 0
        public var flags: UInt32 = 0
        public var extFlags: UInt64 = 0
        public var device: Int32 = 1
        public var fileID: UInt64 = 0
        public var linkCount: UInt32 = 1
        public var cloneID: UInt64 = 0
        public var isMountPoint = false
        public var entryError: Int32 = 0
        public var readError: DirectoryReadError?
        public var children: [String] = []
    }

    public let root: String
    public private(set) var items: [String: Item]
    private var nextID: UInt64 = 100
    public let log = ReadLog()
    /// Sleep this long in each folder read (for stop tests).
    public var readDelay: TimeInterval = 0

    public init(root: String = "/fake") {
        self.root = root
        items = [root: Item(kind: .directory, fileID: 2)]
    }

    public func full(_ relative: String) -> String { relative.isEmpty ? root : root + "/" + relative }

    @discardableResult
    public mutating func dir(_ relative: String) -> String {
        let path = full(relative)
        guard items[path] == nil else { return path }
        let parent = (relative as NSString).deletingLastPathComponent
        let parentPath = dir(parent)
        nextID += 1
        items[path] = Item(kind: .directory, fileID: nextID)
        items[parentPath]!.children.append((relative as NSString).lastPathComponent)
        return path
    }

    /// A file. `size` is the space on disk; `logical` defaults to it.
    public mutating func file(_ relative: String, size: Int64, logical: Int64? = nil, links: UInt32 = 1, id: UInt64? = nil,
                              cloneID: UInt64 = 0, sharesAll: Bool = false, partialClone: Bool = false,
                              dataless: Bool = false, purgeable: Bool = false, sparse: Bool = false,
                              compressed: Bool = false, kind: EntryKind = .file, entryError: Int32 = 0) {
        let path = full(relative)
        let parentPath = dir((relative as NSString).deletingLastPathComponent)
        nextID += 1
        var item = Item(kind: kind)
        item.allocated = size
        item.logical = logical ?? size
        item.fileID = id ?? nextID
        item.linkCount = links
        item.cloneID = cloneID
        if sharesAll { item.extFlags |= UInt64(EF_SHARES_ALL_BLOCKS | EF_MAY_SHARE_BLOCKS) }
        if partialClone { item.extFlags |= UInt64(EF_MAY_SHARE_BLOCKS) }
        if purgeable { item.extFlags |= UInt64(EF_IS_PURGEABLE) }
        if sparse { item.extFlags |= UInt64(EF_IS_SPARSE) }
        if dataless { item.flags |= UInt32(SF_DATALESS) }
        if compressed { item.flags |= UInt32(UF_COMPRESSED) }
        item.entryError = entryError
        if items[path] == nil { items[parentPath]!.children.append((relative as NSString).lastPathComponent) }
        items[path] = item
    }

    /// Many files at once, named `prefix-0`, `prefix-1`...
    public mutating func files(_ folder: String, count: Int, size: Int64, prefix: String = "f") {
        for i in 0..<count { file(folder + "/" + "\(prefix)-\(i)", size: size) }
    }

    public mutating func deny(_ relative: String) {
        let path = dir(relative)
        items[path]!.readError = .denied
    }

    /// A cloud placeholder folder (`SF_DATALESS`): reading it would download it.
    public mutating func dataless(_ relative: String) {
        let path = dir(relative)
        items[path]!.flags |= UInt32(SF_DATALESS)
        items[path]!.readError = .dataless
    }

    /// Another volume mounted here (its contents must never be counted).
    public mutating func mountPoint(_ relative: String, contents: Int64 = 1_000_000_000) {
        let path = dir(relative)
        items[path]!.isMountPoint = true
        file(relative + "/huge.bin", size: contents)
        items[full(relative + "/huge.bin")]!.device = 9
    }

    /// A folder on another device without a mount flag (belt and braces).
    public mutating func otherDevice(_ relative: String) {
        let path = dir(relative)
        items[path]!.device = 7
    }

    public func prepareThread() {
        log.prepared()
    }

    public func info(_ path: String) -> ItemInfo? {
        guard let item = items[path] else { return nil }
        return ItemInfo(kind: item.kind, device: item.device, fileID: item.fileID, allocated: item.allocated, flags: item.flags)
    }

    public func read(_ path: String, shouldStop: () -> Bool, _ body: (RawEntry) -> Void) -> DirectoryReadError? {
        log.read(path)
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        guard let item = items[path] else { return .vanished }
        guard item.kind == .directory else { return .notDirectory }
        if let error = item.readError { return error }
        for name in item.children {
            guard let child = items[path + "/" + name] else { continue }
            var bytes = Array(name.utf8)
            bytes.withUnsafeMutableBufferPointer { buffer in
                body(RawEntry(name: UnsafeBufferPointer(buffer), kind: child.kind, allocated: child.allocated,
                              logical: child.logical, flags: child.flags, extFlags: child.extFlags, device: child.device,
                              fileID: child.fileID, linkCount: child.linkCount, cloneID: child.cloneID,
                              isMountPoint: child.isMountPoint, error: child.entryError))
            }
        }
        return nil
    }
}

/// What a fake reader was asked to do (shared across scanner threads).
public final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var threads = 0
    public init() {}
    func read(_ path: String) { lock.withLock { paths.append(path) } }
    func prepared() { lock.withLock { threads += 1 } }
    public var reads: [String] { lock.withLock { paths } }
    public var preparedThreads: Int { lock.withLock { threads } }
}

/// A big tree made up on the fly, so 5 million files can be "scanned" without touching the
/// disk or holding the tree in memory. Every folder has `fanout` subfolders down to `depth`,
/// and `filesPerFolder` files; every `bigEvery`th file is 2 MB, the rest 4 KB.
public struct GeneratedFileSystem: DirectoryReader {
    public let root: String
    public var fanout: Int
    public var depth: Int
    public var filesPerFolder: Int
    public var bigEvery: Int
    public var readDelay: TimeInterval = 0

    public init(root: String = "/generated", fanout: Int = 8, depth: Int = 6, filesPerFolder: Int = 17, bigEvery: Int = 7) {
        self.root = root
        self.fanout = fanout
        self.depth = depth
        self.filesPerFolder = filesPerFolder
        self.bigEvery = bigEvery
    }

    /// A tree with about `files` files (folders ≈ files / filesPerFolder).
    public static func sized(files: Int, filesPerFolder: Int = 17, fanout: Int = 8) -> GeneratedFileSystem {
        var depth = 0
        var folders = 1
        var level = 1
        while folders * filesPerFolder < files {
            depth += 1
            level *= fanout
            folders += level
        }
        let perFolder = max(1, Int((Double(files) / Double(folders)).rounded(.up)))
        return GeneratedFileSystem(fanout: fanout, depth: depth, filesPerFolder: perFolder)
    }

    public var folderCount: Int {
        var total = 1, level = 1
        for _ in 0..<depth { level *= fanout; total += level }
        return total
    }

    public var fileCount: Int { folderCount * filesPerFolder }

    public var expectedBytes: Int64 {
        let big = (0..<filesPerFolder).filter { bigEvery > 0 && $0 % bigEvery == bigEvery - 1 }.count
        return Int64(folderCount) * (Int64(big) * 2_000_000 + Int64(filesPerFolder - big) * 4_096)
    }

    public func prepareThread() {}

    public func info(_ path: String) -> ItemInfo? {
        path == root ? ItemInfo(kind: .directory, device: 1, fileID: 1) : nil
    }

    public func read(_ path: String, shouldStop: () -> Bool, _ body: (RawEntry) -> Void) -> DirectoryReadError? {
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        let level = path == root ? 0 : path.utf8.dropFirst(root.utf8.count).filter { $0 == UInt8(ascii: "/") }.count
        var id = UInt64(truncatingIfNeeded: path.hashValue) &* 1_000_003
        var name = [UInt8](repeating: 0, count: 32)
        func emit(_ text: String, _ kind: EntryKind, _ size: Int64) {
            var count = 0
            for byte in text.utf8 { name[count] = byte; count += 1 }
            id &+= 1
            name.withUnsafeBufferPointer { buffer in
                body(RawEntry(name: UnsafeBufferPointer(rebasing: buffer[0..<count]), kind: kind, allocated: size,
                              logical: size, fileID: id))
            }
        }
        if level < depth {
            for i in 0..<fanout { emit("folder-\(i)", .directory, 0) }
        }
        for i in 0..<filesPerFolder {
            if i % 512 == 511, shouldStop() { return nil }
            let big = bigEvery > 0 && i % bigEvery == bigEvery - 1
            emit("file-\(i).dat", .file, big ? 2_000_000 : 4_096)
        }
        return nil
    }
}
