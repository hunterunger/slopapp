import Darwin
import Foundation
import os

/// What the map knows about a node, beyond its size.
public struct MapFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let directory = MapFlags(rawValue: 1 << 0)
    /// An app, library or other bundle: one item, contents not listed.
    public static let package = MapFlags(rawValue: 1 << 1)
    /// Its size won't change any more (it and everything inside it was read).
    public static let final = MapFlags(rawValue: 1 << 2)
    /// Something inside couldn't be read: the size is a lower bound ("+").
    public static let partial = MapFlags(rawValue: 1 << 3)
    /// A file with more than one name (hard links). Counted once, at the first name reached.
    public static let hardLinked = MapFlags(rawValue: 1 << 4)
    /// Another name of a hard-linked file, or a later member of a clone group: counted 0 here.
    public static let countedElsewhere = MapFlags(rawValue: 1 << 5)
    /// Shares all its blocks with other files (an APFS clone group).
    public static let clone = MapFlags(rawValue: 1 << 6)
    /// A cloud placeholder (iCloud Drive and other File Provider folders): not downloaded.
    public static let dataless = MapFlags(rawValue: 1 << 7)
    /// macOS may delete it on its own when it needs room.
    public static let purgeable = MapFlags(rawValue: 1 << 8)
    public static let sparse = MapFlags(rawValue: 1 << 9)
    public static let compressed = MapFlags(rawValue: 1 << 10)
    /// Shares some blocks with other files (a clone that has since changed).
    public static let partialClone = MapFlags(rawValue: 1 << 11)
    /// Left out on purpose (protected folder without Full Disk Access).
    public static let excluded = MapFlags(rawValue: 1 << 12)
    /// This folder itself couldn't be read.
    public static let unreadable = MapFlags(rawValue: 1 << 13)
    public static let symlink = MapFlags(rawValue: 1 << 14)
    /// Moved to the Trash since the scan (sizes above it already subtract it).
    public static let removed = MapFlags(rawValue: 1 << 15)
    /// Listed from inside a package (Show Package Contents): read-only.
    public static let insidePackage = MapFlags(rawValue: 1 << 16)
}

/// One node: 64 bytes. Names live in one shared byte arena.
public struct MapNode: Sendable {
    /// Space on disk counted here, whole subtree (running total while scanning).
    public var size: Int64 = 0
    /// File size (logical), whole subtree.
    public var logical: Int64 = 0
    /// Folders: space taken by files too small to list on their own. Files: the size on
    /// disk the file reports (differs from `size` when it's counted elsewhere).
    public var aux: Int64 = 0
    public var fileID: UInt64 = 0
    public var parent: UInt32 = MapNode.none
    public var childStart: UInt32 = 0
    public var childCount: UInt32 = 0
    /// Folders: how many files are folded into `aux`.
    public var otherCount: UInt32 = 0
    /// Files in the subtree.
    public var itemCount: UInt32 = 0
    /// Reads and child folders still outstanding (0 = final).
    public var pending: UInt32 = 0
    public var nameOffset: UInt32 = 0
    /// Flags in the low 24 bits, the name's length (≤ 255 bytes, `NAME_MAX`) in the top 8.
    private var packed: UInt32 = 0

    public var flags: MapFlags {
        get { MapFlags(rawValue: packed & 0x00FF_FFFF) }
        set { packed = (packed & 0xFF00_0000) | (newValue.rawValue & 0x00FF_FFFF) }
    }

    public var nameLength: Int {
        get { Int(packed >> 24) }
        set { packed = (packed & 0x00FF_FFFF) | (UInt32(min(255, max(0, newValue))) << 24) }
    }

    public static let none = UInt32.max

    public var isDirectory: Bool { flags.contains(.directory) }
    public var isFinal: Bool { flags.contains(.final) }
}

/// Cloud placeholders found under a folder (not downloaded, so they take ~0 on disk).
public struct CloudTally: Sendable, Equatable {
    public var count: Int = 0
    public var bytes: Int64 = 0
    public init(count: Int = 0, bytes: Int64 = 0) {
        self.count = count
        self.bytes = bytes
    }
}

/// A plain unfair lock, for the scanner's hot paths.
final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t
    init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }
    deinit { pointer.deallocate() }
    @inline(__always) func lock() { os_unfair_lock_lock(pointer) }
    @inline(__always) func unlock() { os_unfair_lock_unlock(pointer) }
    @inline(__always) func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// The whole map in a few flat arrays: every folder, but only the biggest files of each
