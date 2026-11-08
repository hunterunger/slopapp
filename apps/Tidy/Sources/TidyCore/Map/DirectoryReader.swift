import Darwin
import Foundation

/// What kind of thing a directory entry is.
public enum EntryKind: UInt8, Sendable {
    case file, directory, symlink, other
}

/// One directory entry as the file system reports it. `name` points into the reader's buffer
/// and is only valid inside the callback that received it: copy it if you keep it.
public struct RawEntry {
    public var name: UnsafeBufferPointer<UInt8>
    public var kind: EntryKind
    /// Space on disk, all forks (`ATTR_FILE_ALLOCSIZE`).
    public var allocated: Int64
    /// File size (`ATTR_FILE_TOTALSIZE`).
    public var logical: Int64
    /// BSD flags (`st_flags`): `SF_DATALESS`, `UF_COMPRESSED`...
    public var flags: UInt32
    /// Extended flags (`EF_*`): clones, purgeable, sparse.
    public var extFlags: UInt64
    public var device: Int32
    public var fileID: UInt64
    public var linkCount: UInt32
    /// Same value for files that are full clones of each other (0 when unknown).
    public var cloneID: UInt64
    /// Something else is mounted here.
    public var isMountPoint: Bool
    /// A per-entry error (`ENOENT` when it vanished mid-read), 0 when fine.
    public var error: Int32

    public init(name: UnsafeBufferPointer<UInt8>, kind: EntryKind, allocated: Int64 = 0, logical: Int64 = 0,
                flags: UInt32 = 0, extFlags: UInt64 = 0, device: Int32 = 1, fileID: UInt64 = 0, linkCount: UInt32 = 1,
                cloneID: UInt64 = 0, isMountPoint: Bool = false, error: Int32 = 0) {
        self.name = name
        self.kind = kind
        self.allocated = allocated
        self.logical = logical
        self.flags = flags
        self.extFlags = extFlags
        self.device = device
        self.fileID = fileID
        self.linkCount = linkCount
        self.cloneID = cloneID
        self.isMountPoint = isMountPoint
        self.error = error
    }

    public var isDataless: Bool { flags & UInt32(SF_DATALESS) != 0 }
    public var isCompressed: Bool { flags & UInt32(UF_COMPRESSED) != 0 }
    public var sharesAllBlocks: Bool { extFlags & UInt64(EF_SHARES_ALL_BLOCKS) != 0 }
    public var maySharePartly: Bool { extFlags & UInt64(EF_MAY_SHARE_BLOCKS) != 0 && !sharesAllBlocks }
    public var isPurgeable: Bool { extFlags & UInt64(EF_IS_PURGEABLE) != 0 }
    public var isSparse: Bool { extFlags & UInt64(EF_IS_SPARSE) != 0 }
}

/// The scan's root, or any single item.
public struct ItemInfo: Sendable, Equatable {
    public var kind: EntryKind
    public var device: Int32
    public var fileID: UInt64
    public var allocated: Int64
    public var flags: UInt32

    public init(kind: EntryKind, device: Int32, fileID: UInt64, allocated: Int64 = 0, flags: UInt32 = 0) {
        self.kind = kind
        self.device = device
        self.fileID = fileID
        self.allocated = allocated
        self.flags = flags
    }
}

/// Why a folder couldn't be read.
public enum DirectoryReadError: Error, Equatable, Sendable {
    /// Permissions (or macOS privacy protection).
    case denied
    /// A cloud placeholder folder: reading it would download it, and the scanner said no.
    case dataless
    /// It was there a moment ago.
    case vanished
    case notDirectory
    case other(Int32)

    public init(errno code: Int32) {
        switch code {
        case EACCES, EPERM: self = .denied
        case EDEADLK: self = .dataless
        case ENOENT: self = .vanished
        case ENOTDIR: self = .notDirectory
        default: self = .other(code)
        }
    }
}

