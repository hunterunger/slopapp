import Foundation

/// Where Focus keeps its state, settings and session history.
public protocol FocusStorage: AnyObject {
    func loadState() -> TimerState?
    func saveState(_ state: TimerState) throws
    func loadSettings() -> TimerSettings?
    func saveSettings(_ settings: TimerSettings) throws
    func append(_ record: SessionRecord) throws
    /// Records that ended on or after `since`, oldest first.
    func records(since: Date) -> [SessionRecord]
}

/// Files in one folder: `state.json`, `settings.json` and `history.jsonl` (one session per
/// line, a few hundred KB after years of daily use).
public final class FileStorage: FocusStorage {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var historyURL: URL { directory.appendingPathComponent("history.jsonl") }

    public func loadState() -> TimerState? { load(TimerState.self, from: stateURL) }
    public func saveState(_ state: TimerState) throws { try save(state, to: stateURL) }
    public func loadSettings() -> TimerSettings? { load(TimerSettings.self, from: settingsURL) }
    public func saveSettings(_ settings: TimerSettings) throws { try save(settings, to: settingsURL) }

    public func append(_ record: SessionRecord) throws {
        try ensureDirectory()
        var line = try encoder.encode(record)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: historyURL, options: .atomic)
        }
    }

    public func records(since: Date) -> [SessionRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        // Newest lines are at the end: read backwards and stop a day before `since`
        // (records are appended in the order sessions end, give or take a catch-up).
        let stopBefore = since.addingTimeInterval(-86_400)
        var found: [SessionRecord] = []
        for line in data.split(separator: 0x0A).reversed() {
            guard let record = try? decoder.decode(SessionRecord.self, from: Data(line)) else { continue }
            if record.endedAt < stopBefore { break }
            if record.endedAt >= since { found.append(record) }
        }
        return found.sorted { $0.endedAt < $1.endedAt }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory()
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// In-memory storage for tests and previews.
public final class MemoryStorage: FocusStorage {
    public var state: TimerState?
    public var settings: TimerSettings?
    public var history: [SessionRecord] = []
    public var failWrites = false
    public private(set) var stateSaves = 0

    public init(state: TimerState? = nil, settings: TimerSettings? = nil, history: [SessionRecord] = []) {
        self.state = state
        self.settings = settings
        self.history = history
    }

    struct WriteError: Error {}

    public func loadState() -> TimerState? { state }
    public func saveState(_ state: TimerState) throws {
        if failWrites { throw WriteError() }
        self.state = state
        stateSaves += 1
    }
    public func loadSettings() -> TimerSettings? { settings }
    public func saveSettings(_ settings: TimerSettings) throws {
        if failWrites { throw WriteError() }
        self.settings = settings
    }
    public func append(_ record: SessionRecord) throws {
        if failWrites { throw WriteError() }
        history.append(record)
    }
    public func records(since: Date) -> [SessionRecord] { history.filter { $0.endedAt >= since } }
}
