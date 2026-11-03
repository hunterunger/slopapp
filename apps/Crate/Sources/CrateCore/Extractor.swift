import CArchive
import Darwin
import Foundation

/// Limits that stop zip bombs and full disks.
public struct ExtractionLimits: Sendable, Equatable {
    /// Unpacked bytes may grow to `maxRatio` × the archive's size…
    public var maxRatio: Int64
    /// …but anything under this is always allowed (small archives of text compress well).
    public var ratioFloor: Int64
    /// Keep at least this much free on the destination volume.
    public var reserve: Int64

    public init(maxRatio: Int64 = 100, ratioFloor: Int64 = 1 << 30, reserve: Int64 = 256 << 20) {
        self.maxRatio = maxRatio
        self.ratioFloor = ratioFloor
        self.reserve = reserve
    }

    public static let standard = ExtractionLimits()

    /// The most an archive of `packed` bytes may unpack to.
    public func maximumUnpacked(forPacked packed: Int64) -> Int64 {
        let (product, overflow) = max(packed, 1).multipliedReportingOverflow(by: maxRatio)
        return max(ratioFloor, overflow ? .max : product)
    }
}

public struct ExtractionOptions: Sendable {
    public enum Layout: Sendable, Equatable {
        /// One top-level item → placed as is. Several → a folder named after the archive.
        case smart
        /// Every top-level item placed straight into the destination.
        case loose
    }

    public var password: String?
    /// Paths (from the listing) of the files and folders to extract; nil extracts all.
    /// Selected items become top-level items: "a/b" extracts as "b".
    public var selection: [String]?
    public var layout: Layout
    public var limits: ExtractionLimits
    /// The unpacked size the listing claims, when known: checked against the limits and
    /// free space before anything is written. (Headers can lie, so writing is checked too.)
    public var declaredBytes: Int64?

    public init(password: String? = nil, selection: [String]? = nil, layout: Layout = .smart,
                limits: ExtractionLimits = .standard, declaredBytes: Int64? = nil) {
        self.password = password
        self.selection = selection
        self.layout = layout
        self.limits = limits
        self.declaredBytes = declaredBytes
    }
}

/// An entry that wasn't written, and why.
public struct SkippedEntry: Sendable, Equatable {
    public enum Reason: String, Sendable {
        case absolutePath = "has an absolute path"
        case parentReference = "points outside the folder (“..”)"
        case linkOutside = "is a link to somewhere outside the folder"
        case writesThroughLink = "would be written through a link"
        case specialFile = "is a device or other special file"
        case nameTooLong = "has a name that's too long"
        case brokenHardlink = "links to a file that wasn't unpacked"
        case refused = "couldn't be written"
    }

    public let path: String
    public let reason: Reason
}

public struct ExtractionResult: Sendable, Equatable {
    /// The items placed in the destination (one folder for a wrapped extraction).
    public let outputs: [URL]
    public let fileCount: Int
    public let bytes: Int64
    public let skipped: [SkippedEntry]

    /// What to reveal or open.
    public var primary: URL? { outputs.first }

    /// "Skipped 2 unsafe items" style note, or nil.
    public var skippedNote: String? {
        guard !skipped.isEmpty else { return nil }
        return skipped.count == 1
            ? "Skipped 1 unsafe item: “\(skipped[0].path)” \(skipped[0].reason.rawValue)."
            : "Skipped \(skipped.count) unsafe items, such as “\(skipped[0].path)”, which \(skipped[0].reason.rawValue)."
    }
}