/// Reads folders for the space map. The real one wraps `getattrlistbulk`; tests use an
/// in-memory fake. Must be safe to call from several threads at once.
public protocol DirectoryReader: Sendable {
    /// Called once on each scanner thread before it reads anything (the real reader turns off
    /// cloud downloads for that thread).
    func prepareThread()
    /// The item at `path` itself (not followed if it's a symlink). Nil if it isn't there.
    func info(_ path: String) -> ItemInfo?
    /// Calls `body` for every entry in the folder at `path` (no `.` or `..`). Returns nil when
    /// the whole folder was read. `shouldStop` is polled between batches.
    func read(_ path: String, shouldStop: () -> Bool, _ body: (RawEntry) -> Void) -> DirectoryReadError?
}

/// Keeps macOS from downloading cloud placeholders (iCloud Drive, File Provider folders) on
/// the calling thread: reads of a dataless item fail with `EDEADLK` instead (TN3150). Per
/// thread on purpose: Quick Look of a cloud file the person asked for should still download.
public enum DatalessPolicy {
    /// Returns true if the policy is now set for this thread.
    @discardableResult
    public static func preventDownloadsOnThisThread() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
    }

    /// The calling thread's setting (`IOPOL_MATERIALIZE_DATALESS_FILES_*`), or -1.
    public static func currentThreadSetting() -> Int32 {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    }
}

/// `getattrlistbulk` on real folders: one call returns many entries with every attribute the
/// map needs, which is what makes a parallel walk fast. Private size is never requested here
/// (it makes the call about 3× slower); the details fetch it for one file when shown.
public struct BulkDirectoryReader: DirectoryReader {
    /// 128 KB per call: a few thousand entries.
    static let bufferSize = 128 * 1024

    public init() {}

    public func prepareThread() {
        DatalessPolicy.preventDownloadsOnThisThread()
    }

