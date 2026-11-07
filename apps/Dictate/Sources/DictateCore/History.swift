import Foundation
import Observation

/// One past dictation. The file format matches the app Dictate replaces, so its history
/// imports byte for byte.
public struct TranscriptEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var text: String
    /// The app that was in front when it was dictated, if known.
    public var appName: String?

    public init(id: UUID = UUID(), date: Date, text: String, appName: String?) {
        self.id = id
        self.date = date
        self.text = text
        self.appName = appName
    }
}

/// Reads and writes the history file. Faked in tests.
public protocol HistoryPersistence: Sendable {
    func load() -> [TranscriptEntry]
    func save(_ entries: [TranscriptEntry])
}

/// `history.json` in Application Support, written atomically.
public struct HistoryFile: HistoryPersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TranscriptEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [TranscriptEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// True when the data is a history file this app can read.
    public static func isValid(_ data: Data) -> Bool {
        (try? JSONDecoder().decode([TranscriptEntry].self, from: data)) != nil
    }
}

/// Past dictations, newest first, capped so the file stays small.
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var entries: [TranscriptEntry]
    public let cap: Int
    @ObservationIgnored private let persistence: HistoryPersistence
    /// The last deletion, for Undo.
    @ObservationIgnored public private(set) var lastRemoved: [(entry: TranscriptEntry, index: Int)] = []

    public init(persistence: HistoryPersistence, cap: Int = 500) {
        self.persistence = persistence
        self.cap = cap
        entries = persistence.load()
    }

    /// Re-reads the file (after an import wrote it).
    public func reload() {
        entries = persistence.load()
    }

    public func add(_ text: String, appName: String?, date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(TranscriptEntry(date: date, text: trimmed, appName: appName), at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        persistence.save(entries)
    }

    public func delete(ids: Set<UUID>) {
        lastRemoved = entries.enumerated().filter { ids.contains($0.element.id) }.map { ($0.element, $0.offset) }
        guard !lastRemoved.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        persistence.save(entries)
    }

    public func clear() {
        lastRemoved = entries.enumerated().map { ($0.element, $0.offset) }
        entries.removeAll()
        persistence.save(entries)
    }

    /// Puts back what the last delete or clear removed, in their old places.
    public func undoRemoval() {
        guard !lastRemoved.isEmpty else { return }
        for (entry, index) in lastRemoved.sorted(by: { $0.index < $1.index }) where !entries.contains(where: { $0.id == entry.id }) {
            entries.insert(entry, at: min(index, entries.count))
        }
        lastRemoved = []
        persistence.save(entries)
    }

    /// Entries whose text or app name contains every word of `query` (any case, any accents).
    public func search(_ query: String) -> [TranscriptEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = entry.text + " " + (entry.appName ?? "")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
