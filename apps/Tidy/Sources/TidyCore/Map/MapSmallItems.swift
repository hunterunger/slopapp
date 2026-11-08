import Darwin
import Foundation

/// One file from a folder's "smaller items", read again on demand.
public struct SmallItem: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    /// Space on disk it reports.
    public var size: Int64
    public var logical: Int64
    public var flags: MapFlags
    public var device: Int32
    public var fileID: UInt64

    public init(name: String, size: Int64, logical: Int64 = 0, flags: MapFlags = [], device: Int32 = 1, fileID: UInt64 = 0) {
        self.name = name
        self.size = size
        self.logical = logical
        self.flags = flags
        self.device = device
        self.fileID = fileID
    }
}

/// Opening "N smaller items": one bulk read of that folder, keeping only the files the map
/// didn't list, biggest first. Nothing is kept once you leave it.
public enum SmallItemsReader {
    public static func read<R: DirectoryReader>(_ path: String, excluding listed: Set<String>, reader: R,
                                                shouldStop: () -> Bool = { false }) -> Result<[SmallItem], DirectoryReadError> {
        var items: [SmallItem] = []
        let failure = reader.read(path, shouldStop: shouldStop) { entry in
            guard entry.error == 0, entry.kind != .directory else { return }
            let name = String(decoding: entry.name, as: UTF8.self)
            guard !listed.contains(name) else { return }
            var flags: MapFlags = entry.kind == .symlink ? [.symlink] : []
            if entry.linkCount > 1 { flags.insert(.hardLinked) }
            if entry.sharesAllBlocks { flags.insert(.clone) }
            if entry.isDataless { flags.insert(.dataless) }
            if entry.isPurgeable { flags.insert(.purgeable) }
            if entry.isSparse { flags.insert(.sparse) }
            if entry.isCompressed { flags.insert(.compressed) }
            items.append(SmallItem(name: name, size: entry.allocated, logical: entry.logical, flags: flags.union(.final),
                                   device: entry.device, fileID: entry.fileID))
        }
        if let failure { return .failure(failure) }
        items.sort { $0.size != $1.size ? $0.size > $1.size : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return .success(items)
    }
}

/// Runs work on a dedicated thread with cloud downloads turned off for it (a Swift task can
/// hop threads, and the policy is per thread).
public enum ScannerThread {
    public static func run<T: Sendable, R: DirectoryReader>(reader: R, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                reader.prepareThread()
                continuation.resume(returning: body())
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
}

/// Facts for the details and Get Info, read for one item when it's shown.
public struct ItemFacts: Sendable, Equatable {
    public var modified: Date?
    public var created: Date?
    /// What deleting it would free right now (partial clones only).
    public var privateSize: Int64?

    public init(modified: Date? = nil, created: Date? = nil, privateSize: Int64? = nil) {
        self.modified = modified
        self.created = created
        self.privateSize = privateSize
    }

    /// Reads dates (and the private size when `wantsPrivateSize`). Call it on a thread from
    /// `ScannerThread` so it can't download a cloud file.
    public static func read(_ path: String, wantsPrivateSize: Bool) -> ItemFacts {
        var st = stat()
        guard lstat(path, &st) == 0 else { return ItemFacts() }
        func date(_ t: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9) }
        var facts = ItemFacts(modified: date(st.st_mtimespec), created: date(st.st_birthtimespec))
        if wantsPrivateSize { facts.privateSize = privateSize(path) }
        return facts
    }

    /// `ATTR_CMNEXT_PRIVATESIZE`: the blocks only this file uses.
    public static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = (UInt32(0), Int64(0))
        let result = withUnsafeMutableBytes(of: &buffer) { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard result == 0 else { return nil }
        return withUnsafeBytes(of: &buffer) { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}