    public func info(_ path: String) -> ItemInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let kind: EntryKind = switch st.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symlink
        default: .other
        }
        return ItemInfo(kind: kind, device: st.st_dev, fileID: UInt64(st.st_ino), allocated: Int64(st.st_blocks) * 512,
                        flags: st.st_flags)
    }

    /// Opens a folder without following a symlink at the end. Paths longer than `PATH_MAX`
    /// are opened one component at a time from the root.
    static func openDirectory(_ path: String) -> Int32 {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd < 0, errno == ENAMETOOLONG else { return fd }
        var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        let components = path.split(separator: "/")
        for (index, component) in components.enumerated() where current >= 0 {
            // Like open(2): folders on the way may be symlinks (/tmp), the last one may not.
            let last = index == components.count - 1
            let next = openat(current, String(component), O_RDONLY | O_DIRECTORY | O_CLOEXEC | (last ? O_NOFOLLOW : 0))
            let saved = errno
            close(current)
            errno = saved
            current = next
        }
        return current
    }

    private final class Buffer {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: BulkDirectoryReader.bufferSize, alignment: 16)
        deinit { pointer.deallocate() }
    }

    // One buffer per thread, reused for every folder that thread reads.
    private static let bufferKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { raw in Unmanaged<AnyObject>.fromOpaque(raw).release() }
        return key
    }()

    private static func threadBuffer() -> UnsafeMutableRawPointer {
        if let raw = pthread_getspecific(bufferKey) {
            return (Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as! Buffer).pointer
        }
        let buffer = Buffer()
        pthread_setspecific(bufferKey, Unmanaged.passRetained(buffer as AnyObject).toOpaque())
        return buffer.pointer
    }

    public func read(_ path: String, shouldStop: () -> Bool, _ body: (RawEntry) -> Void) -> DirectoryReadError? {
        let fd = Self.openDirectory(path)
        guard fd >= 0 else { return DirectoryReadError(errno: errno) }
        defer { close(fd) }

        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_DEVID
            | ATTR_CMN_OBJTYPE | ATTR_CMN_FLAGS | ATTR_CMN_FILEID | ATTR_CMN_ERROR)
        list.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS | ATTR_DIR_ALLOCSIZE)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE)
        // With FSOPT_ATTR_CMN_EXTENDED the fork group holds the extended common attributes.
        list.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS)
        let options = UInt64(FSOPT_ATTR_CMN_EXTENDED)
        let buffer = Self.threadBuffer()

        while true {
            if shouldStop() { return nil }
            let count = getattrlistbulk(fd, &list, buffer, Self.bufferSize, options)
            if count == 0 { return nil }
            if count < 0 { return DirectoryReadError(errno: errno) }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.load(as: UInt32.self))
                Self.parse(entry, body)
                entry += length
            }
        }
    }

    /// Unpacks one entry. Attributes are packed in a fixed order, but only the ones in
    /// `returned` are there (a file has no folder attributes and the other way round).
    @inline(__always)
    private static func parse(_ start: UnsafeMutableRawPointer, _ body: (RawEntry) -> Void) {
        var p = UnsafeRawPointer(start) + 4
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        @inline(__always) func has(_ group: attrgroup_t, _ bit: Int32) -> Bool { group & attrgroup_t(bit) != 0 }
        @inline(__always) func take<T>(_ present: Bool, _ type: T.Type, _ fallback: T) -> T {
            guard present else { return fallback }
            let value = p.loadUnaligned(as: T.self)
            p += MemoryLayout<T>.size
            return value
        }
        let common = returned.commonattr
        let error = take(has(common, ATTR_CMN_ERROR), UInt32.self, 0)
        let nameStart = p
        let nameRef = p.loadUnaligned(as: attrreference_t.self)
        p += MemoryLayout<attrreference_t>.size
        let namePointer = (nameStart + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: UInt8.self)
        // The length includes the terminating NUL.
        let name = UnsafeBufferPointer(start: namePointer, count: max(0, Int(nameRef.attr_length) - 1))
        let device = take(has(common, ATTR_CMN_DEVID), Int32.self, 0)
        let objType = take(has(common, ATTR_CMN_OBJTYPE), UInt32.self, 0)
        let flags = take(has(common, ATTR_CMN_FLAGS), UInt32.self, 0)
        let fileID = take(has(common, ATTR_CMN_FILEID), UInt64.self, 0)
        let mountStatus = take(has(returned.dirattr, ATTR_DIR_MOUNTSTATUS), UInt32.self, 0)
        let dirAlloc = take(has(returned.dirattr, ATTR_DIR_ALLOCSIZE), Int64.self, 0)
        let linkCount = take(has(returned.fileattr, ATTR_FILE_LINKCOUNT), UInt32.self, 1)
        let totalSize = take(has(returned.fileattr, ATTR_FILE_TOTALSIZE), Int64.self, 0)
        let fileAlloc = take(has(returned.fileattr, ATTR_FILE_ALLOCSIZE), Int64.self, 0)
        let cloneID = take(has(returned.forkattr, ATTR_CMNEXT_CLONEID), UInt64.self, 0)
        let extFlags = take(has(returned.forkattr, ATTR_CMNEXT_EXT_FLAGS), UInt64.self, 0)

        let kind: EntryKind = switch objType {
        case UInt32(VREG.rawValue): .file
        case UInt32(VDIR.rawValue): .directory
        case UInt32(VLNK.rawValue): .symlink
        default: .other
        }
        let isDirectory = kind == .directory
        let raw = RawEntry(
            name: name, kind: kind,
            allocated: isDirectory ? dirAlloc : fileAlloc,
            logical: isDirectory ? 0 : totalSize,
            flags: flags, extFlags: extFlags, device: device, fileID: fileID,
            linkCount: isDirectory ? 1 : max(1, linkCount), cloneID: cloneID,
            isMountPoint: isDirectory && mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0,
            error: Int32(bitPattern: error))
        body(raw)
    }
}
