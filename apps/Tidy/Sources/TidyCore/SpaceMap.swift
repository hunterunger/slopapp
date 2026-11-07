import CoreGraphics
import Darwin
import Foundation
import UniformTypeIdentifiers

/// One file or folder in the space map. Built once on a background thread, then read-only.
public final class SpaceNode: @unchecked Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    /// Space on disk (allocated blocks), what moving it to the Trash and emptying it gives back.
    public let size: Int64
    public let isDirectory: Bool
    /// Apps, libraries and other packages show as one item.
    public let isPackage: Bool
    /// Biggest first. Small items are folded into `otherSize`.
    public let children: [SpaceNode]
    /// Space taken by items too small to list on their own.
    public let otherSize: Int64
    public let otherCount: Int
    /// Some of it couldn't be read, so `size` is a lower bound.
    public let isPartial: Bool

    public init(url: URL, size: Int64, isDirectory: Bool, isPackage: Bool = false, children: [SpaceNode] = [],
                otherSize: Int64 = 0, otherCount: Int = 0, isPartial: Bool = false) {
        self.url = url
        name = url.lastPathComponent
        self.size = size
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.children = children
        self.otherSize = otherSize
        self.otherCount = otherCount
        self.isPartial = isPartial
    }

    /// Can be opened in the map (a folder with listed contents).
    public var canOpen: Bool { isDirectory && !isPackage && !children.isEmpty }

    /// The node at `url` in this tree, if it's listed.
    public func find(_ url: URL) -> SpaceNode? {
        let path = url.standardizedFileURL.path
        if path == self.url.path { return self }
        guard path.hasPrefix(self.url.path == "/" ? "/" : self.url.path + "/") else { return nil }
        for child in children {
            if let found = child.find(url) { return found }
        }
        return nil
    }
}

/// Walks a folder and adds up sizes. Hard-linked files count once. Doesn't cross into other
/// volumes.
public struct SpaceScanner: Sendable {
    public var root: URL
    /// Folders left out entirely (protected ones without Full Disk Access).
    public var excluded: [URL]
    /// Items smaller than this aren't listed on their own (they still count).
    public var minimumListedSize: Int64
    /// At most this many children per folder are listed.
    public var maximumChildren: Int

    public init(root: URL, excluded: [URL] = [], minimumListedSize: Int64 = 1_000_000, maximumChildren: Int = 60) {
        self.root = root.standardizedFileURL
        self.excluded = excluded.map(\.standardizedFileURL)
        self.minimumListedSize = minimumListedSize
        self.maximumChildren = maximumChildren
    }

