import Darwin
import Foundation

/// The space a file or folder takes on disk (what moving it to the Trash and emptying the
/// Trash gives back). Walks with `fts`, which is several times faster than
/// `FileManager.enumerator` with resource keys.
public struct DiskUsage: Sendable, Equatable {
    public var bytes: Int64
    public var files: Int
    /// Some of it couldn't be read (permissions); `bytes` is then a lower bound.
    public var isPartial: Bool

    public init(bytes: Int64 = 0, files: Int = 0, isPartial: Bool = false) {
        self.bytes = bytes
        self.files = files
        self.isPartial = isPartial
    }

    public static func + (lhs: DiskUsage, rhs: DiskUsage) -> DiskUsage {
        DiskUsage(bytes: lhs.bytes + rhs.bytes, files: lhs.files + rhs.files, isPartial: lhs.isPartial || rhs.isPartial)
    }

    /// Measures `url`. Returns `nil` when it doesn't exist or can't be read at all, or when
    /// the task was cancelled. Hard-linked files are counted once.
    public static func measure(_ url: URL) -> DiskUsage? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        if (info.st_mode & S_IFMT) != S_IFDIR {
            return DiskUsage(bytes: Int64(info.st_blocks) * 512, files: 1)
        }
        return walk(url.path)
    }

    private static func walk(_ path: String) -> DiskUsage? {
        guard let cPath = strdup(path) else { return nil }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }

        var usage = DiskUsage()
        var seenLinks = Set<HardLink>()
        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 1023 == 0, Task.isCancelled { return nil }
            let ent = entry.pointee
            switch Int32(ent.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = ent.fts_statp?.pointee else { continue }
                if st.st_nlink > 1, (st.st_mode & S_IFMT) == S_IFREG {
                    guard seenLinks.insert(HardLink(device: st.st_dev, inode: st.st_ino)).inserted else { continue }
                }
                usage.bytes += Int64(st.st_blocks) * 512
                usage.files += 1
            case FTS_D:
                if let st = ent.fts_statp?.pointee { usage.bytes += Int64(st.st_blocks) * 512 }
            case FTS_DNR, FTS_ERR, FTS_NS:
                usage.isPartial = true
                if ent.fts_level == 0 && Int32(ent.fts_info) != FTS_DNR { return nil }
            default:
                continue
            }
        }
        return usage
    }

    private struct HardLink: Hashable {
        var device: dev_t
        var inode: ino_t
    }
}

/// Byte counts the way Finder shows them ("1.2 GB").
public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}
