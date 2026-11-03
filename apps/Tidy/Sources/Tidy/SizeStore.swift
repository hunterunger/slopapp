import Foundation
import TidyCore

/// Sizes of files and folders, measured in the background (up to 6 at a time) and published
/// in small batches so long lists fill in without stuttering. Results are kept until
/// something is moved or the user rescans.
@MainActor
@Observable
final class SizeStore {
    private(set) var sizes: [String: DiskUsage] = [:]
    private(set) var pending: Set<String> = []
    /// Paths that couldn't be read at all.
    private(set) var failed: Set<String> = []

    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var workers = 0
    @ObservationIgnored private var batch: [(String, DiskUsage?)] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
    private let maxWorkers = 6

    /// Called with each new measurement (used to remember app sizes between launches).
    @ObservationIgnored var onMeasured: ((String, DiskUsage) -> Void)?

    func size(_ url: URL) -> DiskUsage? { sizes[url.path] }

    /// A size known from before (e.g. remembered from the last launch).
    func preset(_ path: String, _ usage: DiskUsage) {
        guard sizes[path] == nil, !pending.contains(path) else { return }
        sizes[path] = usage
    }
    func isMeasuring(_ url: URL) -> Bool { pending.contains(url.path) }

    /// Total bytes of the measured ones, and whether any are still pending.
    func total(_ urls: [URL]) -> (bytes: Int64, isComplete: Bool) {
        var bytes: Int64 = 0
        var complete = true
        for url in urls {
            if let usage = sizes[url.path] { bytes += usage.bytes } else if !failed.contains(url.path) { complete = false }
        }
        return (bytes, complete)
    }

    /// Queues the ones not measured yet. Folders the list shows first go first.
    func request(_ urls: [URL]) {
        var added = false
        for url in urls where sizes[url.path] == nil && !pending.contains(url.path) && !failed.contains(url.path) {
            pending.insert(url.path)
            queue.append(url)
            added = true
        }
        if added { pump() }
    }

    /// Forgets sizes (after moving things, or on rescan) so they're measured again.
    func forget(_ urls: [URL]) {
        for url in urls {
            sizes[url.path] = nil
            failed.remove(url.path)
        }
    }

    func reset() {
        generation += 1
        running.values.forEach { $0.cancel() }
        queue.removeAll()
        pending.removeAll()
        sizes.removeAll()
        failed.removeAll()
        batch.removeAll()
    }

    private func pump() {
        while workers < maxWorkers, !queue.isEmpty {
            let url = queue.removeFirst()
            workers += 1
            let generation = self.generation
            let id = UUID()
            running[id] = Task.detached(priority: .utility) { [weak self] in
                let usage = DiskUsage.measure(url)
                await self?.finished(url.path, usage, generation: generation, id: id)
            }
        }
    }

    private func finished(_ path: String, _ usage: DiskUsage?, generation: Int, id: UUID) {
        workers -= 1
        running[id] = nil
        guard generation == self.generation else { pump(); return }
        batch.append((path, usage))
        if !flushScheduled {
            flushScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                self.flush()
            }
        }
        pump()
    }

    private func flush() {
        flushScheduled = false
        for (path, usage) in batch {
            pending.remove(path)
            if let usage {
                sizes[path] = usage
                onMeasured?(path, usage)
            } else {
                failed.insert(path)
            }
        }
        batch.removeAll()
    }
}
