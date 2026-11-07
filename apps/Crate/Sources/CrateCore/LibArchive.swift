import CArchive
import Darwin
import Foundation

/// The system libarchive's version, e.g. "3.7.4".
public enum LibArchive {
    public static var version: String {
        let number = Int(archive_version_number())
        return "\(number / 1_000_000).\(number / 1000 % 1000).\(number % 1000)"
    }
}

/// An archive opened for reading. One per pass: libarchive reads sequentially.
final class ReadArchive {
    let handle: OpaquePointer
    let source: ArchiveSource
    let hasPassword: Bool
    /// An encrypted 7z being decrypted as it's read (see `SevenZipDecryptedView`).
    private(set) var isDecryptedSevenZip = false
    private var cPaths: [UnsafeMutablePointer<CChar>?] = []
    private var viewReader: ViewReader?

    init(_ source: ArchiveSource, password: String?) throws {
        guard let handle = archive_read_new() else { throw CrateError.unreadableSource(name: source.fileName) }
        self.handle = handle
        self.source = source
        self.hasPassword = password?.isEmpty == false
        archive_read_support_filter_all(handle)
        archive_read_support_format_all(handle)
        // Lets single-file .gz/.bz2/.xz open as one entry. Only bids when nothing else does.
        archive_read_support_format_raw(handle)
        if let password, !password.isEmpty {
            archive_read_add_passphrase(handle, password)
        }
        for part in source.parts where !FileManager.default.isReadableFile(atPath: part.path) {
            if !FileManager.default.fileExists(atPath: part.path), source.isMultiPart {
                throw CrateError.missingPart(archive: source.fileName, part: part.lastPathComponent)
            }
            throw CrateError.unreadableSource(name: part.lastPathComponent)
        }
        let result: Int32
        if let view = try SevenZipDecryptedView.open(source, password: password) {
            let reader = ViewReader(view)
            viewReader = reader
            isDecryptedSevenZip = true
            archive_read_set_seek_callback(handle, viewSeek)
            result = archive_read_open2(handle, Unmanaged.passUnretained(reader).toOpaque(), nil, viewRead, viewSkip, nil)
        } else if source.parts.count == 1 {
            result = source.parts[0].withUnsafeFileSystemRepresentation { archive_read_open_filename(handle, $0, 64 * 1024) }
        } else {
            cPaths = source.parts.map { url in url.withUnsafeFileSystemRepresentation { strdup($0!) } } + [nil]
            result = cPaths.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                    archive_read_open_filenames(handle, $0, 64 * 1024)
                }
            }
        }
        if result < ARCHIVE_WARN {
            throw error(result)
        }
    }

    deinit {
        archive_read_free(handle)
        cPaths.forEach { free($0) }
    }

    /// The next entry, or nil at the end.
    func next() throws -> OpaquePointer? {
        var entry: OpaquePointer?
        let result = archive_read_next_header(handle, &entry)
        if result == ARCHIVE_EOF { return nil }
        if result < ARCHIVE_WARN { throw error(result) }
        // A plain file read as "raw" with no decompression isn't an archive.
        if formatCode == ARCHIVE_FORMAT_RAW, archive_filter_count(handle) <= 1 {
            throw CrateError.notAnArchive(name: source.fileName)
        }
        return entry
    }

    var formatCode: Int32 { archive_format(handle) & Int32(ARCHIVE_FORMAT_BASE_MASK) }

    /// "Zip", "7z", "RAR", "Tar.gz"…
    var formatName: String { ArchiveFormatName.name(format: formatCode, filter: outerFilter) }

    var outerFilter: Int32 {
        let count = archive_filter_count(handle)
        return count > 1 ? archive_filter_code(handle, 0) : ARCHIVE_FILTER_NONE
    }

    /// Compressed bytes consumed so far.
    var bytesRead: Int64 { archive_filter_bytes(handle, -1) }

    /// Maps libarchive's last error to a `CrateError`.
    func error(_ code: Int32, encryptedEntry: Bool = false) -> CrateError {
        if let failure = viewReader?.failure {
            if case .malformed("ends early") = failure { return .truncated(name: source.fileName) }
            return .damaged(name: source.fileName, detail: "")
        }
        let message = archive_error_string(handle).map { String(cString: $0) } ?? ""
        // Data that fails to decompress after decryption almost always means a wrong
        // password that slipped past the quick check (as 7-Zip says too).
        return ErrorMapping.map(message: message, format: formatCode, name: source.fileName,
                                hasPassword: hasPassword, encryptedEntry: encryptedEntry || isDecryptedSevenZip)
    }
}

/// Feeds libarchive from a `SevenZipDecryptedView`.
private final class ViewReader {
    let view: SevenZipDecryptedView
    var position: Int64 = 0
    var failure: SevenZipError?
    static let bufferSize = 1 << 20
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: ViewReader.bufferSize, alignment: 16)

    init(_ view: SevenZipDecryptedView) { self.view = view }
    deinit { buffer.deallocate() }

    static func from(_ data: UnsafeMutableRawPointer?) -> ViewReader {
        Unmanaged<ViewReader>.fromOpaque(data!).takeUnretainedValue()
    }
}

