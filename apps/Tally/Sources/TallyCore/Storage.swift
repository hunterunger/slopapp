import Foundation

/// Where the sheet text lives. The app uses a file; tests use a fake.
public protocol SheetStorage {
    func load() -> String?
    func save(_ text: String) throws
}

/// What's on disk for exchange rates.
public enum StoredRates: Equatable, Sendable {
    case none
    case table(RateTable)
    case unreadable
}

public protocol RatesStorage {
    func load() -> StoredRates
    func save(_ table: RateTable) throws
    func delete() throws
}

/// Downloads the raw ECB XML. The app uses URLSession; tests use a fake.
public protocol RatesFetching: Sendable {
    func fetch() async throws -> Data
}

/// The system clipboard.
@MainActor
public protocol Clipboard {
    func setString(_ string: String)
}

/// `sheet.txt` in a folder (Application Support, or `TALLY_DATA_DIR` in tests).
public struct FileSheetStorage: SheetStorage {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("sheet.txt")
    }

    public func load() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    public func save(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}

/// `rates.json` in a folder.
public struct FileRatesStorage: RatesStorage {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("rates.json")
    }

    public func load() -> StoredRates {
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(RateTable.self, from: data) else { return .unreadable }
        return .table(table)
    }

    public func save(_ table: RateTable) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(table).write(to: url, options: .atomic)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
