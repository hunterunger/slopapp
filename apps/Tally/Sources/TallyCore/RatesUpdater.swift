import Foundation

/// Opt-in exchange-rate downloads: at most one fetch per `minimumInterval`, only when the
/// user turned downloading on (or pressed Update Now).
@MainActor
public final class RatesUpdater {
    public enum Status: Equatable, Sendable {
        case idle
        case updating
        case failed(String)
    }

    public private(set) var stored: StoredRates
    public private(set) var status: Status = .idle
    public private(set) var lastAttempt: Date?
    public var onChange: (() -> Void)?

    private let storage: RatesStorage
    private let fetcher: RatesFetching
    private let now: () -> Date
    public static let minimumInterval: TimeInterval = 20 * 3600

    public init(storage: RatesStorage, fetcher: RatesFetching, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.fetcher = fetcher
        self.now = now
        stored = storage.load()
    }

    /// What the sheet evaluates with.
    public var state: RatesState {
        switch stored {
        case .none: .off
        case .unreadable: .unavailable
        case .table(let t): .loaded(t, stale: t.isStale(now: now()))
        }
    }

    public var table: RateTable? {
        if case .table(let t) = stored { return t }
        return nil
    }

    /// Whether an automatic update is due.
    public func isDue(enabled: Bool) -> Bool {
        guard enabled, status != .updating else { return false }
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.minimumInterval { return false }
        guard let table else { return true }
        guard let published = table.publishedDate else { return true }
        // The ECB publishes once per working day; a table from today or yesterday is current.
        return now().timeIntervalSince(published) > Self.minimumInterval + 86_400
    }

    /// Updates if due. Returns whether a fetch happened.
    @discardableResult
    public func updateIfDue(enabled: Bool) async -> Bool {
        guard isDue(enabled: enabled) else { return false }
        await update()
        return true
    }

    /// Fetches now (Update Now, or turning downloading on).
    public func update() async {
        guard status != .updating else { return }
        status = .updating
        lastAttempt = now()
        onChange?()
        do {
            let data = try await fetcher.fetch()
            let table = try ECBRatesParser.parse(data)
            try storage.save(table)
            stored = .table(table)
            status = .idle
        } catch is RatesError {
            status = .failed("The rates download wasn’t in the expected format. Try again later.")
        } catch {
            status = .failed("Couldn’t download rates. Check your connection, then choose Update Now.")
        }
        onChange?()
    }

    public func delete() {
        try? storage.delete()
        stored = storage.load()
        status = .idle
        onChange?()
    }

    public func reload() {
        stored = storage.load()
        onChange?()
    }
}