/// (the rest are folded into a per-folder total). Shared between the scanner threads and the
/// UI; every access takes the lock, and the UI only ever copies small snapshots out.
public final class MapStore: @unchecked Sendable {
    let lock = UnfairLock()
    /// 65,536 nodes (4 MB) per chunk.
    let nodes = Chunks<MapNode>(shift: 16)
    /// 1 MB per chunk.
    let names = Chunks<UInt8>(shift: 20)
    /// Hard-linked files' name counts (only for listed ones).
    var linkCounts: [UInt32: UInt32] = [:]
    /// Placeholders not downloaded, per folder (aggregated upwards).
    var cloud: [UInt32: CloudTally] = [:]
    /// Folders that couldn't be read, per folder (aggregated upwards).
    var unreadable: [UInt32: UInt32] = [:]
    /// Bumped on every change, so the UI knows when to refresh.
    private(set) var versionStorage: UInt64 = 0
    /// Entries looked at so far (files and folders).
    var visited: Int = 0
    /// The device the scan stays on.
    public let device: Int32

    public static let root: UInt32 = 0

    public init(rootName: String, device: Int32, fileID: UInt64) {
        self.device = device
        var node = MapNode()
        node.flags = [.directory]
        node.fileID = fileID
        node.pending = 1
        nodes.append(node)
        setName(0, Array(rootName.utf8))
    }

    // MARK: Writing (scanner, under the lock)

    func setName(_ index: UInt32, _ bytes: [UInt8]) {
        let bytes = Array(bytes.prefix(255))
        let offset = bytes.withUnsafeBufferPointer { names.appendContiguous($0) }
        nodes[Int(index)].nameOffset = UInt32(offset)
        nodes[Int(index)].nameLength = bytes.count
    }

    func appendNode(_ node: MapNode, name: UnsafeBufferPointer<UInt8>) -> UInt32 {
        var node = node
        let name = UnsafeBufferPointer(rebasing: name.prefix(255))
        node.nameOffset = UInt32(names.appendContiguous(name))
        node.nameLength = name.count
        return UInt32(nodes.append(node))
    }

    /// Adds to a node and every folder above it.
    func addUp(from index: UInt32, size: Int64, logical: Int64, items: UInt32) {
        guard size != 0 || logical != 0 || items != 0 else { return }
        var i = index
        while i != MapNode.none {
            nodes[Int(i)].size &+= size
            nodes[Int(i)].logical &+= logical
            nodes[Int(i)].itemCount &+= items
            i = nodes[Int(i)].parent
        }
    }

    func subtractUp(from index: UInt32, size: Int64, logical: Int64, items: UInt32) {
        var i = index
        while i != MapNode.none {
            nodes[Int(i)].size = max(0, nodes[Int(i)].size - size)
            nodes[Int(i)].logical = max(0, nodes[Int(i)].logical - logical)
            nodes[Int(i)].itemCount = nodes[Int(i)].itemCount >= items ? nodes[Int(i)].itemCount - items : 0
            i = nodes[Int(i)].parent
        }
    }

    func markPartialUp(from index: UInt32) {
        var i = index
        while i != MapNode.none, !nodes[Int(i)].flags.contains(.partial) {
            nodes[Int(i)].flags.insert(.partial)
            i = nodes[Int(i)].parent
        }
    }

    func addCloudUp(from index: UInt32, _ tally: CloudTally) {
        guard tally.count > 0 else { return }
        var i = index
        while i != MapNode.none {
            cloud[i, default: CloudTally()].count += tally.count
            cloud[i, default: CloudTally()].bytes += tally.bytes
            i = nodes[Int(i)].parent
        }
    }

    func addUnreadableUp(from index: UInt32, _ count: UInt32) {
        guard count > 0 else { return }
        var i = index
        while i != MapNode.none {
            unreadable[i, default: 0] += count
            i = nodes[Int(i)].parent
        }
    }

    /// One read or child finished under `index`; finalizes it (and folders above) when
    /// nothing is left.
    func settle(_ index: UInt32) {
        var i = index
        while i != MapNode.none {
            let pending = nodes[Int(i)].pending
            nodes[Int(i)].pending = pending > 0 ? pending - 1 : 0
            guard nodes[Int(i)].pending == 0 else { return }
            nodes[Int(i)].flags.insert(.final)
            i = nodes[Int(i)].parent
        }
    }

    func bump() { versionStorage &+= 1 }

    /// After the walk. Chunks have no growth slack to give back; kept so callers don't care.
    public func trim() {}

    // MARK: Reading

    public var version: UInt64 { lock.withLock { versionStorage } }

    public var count: Int { lock.withLock { nodes.count } }

    public func node(_ index: UInt32) -> MapNode { lock.withLock { nodes[Int(index)] } }

