import Foundation

/// One Move to Trash, remembered so it can be put back later, even after a relaunch.
public struct TrashLogEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    /// Which part of the app did it ("uninstall", "junk"...).
    public var section: String
    public var moved: [TrashedItem]
    public var appName: String?
    public var keptAppName: String?
    public var wasPutBack: Bool
    /// Some items were put back; `moved` lists the ones still in the Trash.
    public var partlyPutBack: Bool?

    public init(id: UUID = UUID(), date: Date = Date(), section: String, moved: [TrashedItem],
                appName: String? = nil, keptAppName: String? = nil, wasPutBack: Bool = false, partlyPutBack: Bool? = nil) {
        self.partlyPutBack = partlyPutBack
        self.id = id
        self.date = date
        self.section = section
        self.moved = moved
        self.appName = appName
        self.keptAppName = keptAppName
        self.wasPutBack = wasPutBack
    }
}

/// The log on disk: a small JSON file. Loading keeps only what can still be put back
/// (items still in the Trash, moves not yet undone).
public enum TrashLog {
    public static let maxEntries = 100

    public static func load(from file: URL, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [TrashLogEntry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([TrashLogEntry].self, from: data) else { return [] }
        return entries.compactMap { entry in
            guard !entry.wasPutBack else { return nil }
            var entry = entry
            entry.moved = entry.moved.filter { fileExists($0.trashed.path) }
            return entry.moved.isEmpty ? nil : entry
        }
    }

    public static func save(_ entries: [TrashLogEntry], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(entries.suffix(maxEntries)))
        try data.write(to: file, options: .atomic)
    }
}
