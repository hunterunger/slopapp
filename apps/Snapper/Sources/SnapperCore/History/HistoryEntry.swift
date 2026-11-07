import CoreGraphics
import Foundation

// Capture History: every capture kept on disk (its own folder), listed in one small index.
// Pure values here; `HistoryStore` does the file work.

/// What kind of capture an entry is, for the History window's filter.
public enum HistoryKind: String, Sendable, CaseIterable, Identifiable, Codable {
    case screenshot, window, scrolling, recording, gif

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenshot: "Screenshots"
        case .window: "Windows"
        case .scrolling: "Scrolling Captures"
        case .recording: "Recordings"
        case .gif: "GIFs"
        }
    }

    /// One item, for labels ("Screenshot", "GIF").
    public var singular: String {
        switch self {
        case .screenshot: "Screenshot"
        case .window: "Window"
        case .scrolling: "Scrolling Capture"
        case .recording: "Recording"
        case .gif: "GIF"
        }
    }

    public var isMedia: Bool { self == .recording || self == .gif }

    /// The kind for a capture path's diagnostic name ("area", "window", "gif"…).
    public init(captureKind: String) {
        switch captureKind {
        case "window", "selfTimerWindow": self = .window
        case "scrolling": self = .scrolling
        case "video": self = .recording
        case "gif": self = .gif
        default: self = .screenshot
        }
    }

    /// Unknown kinds (from a newer version) read as screenshots instead of failing.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HistoryKind(rawValue: raw) ?? .screenshot
    }
}

/// The app a capture came from.
public struct SourceApp: Equatable, Hashable, Sendable, Codable {
    public var bundleID: String?
    public var name: String

    public init(bundleID: String?, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// One capture in history. Every field but `id` decodes with a default, so an index written
/// by an older or newer Snapper still loads.
public struct HistoryEntry: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var createdAt: Date
    public var kind: HistoryKind
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Pixels per point.
    public var scale: Double
    /// The current version (edits burned in), named like a saved capture. A recording's file.
    public var fileName: String
    /// The unedited capture (images only), so edits stay editable.
    public var originalFileName: String?
    /// The edits as an `AnnotationDocument` (JSON), when edited.
    public var documentFileName: String?
    /// A recording's first frame.
    public var posterFileName: String?
    /// Bytes on disk for the whole folder.
    public var byteSize: Int64
    public var source: SourceApp?
    /// Recordings.
    public var duration: Double?
    /// Where Save last wrote it.
    public var savedPath: String?

    public init(id: UUID = UUID(), createdAt: Date, kind: HistoryKind, pixelWidth: Int, pixelHeight: Int, scale: Double,
                fileName: String, originalFileName: String? = nil, documentFileName: String? = nil, posterFileName: String? = nil,
                byteSize: Int64 = 0, source: SourceApp? = nil, duration: Double? = nil, savedPath: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.documentFileName = documentFileName
        self.posterFileName = posterFileName
        self.byteSize = byteSize
        self.source = source
        self.duration = duration
        self.savedPath = savedPath
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, pixelWidth, pixelHeight, scale, fileName, originalFileName, documentFileName
        case posterFileName, byteSize, source, duration, savedPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        kind = (try? c.decodeIfPresent(HistoryKind.self, forKey: .kind)) ?? .screenshot
        pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 2
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        originalFileName = try c.decodeIfPresent(String.self, forKey: .originalFileName)
        documentFileName = try c.decodeIfPresent(String.self, forKey: .documentFileName)
        posterFileName = try c.decodeIfPresent(String.self, forKey: .posterFileName)
        byteSize = try c.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0
        source = try? c.decodeIfPresent(SourceApp.self, forKey: .source)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        savedPath = try c.decodeIfPresent(String.self, forKey: .savedPath)
    }

    /// Size in points.
    public var pointSize: CGSize {
        CGSize(width: Double(pixelWidth) / max(scale, 1), height: Double(pixelHeight) / max(scale, 1))
    }

    public var isEdited: Bool { documentFileName != nil }
}

/// How long history keeps captures.
public enum HistoryRetention: String, Sendable, CaseIterable, Identifiable {
    case off, day, week, month, forever

