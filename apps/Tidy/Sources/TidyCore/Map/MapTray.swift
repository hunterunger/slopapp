import Foundation

/// Something checked in the map, remembered by path so checks survive navigation and
/// rescans.
public struct CheckedItem: Sendable, Hashable, Identifiable {
    public var id: String { path }
    /// Full path (what's moved).
    public var path: String
    public var name: String
    /// Space on disk counted for it in the map.
    public var size: Int64
    public var isDirectory: Bool
    /// Identity at scan time, to notice if it changed before the move.
    public var device: Int32
    public var fileID: UInt64
    /// A hard link or clone: moving it frees nothing while the other copies exist.
    public var mayFreeNothing: Bool
    /// The folder it's in, for the tray ("in Downloads").
    public var folderName: String
    /// The folder above it with symlinks resolved, when it was checked: if that changes
    /// before the move, something was swapped in and the move is refused.
    public var resolvedParent: String

    public init(path: String, name: String, size: Int64, isDirectory: Bool, device: Int32, fileID: UInt64,
                mayFreeNothing: Bool = false, folderName: String = "", resolvedParent: String = "") {
        self.resolvedParent = resolvedParent
        self.path = path
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.device = device
        self.fileID = fileID
        self.mayFreeNothing = mayFreeNothing
        self.folderName = folderName
    }

    /// What moving it to the Trash and emptying it can give back, at most.
    public var freeable: Int64 { mayFreeNothing ? 0 : size }
}

public enum CheckOutcome: Sendable, Equatable {
    /// Checked; `absorbed` items inside it were checked before and are now covered by it.
    case checked(absorbed: Int)
    /// Refused: a checked folder already contains it (named here).
    case insideChecked(String)
    case alreadyChecked
}

/// The checked-items tray. Rules (each unit-tested):
/// - Checking a folder absorbs anything checked inside it, so nothing is counted or moved
///   twice.
/// - Checking something inside an already-checked folder is refused.
/// - The total is "up to": hard links and clones add nothing.
public struct CheckTray: Sendable, Equatable {
    public private(set) var items: [CheckedItem] = []

    public init() {}

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var freeable: Int64 { items.reduce(0) { $0 + $1.freeable } }
    /// How many may free nothing (hard links, clones).
    public var sharedCount: Int { items.filter(\.mayFreeNothing).count }

    public func contains(_ path: String) -> Bool { items.contains { $0.path == path } }

    /// A checked folder that contains `path` (not `path` itself).
    public func covering(_ path: String) -> CheckedItem? {
        items.first { $0.path != path && $0.isDirectory && Self.isInside(path, $0.path) }
    }

    @discardableResult
    public mutating func check(_ item: CheckedItem) -> CheckOutcome {
        if contains(item.path) { return .alreadyChecked }
        if let outer = covering(item.path) { return .insideChecked(outer.name) }
        var absorbed = 0
        if item.isDirectory {
            let before = items.count
            items.removeAll { Self.isInside($0.path, item.path) }
            absorbed = before - items.count
        }
        items.append(item)
        return .checked(absorbed: absorbed)
    }

    public mutating func uncheck(_ path: String) {
        items.removeAll { $0.path == path }
    }

    /// Drops checks for moved items and anything inside them.
    public mutating func remove(paths: Set<String>) {
        items.removeAll { item in paths.contains { Self.isInside(item.path, $0) } }
    }

    public mutating func removeAll(where predicate: (CheckedItem) -> Bool) {
        items.removeAll(where: predicate)
    }
}
