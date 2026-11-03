import CArchive
import Darwin
import Foundation

public enum CreateFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case zip, tarGz, tarXz, sevenZip

    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .tarGz: "tar.gz"
        case .tarXz: "tar.xz"
        case .sevenZip: "7z"
        }
    }
    public var title: String {
        switch self {
        case .zip: "Zip"
        case .tarGz: "Tar.gz"
        case .tarXz: "Tar.xz"
        case .sevenZip: "7z"
        }
    }
    /// One line on what it's for.
    public var summary: String {
        switch self {
        case .zip: "Opens on any computer"
        case .tarGz: "Common for code and on Linux"
        case .tarXz: "Smaller than tar.gz, slower to make"
        case .sevenZip: "Smallest, but needs 7-Zip or Keka to open"
        }
    }
    public var supportsPassword: Bool { self == .zip }
}

public enum CompressionLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case fast, normal, best
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .best: "Best"
        }
    }
    func value(for format: CreateFormat) -> Int {
        switch (self, format) {
        case (.fast, _): 1
        case (.normal, _): 6
        // xz and 7z at 9 need several hundred MB of memory; 7 is nearly as small.
        case (.best, .tarXz), (.best, .sevenZip): 7
        case (.best, _): 9
        }
    }
}

public enum ZipEncryption: String, Codable, CaseIterable, Sendable, Identifiable {
    case aes256, zipCrypto
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .aes256: "Strong (AES-256)"
        case .zipCrypto: "Compatible (ZipCrypto, weak)"
        }
    }
    public var note: String {
        switch self {
        case .aes256: "Archive Utility on Mac and Windows Explorer can't open it. Use 7-Zip, Keka or The Unarchiver."
        case .zipCrypto: "Opens almost everywhere, but is easy to crack. Don't use it for anything sensitive."
        }
    }
}

public struct CreateRequest: Sendable, Equatable {
    public var sources: [URL]
    /// Where the archive goes.
    public var folder: URL
    /// The archive's name without extension.
    public var name: String
    public var format: CreateFormat
    public var level: CompressionLevel
    public var password: String?
    public var encryption: ZipEncryption
    /// Leave out .DS_Store, ._*, __MACOSX, Icon\r and volume folders.
    public var leaveOutMacFiles: Bool
    /// Split into parts of this many bytes (`name.zip.001`, `.002`…); nil for one file.
    public var partSize: Int64?

    public init(sources: [URL], folder: URL, name: String, format: CreateFormat = .zip, level: CompressionLevel = .normal,
                password: String? = nil, encryption: ZipEncryption = .aes256, leaveOutMacFiles: Bool = true, partSize: Int64? = nil) {
        self.sources = sources
        self.folder = folder
        self.name = name
        self.format = format
        self.level = level
        self.password = password
        self.encryption = encryption
        self.leaveOutMacFiles = leaveOutMacFiles
        self.partSize = partSize
    }

