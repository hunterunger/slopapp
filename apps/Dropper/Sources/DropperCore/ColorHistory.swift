import Foundation

/// One color in the history.
public struct PickedColor: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var color: ColorValue
    public var date: Date

    public init(id: UUID = UUID(), color: ColorValue, date: Date) {
        self.id = id
        self.color = color
        self.date = date
    }
}

/// Newest first, no duplicates, at most `limit` colors.
public struct ColorHistory: Equatable, Sendable {
    public static let defaultLimit = 100

    public private(set) var items: [PickedColor]
    public let limit: Int

    public init(items: [PickedColor] = [], limit: Int = defaultLimit) {
        self.limit = limit
        self.items = []
        // Normalize whatever was loaded: newest first is the file order; drop repeats and overflow.
        for item in items where !self.items.contains(where: { $0.color.identityKey == item.color.identityKey }) {
            self.items.append(item)
        }
        if self.items.count > limit { self.items.removeLast(self.items.count - limit) }
    }

    public var latest: PickedColor? { items.first }

    /// Adds a color at the top. Picking a color that's already there moves it to the top.
    @discardableResult
    public mutating func add(_ color: ColorValue, at date: Date) -> PickedColor {
        items.removeAll { $0.color.identityKey == color.identityKey }
        let item = PickedColor(color: color, date: date)
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        return item
    }

    /// Moves an existing color to the top (it was just used again).
    public mutating func touch(_ id: PickedColor.ID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.date = date
        items.insert(item, at: 0)
    }

    public mutating func remove(_ id: PickedColor.ID) {
        items.removeAll { $0.id == id }
    }

    public mutating func clear() {
        items.removeAll()
    }
}

/// Where the history is kept. Faked in tests.
public protocol HistoryStore: Sendable {
    func load() throws -> [PickedColor]
    func save(_ items: [PickedColor]) throws
}

/// `colors.json` in a folder. A file that can't be read is moved aside (never deleted) and the
/// app starts with an empty history.
public struct FileHistoryStore: HistoryStore {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("colors.json")
    }

    struct FileContents: Codable {
        var version: Int
        var history: [PickedColor]
    }

    public func load() throws -> [PickedColor] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(FileContents.self, from: data).history
        } catch {
            try? moveAside()
            throw error
        }
    }

    public func save(_ items: [PickedColor]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(FileContents(version: 1, history: items))
        try data.write(to: fileURL, options: .atomic)
    }

    /// Renames an unreadable file to `colors.json.unreadable-<timestamp>`.
    func moveAside() throws {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("colors.json.unreadable-\(stamp)")
        try FileManager.default.moveItem(at: fileURL, to: backup)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Keeps everything in memory. For tests and previews.
public final class MemoryHistoryStore: HistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PickedColor]
    public private(set) var saveCount = 0

    public init(_ items: [PickedColor] = []) {
        stored = items
    }

    public func load() throws -> [PickedColor] {
        lock.withLock { stored }
    }

    public func save(_ items: [PickedColor]) throws {
        lock.withLock {
            stored = items
            saveCount += 1
        }
    }
}