    public var id: String { rawValue }
    public static let `default`: HistoryRetention = .month

    public var title: String {
        switch self {
        case .off: "Off"
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        case .forever: "Forever"
        }
    }

    /// How old an entry may get; nil keeps it forever. Off keeps nothing.
    public var maximumAge: TimeInterval? {
        switch self {
        case .off: 0
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .forever: nil
        }
    }

    public var keepsCaptures: Bool { self != .off }
}

/// The on-disk index: a version and the entries, newest first.
public struct HistoryIndex: Equatable, Sendable {
    public static let currentVersion = 1
    public private(set) var entries: [HistoryEntry]

    public init(entries: [HistoryEntry] = []) {
        self.entries = entries.sorted { $0.createdAt > $1.createdAt }
    }

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteSize } }

    public func entry(_ id: UUID) -> HistoryEntry? { entries.first { $0.id == id } }

    public mutating func insert(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        let index = entries.firstIndex { $0.createdAt < entry.createdAt } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    public mutating func update(_ id: UUID, _ change: (inout HistoryEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> [HistoryEntry] {
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        return removed
    }

    /// The entries `retention` no longer keeps at `now`, leaving out `protected` ones (open
    /// cards, editors and pins).
    public func expired(retention: HistoryRetention, now: Date, protected: Set<UUID> = []) -> [HistoryEntry] {
        guard let maximumAge = retention.maximumAge else { return [] }
        return entries.filter { !protected.contains($0.id) && now.timeIntervalSince($0.createdAt) >= maximumAge }
    }

    /// Entries of `kind` (nil: all) whose source app or kind matches `search`.
    public func filtered(kind: HistoryKind?, search: String) -> [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if let kind, entry.kind != kind { return false }
            guard !query.isEmpty else { return true }
            let haystack = [entry.source?.name, entry.source?.bundleID, entry.kind.singular, entry.fileName].compactMap { $0 }
            return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: Coding

    private struct File: Codable {
        var version: Int
        var entries: [Lenient]
    }

    /// An entry that failed to decode becomes nil instead of failing the whole index.
    private struct Lenient: Codable {
        var entry: HistoryEntry?
        init(_ entry: HistoryEntry) { self.entry = entry }
        init(from decoder: Decoder) throws { entry = try? HistoryEntry(from: decoder) }
        func encode(to encoder: Encoder) throws { try entry?.encode(to: encoder) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(version: Self.currentVersion, entries: entries.map(Lenient.init)))
    }

    /// Reads an index file. Accepts a bare array too; skips entries it can't read; never throws
    /// for bad content (an unreadable file is an empty history).
    public static func decode(_ data: Data) -> HistoryIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(File.self, from: data) {
            return HistoryIndex(entries: file.entries.compactMap(\.entry))
        }
        if let array = try? decoder.decode([Lenient].self, from: data) {
            return HistoryIndex(entries: array.compactMap(\.entry))
        }
        return HistoryIndex()
    }
}

/// Groups entries by calendar day, newest day first, for the History window's sections.
public enum HistoryDays {
    public struct Day: Identifiable, Equatable, Sendable {
        public var id: Date { start }
        public let start: Date
        public let entries: [HistoryEntry]
    }

    public static func group(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [Day] {
        var days: [Date: [HistoryEntry]] = [:]
        for entry in entries { days[calendar.startOfDay(for: entry.createdAt), default: []].append(entry) }
        return days.keys.sorted(by: >).map { start in
            Day(start: start, entries: days[start, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }

    /// "Today", "Yesterday", or the date ("Wednesday, November 5", with the year when it isn't this year's).
    public static func title(for day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let text = day.formatted(style)
        if sameYear, let range = text.range(of: ", \(calendar.component(.year, from: day))") {
            return text.replacingCharacters(in: range, with: "")
        }
        return text
    }
}