/// Unpacks archives safely:
/// - refuses absolute paths, "..", writing through symlinks, and links that leave the folder
/// - never overwrites anything (works in a hidden folder, then moves into place with
///   `RENAME_EXCL` and numbered names)
/// - stops zip bombs (`ExtractionLimits`) and full disks, removing partial output
/// - strips setuid/setgid bits, skips devices and FIFOs
/// - copies the archive's quarantine attribute onto everything it writes
public struct Extractor: Sendable {
    public let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = SystemFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Extracts into `destination`. Checks task cancellation; on any failure or cancel,
    /// nothing is left behind.
    public func extract(_ source: ArchiveSource, to destination: URL, options: ExtractionOptions = ExtractionOptions(),
                        progress: (@Sendable (Double) -> Void)? = nil) throws -> ExtractionResult {
        guard fileSystem.isWritableFolder(destination) else {
            throw CrateError.destinationNotWritable(folder: destination.lastPathComponent)
        }
        let packed = ArchiveReader.packedSize(of: source)
        let free = fileSystem.availableCapacity(at: destination)
        if let declared = options.declaredBytes {
            let limit = options.limits.maximumUnpacked(forPacked: packed)
            if declared > limit { throw CrateError.suspiciousSize(name: source.fileName, limit: limit) }
            if let free, declared + options.limits.reserve > free {
                throw CrateError.notEnoughSpace(name: source.fileName, needed: declared, available: free)
            }
        }
        let work = try Naming.makeWorkFolder(in: destination)
        var placed = false
        defer { if !placed { Naming.removeWorkFolder(work) } }

        let stats = try unpack(source, into: work, packed: packed, options: options, free: free, progress: progress)

        if let quarantine = source.parts.lazy.compactMap({ fileSystem.quarantine(of: $0) }).first {
            applyQuarantine(quarantine, under: work)
        }
        try Task.checkCancellation()

        let top = ((try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var outputs: [URL] = []
        switch options.layout {
        case .smart where top.count == 1:
            let item = work.appendingPathComponent(top[0])
            outputs = [try Naming.moveIntoPlace(item, named: top[0], in: destination, isFolder: isFolder(item))]
        case .smart:
            // Several items (or none): the working folder becomes the output folder.
            outputs = [try Naming.moveIntoPlace(work, named: source.baseName, in: destination, isFolder: true)]
            WorkFolderLedger.shared.remove(work)
            placed = true
        case .loose:
            for name in top {
                let item = work.appendingPathComponent(name)
                outputs.append(try Naming.moveIntoPlace(item, named: name, in: destination, isFolder: isFolder(item)))
            }
        }
        progress?(1)
        return ExtractionResult(outputs: outputs, fileCount: stats.files, bytes: stats.bytes, skipped: stats.skipped)
    }

    private struct Stats {
        var files = 0
        var bytes: Int64 = 0
        var skipped: [SkippedEntry] = []
    }

    // MARK: Unpacking

    private func unpack(_ source: ArchiveSource, into root: URL, packed: Int64, options: ExtractionOptions,
                        free: Int64?, progress: (@Sendable (Double) -> Void)?) throws -> Stats {
        let archive = try ReadArchive(source, password: options.password)
        guard let disk = archive_write_disk_new() else { throw CrateError.writeFailed(name: source.baseName, detail: "") }
        defer { archive_write_free(disk) }
        let flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_NO_OVERWRITE | ARCHIVE_EXTRACT_SECURE_SYMLINKS
            | ARCHIVE_EXTRACT_SECURE_NODOTDOT
        archive_write_disk_set_options(disk, Int32(flags))

        let rootPath = root.path
        let selection = SelectionMap(options.selection)
        let maxBytes = options.limits.maximumUnpacked(forPacked: packed)
        var stats = Stats()
        // Paths written so far, lowercased (APFS is usually case-insensitive) → is a folder.
        var taken: [String: Bool] = [:]
        // Archive path (lowercased) → where the file really went, for hardlinks.
        var realPaths: [String: String] = [:]
        var renamedFolders: [String: String] = [:]
        var blocks = 0
        var buffer: UnsafeRawPointer?
        var size = 0
        var offset: Int64 = 0

        func checkLimits() throws {
            if stats.bytes > maxBytes {
                throw CrateError.suspiciousSize(name: source.fileName, limit: maxBytes)
            }
            if let free, stats.bytes + options.limits.reserve > free {
                throw CrateError.notEnoughSpace(name: source.fileName, needed: stats.bytes + options.limits.reserve,
                                                available: free)
            }
        }

        while let entry = try archive.next() {
            try Task.checkCancellation()
            let header = EntryHeader(entry)
            let isRaw = archive.formatCode == ARCHIVE_FORMAT_RAW

            // 1. Where would it go?
            var components: [String]
            if isRaw {
                components = [source.baseName]
            } else {
                switch SafePath.check(header.rawPath) {
                case .safe(let parts): components = parts
                case .absolute:
                    stats.skipped.append(SkippedEntry(path: header.rawPath, reason: .absolutePath)); continue
                case .parentReference:
                    stats.skipped.append(SkippedEntry(path: header.rawPath, reason: .parentReference)); continue
                case .nameTooLong:
                    stats.skipped.append(SkippedEntry(path: header.rawPath, reason: .nameTooLong)); continue
                case .empty: continue
                }
                if components.first == "__MACOSX" { continue }
            }
            guard let mapped = selection.map(components) else { continue }
            components = mapped
            // Follow any renames of folders above it; a file in the way of a folder
            // renames the folder (the preview shows the same names).
            components = applyFolderRenames(components, renamedFolders)
            if components.count > 1 {
                for depth in 1..<components.count {
                    let prefix = components[0..<depth].joined(separator: "/").lowercased()
                    guard taken[prefix] == false else { continue }
                    let renamed = uniqueComponents(Array(components[0..<depth]), taken: taken)
                    renamedFolders[prefix] = renamed.last!
                    components[depth - 1] = renamed.last!
                }
            }
            let display = components.joined(separator: "/")

            // 2. What is it?
            switch header.kind {
            case .special:
                stats.skipped.append(SkippedEntry(path: display, reason: .specialFile)); continue
            case .symlink:
                guard let target = header.symlinkTarget, SafePath.linkStaysInside(components: components, target: target) else {
                    stats.skipped.append(SkippedEntry(path: display, reason: .linkOutside)); continue
                }
            case .hardlink:
                guard let rawTarget = header.hardlinkTarget, case .safe(var targetParts) = SafePath.check(rawTarget),
                      let mappedTarget = selection.map(targetParts) else {
                    stats.skipped.append(SkippedEntry(path: display, reason: .brokenHardlink)); continue
                }
                targetParts = applyFolderRenames(mappedTarget, renamedFolders)
                guard let real = realPaths[targetParts.joined(separator: "/").lowercased()] else {
                    stats.skipped.append(SkippedEntry(path: display, reason: .brokenHardlink)); continue
                }
                archive_entry_set_hardlink_utf8(entry, rootPath + "/" + real)
            case .file:
                if archive_entry_is_data_encrypted(entry) != 0, !archive.hasPassword {
                    throw CrateError.passwordRequired(name: source.fileName)
                }
            case .directory:
                break
            }

            // 3. Never let two entries share a name (README and readme on APFS, duplicates,
            //    a file named like a folder). Folders with the same name merge.
            let key = components.joined(separator: "/").lowercased()
            if let existingIsFolder = taken[key] {
                if !(header.kind == .directory && existingIsFolder) {
                    components = uniqueComponents(components, taken: taken)
                    if header.kind == .directory { renamedFolders[key] = components.last! }
                }
            } else if header.kind != .directory, Naming.exists(root.appendingPathComponent(components.joined(separator: "/"))) {
                components = uniqueComponents(components, taken: taken)
            }
            let relative = components.joined(separator: "/")
            for depth in 1..<max(components.count, 1) {
                let parent = components[0..<depth].joined(separator: "/").lowercased()
                if taken[parent] == nil { taken[parent] = true }
            }
            taken[relative.lowercased()] = header.kind == .directory
            if header.kind == .file { realPaths[key] = relative }

            // 4. Write it.
            archive_entry_set_pathname_utf8(entry, rootPath + "/" + relative)
            let perm = header.perm & 0o777
            archive_entry_set_perm(entry, header.kind == .directory ? perm | 0o700 : perm | 0o600)
            let result = archive_write_header(disk, entry)
            if result < ARCHIVE_WARN {
                if result == ARCHIVE_FATAL {
                    throw CrateError.writeFailed(name: source.baseName, detail: diskError(disk))
                }
                let message = diskError(disk).lowercased()
                let reason: SkippedEntry.Reason = message.contains("symlink") || message.contains("link")
                    ? .writesThroughLink : .refused
                stats.skipped.append(SkippedEntry(path: relative, reason: reason))
                taken[relative.lowercased()] = nil
                realPaths[key] = nil
                continue
            }
            if header.kind == .file {
                while true {
                    let r = archive_read_data_block(archive.handle, &buffer, &size, &offset)
                    if r == ARCHIVE_EOF { break }
                    if r < ARCHIVE_WARN {
                        throw archive.error(r, encryptedEntry: header.isEncrypted)
                    }
                    if size > 0, let buffer {
                        if archive_write_data_block(disk, buffer, size, offset) < 0 {
                            throw CrateError.writeFailed(name: source.baseName, detail: diskError(disk))
                        }
                        stats.bytes += Int64(size)
                        try checkLimits()
                    }
                    blocks += 1
                    if blocks % 64 == 0 {
                        try Task.checkCancellation()
                        if packed > 0 { progress?(min(0.99, Double(archive.bytesRead) / Double(packed))) }
                    }
                }
                stats.files += 1
            }
            if archive_write_finish_entry(disk) < ARCHIVE_WARN {
                throw CrateError.writeFailed(name: source.baseName, detail: diskError(disk))
            }
            if packed > 0 { progress?(min(0.99, Double(archive.bytesRead) / Double(packed))) }
        }
        return stats
    }

    private func diskError(_ disk: OpaquePointer) -> String {
        archive_error_string(disk).map { String(cString: $0) } ?? ""
    }

    private func applyFolderRenames(_ components: [String], _ renames: [String: String]) -> [String] {
        guard !renames.isEmpty, components.count > 1 else { return components }
        var result = components
        for index in 0..<(components.count - 1) {
            let key = result[0...index].joined(separator: "/").lowercased()
            if let renamed = renames[key] { result[index] = renamed }
        }
        return result
    }

    private func uniqueComponents(_ components: [String], taken: [String: Bool]) -> [String] {
        var number = 2
        let parent = components.dropLast()
        let name = components.last!
        while true {
            let candidate = Array(parent) + [Naming.candidate(name, number: number, isFolder: false)]
            if taken[candidate.joined(separator: "/").lowercased()] == nil { return candidate }
            number += 1
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0!, &info) }) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }

