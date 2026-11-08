import Darwin
import Foundation

/// A disk the map can show.
public struct MapVolume: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        /// The startup disk: its Data volume is walked, the sealed system volume is one block.
        case startup
        /// Another internal disk or volume.
        case `internal`
        /// USB, Thunderbolt, SD cards, disk images.
        case external
        /// SMB, NFS, WebDAV.
        case network
    }

    public var id: String { root.path }
    /// Where it's mounted ("/" for the startup disk).
    public var root: URL
    /// What's walked: the Data volume for the startup disk, else the root.
    public var walkRoot: URL
    public var name: String
    public var kind: Kind
    public var isReadOnly: Bool
    public var format: String
    public var total: Int64
    /// Free right now (`volumeAvailableCapacity`).
    public var free: Int64
    /// Free plus what macOS can purge when it needs room
    /// (`volumeAvailableCapacityForImportantUsage`).
    public var freeForImportantUse: Int64
    /// Startup disk: space the sealed macOS system volume uses.
    public var systemBytes: Int64

    public init(root: URL, walkRoot: URL? = nil, name: String, kind: Kind, isReadOnly: Bool = false, format: String = "",
                total: Int64, free: Int64, freeForImportantUse: Int64? = nil, systemBytes: Int64 = 0) {
        self.root = root.standardizedFileURL
        self.walkRoot = (walkRoot ?? root).standardizedFileURL
        self.name = name
        self.kind = kind
        self.isReadOnly = isReadOnly
        self.format = format
        self.total = total
        self.free = free
        self.freeForImportantUse = max(free, freeForImportantUse ?? free)
        self.systemBytes = systemBytes
    }

    public var used: Int64 { max(0, total - free) }

    /// "External disk", "Network disk"... for the scope menu.
    public var kindDescription: String {
        switch kind {
        case .startup: "Startup disk"
        case .internal: "Internal disk"
        case .external: "External disk"
        case .network: "Network disk"
        }
    }
}

/// The volume bar: what the disk's used space is made of. Every segment is a number we can
/// explain; anything the walk and the volume figures disagree on goes to "Other used space".
public struct VolumeFigures: Sendable, Equatable {
    public var total: Int64
    /// Found by the scan.
    public var mapped: Int64
    /// Used space the scan didn't find: the system volume, other volumes in the same
    /// container, snapshots, other users, unreadable folders, file system overhead.
    public var other: Int64
    /// macOS frees this on its own when it needs room (caches, snapshots it can drop).
    public var purgeable: Int64
    public var free: Int64
    /// Startup disk: the sealed macOS volume, part of `other`.
    public var system: Int64

    public init(volume: MapVolume, mapped: Int64) {
        total = volume.total
        free = min(volume.free, volume.total)
        let used = max(0, total - free)
        let mappedPart = min(max(0, mapped), used)
        self.mapped = mappedPart
        // Purgeable space counts as used in `free`, so it comes out of what's left after the
        // mapped part; what remains is other used space.
        purgeable = min(max(0, volume.freeForImportantUse - volume.free), used - mappedPart)
        other = max(0, used - mappedPart - purgeable)
        system = min(volume.systemBytes, other)
    }

    public var used: Int64 { mapped + other + purgeable }
    /// Other used space apart from the system volume ("Not mapped" in the map).
    public var notMapped: Int64 { max(0, other - system) }
}

/// Where the disks come from: the real mounted volumes, or `TIDY_VOLUMES` in test mode.
public protocol VolumeSource: Sendable {
    func volumes() -> [MapVolume]
}

/// Test mode: fixture folders stand in for disks, with made-up names and capacities, so the
/// map, the scope menu and the volume bar never show the Mac's real disks.
///
///     TIDY_VOLUMES='/tmp/tidy-test/disks/Startup|Fixture HD|startup|500000000000|80000000000|30000000000|12000000000;/tmp/tidy-test/disks/Stick|Fixture Stick|external|64000000000|50000000000'
///
/// Fields: path | name | kind (startup, internal, external, network, readonly) | total bytes |
/// free bytes | purgeable bytes (optional) | system bytes (optional, startup only).
public struct TestVolumes: VolumeSource {
    public let list: [MapVolume]

    public init(_ value: String) {
        list = value.split(separator: ";").compactMap { Self.parse(String($0)) }
    }

    static func parse(_ entry: String) -> MapVolume? {
        let fields = entry.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5, !fields[0].isEmpty, let total = Int64(fields[3]), let free = Int64(fields[4]) else { return nil }
        let url = URL(fileURLWithPath: (fields[0] as NSString).expandingTildeInPath, isDirectory: true)
        let purgeable = fields.count > 5 ? Int64(fields[5]) ?? 0 : 0
        let system = fields.count > 6 ? Int64(fields[6]) ?? 0 : 0
        let readOnly = fields[2] == "readonly"
        let kind = MapVolume.Kind(rawValue: readOnly ? "external" : fields[2]) ?? .external
        return MapVolume(root: url, name: fields[1].isEmpty ? url.lastPathComponent : fields[1], kind: kind,
                         isReadOnly: readOnly, format: kind == .network ? "SMB" : "APFS", total: total, free: free,
                         freeForImportantUse: free + purgeable, systemBytes: kind == .startup ? system : 0)
    }

