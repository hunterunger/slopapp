import Foundation

/// One saved color: in the history or in a palette.
public struct PickedColor: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var color: ColorValue
    /// When it was picked or added.
    public var date: Date
    /// A name the person gave it. nil shows the plain generated name.
    public var name: String?
    public var note: String?
    public var modified: Date?

    public init(id: UUID = UUID(), color: ColorValue, date: Date, name: String? = nil, note: String? = nil, modified: Date? = nil) {
        self.id = id
        self.color = color
        self.date = date
        self.name = name
        self.note = note
        self.modified = modified
    }

    /// The person's name for it, or a plain generated one ("Dark Blue").
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return ColorNamer.name(for: color)
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

    /// Replaces an item's name, note or color (edited in the color editor). A new color
    /// that's already elsewhere in the history replaces that older copy.
    public mutating func update(_ item: PickedColor) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        items.removeAll { $0.id != item.id && $0.color.identityKey == item.color.identityKey }
    }

    public mutating func clear() {
        items.removeAll()
    }
}

/// Everything Dropper saves: the history, the palettes and which palette new picks join.
public struct LibraryContents: Equatable, Codable, Sendable {
    public var history: [PickedColor]
    public var palettes: [Palette]
    public var activePaletteID: UUID?

    public init(history: [PickedColor] = [], palettes: [Palette] = [], activePaletteID: UUID? = nil) {
        self.history = history
        self.palettes = palettes
        self.activePaletteID = activePaletteID
    }
}

/// Where the library is kept. Faked in tests.
public protocol LibraryStore: Sendable {
    func load() throws -> LibraryContents
    func save(_ contents: LibraryContents) throws
}

/// `colors.json` in a folder. A file that can't be read is moved aside (never deleted) and the
/// app starts empty. Version 1 files (history only) load fine.
public struct FileLibraryStore: LibraryStore {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("colors.json")
    }

    struct FileContents: Codable {
        var version: Int
        var history: [PickedColor]
        var palettes: [Palette]?
        var activePalette: UUID?
    }

    public func load() throws -> LibraryContents {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LibraryContents() }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try Self.decoder.decode(FileContents.self, from: data)
            return LibraryContents(history: file.history, palettes: file.palettes ?? [], activePaletteID: file.activePalette)
        } catch {
            try? moveAside()
            throw error
        }
    }

    public func save(_ contents: LibraryContents) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = FileContents(version: 2, history: contents.history, palettes: contents.palettes,
                                activePalette: contents.activePaletteID)
        let data = try Self.encoder.encode(file)
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
public final class MemoryLibraryStore: LibraryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LibraryContents
    public private(set) var saveCount = 0

    public init(_ history: [PickedColor] = [], palettes: [Palette] = []) {
        stored = LibraryContents(history: history, palettes: palettes)
    }

    public func load() throws -> LibraryContents {
        lock.withLock { stored }
    }

    public func save(_ contents: LibraryContents) throws {
        lock.withLock {
            stored = contents
            saveCount += 1
        }
    }
}
