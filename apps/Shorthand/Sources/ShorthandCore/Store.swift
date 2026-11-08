import Foundation

/// The library on disk: one JSON file, written atomically, with daily backups (the last 7).
/// A damaged file loads the newest readable backup instead, and says so.
public final class SnippetStore: @unchecked Sendable {
    public static let fileName = "Library.json"
    public static let backupsFolder = "Backups"
    public static let keepBackups = 7

    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    public var backupsURL: URL { directory.appendingPathComponent(Self.backupsFolder, isDirectory: true) }

    public enum LoadResult: Equatable, Sendable {
        case fresh(Library)
        case loaded(Library)
        /// The library file couldn't be read; this is the newest backup.
        case recovered(Library, backupName: String)
        /// Nothing readable at all: an empty library (the damaged file is kept aside).
        case damaged(Library)

        public var library: Library {
            switch self {
            case .fresh(let l), .loaded(let l), .recovered(let l, _), .damaged(let l): l
            }
        }
    }

    public func load() -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .fresh(Library()) }
        if let library = read(fileURL) { return .loaded(library) }
        // Keep the damaged file for the person (or us) to look at.
        let aside = directory.appendingPathComponent("Library (damaged \(Self.stamp(Date()))).json")
        try? fileManager.moveItem(at: fileURL, to: aside)
        for backup in backups().reversed() {
            if let library = read(backup) {
                try? save(library)
                return .recovered(library, backupName: backup.lastPathComponent)
            }
        }
        return .damaged(Library())
    }

    func read(_ url: URL) -> Library? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var library = try? decoder.decode(Library.self, from: data) else { return nil }
        library.normalize()
        return library
    }

    public static func encode(_ library: Library) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(library)
    }

    public static func decode(_ data: Data) throws -> Library {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var library = try decoder.decode(Library.self, from: data)
        library.normalize()
        return library
    }

    public func save(_ library: Library) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(library).write(to: fileURL, options: .atomic)
    }

    /// Copies today's library into Backups once per day and keeps the newest 7.
    @discardableResult
    public func backUpIfNeeded(now: Date = Date()) -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let name = "Library \(Self.day(now)).json"
        let target = backupsURL.appendingPathComponent(name)
        try? fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: target.path) {
            try? fileManager.copyItem(at: fileURL, to: target)
        }
        let all = backups()
        if all.count > Self.keepBackups {
            for old in all.prefix(all.count - Self.keepBackups) { try? fileManager.removeItem(at: old) }
        }
        return fileManager.fileExists(atPath: target.path) ? target : nil
    }

    /// Oldest first (names sort by date).
    public func backups() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("Library ") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}

/// Export and import of Shorthand's own JSON (the same shape as the library file).
public enum LibraryExport {
    public static func data(_ library: Library) throws -> Data { try SnippetStore.encode(library) }

    /// Merges an exported library: groups by name, snippets whose abbreviation already exists
    /// are skipped. Returns how many snippets were added.
    @discardableResult
    public static func merge(_ imported: Library, into library: inout Library) -> Int {
        let existing = Set(library.snippets.map(\.abbreviation))
        var added = 0
        for group in imported.groups {
            let snippets = imported.snippets.filter { $0.groupID == group.id && !existing.contains($0.abbreviation) }
            guard !snippets.isEmpty else { continue }
            let target = library.groups.first { $0.name == group.name }?.id ?? library.addGroup(named: group.name).id
            for var snippet in snippets {
                snippet.id = UUID()
                snippet.groupID = target
                library.addSnippet(snippet)
                added += 1
            }
        }
        return added
    }
}
