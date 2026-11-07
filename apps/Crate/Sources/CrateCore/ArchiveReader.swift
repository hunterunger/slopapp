import CArchive
import Foundation

/// One item in an archive, as listed.
public struct ArchiveEntryInfo: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case file, directory, symlink, hardlink, special
    }

    /// Clean path: no leading "./" or "/", no trailing "/", components joined by "/".
    public let path: String
    public let kind: Kind
    public let size: Int64?
    public let modified: Date?
    public let isEncrypted: Bool
    /// For links: where they point.
    public let linkTarget: String?

    public init(path: String, kind: Kind, size: Int64? = nil, modified: Date? = nil, isEncrypted: Bool = false, linkTarget: String? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.linkTarget = linkTarget
    }
}

/// What's inside an archive.
public struct ArchiveListing: Sendable {
    public let source: ArchiveSource
    public let entries: [ArchiveEntryInfo]
    /// "Zip", "Tar.gz", "RAR 5"…
    public let formatName: String
    /// Some entries need a password.
    public let hasEncryptedEntries: Bool
    /// Encrypted, in a format Crate can't decrypt (7z, RAR).
    public let encryptionUnsupported: Bool
    /// Size of the archive file(s).
    public let packedBytes: Int64
    /// Set when reading stopped partway: the entries are what could be read.
    public let problem: CrateError?
    /// Entries left out because extracting them would be unsafe ("../", absolute paths,
    /// links that leave the folder). Extraction skips them too.
    public var unsafeEntries: [String] = []

    public var unpackedBytes: Int64 { entries.reduce(0) { $0 + ($1.size ?? 0) } }
}

/// Lists archives. Stateless; safe to use from any thread.
public enum ArchiveReader {
    /// Lists every entry without unpacking. Throws when nothing at all could be read.
    /// `progress` gets 0...1 by compressed bytes read (useful for .tar.gz, which must be
    /// decompressed to be listed). Checks for task cancellation.
    public static func list(_ source: ArchiveSource, password: String? = nil,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> ArchiveListing {
        let packed = packedSize(of: source)
        let archive = try ReadArchive(source, password: password)
        var entries: [ArchiveEntryInfo] = []
        var problem: CrateError?
        var encrypted = false
        var unsafe: [String] = []
        var count = 0
        while true {
            count += 1
            if count % 512 == 0 {
                try Task.checkCancellation()
                if packed > 0 { progress?(Double(archive.bytesRead) / Double(packed)) }
            }
            let entry: OpaquePointer?
            do {
                entry = try archive.next()
            } catch let error as CrateError {
                if entries.isEmpty { throw error }
                problem = error
                break
            }
            guard let entry else { break }
            let header = EntryHeader(entry)
            encrypted = encrypted || header.isEncrypted
            if archive.formatCode != ARCHIVE_FORMAT_RAW, !isSafe(header) {
                unsafe.append(header.rawPath)
            } else if let info = info(for: header, source: source, format: archive.formatCode) {
                entries.append(info)
            }
        }
        let formatCode = archive.formatCode
        // Encrypted 7z is decrypted by Crate itself; encrypted RAR isn't yet.
        let isUnsupportedFormat = formatCode == ARCHIVE_FORMAT_RAR || formatCode == ARCHIVE_FORMAT_RAR_V5
        if case .unsupportedEncryption = problem { encrypted = true }
        progress?(1)
        var listing = ArchiveListing(
            source: source, entries: entries, formatName: archive.formatName,
            hasEncryptedEntries: encrypted,
            encryptionUnsupported: encrypted && isUnsupportedFormat,
            packedBytes: packed, problem: problem
        )
        listing.unsafeEntries = unsafe
        return listing
    }

    /// The same path and link checks extraction applies.
    static func isSafe(_ header: EntryHeader) -> Bool {
        guard case .safe(let components) = SafePath.check(header.rawPath) else {
            return SafePath.check(header.rawPath) == .empty
        }
        switch header.kind {
        case .symlink:
            return header.symlinkTarget.map { SafePath.linkStaysInside(components: components, target: $0) } ?? false
        case .hardlink:
            if case .safe = SafePath.check(header.hardlinkTarget ?? "") { return true }
            return false
        case .special:
            return false
        default:
            return true
        }
    }

    /// Checks a password against the first encrypted entry. True if it opens it.
    public static func checkPassword(_ password: String, for source: ArchiveSource) throws -> Bool {
        let archive: ReadArchive
        do {
            archive = try ReadArchive(source, password: password)
        } catch let error as CrateError where error.needsPassword {
            return false
        }
        while let entry = try archive.next() {
            if archive.isDecryptedSevenZip {
                // Decrypted as it's read: the first file with data is the test.
                guard EntryHeader(entry).kind == .file, archive_entry_size(entry) > 0 else { continue }
            } else {
                guard archive_entry_is_data_encrypted(entry) != 0 else { continue }
            }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let read = buffer.withUnsafeMutableBytes { archive_read_data(archive.handle, $0.baseAddress, $0.count) }
            if read >= 0 { return true }
            switch archive.error(Int32(read), encryptedEntry: true) {
            case .wrongPassword, .passwordRequired: return false
            case let other: throw other
            }
        }
        return true
    }

    /// Forgets cached 7z keys (derived from passwords). Called when an archive closes.
    public static func forgetDecryptionKeys() {
        SevenZipKey.forgetAll()
    }

    public static func packedSize(of source: ArchiveSource) -> Int64 {
        source.parts.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0)
        }
    }

    static func info(for header: EntryHeader, source: ArchiveSource, format: Int32) -> ArchiveEntryInfo? {
        let path: String
        if format == ARCHIVE_FORMAT_RAW {
            path = ArchiveTypes.baseName(of: source.fileName)
        } else {
            guard let clean = SafePath.displayPath(header.rawPath), !SafePath.isMacMetadata(clean) else { return nil }
            path = clean
        }
        return ArchiveEntryInfo(
            path: path, kind: header.kind,
            size: header.kind == .file ? header.size : nil,
            modified: header.modified, isEncrypted: header.isEncrypted,
            linkTarget: header.symlinkTarget ?? header.hardlinkTarget
        )
    }
}

/// Path checks for entries: what's safe to write, and how to show it.
public enum SafePath {
    public enum Verdict: Equatable, Sendable {
        case safe([String])
        case absolute
        case parentReference
        case nameTooLong
        case empty
    }

    /// Splits an entry path into components that are safe to create under a folder.
    /// Refuses absolute paths and any "..". Drops "." and empty components.
    public static func check(_ raw: String) -> Verdict {
        if raw.hasPrefix("/") || raw.hasPrefix("\\") { return .absolute }
        var components: [String] = []
        for part in raw.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { return .parentReference }
            if part.utf8.count > 255 { return .nameTooLong }
            components.append(String(part))
        }
        return components.isEmpty ? .empty : .safe(components)
    }

    /// How a path is shown in the list: leading "./" and "/" and ".." removed.
    static func displayPath(_ raw: String) -> String? {
        let parts = raw.split(separator: "/").filter { $0 != "." && $0 != ".." && !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Mac resource-fork folders that other unzippers leave behind.
    static func isMacMetadata(_ path: String) -> Bool {
        path == "__MACOSX" || path.hasPrefix("__MACOSX/")
    }

    /// Whether a symlink at `components` pointing to `target` stays inside the root.
    public static func linkStaysInside(components: [String], target: String) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("/") else { return false }
        var stack = Array(components.dropLast())
        for part in target.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                guard !stack.isEmpty else { return false }
                stack.removeLast()
            } else {
                stack.append(String(part))
            }
        }
        return true
    }
}