    private func applyQuarantine(_ value: Data, under root: URL) {
        // The root too: it becomes the output folder when the contents get wrapped.
        fileSystem.setQuarantine(value, on: root)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        while let url = enumerator.nextObject() as? URL {
            fileSystem.setQuarantine(value, on: url)
        }
    }
}

/// Maps entry paths to their place in a selective extraction: selected "a/b" makes
/// "a/b/c.txt" land as "b/c.txt". Two selected items with the same name get numbered.
struct SelectionMap {
    private let roots: [(parts: [String], name: String)]?

    init(_ selection: [String]?) {
        guard let selection else { roots = nil; return }
        // Drop items inside other selected items (they come with their folder).
        let sorted = selection.map { $0.split(separator: "/").map(String.init) }.filter { !$0.isEmpty }
            .sorted { $0.count < $1.count }
        var kept: [[String]] = []
        for parts in sorted where !kept.contains(where: { parts.starts(with: $0) }) {
            kept.append(parts)
        }
        var used: Set<String> = []
        roots = kept.map { parts in
            var number = 1
            var name = parts.last!
            while used.contains(name.lowercased()) {
                number += 1
                name = Naming.candidate(parts.last!, number: number, isFolder: false)
            }
            used.insert(name.lowercased())
            return (parts, name)
        }
    }

    /// Nil when the entry isn't selected.
    func map(_ components: [String]) -> [String]? {
        guard let roots else { return components }
        for root in roots where components.starts(with: root.parts) {
            return [root.name] + components.dropFirst(root.parts.count)
        }
        return nil
    }
}