    /// "Archive" for several items, the item's name (without extension for files) for one.
    public static func defaultName(for sources: [URL]) -> String {
        guard sources.count == 1, let only = sources.first else { return "Archive" }
        let isFolder = (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isPackage = (try? only.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        return isFolder && !isPackage ? only.lastPathComponent : only.deletingPathExtension().lastPathComponent
    }
}

public struct CreateResult: Sendable, Equatable {
    /// The archive, or its parts in order.
    public let outputs: [URL]
    public let bytes: Int64
    public let fileCount: Int
    /// Mac files left out.
    public let leftOut: Int

    public var primary: URL? { outputs.first }
    public var wasSplit: Bool { outputs.count > 1 }
}

/// Mac-only clutter that shouldn't end up in archives for other systems.
public enum MacJunk {
    static let names: Set<String> = [
        ".DS_Store", "__MACOSX", "Icon\r", ".Spotlight-V100", ".Trashes", ".fseventsd",
        ".TemporaryItems", ".DocumentRevisions-V100", ".apdisk",
    ]

    public static func isJunk(_ name: String) -> Bool {
        names.contains(name) || name.hasPrefix("._")
    }
}

/// Makes archives with the system libarchive. Writes to a hidden file next to the
/// destination and moves it into place at the end, so a cancelled or failed run leaves
/// nothing behind and nothing is ever overwritten.
public struct ArchiveCreator: Sendable {
    public init() {}

    struct Item {
        let url: URL
        let path: String
        let type: mode_t
        let size: Int64
        let perm: mode_t
        let mtime: timespec
    }

    public func create(_ request: CreateRequest, progress: (@Sendable (Double) -> Void)? = nil) throws -> CreateResult {
        if request.password?.isEmpty == false, !request.format.supportsPassword {
            throw CrateError.passwordNotSupported(format: request.format.title)
        }
        guard FileManager.default.isWritableFile(atPath: request.folder.path) else {
            throw CrateError.destinationNotWritable(folder: request.folder.lastPathComponent)
        }
        let work = try Naming.makeWorkFolder(in: request.folder)
        defer { Naming.removeWorkFolder(work) }

        var leftOut = 0
        let items = try collect(request.sources, leaveOutMacFiles: request.leaveOutMacFiles, skipping: work, leftOut: &leftOut)
        guard !items.isEmpty else { throw CrateError.nothingToArchive }
        let total = max(1, items.reduce(Int64(0)) { $0 + $1.size })
        let fileName = request.name + "." + request.format.fileExtension
        let temp = work.appendingPathComponent("archive")

        try write(items, to: temp, request: request, fileName: fileName) { done in
            progress?(min(0.99, Double(done) / Double(total)) * (request.partSize == nil ? 1 : 0.9))
        }
        try Task.checkCancellation()

        let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        var outputs: [URL]
        if let partSize = request.partSize, partSize > 0, size > partSize {
            outputs = try split(temp, partSize: partSize, fileName: fileName, in: request.folder, work: work)
        } else {
            outputs = [try Naming.moveIntoPlace(temp, named: fileName, in: request.folder, isFolder: false)]
        }
        progress?(1)
        return CreateResult(outputs: outputs, bytes: size, fileCount: items.count(where: { $0.type == S_IFREG }), leftOut: leftOut)
    }

    // MARK: Collecting

    private func collect(_ sources: [URL], leaveOutMacFiles: Bool, skipping work: URL, leftOut: inout Int) throws -> [Item] {
        var items: [Item] = []
        var topNames = Set<String>()
        let workPath = work.standardizedFileURL.path

        func stat(_ url: URL) -> Darwin.stat? {
            var info = Darwin.stat()
            return url.withUnsafeFileSystemRepresentation { lstat($0!, &info) } == 0 ? info : nil
        }

        func add(_ url: URL, path: String, info: Darwin.stat) throws {
            let type = info.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR || type == S_IFLNK else { return }
            items.append(Item(url: url, path: path.precomposedStringWithCanonicalMapping, type: type,
                              size: type == S_IFREG ? Int64(info.st_size) : 0,
                              perm: info.st_mode & 0o777, mtime: info.st_mtimespec))
            guard type == S_IFDIR else { return }
            let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            for name in children.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                if leaveOutMacFiles, MacJunk.isJunk(name) { leftOut += 1; continue }
                let child = url.appendingPathComponent(name)
                if child.standardizedFileURL.path == workPath || child.resolvingSymlinksInPath().path == workPath { continue }
                guard let childInfo = stat(child) else { continue }
                try add(child, path: path + "/" + name, info: childInfo)
            }
        }

        for source in sources {
            try Task.checkCancellation()
            guard let info = stat(source) else { throw CrateError.unreadableSource(name: source.lastPathComponent) }
            let name = source.lastPathComponent
            if leaveOutMacFiles, MacJunk.isJunk(name) { leftOut += 1; continue }
            // Two dropped items with the same name (from different folders) get numbered.
            var top = name
            var number = 1
            let isFolder = (info.st_mode & S_IFMT) == S_IFDIR
            while topNames.contains(top.lowercased()) {
                number += 1
                top = Naming.candidate(name, number: number, isFolder: isFolder)
            }
            topNames.insert(top.lowercased())
            try add(source, path: top, info: info)
        }
        return items
    }

    // MARK: Writing

    private func write(_ items: [Item], to output: URL, request: CreateRequest, fileName: String,
                       progress: (Int64) -> Void) throws {
        guard let archive = archive_write_new() else { throw CrateError.writeFailed(name: fileName, detail: "") }
        defer { archive_write_free(archive) }
        func fail(_ detail: String? = nil) -> CrateError {
            .writeFailed(name: fileName, detail: detail ?? archive_error_string(archive).map { String(cString: $0) } ?? "")
        }
        func option(_ text: String, required: Bool = true) throws {
            if archive_write_set_options(archive, text) < ARCHIVE_WARN, required { throw fail() }
        }

        let level = request.level.value(for: request.format)
        switch request.format {
        case .zip:
            archive_write_set_format_zip(archive)
            try option("zip:compression=deflate")
            try option("zip:compression-level=\(level)")
            try option("zip:hdrcharset=UTF-8")
            if let password = request.password, !password.isEmpty {
                try option(request.encryption == .aes256 ? "zip:encryption=aes256" : "zip:encryption=zipcrypt")
                guard archive_write_set_passphrase(archive, password) == ARCHIVE_OK else { throw fail() }
            }
        case .tarGz:
            archive_write_set_format_pax_restricted(archive)
            archive_write_add_filter_gzip(archive)
            try option("gzip:compression-level=\(level)")
        case .tarXz:
            archive_write_set_format_pax_restricted(archive)
            archive_write_add_filter_xz(archive)
            try option("xz:compression-level=\(level)")
            try option("xz:threads=0", required: false)
        case .sevenZip:
            archive_write_set_format_7zip(archive)
            try option("7zip:compression=lzma2")
            try option("7zip:compression-level=\(level)")
        }
        let opened = output.withUnsafeFileSystemRepresentation { archive_write_open_filename(archive, $0) }
        guard opened == ARCHIVE_OK else { throw fail() }

        guard let entry = archive_entry_new() else { throw fail("") }
        defer { archive_entry_free(entry) }
        var done: Int64 = 0
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }

        for item in items {
            try Task.checkCancellation()
            archive_entry_clear(entry)
            archive_entry_set_pathname_utf8(entry, item.type == S_IFDIR ? item.path + "/" : item.path)
            archive_entry_set_filetype(entry, UInt32(item.type))
            archive_entry_set_perm(entry, item.perm)
            archive_entry_set_mtime(entry, item.mtime.tv_sec, item.mtime.tv_nsec)
            switch item.type {
            case S_IFREG:
                archive_entry_set_size(entry, item.size)
            case S_IFLNK:
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: item.url.path)) ?? ""
                archive_entry_set_symlink_utf8(entry, target)
                archive_entry_set_size(entry, 0)
            default:
                archive_entry_set_size(entry, 0)
            }
            if archive_write_header(archive, entry) < ARCHIVE_WARN { throw fail() }
            if item.type == S_IFREG {
                let fd = item.url.withUnsafeFileSystemRepresentation { open($0!, O_RDONLY) }
                guard fd >= 0 else { throw CrateError.unreadableSource(name: item.url.lastPathComponent) }
                defer { close(fd) }
                var remaining = item.size
                while remaining > 0 {
                    let count = read(fd, buffer, min(chunk, Int(remaining)))
                    if count < 0 { throw CrateError.unreadableSource(name: item.url.lastPathComponent) }
                    if count == 0 { throw CrateError.unreadableSource(name: item.url.lastPathComponent) }
                    if archive_write_data(archive, buffer, count) < 0 { throw fail() }
                    remaining -= Int64(count)
                    done += Int64(count)
                    progress(done)
                    if done % (32 << 20) < Int64(chunk) { try Task.checkCancellation() }
                }
            }
            if archive_write_finish_entry(archive) < ARCHIVE_WARN { throw fail() }
        }
        if archive_write_close(archive) != ARCHIVE_OK { throw fail() }
    }

    // MARK: Splitting

    /// Byte-splits `file` into `name.001`, `name.002`… (the 7-Zip convention), choosing a
    /// set name that clashes with nothing.
    private func split(_ file: URL, partSize: Int64, fileName: String, in folder: URL, work: URL) throws -> [URL] {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        let count = Int((size + partSize - 1) / partSize)
        // Write the parts inside the working folder first.
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var temps: [URL] = []
        for index in 1...count {
            try Task.checkCancellation()
            let part = work.appendingPathComponent(String(format: "part.%03d", index))
            FileManager.default.createFile(atPath: part.path, contents: nil)
            let output = try FileHandle(forWritingTo: part)
            var remaining = min(partSize, size - Int64(index - 1) * partSize)
            while remaining > 0 {
                let data = try input.read(upToCount: Int(min(remaining, 4 << 20))) ?? Data()
                guard !data.isEmpty else { break }
                try output.write(contentsOf: data)
                remaining -= Int64(data.count)
            }
            try output.close()
            temps.append(part)
        }
        // Pick a set name with no existing parts, then move every part in without replacing.
        var number = 1
        while true {
            let base = Naming.candidate(fileName, number: number, isFolder: false)
            let names = (1...count).map { base + String(format: ".%03d", $0) }
            if Naming.exists(folder.appendingPathComponent(base)) || names.contains(where: { Naming.exists(folder.appendingPathComponent($0)) }) {
                number += 1
                continue
            }
            var placed: [URL] = []
            do {
                for (temp, name) in zip(temps, names) {
                    let target = folder.appendingPathComponent(name)
                    try moveExclusive(temp, to: target)
                    placed.append(target)
                }
                return placed
            } catch {
                placed.forEach { try? FileManager.default.removeItem(at: $0) }
                throw error
            }
        }
    }

    private func moveExclusive(_ from: URL, to: URL) throws {
        let result = from.withUnsafeFileSystemRepresentation { a in
            to.withUnsafeFileSystemRepresentation { b in renamex_np(a!, b!, UInt32(RENAME_EXCL)) }
        }
        if result != 0 { throw CrateError.writeFailed(name: to.lastPathComponent, detail: String(cString: strerror(errno))) }
    }
}

/// Repacks an archive in another format: unpack to a hidden folder, pack, clean up.
public struct Converter: Sendable {
    public let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = SystemFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// `template` supplies format, level, password and options; its sources and name are
    /// replaced by the archive's contents and base name.
    public func convert(_ source: ArchiveSource, password: String?, to template: CreateRequest,
                        progress: (@Sendable (Double) -> Void)? = nil) throws -> CreateResult {
        let work = try Naming.makeWorkFolder(in: template.folder)
        defer { Naming.removeWorkFolder(work) }
        _ = try Extractor(fileSystem: fileSystem).extract(
            source, to: work, options: ExtractionOptions(password: password, layout: .loose)
        ) { progress?($0 * 0.5) }
        let contents = ((try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { work.appendingPathComponent($0) }
        var request = template
        request.sources = contents
        request.name = template.name.isEmpty ? source.baseName : template.name
        let result = try ArchiveCreator().create(request) { progress?(0.5 + $0 * 0.5) }
        if let quarantine = source.parts.lazy.compactMap({ fileSystem.quarantine(of: $0) }).first {
            result.outputs.forEach { fileSystem.setQuarantine(quarantine, on: $0) }
        }
        return result
    }
}
