import Darwin
import Foundation
import UniformTypeIdentifiers

/// Broad file kinds for grouping and filtering large files.
public enum FileKind: String, CaseIterable, Sendable, Identifiable {
    case diskImage, archive, video, audio, image, document, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .diskImage: "Disk Images and Installers"
        case .archive: "Archives"
        case .video: "Movies"
        case .audio: "Audio"
        case .image: "Pictures"
        case .document: "Documents"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .diskImage: "opticaldiscdrive"
        case .archive: "doc.zipper"
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc.richtext"
        case .other: "doc"
        }
    }

    public static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ["dmg", "iso", "img", "sparseimage", "pkg", "mpkg", "toast", "cdr"].contains(ext) { return .diskImage }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .document }
        return .other
    }
}

public struct LargeFile: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    /// The file's size (what Finder shows).
    public var size: Int64
    public var modified: Date
    /// When it was last opened, if Spotlight knows; otherwise nil.
    public var lastOpened: Date?
    public var kind: FileKind

    public init(url: URL, size: Int64, modified: Date, lastOpened: Date? = nil, kind: FileKind? = nil) {
        self.url = url
        self.size = size
        self.modified = modified
        self.lastOpened = lastOpened
        self.kind = kind ?? FileKind.of(url)
    }

    /// The date "old" is judged by: last opened, or last modified when that's unknown.
    public var lastUsed: Date { max(lastOpened ?? modified, modified) }

    public var name: String { url.lastPathComponent }
}

/// Finds big files under a folder. Skips `~/Library`, hidden folders, the Trash, packages
/// (apps, Photos libraries...) and cloud files that aren't downloaded.
public struct LargeFileScanner: Sendable {
    public var root: URL
    public var minimumSize: Int64
    public var excluded: [URL]

    public init(root: URL, minimumSize: Int64, excluded: [URL] = []) {
        self.root = root.standardizedFileURL
        self.minimumSize = minimumSize
        self.excluded = excluded.map(\.standardizedFileURL)
    }

    public static func forHome(_ environment: TidyEnvironment, minimumSize: Int64) -> LargeFileScanner {
        LargeFileScanner(root: environment.home, minimumSize: minimumSize,
                         excluded: [environment.library, environment.home.appendingPathComponent(".Trash")]
                            + [environment.trashDirectory].compactMap { $0 } + environment.applicationDirectories)
    }

    /// Walks the folder. `progress` gets the number of files looked at (every few thousand).
    /// Returns nil if cancelled.
    public func scan(progress: (@Sendable (Int) -> Void)? = nil) -> [LargeFile]? {
        guard let cPath = strdup(root.path) else { return [] }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return [] }
        defer { fts_close(fts) }

        let excludedPaths = Set(excluded.map(\.path) + excluded.map { $0.resolvingSymlinksInPath().path })
        var packageExtensions: [String: Bool] = [:]
        var found: [LargeFile] = []
        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 2047 == 0 {
                if Task.isCancelled { return nil }
                progress?(visited)
            }
            let ent = entry.pointee
            let info = Int32(ent.fts_info)
            if info == FTS_D {
                guard ent.fts_level > 0 else { continue }
                let path = String(cString: ent.fts_path)
                let name = (path as NSString).lastPathComponent
                let ext = (name as NSString).pathExtension.lowercased()
                var skip = name.hasPrefix(".") || excludedPaths.contains(path)
                if !skip, !ext.isEmpty {
                    let isPackage = packageExtensions[ext] ?? {
                        let type = UTType(filenameExtension: ext, conformingTo: .directory)
                        let result = type.map { $0.conforms(to: .package) || $0.conforms(to: .bundle) } ?? false
                        packageExtensions[ext] = result
                        return result
                    }()
                    skip = isPackage
                }
                if skip { fts_set(fts, entry, FTS_SKIP) }
                continue
            }
            guard info == FTS_F, let st = ent.fts_statp?.pointee else { continue }
            let size = Int64(st.st_size)
            // Skip files smaller than the threshold and cloud placeholders (no blocks on disk).
            guard size >= minimumSize, st.st_blocks > 0 else { continue }
            let path = String(cString: ent.fts_path)
            if (path as NSString).lastPathComponent.hasPrefix(".") { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            found.append(LargeFile(url: URL(fileURLWithPath: path), size: size, modified: modified))
        }
        progress?(visited)
        return found.sorted { $0.size > $1.size }
    }
}

/// Filters for the Large & Old list.
public struct LargeFileFilter: Sendable, Equatable {
    public var minimumSize: Int64
    /// Only files not used for at least this long (nil = any age).
    public var olderThan: TimeInterval?
    public var kind: FileKind?

    public init(minimumSize: Int64 = 100_000_000, olderThan: TimeInterval? = nil, kind: FileKind? = nil) {
        self.minimumSize = minimumSize
        self.olderThan = olderThan
        self.kind = kind
    }

    public func apply(_ files: [LargeFile], now: Date) -> [LargeFile] {
        files.filter { file in
            file.size >= minimumSize
                && (olderThan.map { file.lastUsed <= now.addingTimeInterval(-$0) } ?? true)
                && (kind.map { file.kind == $0 } ?? true)
        }
    }
}