    public func name(_ index: UInt32) -> String { lock.withLock { nameLocked(index) } }

    func nameLocked(_ index: UInt32) -> String {
        let node = nodes[Int(index)]
        return String(decoding: UnsafeBufferPointer(start: names.pointer(Int(node.nameOffset)), count: node.nameLength),
                      as: UTF8.self)
    }

    /// Names from the root (excluded) down to `index`.
    public func components(_ index: UInt32) -> [String] {
        lock.withLock {
            var parts: [String] = []
            var i = index
            while i != MapStore.root, i != MapNode.none {
                parts.append(nameLocked(i))
                i = nodes[Int(i)].parent
            }
            return parts.reversed()
        }
    }

    public func children(_ index: UInt32) -> [UInt32] {
        lock.withLock {
            let node = nodes[Int(index)]
            return (0..<node.childCount).map { node.childStart + $0 }
        }
    }

    /// The node at `components` below the root, if it's listed.
    public func find(_ components: [String]) -> UInt32? {
        lock.withLock {
            var current = MapStore.root
            for part in components {
                let wanted = Array(part.utf8)
                let node = nodes[Int(current)]
                var found: UInt32?
                for c in 0..<node.childCount {
                    let child = nodes[Int(node.childStart + c)]
                    guard child.nameLength == wanted.count else { continue }
                    if wanted.withUnsafeBytes({ memcmp($0.baseAddress, names.pointer(Int(child.nameOffset)), wanted.count) }) == 0 {
                        found = node.childStart + c
                        break
                    }
                }
                guard let next = found else { return nil }
                current = next
            }
            return current
        }
    }

    public func linkCount(_ index: UInt32) -> UInt32? { lock.withLock { linkCounts[index] } }
    public func cloudTally(_ index: UInt32) -> CloudTally? { lock.withLock { cloud[index] } }
    public func unreadableCount(_ index: UInt32) -> Int { lock.withLock { Int(unreadable[index] ?? 0) } }

    /// Items looked at and space found so far.
    public var progress: (items: Int, bytes: Int64) { lock.withLock { (visited, nodes[0].size) } }

    /// Memory the store holds (nodes, names and the sparse tables), for the budgets.
    public var approximateBytes: Int {
        lock.withLock {
            nodes.mappedBytes + names.mappedBytes
                + (linkCounts.capacity + unreadable.capacity) * 16 + cloud.capacity * 32
        }
    }

    // MARK: Changes after the scan (moves to the Trash and Put Back)

    /// Marks a node moved to the Trash and takes its size out of every folder above it.
    /// Returns false if it already was.
    @discardableResult
    public func markRemoved(_ index: UInt32) -> Bool {
        lock.withLock {
            let node = nodes[Int(index)]
            guard !node.flags.contains(.removed) else { return false }
            nodes[Int(index)].flags.insert(.removed)
            subtractUp(from: node.parent, size: node.size, logical: node.logical, items: node.itemCount)
            bump()
            return true
        }
    }

    /// Undoes `markRemoved` (Put Back).
    @discardableResult
    public func restore(_ index: UInt32) -> Bool {
        lock.withLock {
            let node = nodes[Int(index)]
            guard node.flags.contains(.removed) else { return false }
            nodes[Int(index)].flags.remove(.removed)
            addUp(from: node.parent, size: node.size, logical: node.logical, items: node.itemCount)
            bump()
            return true
        }
    }

    /// Files from a folder's "smaller items" were moved to the Trash (`restoring` false) or
    /// put back (true).
    public func adjustSmallItems(in folder: UInt32, size: Int64, logical: Int64, count: Int, restoring: Bool) {
        lock.withLock {
            let n = UInt32(max(0, count))
            if restoring {
                nodes[Int(folder)].aux += size
                nodes[Int(folder)].otherCount += n
                addUp(from: folder, size: size, logical: logical, items: n)
            } else {
                nodes[Int(folder)].aux = max(0, nodes[Int(folder)].aux - size)
                nodes[Int(folder)].otherCount -= min(nodes[Int(folder)].otherCount, n)
                subtractUp(from: folder, size: size, logical: logical, items: n)
            }
            bump()
        }
    }

    /// Whether `index` is `ancestor` or inside it.
    public func isInside(_ index: UInt32, _ ancestor: UInt32) -> Bool {
        lock.withLock { isInsideLocked(index, ancestor) }
    }

    func isInsideLocked(_ index: UInt32, _ ancestor: UInt32) -> Bool {
        var i = index
        while i != MapNode.none {
            if i == ancestor { return true }
            i = nodes[Int(i)].parent
        }
        return false
    }
}
