import Foundation

/// One sheet in the library (its text lives in its own file).
public struct SheetInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), created: Date, modified: Date) {
        self.id = id
        self.created = created
        self.modified = modified
    }
}

/// `sheets.json`: which sheets exist and which one is open.
public struct LibraryIndex: Codable, Equatable, Sendable {
    public var sheets: [SheetInfo]
    public var current: UUID?

    public init(sheets: [SheetInfo] = [], current: UUID? = nil) {
        self.sheets = sheets
        self.current = current
    }
}

/// Where sheets are kept. The app uses files; tests use memory.
public protocol LibraryStorage {
    func loadIndex() -> LibraryIndex?
    func saveIndex(_ index: LibraryIndex) throws
    func loadText(_ id: UUID) -> String?
    func saveText(_ text: String, id: UUID) throws
    func deleteText(_ id: UUID) throws
    /// The single sheet from before there were several (`sheet.txt`), if it's still there.
    /// It's copied in once and left in place, so going back to an older Tally loses nothing.
    func loadLegacySheet() -> String?
}

/// `sheets.json` and `sheets/<id>.txt` in a folder; plain UTF-8 text, so sheets are never
/// locked in.
public struct FileLibraryStorage: LibraryStorage {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appendingPathComponent("sheets.json") }
    private var sheetsFolder: URL { directory.appendingPathComponent("sheets", isDirectory: true) }
    private var legacyURL: URL { directory.appendingPathComponent("sheet.txt") }
    public func url(for id: UUID) -> URL { sheetsFolder.appendingPathComponent("\(id.uuidString).txt") }

    public func loadIndex() -> LibraryIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryIndex.self, from: data)
    }

    public func saveIndex(_ index: LibraryIndex) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    public func loadText(_ id: UUID) -> String? {
        try? String(contentsOf: url(for: id), encoding: .utf8)
    }

    public func saveText(_ text: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: sheetsFolder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(for: id), options: .atomic)
    }

    public func deleteText(_ id: UUID) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func loadLegacySheet() -> String? {
        try? String(contentsOf: legacyURL, encoding: .utf8)
    }
}

/// The list of sheets: newest edit first, like Notes. Keeps the index and each sheet's
/// file in step. Pure logic; the app wraps it on the main actor.
public final class SheetLibrary {
    public private(set) var index: LibraryIndex
    private let storage: LibraryStorage
    private let now: () -> Date
    /// The first-run sheet, kept in memory until something is edited, so opening Tally and
    /// closing it again writes nothing.
    private var unsaved: (id: UUID, text: String)?

    /// Loads the library, copying a pre-library `sheet.txt` in as the first sheet, or starting
    /// with one sheet holding `firstText`.
    public init(storage: LibraryStorage, firstText: String, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
        if var loaded = storage.loadIndex(), !loaded.sheets.isEmpty {
            if loaded.current.map({ id in !loaded.sheets.contains { $0.id == id } }) ?? true {
                loaded.current = loaded.sheets.max { $0.modified < $1.modified }?.id
            }
            index = loaded
        } else {
            let date = now()
            let sheet = SheetInfo(created: date, modified: date)
            index = LibraryIndex(sheets: [sheet], current: sheet.id)
            unsaved = (sheet.id, storage.loadLegacySheet() ?? firstText)
        }
    }

    /// Writes the first-run sheet and the index once anything changes.
    private func persistFirstSheet() {
        guard let pending = unsaved else { return }
        unsaved = nil
        if index.sheets.contains(where: { $0.id == pending.id }) {
            try? storage.saveText(pending.text, id: pending.id)
        }
    }

    /// Newest edit first.
    public var sheets: [SheetInfo] {
        index.sheets.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.created > $1.created }
    }

    public var currentID: UUID {
        index.current ?? sheets[0].id
    }

    public func text(of id: UUID) -> String {
        if let pending = unsaved, pending.id == id { return pending.text }
        return storage.loadText(id) ?? ""
    }

    public func select(_ id: UUID) {
        guard index.sheets.contains(where: { $0.id == id }), index.current != id else { return }
        persistFirstSheet()
        index.current = id
        try? storage.saveIndex(index)
    }

    /// A new sheet, made current.
    @discardableResult
    public func create(text: String = "") -> SheetInfo {
        persistFirstSheet()
        let date = now()
        let sheet = SheetInfo(created: date, modified: date)
        index.sheets.append(sheet)
        index.current = sheet.id
        try? storage.saveText(text, id: sheet.id)
        try? storage.saveIndex(index)
        return sheet
    }

    /// Writes a sheet's text and marks it edited.
    public func save(_ text: String, id: UUID) throws {
        if unsaved?.id == id { unsaved = nil } else { persistFirstSheet() }
        try storage.saveText(text, id: id)
        if let i = index.sheets.firstIndex(where: { $0.id == id }) {
            index.sheets[i].modified = now()
            try storage.saveIndex(index)
        }
    }

    /// Removes a sheet. The library always keeps one: deleting the last leaves a new empty
    /// sheet. Returns the sheet that's current afterwards.
    @discardableResult
    public func delete(_ id: UUID) -> UUID {
        let order = sheets
        guard let position = order.firstIndex(where: { $0.id == id }) else { return currentID }
        if unsaved?.id == id { unsaved = nil } else { persistFirstSheet() }
        index.sheets.removeAll { $0.id == id }
        try? storage.deleteText(id)
        if index.sheets.isEmpty {
            return create().id
        }
        if index.current == id {
            // The next one down the list, like Notes.
            let remaining = order.filter { $0.id != id }
            index.current = remaining[min(position, remaining.count - 1)].id
        }
        try? storage.saveIndex(index)
        return currentID
    }

    /// The sheet `offset` places away from the current one in list order, wrapping around.
    public func neighbour(_ offset: Int) -> UUID {
        let order = sheets
        guard let i = order.firstIndex(where: { $0.id == currentID }), !order.isEmpty else { return currentID }
        return order[((i + offset) % order.count + order.count) % order.count].id
    }
}

/// What the sidebar calls a sheet: its first line with text, without `#` or `//`.
public enum SheetTitle {
    public static let untitled = "New Sheet"

    public static func title(of text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var t = line.trimmingCharacters(in: .whitespaces)
            while t.hasPrefix("#") { t.removeFirst() }
            if t.hasPrefix("//") { t.removeFirst(2) }
            t = t.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t.count > 60 ? String(t.prefix(60)) + "…" : t }
        }
        return untitled
    }
}
