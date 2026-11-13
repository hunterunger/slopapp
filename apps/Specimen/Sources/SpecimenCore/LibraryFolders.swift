import Foundation

// Library folders: fonts managed where they are. A folder you add is scanned (recursively)
// and watched; its fonts join the library inactive, and activating one registers the file in
// place (nothing is copied). See `Registration.swift` for turning them on and off.

/// A folder of fonts in the library. Specimen isn't sandboxed, so a path is enough to read it;
/// the bookmark only follows the folder if it's moved or renamed while Specimen is closed.
public struct LibraryFolder: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// As added (not resolved through symlinks): font paths and registrations use this form.
    public var path: String
    public var bookmark: Data?
    public var added: Date

    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, added: Date = Date()) {
        self.id = id
        self.path = LibraryPaths.trimmed(path)
        self.bookmark = bookmark
        self.added = added
    }

    public var name: String { (path as NSString).lastPathComponent }

    public func contains(_ path: String) -> Bool { LibraryPaths.isInside(path, folder: self.path) }
}

public enum LibraryPaths {
    /// What the scanner reads. (Type 1 and suitcases need files CoreText can't register.)
    public static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont", "woff", "woff2"]

    public static func isFontFile(_ path: String) -> Bool {
        fontExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// `path` is `folder` itself or anywhere below it.
    public static func isInside(_ path: String, folder: String, orEqual: Bool = false) -> Bool {
        if orEqual, path == folder { return true }
        return path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// No trailing slash (except "/").
    public static func trimmed(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Hidden files and folders (".git", "._Font.otf") are skipped, like Finder does.
    public static func isHidden(_ path: String, below root: String) -> Bool {
        guard isInside(path, folder: root) else { return false }
        return path.dropFirst(root.count + 1).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// FSEvents reports real paths ("/private/tmp/…"); map one back to the form the folder
    /// was added in ("/tmp/…"). Nil when it isn't inside `real`.
    public static func rebase(_ path: String, real: String, root: String) -> String? {
        let path = trimmed(path)
        if path == real { return root }
        guard isInside(path, folder: real) else { return nil }
        return root + path.dropFirst(real.count)
    }

    /// The folders macOS installs fonts into. They're already in the library, switched on
    /// and off with the system switch, so they can't also be library folders.
    public static func installedFontFolders(home: String = NSHomeDirectory()) -> [String] {
        ["/System/Library/Fonts", "/System/Library/AssetsV2", "/Library/Fonts", "/Network/Library/Fonts", home + "/Library/Fonts"]
    }
}

/// What adding a folder does, given the folders already there.
public enum FolderAddition: Equatable, Sendable {
    /// Add it; any existing folders inside it are folded into it.
    case add(path: String, replacing: [UUID])
    /// It's already in the library (it is, or is inside, `folder`).
    case alreadyIncluded(folder: UUID)
    /// It's (inside) a folder macOS installs fonts into.
    case installedFonts

    public static func plan(_ path: String, existing: [LibraryFolder], installed: [String] = LibraryPaths.installedFontFolders()) -> FolderAddition {
        let path = LibraryPaths.trimmed(path)
        if installed.contains(where: { LibraryPaths.isInside(path, folder: $0, orEqual: true) }) { return .installedFonts }
        if let parent = existing.first(where: { LibraryPaths.isInside(path, folder: $0.path, orEqual: true) }) {
            return .alreadyIncluded(folder: parent.id)
        }
        return .add(path: path, replacing: existing.filter { LibraryPaths.isInside($0.path, folder: path) }.map(\.id))
    }
}

/// The library folders, in folders.json.
public struct FoldersStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("folders.json")
    }

    struct File: Codable {
        var version = 1
        var folders: [LibraryFolder]
    }

    public func load() -> [LibraryFolder] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(File.self, from: data) { return file.folders }
        let backup = url.deletingPathExtension().appendingPathExtension("damaged.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return []
    }

    public func save(_ folders: [LibraryFolder]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(File(folders: folders)).write(to: url, options: .atomic)
    }
}

// MARK: Scanning

/// Enough to tell whether a file changed since it was read.
public struct FileStamp: Codable, Hashable, Sendable {
    public var path: String
    public var modified: Date?
    public var size: Int64

    public init(path: String, modified: Date?, size: Int64) {
        self.path = path
        self.modified = modified
        self.size = size
    }
}

/// The file system as the scanner sees it. `LocalLibraryFileSystem` in the app; a fake in tests.
public protocol LibraryFileSystem: Sendable {
    /// Every font file under `root`, recursively, skipping hidden items and packages.
    func fontFiles(under root: String) -> [FileStamp]
    /// Nil when the file is gone.
    func stamp(of path: String) -> FileStamp?
    func directoryExists(_ path: String) -> Bool
    /// The faces in each file (empty for a file CoreText can't read). Paths are read in parallel.
    func readFaces(_ paths: [String]) -> [String: [SystemFace]]
}

/// One change FSEvents reported (or a fake one in tests).
public struct FolderEvent: Equatable, Sendable {
    public struct Flags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let created = Flags(rawValue: 1 << 0)
        public static let removed = Flags(rawValue: 1 << 1)
        public static let renamed = Flags(rawValue: 1 << 2)
        public static let modified = Flags(rawValue: 1 << 3)
        public static let isFile = Flags(rawValue: 1 << 4)
        public static let isDirectory = Flags(rawValue: 1 << 5)
        /// Events were coalesced or dropped: rescan below this path.
        public static let mustRescan = Flags(rawValue: 1 << 6)
        /// The watched folder itself was moved, renamed or deleted.
        public static let rootChanged = Flags(rawValue: 1 << 7)
    }

    public var path: String
    public var flags: Flags

    public init(path: String, flags: Flags) {
        self.path = path
        self.flags = flags
    }
}

/// What a scan or a batch of events changed, by file. Names are PostScript names, kept so a
/// renamed or moved file can stay active (see `RegistrationCarryOver`).
public struct LibraryChange: Equatable, Sendable {
    public var added: [String: [String]] = [:]
    public var removed: [String: [String]] = [:]
    public var changed: Set<String> = []