private func viewRead(_ archive: OpaquePointer?, _ data: UnsafeMutableRawPointer?,
                      _ buffer: UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int {
    let reader = ViewReader.from(data)
    do {
        let count = try reader.view.read(at: reader.position, count: ViewReader.bufferSize, into: reader.buffer)
        reader.position += Int64(count)
        buffer?.pointee = UnsafeRawPointer(reader.buffer)
        return count
    } catch {
        reader.failure = error as? SevenZipError ?? .io("")
        return Int(ARCHIVE_FATAL)
    }
}

private func viewSkip(_ archive: OpaquePointer?, _ data: UnsafeMutableRawPointer?, _ request: Int64) -> Int64 {
    let reader = ViewReader.from(data)
    let skipped = max(0, min(request, reader.view.size - reader.position))
    reader.position += skipped
    return skipped
}

private func viewSeek(_ archive: OpaquePointer?, _ data: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    let reader = ViewReader.from(data)
    let target: Int64
    switch whence {
    case SEEK_SET: target = offset
    case SEEK_CUR: target = reader.position + offset
    case SEEK_END: target = reader.view.size + offset
    default: return Int64(ARCHIVE_FATAL)
    }
    guard target >= 0 else { return Int64(ARCHIVE_FATAL) }
    reader.position = target
    return target
}

enum ErrorMapping {
    static func map(message: String, format: Int32, name: String, hasPassword: Bool, encryptedEntry: Bool) -> CrateError {
        let lower = message.lowercased()
        let isSevenZip = format == ARCHIVE_FORMAT_7ZIP || lower.contains("7-zip") || lower.contains("7zip")
        let isRar = format == ARCHIVE_FORMAT_RAR || format == ARCHIVE_FORMAT_RAR_V5 || lower.contains("rar")
        if lower.contains("incorrect passphrase") {
            return .wrongPassword(name: name)
        }
        if lower.contains("passphrase required") || lower.contains("passphrase is required") {
            return hasPassword ? .wrongPassword(name: name) : .passwordRequired(name: name)
        }
        if lower.contains("encrypt") || lower.contains("decrypt") {
            // 7z encryption is handled by `SevenZipDecryptedView`; libarchive only gets
            // here when no password was given.
            if isRar, !isSevenZip { return .unsupportedEncryption(name: name, format: "RAR") }
            // Only reached with a password when Crate couldn't decrypt this 7z's layout.
            if isSevenZip, hasPassword { return .unsupportedEncryption(name: name, format: "7z") }
            return hasPassword ? .wrongPassword(name: name) : .passwordRequired(name: name)
        }
        // A weak ZipCrypto check can pass with the wrong password; the data then fails its CRC.
        if encryptedEntry, lower.contains("crc") || lower.contains("checksum") || lower.contains("invalid")
            || lower.contains("damaged") || lower.contains("decompress") || lower.contains("corrupt") {
            return hasPassword ? .wrongPassword(name: name) : .passwordRequired(name: name)
        }
        if lower.contains("unrecognized archive format") || lower.contains("not an archive") {
            return .notAnArchive(name: name)
        }
        if lower.contains("truncated") || lower.contains("premature end") || lower.contains("unexpected end")
            || lower.contains("eof") || lower.contains("end of file") {
            return .truncated(name: name)
        }
        return .damaged(name: name, detail: message)
    }
}

enum ArchiveFormatName {
    static func name(format: Int32, filter: Int32) -> String {
        let base: String
        switch format {
        case ARCHIVE_FORMAT_ZIP: base = "Zip"
        case ARCHIVE_FORMAT_7ZIP: base = "7z"
        case ARCHIVE_FORMAT_RAR: base = "RAR"
        case ARCHIVE_FORMAT_RAR_V5: base = "RAR 5"
        case ARCHIVE_FORMAT_TAR: base = "Tar"
        case ARCHIVE_FORMAT_CPIO: base = "cpio"
        case ARCHIVE_FORMAT_ISO9660: base = "Disc image (ISO)"
        case ARCHIVE_FORMAT_AR: base = "ar"
        case ARCHIVE_FORMAT_XAR: base = "xar"
        case ARCHIVE_FORMAT_LHA: base = "LHA"
        case ARCHIVE_FORMAT_CAB: base = "Cabinet"
        case ARCHIVE_FORMAT_RAW: base = ""
        default: base = "Archive"
        }
        let filterName: String? = switch filter {
        case ARCHIVE_FILTER_GZIP: "gz"
        case ARCHIVE_FILTER_BZIP2: "bz2"
        case ARCHIVE_FILTER_XZ: "xz"
        case ARCHIVE_FILTER_LZMA: "lzma"
        case ARCHIVE_FILTER_COMPRESS: "Z"
        default: nil
        }
        if base.isEmpty { return filterName.map { "Compressed file (\($0))" } ?? "File" }
        return filterName.map { "\(base).\($0)" } ?? base
    }
}

/// An entry's facts, read from its header.
struct EntryHeader {
    let rawPath: String
    let kind: ArchiveEntryInfo.Kind
    let size: Int64?
    let modified: Date?
    let isEncrypted: Bool
    let perm: mode_t
    let symlinkTarget: String?
    let hardlinkTarget: String?

    init(_ entry: OpaquePointer) {
        let path = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
        rawPath = path.map { String(cString: $0) } ?? ""
        let hardlink = archive_entry_hardlink_utf8(entry) ?? archive_entry_hardlink(entry)
        hardlinkTarget = hardlink.map { String(cString: $0) }
        let type = Int32(archive_entry_filetype(entry)) & AE_IFMT
        if hardlinkTarget != nil {
            kind = .hardlink
        } else if type == AE_IFDIR || (type == 0 && rawPath.hasSuffix("/")) {
            kind = .directory
        } else if type == AE_IFLNK {
            kind = .symlink
        } else if type == AE_IFREG || type == 0 {
            kind = .file
        } else {
            kind = .special
        }
        let symlink = archive_entry_symlink_utf8(entry) ?? archive_entry_symlink(entry)
        symlinkTarget = symlink.map { String(cString: $0) }
        size = archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : nil
        modified = archive_entry_mtime_is_set(entry) != 0 ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil
        isEncrypted = archive_entry_is_encrypted(entry) != 0
        perm = archive_entry_perm(entry)
    }
}