    public func volumes() -> [MapVolume] { list }
}

/// The Mac's mounted volumes, from URL resource values and `statfs` only: listing them reads
/// no files on them, so it never makes macOS ask for access to a removable disk.
public struct SystemVolumes: VolumeSource {
    public init() {}

    static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsReadOnlyKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey, .volumeLocalizedFormatDescriptionKey,
    ]

    public func volumes() -> [MapVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(Self.volume).sorted { a, b in
            if a.kind == .startup { return b.kind != .startup }
            if b.kind == .startup { return false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func volume(_ url: URL) -> MapVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        // Time Machine snapshots and other system mounts aren't browsable.
        if values.volumeIsBrowsable == false { return nil }
        let isStartup = values.volumeIsRootFileSystem == true
        let kind: MapVolume.Kind = isStartup ? .startup
            : values.volumeIsLocal == false ? .network
            : values.volumeIsInternal == true ? .internal : .external
        let data = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        let walkRoot = isStartup && FileManager.default.fileExists(atPath: data.path) ? data : url
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        return MapVolume(root: url, walkRoot: walkRoot,
                         name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent, kind: kind,
                         isReadOnly: values.volumeIsReadOnly == true && !isStartup,
                         format: values.volumeLocalizedFormatDescription ?? "", total: Int64(values.volumeTotalCapacity ?? 0),
                         free: free, freeForImportantUse: values.volumeAvailableCapacityForImportantUsage ?? free,
                         systemBytes: isStartup ? spaceUsed(of: "/") : 0)
    }

    /// `ATTR_VOL_SPACEUSED`: what one volume uses inside its APFS container.
    public static func spaceUsed(of path: String) -> Int64 {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var buffer = (UInt32(0), Int64(0))
        let result = withUnsafeMutableBytes(of: &buffer) { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, 0)
        }
        guard result == 0 else { return 0 }
        return withUnsafeBytes(of: &buffer) { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}

/// The startup disk's firmlinks: folders on the Data volume that appear at the top of the
/// disk (`/Users` is `/System/Volumes/Data/Users`). The map walks the Data volume and shows
/// paths the way Finder does.
public struct Firmlinks: Sendable, Equatable {
    /// (shown at, path on the Data volume), longest first.
    public let links: [(shown: String, data: String)]
    public let dataRoot: String

    public static func == (a: Firmlinks, b: Firmlinks) -> Bool {
        a.dataRoot == b.dataRoot && a.links.map(\.shown) == b.links.map(\.shown) && a.links.map(\.data) == b.links.map(\.data)
    }

    public init(_ text: String, dataRoot: String = "/System/Volumes/Data") {
        self.dataRoot = dataRoot
        links = text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].hasPrefix("/"), !parts[1].isEmpty else { return nil }
            return (parts[0], parts[1])
        }.sorted { $0.data.count > $1.data.count }
    }

    public static var system: Firmlinks {
        Firmlinks((try? String(contentsOfFile: "/usr/share/firmlinks", encoding: .utf8)) ?? "")
    }

    /// The path people know for something at `relative` (below the Data volume's root).
    public func shownPath(forDataRelative relative: String) -> String {
        guard !relative.isEmpty else { return "/" }
        for link in links where relative == link.data || relative.hasPrefix(link.data + "/") {
            return link.shown + relative.dropFirst(link.data.count)
        }
        return dataRoot + "/" + relative
    }
}

/// Turns map ids (paths below the walked root) into the paths people know, and back. The
/// startup disk walks the Data volume but shows `/Users/…` (firmlinks); everything else is
/// the walked root plus the id.
public struct MapPaths: Sendable, Equatable {
    public let walkRoot: String
    public let firmlinks: Firmlinks?

    public init(walkRoot: String, firmlinks: Firmlinks? = nil) {
        self.walkRoot = MapScanOptions.normalized(walkRoot)
        self.firmlinks = firmlinks
    }

    public func path(_ id: String) -> String {
        if let firmlinks { return firmlinks.shownPath(forDataRelative: id) }
        guard !id.isEmpty else { return walkRoot }
        return walkRoot == "/" ? "/" + id : walkRoot + "/" + id
    }

    /// The id for a full path, if it's inside the map.
    public func id(for path: String) -> String? {
        if let firmlinks {
            for link in firmlinks.links where path == link.shown || path.hasPrefix(link.shown + "/") {
                return link.data + path.dropFirst(link.shown.count)
            }
            let data = firmlinks.dataRoot
            if path == data { return "" }
            if path.hasPrefix(data + "/") { return String(path.dropFirst(data.count + 1)) }
            return path == "/" ? "" : nil
        }
        if path == walkRoot { return "" }
        let prefix = walkRoot == "/" ? "/" : walkRoot + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }
}