    public init() {}

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
    public var fileCount: Int { added.count + removed.count + changed.count }

    public mutating func merge(_ other: LibraryChange) {
        for (path, names) in other.added {
            if removed[path] != nil { removed[path] = nil; changed.insert(path) } else { added[path] = names }
        }
        for (path, names) in other.removed {
            if added[path] != nil { added[path] = nil } else { removed[path] = names }
            changed.remove(path)
        }
        changed.formUnion(other.changed.filter { added[$0] == nil })
    }
}

/// Every font file in the library folders and the faces in it. Cached on disk (library.plist)
/// so a launch only re-reads files whose date or size changed. Pure apart from the
/// `LibraryFileSystem` it's given.
public struct LibraryScan: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public var stamp: FileStamp
        /// Empty when the file isn't a font CoreText can read (kept so it isn't re-read).
        public var faces: [SystemFace]
    }

    public static let currentVersion = 1
    public var version = LibraryScan.currentVersion
    public private(set) var files: [String: File] = [:]

    public init() {}

    public static func load(from url: URL) -> LibraryScan {
        guard let data = try? Data(contentsOf: url),
              let scan = try? PropertyListDecoder().decode(LibraryScan.self, from: data),
              scan.version == currentVersion else { return LibraryScan() }
        return scan
    }

    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Faces of files inside `roots` (folders that are online), sorted by path for stable output.
    public func faces(in roots: [String]) -> [SystemFace] {
        files.keys.sorted().filter { path in roots.contains { LibraryPaths.isInside(path, folder: $0) } }
            .flatMap { files[$0]?.faces ?? [] }
    }

    public func paths(in root: String) -> [String] {
        files.keys.filter { LibraryPaths.isInside($0, folder: root) }
    }

    /// Files CoreText couldn't read, inside `root`.
    public func unreadableCount(in root: String) -> Int {
        files.filter { LibraryPaths.isInside($0.key, folder: root) && $0.value.faces.isEmpty }.count
    }

    /// Brings `directory` (a library folder or one inside it) up to date: new and changed
    /// files are read, missing ones dropped. A directory that's gone drops everything below it.
    public mutating func rescan(_ directory: String, fileSystem: some LibraryFileSystem) -> LibraryChange {
        let directory = LibraryPaths.trimmed(directory)
        var change = LibraryChange()
        let known = files.keys.filter { LibraryPaths.isInside($0, folder: directory) }
        guard fileSystem.directoryExists(directory) else {
            for path in known { change.removed[path] = files.removeValue(forKey: path)?.faces.map(\.postScriptName) ?? [] }
            return change
        }
        let found = fileSystem.fontFiles(under: directory)
        let foundPaths = Set(found.map(\.path))
        for path in known where !foundPaths.contains(path) {
            change.removed[path] = files.removeValue(forKey: path)?.faces.map(\.postScriptName) ?? []
        }
        let stale = found.filter { files[$0.path]?.stamp != $0 }
        change.merge(read(stale, fileSystem: fileSystem))
        return change
    }

    /// Applies a batch of FSEvents. Files are re-checked one by one; directory events (and
    /// coalesced ones) rescan that directory. Events outside `roots` are ignored.
    public mutating func apply(_ events: [FolderEvent], roots: [String], fileSystem: some LibraryFileSystem) -> LibraryChange {
        var directories = Set<String>()
        var filePaths = Set<String>()
        for event in events {
            let path = LibraryPaths.trimmed(event.path)
            guard let root = roots.first(where: { LibraryPaths.isInside(path, folder: $0, orEqual: true) }) else { continue }
            if LibraryPaths.isHidden(path, below: root) { continue }
            if event.flags.contains(.rootChanged) {
                // A folder that went away (a disk unplugged, the folder moved) goes offline
                // with its files remembered; only a folder that's still there is rescanned.
                if fileSystem.directoryExists(root) { directories.insert(root) }
            } else if event.flags.contains(.mustRescan) {
                directories.insert(event.flags.contains(.isFile) ? (path as NSString).deletingLastPathComponent : path)
            } else if event.flags.contains(.isDirectory) {
                directories.insert(path)
            } else if LibraryPaths.isFontFile(path) {
                filePaths.insert(path)
            } else if !event.flags.contains(.isFile) {
                // No item type (FSEvents without file events): treat it as a directory.
                directories.insert(path)
            }
        }
        // Rescan the outermost directories only.
        let outermost = directories.filter { dir in !directories.contains { $0 != dir && LibraryPaths.isInside(dir, folder: $0) } }
        var change = LibraryChange()
        for directory in outermost.sorted() { change.merge(rescan(directory, fileSystem: fileSystem)) }
        var stale: [FileStamp] = []
        for path in filePaths.sorted() where !outermost.contains(where: { LibraryPaths.isInside(path, folder: $0) }) {
            if let stamp = fileSystem.stamp(of: path) {
                if files[path]?.stamp != stamp { stale.append(stamp) }
            } else if let gone = files.removeValue(forKey: path) {
                change.removed[path] = gone.faces.map(\.postScriptName)
            }
        }
        change.merge(read(stale, fileSystem: fileSystem))
        return change
    }

    /// Forgets a folder that was removed from the library.
    public mutating func remove(_ root: String) -> LibraryChange {
        var change = LibraryChange()
        for path in paths(in: root) { change.removed[path] = files.removeValue(forKey: path)?.faces.map(\.postScriptName) ?? [] }
        return change
    }

    private mutating func read(_ stamps: [FileStamp], fileSystem: some LibraryFileSystem) -> LibraryChange {
        var change = LibraryChange()
        guard !stamps.isEmpty else { return change }
        let faces = fileSystem.readFaces(stamps.map(\.path))
        for stamp in stamps {
            let read = faces[stamp.path] ?? []
            if files[stamp.path] == nil { change.added[stamp.path] = read.map(\.postScriptName) } else { change.changed.insert(stamp.path) }
            files[stamp.path] = File(stamp: stamp, faces: read)
        }
        return change
    }
}