    /// Folders macOS protects: walking them without Full Disk Access makes it ask about each
    /// one (or another app's data), so they're skipped unless access is granted.
    public static func protectedFolders(in home: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Library/Containers", "Library/Group Containers", "Library/Mail",
         "Library/Messages", "Library/Safari", "Library/Calendars", "Library/Mobile Documents", "Library/CloudStorage",
         "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB", ".Trash"]
            .map { home.appendingPathComponent($0) }
    }

    private final class Builder {
        let url: URL
        let isPackage: Bool
        /// Left out (excluded): fts still visits it once more in post-order.
        var skipped = false
        var size: Int64 = 0
        var children: [SpaceNode] = []
        var partial = false
        init(url: URL, isPackage: Bool) {
            self.url = url
            self.isPackage = isPackage
        }
    }

    /// Returns nil if cancelled. `progress` gets the number of items looked at and the folder
    /// being read (every few thousand items).
    public func scan(progress: (@Sendable (Int, String) -> Void)? = nil) -> SpaceNode? {
        guard let cPath = strdup(root.path) else { return nil }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }

        let excludedPaths = Set(excluded.map(\.path))
        var packageExtensions: [String: Bool] = [:]
        var seenLinks = Set<[UInt64]>()
        var stack: [Builder] = []
        var result: SpaceNode?
        var visited = 0

        func isPackage(_ name: String) -> Bool {
            let ext = (name as NSString).pathExtension.lowercased()
            guard !ext.isEmpty else { return false }
            if let known = packageExtensions[ext] { return known }
            let type = UTType(filenameExtension: ext, conformingTo: .directory)
            let value = type.map { $0.conforms(to: .package) || $0.conforms(to: .bundle) } ?? false
            packageExtensions[ext] = value
            return value
        }

        while let entry = fts_read(fts) {
            visited += 1
            if visited & 4095 == 0 {
                if Task.isCancelled { return nil }
                if let top = stack.last { progress?(visited, top.url.path) }
            }
            let ent = entry.pointee
            let info = Int32(ent.fts_info)
            let path = String(cString: ent.fts_path)
            switch info {
            case FTS_D:
                if ent.fts_level > 0 && excludedPaths.contains(path) {
                    // fts still returns it in post-order (FTS_DP), so it goes on the stack.
                    fts_set(fts, entry, FTS_SKIP)
                    let skipped = Builder(url: URL(fileURLWithPath: path, isDirectory: true), isPackage: false)
                    skipped.skipped = true
                    stack.append(skipped)
                    continue
                }
                let name = (path as NSString).lastPathComponent
                let builder = Builder(url: URL(fileURLWithPath: path, isDirectory: true),
                                      isPackage: ent.fts_level > 0 && (isPackage(name) || stack.last?.isPackage == true))
                if let st = ent.fts_statp?.pointee { builder.size += Int64(st.st_blocks) * 512 }
                stack.append(builder)
            case FTS_DP, FTS_DNR:
                // An unreadable folder comes back as FTS_DNR instead of its post-order visit.
                guard let builder = stack.last, builder.url.path == path else {
                    stack.last?.partial = true
                    continue
                }
                stack.removeLast()
                if info == FTS_DNR { builder.partial = true }
                if builder.skipped {
                    stack.last?.partial = true
                    continue
                }
                if stack.isEmpty && info == FTS_DNR { return nil }
                let node = finish(builder)
                if let parent = stack.last {
                    parent.size += node.size
                    parent.partial = parent.partial || node.isPartial
                    if !parent.isPackage { parent.children.append(node) }
                } else {
                    result = node
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = ent.fts_statp?.pointee else { continue }
                if st.st_nlink > 1, (st.st_mode & S_IFMT) == S_IFREG {
                    guard seenLinks.insert([UInt64(st.st_dev), UInt64(st.st_ino)]).inserted else { continue }
                }
                let size = Int64(st.st_blocks) * 512
                guard let parent = stack.last else {
                    // The root itself is a file.
                    return SpaceNode(url: root, size: size, isDirectory: false)
                }
                parent.size += size
                if !parent.isPackage {
                    parent.children.append(SpaceNode(url: URL(fileURLWithPath: path), size: size, isDirectory: false))
                }
            case FTS_ERR, FTS_NS:
                if ent.fts_level == 0 { return nil }
                stack.last?.partial = true
            default:
                continue
            }
        }
        progress?(visited, root.path)
        return result
    }

    private func finish(_ builder: Builder) -> SpaceNode {
        guard !builder.isPackage else {
            return SpaceNode(url: builder.url, size: builder.size, isDirectory: true, isPackage: true, isPartial: builder.partial)
        }
        let sorted = builder.children.sorted { $0.size > $1.size }
        var listed: [SpaceNode] = []
        var otherSize: Int64 = 0
        var otherCount = 0
        for child in sorted {
            if listed.count < maximumChildren && child.size >= minimumListedSize {
                listed.append(child)
            } else {
                otherSize += child.size
                otherCount += 1
            }
        }
        return SpaceNode(url: builder.url, size: builder.size, isDirectory: true, children: listed,
                         otherSize: otherSize, otherCount: otherCount, isPartial: builder.partial)
    }
}

/// Squarified treemap layout (Bruls, Huizing and van Wijk): rectangles whose areas match the
/// values and whose shapes stay close to squares, biggest first from the top-left.
public enum Treemap {
    /// Rectangles for `values` (any order; results match the input order). Zero or negative
    /// values get empty rectangles.
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        var remaining = rect
        var row: [Int] = []
        var index = 0

        func areas(_ indices: [Int]) -> [Double] { indices.map { values[$0] * scale } }

        func worst(_ indices: [Int], side: Double) -> Double {
            let a = areas(indices)
            guard let maxA = a.max(), let minA = a.min(), side > 0 else { return .infinity }
            let sum = a.reduce(0, +)
            return max(side * side * maxA / (sum * sum), (sum * sum) / (side * side * minA))
        }

        func place(_ indices: [Int]) {
            let a = areas(indices)
            let sum = a.reduce(0, +)
            if remaining.width >= remaining.height {
                // Lay the row down the left side.
                let width = remaining.height > 0 ? CGFloat(sum) / remaining.height : 0
                var y = remaining.minY
                for (i, area) in zip(indices, a) {
                    let height = width > 0 ? CGFloat(area) / width : 0
                    result[i] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                let height = remaining.width > 0 ? CGFloat(sum) / remaining.width : 0
                var x = remaining.minX
                for (i, area) in zip(indices, a) {
                    let width = height > 0 ? CGFloat(area) / height : 0
                    result[i] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
        }

        while index < order.count {
            let item = order[index]
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [item], side: side) <= worst(row, side: side) {
                row.append(item)
                index += 1
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}
