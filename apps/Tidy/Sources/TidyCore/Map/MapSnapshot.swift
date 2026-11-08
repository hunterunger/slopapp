import Foundation

/// One row of the list or tile of the map: a copy of a node, or a virtual item (smaller
/// items, the macOS system volume, space the map couldn't see).
public struct MapItem: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case folder, package, file, symlink
        /// "N smaller items" of a folder (a group, not a thing).
        case smaller
        /// The sealed macOS system volume (startup disk only).
        case system
        /// Used space the walk didn't find (other volumes, snapshots, unreadable folders).
        case notMapped
    }

    /// Path below the map's root, "/"-separated ("" for the root). Virtual items get a
    /// "#…" id that can't clash with a path.
    public var id: String
    public var node: UInt32?
    public var name: String
    public var kind: Kind
    /// Space on disk counted for it here.
    public var size: Int64
    /// The size on disk it reports (bigger than `size` when it's counted elsewhere).
    public var reported: Int64
    public var logical: Int64
    public var flags: MapFlags
    public var itemCount: Int
    /// Folders: files too small to list on their own.
    public var otherSize: Int64
    public var otherCount: Int
    public var childCount: Int
    public var fileID: UInt64

    public init(id: String, node: UInt32? = nil, name: String, kind: Kind, size: Int64, reported: Int64? = nil,
                logical: Int64 = 0, flags: MapFlags = [], itemCount: Int = 0, otherSize: Int64 = 0, otherCount: Int = 0,
                childCount: Int = 0, fileID: UInt64 = 0) {
        self.id = id
        self.node = node
        self.name = name
        self.kind = kind
        self.size = size
        self.reported = reported ?? size
        self.logical = logical
        self.flags = flags
        self.itemCount = itemCount
        self.otherSize = otherSize
        self.otherCount = otherCount
        self.childCount = childCount
        self.fileID = fileID
    }

    public var isVirtual: Bool { node == nil && kind != .file }
    public var isFolderLike: Bool { kind == .folder || kind == .package }
    /// Still being counted (its size can still grow).
    public var isCounting: Bool { node != nil && isFolderLike && !flags.contains(.final) }
    /// Its size is a lower bound ("+"): unreadable parts, or not finished.
    public var isLowerBound: Bool { flags.contains(.partial) || isCounting }
    /// Can be opened in the map.
    public var canOpen: Bool {
        switch kind {
        case .folder: childCount > 0 || otherCount > 0
        case .package: childCount > 0
        case .smaller: otherCount > 0
        default: false
        }
    }
    public var isApp: Bool { kind == .package && name.lowercased().hasSuffix(".app") }
}

/// What the map and list show for one folder: its items biggest first, and the biggest
/// items of each folder inside it (the map's second level).
public struct MapFolderSnapshot: Sendable, Equatable {
    public var folder: MapItem
    public var items: [MapItem]
    /// Second level, keyed by item id.
    public var nested: [String: [MapItem]]
    public var version: UInt64

    public init(folder: MapItem, items: [MapItem], nested: [String: [MapItem]] = [:], version: UInt64 = 0) {
        self.folder = folder
        self.items = items
        self.nested = nested
        self.version = version
    }
}

extension MapStore {
    func itemLocked(_ index: UInt32, id: String) -> MapItem {
        let node = nodes[Int(index)]
        let kind: MapItem.Kind = node.isDirectory
            ? (node.flags.contains(.package) ? .package : .folder)
            : (node.flags.contains(.symlink) ? .symlink : .file)
        return MapItem(id: id, node: index, name: nameLocked(index), kind: kind, size: node.size,
                       reported: node.isDirectory ? node.size : node.aux, logical: node.logical, flags: node.flags,
                       itemCount: Int(node.itemCount), otherSize: node.isDirectory ? node.aux : 0,
                       otherCount: node.isDirectory ? Int(node.otherCount) : 0, childCount: Int(node.childCount),
                       fileID: node.fileID)
    }

    func childrenLocked(_ index: UInt32, prefix: String, limit: Int) -> [MapItem] {
        let node = nodes[Int(index)]
        guard node.childCount > 0 else { return [] }
        var order = (node.childStart..<node.childStart + node.childCount).filter { !nodes[Int($0)].flags.contains(.removed) }
        order.sort { a, b in
            let sa = nodes[Int(a)].size, sb = nodes[Int(b)].size
            if sa != sb { return sa > sb }
            let ra = nodes[Int(a)].aux, rb = nodes[Int(b)].aux
            return ra != rb ? ra > rb : a < b
        }
        if order.count > limit { order.removeLast(order.count - limit) }
        let base = prefix.isEmpty ? "" : prefix + "/"
        return order.map { itemLocked($0, id: base + nameLocked($0)) }
    }

    /// The folder at `index` (whose id is `id`), its items and their biggest items. Cheap
    /// enough to call several times a second while scanning.
    public func snapshot(of index: UInt32, id: String, itemLimit: Int = 5_000, nestedFolders: Int = 200,
                         nestedItems: Int = 60) -> MapFolderSnapshot {
        lock.withLock {
            let folder = itemLocked(index, id: id)
            let items = childrenLocked(index, prefix: id, limit: itemLimit)
            var nested: [String: [MapItem]] = [:]
            for item in items.prefix(nestedFolders) where item.isFolderLike && item.childCount > 0 {
                guard let node = item.node else { continue }
                if item.kind == .package && !item.flags.contains(.insidePackage) && nodes[Int(node)].childCount == 0 { continue }
                nested[item.id] = childrenLocked(node, prefix: item.id, limit: nestedItems)
            }
            return MapFolderSnapshot(folder: folder, items: items, nested: nested, version: versionStorage)
        }
    }

    /// The node for a path below the root ("" is the root).
    public func find(id: String) -> UInt32? {
        id.isEmpty ? MapStore.root : find(id.split(separator: "/", omittingEmptySubsequences: true).map(String.init))
    }

    /// The id (path below the root) of a node.
    public func id(of index: UInt32) -> String { components(index).joined(separator: "/") }
}