// MARK: Sidebar tree

/// A folder in the sidebar: a library folder and, below it, the folders inside it that hold fonts.
public struct FolderNode: Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    /// Nil (not empty) when there are none, so the sidebar shows no disclosure triangle.
    public var children: [FolderNode]?

    public var id: String { path }

    public init(path: String, name: String, children: [FolderNode]? = nil) {
        self.path = path
        self.name = name
        self.children = children
    }

    /// The tree of folders under `root` that contain font files (directly or deeper).
    public static func tree(root: String, files: some Collection<String>) -> FolderNode {
        // Every directory between the root and each file.
        var children: [String: Set<String>] = [:]
        for file in files where LibraryPaths.isInside(file, folder: root) {
            var directory = (file as NSString).deletingLastPathComponent
            while directory != root, LibraryPaths.isInside(directory, folder: root) {
                let parent = (directory as NSString).deletingLastPathComponent
                children[parent, default: []].insert(directory)
                directory = parent
            }
        }
        func node(_ path: String) -> FolderNode {
            let kids = (children[path] ?? []).sorted {
                ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending
            }.map(node)
            return FolderNode(path: path, name: (path as NSString).lastPathComponent, children: kids.isEmpty ? nil : kids)
        }
        return node(root)
    }

    /// This node and every node below it.
    public var allPaths: [String] { [path] + (children ?? []).flatMap(\.allPaths) }
}

// MARK: Merging with the registry

public enum LibraryMerge {
    /// The registry's faces plus library faces that aren't registered (inactive). Registered
    /// library files are already in the registry with their real state. `temporaryPaths` are
    /// files Specimen registered for this session only.
    public static func merge(registry: [SystemFace], library: [SystemFace], temporaryPaths: Set<String>) -> [SystemFace] {
        var result = registry.map { face -> SystemFace in
            var face = face
            face.isTemporary = face.isEnabled && face.path.map(temporaryPaths.contains) == true
            return face
        }
        var ids = Set(result.map(\.id))
        for face in library where ids.insert(face.id).inserted {
            var face = face
            face.isEnabled = false
            face.isTemporary = false
            result.append(face)
        }
        return result
    }
}
