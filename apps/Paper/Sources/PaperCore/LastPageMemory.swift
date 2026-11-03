import Foundation

/// A small key-value store, so tests don't touch `UserDefaults`.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class UserDefaultsStore: KeyValueStore {
    let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}

public final class InMemoryStore: KeyValueStore {
    var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func set(_ data: Data?, forKey key: String) { values[key] = data }
}

/// Remembers the last page viewed per file (most recent first, capped).
public struct LastPageMemory {
    struct Entry: Codable, Equatable {
        var path: String
        var page: Int
    }

    public static let key = "lastPages"
    public let capacity: Int
    let store: KeyValueStore

    public init(store: KeyValueStore, capacity: Int = 200) {
        self.store = store
        self.capacity = capacity
    }

    var entries: [Entry] {
        guard let data = store.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    public func page(for url: URL) -> Int? {
        entries.first { $0.path == url.standardizedFileURL.path }?.page
    }

    public func remember(page: Int, for url: URL) {
        let path = url.standardizedFileURL.path
        var list = entries.filter { $0.path != path }
        list.insert(Entry(path: path, page: page), at: 0)
        if list.count > capacity { list.removeLast(list.count - capacity) }
        store.set(try? JSONEncoder().encode(list), forKey: Self.key)
    }
}
