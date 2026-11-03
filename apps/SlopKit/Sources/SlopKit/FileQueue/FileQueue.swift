import Foundation
import Observation
import UniformTypeIdentifiers

/// One file in the queue. Observable on its own, so a row redraws only when its file
/// changes, not when any of 200 others do.
@MainActor
@Observable
public final class FileQueueItem: Identifiable {
    public enum State: Equatable, Sendable {
        case waiting
        /// `nil` progress means "working, no estimate".
        case working(Double?)
        case finished(FileOutcome)
        case failed(String)
        case cancelled

        /// The outcome, once finished.
        public var outcome: FileOutcome? {
            if case .finished(let outcome) = self { return outcome }
            return nil
        }
    }

    public nonisolated let id = UUID()
    public let input: URL
    public internal(set) var originalBytes: Int64?
    public internal(set) var state: State = .waiting
    /// How many times it has been started (1 on the first run).
    public internal(set) var runs = 0

    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var lastOutput: URL?
    /// The lane it's running in (see `FileQueue.lane`), while it runs.
    @ObservationIgnored var runningLane: String?
    /// Its lane, worked out once (`.some(nil)`: no lane).
    @ObservationIgnored var cachedLane: String??

    init(input: URL, originalBytes: Int64?) {
        self.input = input
        self.originalBytes = originalBytes
    }

    public var name: String { input.lastPathComponent }

    public var output: URL? {
        if case .finished(.produced(let url, _)) = state { return url }
        return nil
    }

    public var outputBytes: Int64? {
        if case .finished(.produced(_, let bytes)) = state { return bytes }
        return nil
    }

    /// Bytes saved by this file (0 unless it produced a smaller file).
    public var savedBytes: Int64 {
        guard let before = originalBytes, let after = outputBytes else { return 0 }
        return max(0, before - after)
    }

    /// Fraction saved, 0...1, or nil when there's no output to compare.
    public var savedFraction: Double? {
        guard let before = originalBytes, before > 0, let after = outputBytes else { return nil }
        return Double(before - after) / Double(before)
    }

    public var isActive: Bool {
        switch state {
        case .waiting, .working: true
        default: false
        }
    }

    /// The failure can't be fixed by trying again (see `FileQueueRetryHint`): no Try Again.
    public internal(set) var failureIsFinal = false

    public var canRetry: Bool {
        switch state {
        case .failed: !failureIsFinal
        case .cancelled, .finished: true
        default: false
        }
    }

    /// The output's file name when it differs from the input's ("Photo-small.jpg" for
    /// "Photo.webp"); nil otherwise. Rows show it as "Photo.webp → Photo-small.jpg".
    public var outputName: String? {
        guard let name = output?.lastPathComponent, name != self.name else { return nil }
        return name
    }

    /// The file to show in Finder: the output if there is one, else the original.
    public var revealURL: URL { output ?? input }
}

/// A queue of files processed in parallel, off the main actor, with bounded concurrency.
///
///     let queue = FileQueue(processor: MyProcessor(), acceptedTypes: [.image, .pdf])
///     await queue.add(urls)          // folders are expanded; duplicates are ignored
///     queue.cancel(item); queue.retry(item); queue.clearFinished()
@MainActor
@Observable
public final class FileQueue {
    public private(set) var items: [FileQueueItem] = []
    /// Used for files that start from now on. Changing it doesn't touch finished files;
    /// retry them to apply the new settings.
    @ObservationIgnored public var processor: any FileProcessor
    /// How many files are processed at once.
    public var maxConcurrent: Int {
        didSet { pump() }
    }
    public let acceptedTypes: [UTType]
    /// Called once each time the queue goes from busy to idle.
    @ObservationIgnored public var onIdle: (() -> Void)?
    /// Called once each time the queue goes from idle to busy (a file starts). Pairs with
    /// `onIdle`, e.g. to keep the Mac awake only while work runs.
    @ObservationIgnored public var onBusy: (() -> Void)?

    /// Optional per-kind limits on top of `maxConcurrent`. `lane` names a file's lane
    /// (e.g. "video"); `laneLimits` caps how many files of a lane run at once. Files in a
    /// full lane wait while files in other lanes go ahead, so a long video never blocks a
    /// batch of photos. Files with no lane (or a lane with no limit) only count against
    /// `maxConcurrent`.
    ///
    ///     queue.lane = { MediaTypes.kind(of: $0)?.rawValue }
    ///     queue.laneLimits = ["video": 1]
    @ObservationIgnored public var lane: ((URL) -> String?)? {
        didSet { items.forEach { $0.cachedLane = nil } }
    }
    @ObservationIgnored public var laneLimits: [String: Int] = [:] {
        didSet { pump() }
    }

    /// When set, files dropped or chosen directly (not found inside folders) that aren't
    /// `acceptedTypes` become failed rows with this message, instead of being skipped
    /// silently. Return nil to skip a file anyway. Views then accept any file in drops.
    ///
    ///     queue.unsupportedReason = { "\($0.lastPathComponent) isn't a video, audio file or image." }
    @ObservationIgnored public var unsupportedReason: (@Sendable (URL) -> String?)?

    @ObservationIgnored private var running = 0
    @ObservationIgnored private var runningByLane: [String: Int] = [:]
    @ObservationIgnored private var wasBusy = false
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(processor: any FileProcessor, acceptedTypes: [UTType], maxConcurrent: Int = FileQueue.defaultConcurrency) {
        self.processor = processor
        self.acceptedTypes = acceptedTypes
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// One per performance core, at least 2 and at most 8: enough to keep the machine
    /// busy, few enough that memory stays sane on big images.
    public nonisolated static var defaultConcurrency: Int {
        min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    // MARK: Adding

    /// Adds files, and the accepted files inside dropped folders.
    ///
    /// - Files already waiting or working, and outputs this queue produced, are ignored.
    /// - A file that's already in the list and finished is run again in its existing row
    ///   (its processor gets `FileJob.previousOutput`, so it can overwrite its own earlier
    ///   output instead of making another copy).
    ///
    /// Returns the items that will run: new rows first, then refreshed ones.
    @discardableResult
    public func add(_ urls: [URL]) async -> [FileQueueItem] {
        let types = acceptedTypes
        let unsupported = unsupportedReason
        let (found, rejected) = await Task.detached(priority: .userInitiated) {
            let found = FileIntake.expand(urls, types: types)
            let rejected = unsupported.map { FileIntake.unaccepted(urls, types: types, reason: $0) } ?? []
            return (found, rejected)
        }.value
        var existing: [String: FileQueueItem] = [:]
        for item in items { existing[item.input.standardizedFileURL.path] = item }
        let outputs = Set(items.compactMap { $0.output?.standardizedFileURL.path })
        var seen = Set<String>()
        var added: [FileQueueItem] = []
        var refreshed: [FileQueueItem] = []
        for file in found {
            let path = file.url.standardizedFileURL.path
            guard !outputs.contains(path), seen.insert(path).inserted else { continue }
            if let item = existing[path] {
                guard item.canRetry else { continue }
                item.originalBytes = file.bytes
                retry(item)
                refreshed.append(item)
            } else {
                added.append(FileQueueItem(input: file.url, originalBytes: file.bytes))
            }
        }
        // Files we can't take become failed rows that say why (unless already listed).
        for file in rejected {
            let path = file.url.standardizedFileURL.path
            guard existing[path] == nil, seen.insert(path).inserted else { continue }
            let item = FileQueueItem(input: file.url, originalBytes: file.bytes)
            item.state = .failed(file.reason)
            item.failureIsFinal = true
            added.append(item)
        }
        // Big drops appear in slices so the list never stalls a frame building 1,000 rows.
        var start = 0
        while start < added.count {
            let end = min(added.count, start + 40)
            items.append(contentsOf: added[start..<end])
            pump()
            start = end
            if start < added.count { try? await Task.sleep(for: .milliseconds(8)) }
        }
        if !(added.isEmpty && refreshed.isEmpty) {
            lastAdded = (added + refreshed).map(\.id)
            addedBatches += 1
        }
        return added + refreshed
    }

    /// The rows the last `add` created or re-ran, and a counter that changes with each
    /// such batch (for views that scroll to new rows).
    public private(set) var lastAdded: [FileQueueItem.ID] = []
    public private(set) var addedBatches = 0

    // MARK: Controlling

    public func cancel(_ item: FileQueueItem) {
        guard item.isActive else { return }
        item.task?.cancel()
        item.state = .cancelled
        checkIdle()
    }

    public func cancelAll() {
        items.forEach(cancel)
    }

    /// Runs a finished, failed or cancelled file again with the current processor.
    public func retry(_ item: FileQueueItem) {
        // A cancelled file may still be winding down; it restarts once its old task ends.
        guard item.canRetry else { return }
        item.lastOutput = item.output ?? item.lastOutput
        item.state = .waiting
        pump()
    }

    public func retryAll() {
        items.filter(\.canRetry).forEach(retry)
    }

    /// Removes files from the list (cancelling them if needed). Never touches the files.
    public func remove(_ toRemove: [FileQueueItem]) {
        let ids = Set(toRemove.map(\.id))
        toRemove.forEach(cancel)
        items.removeAll { ids.contains($0.id) }
        checkIdle()
    }

    /// Replaces a finished file's result, for when the app changes it afterwards
    /// (e.g. it put the original back). Ignored while the file is waiting or working.
    public func setOutcome(_ outcome: FileOutcome, for item: FileQueueItem) {
        guard !item.isActive else { return }
        if outcome != item.state.outcome { item.lastOutput = nil }
        item.state = .finished(outcome)
    }

    /// Puts back items removed with `remove(_:)` (for Undo), at their old positions.
    /// `offsets` are the indices they had in `items`, in the same order as `restored`.
    /// They come back as they were left (finished, failed or canceled); nothing runs.
    public func restore(_ restored: [FileQueueItem], at offsets: [Int]) {
        let known = Set(items.map(\.id))
        let pairs = zip(offsets, restored).filter { !known.contains($0.1.id) }.sorted { $0.0 < $1.0 }
        for (offset, item) in pairs {
            item.task = nil
            if item.isActive { item.state = .cancelled }
            items.insert(item, at: min(max(0, offset), items.count))
        }
    }

    public func clearFinished() {
        items.removeAll { !$0.isActive && $0.task == nil }
    }

    // MARK: State

    public var isBusy: Bool { items.contains(where: \.isActive) }

    public var summary: FileQueueSummary {
        var summary = FileQueueSummary()
        for item in items {
            summary.total += 1
            switch item.state {
            case .waiting, .working: summary.remaining += 1
            case .finished(.produced): summary.produced += 1
            case .finished: summary.unchanged += 1
            case .failed: summary.failed += 1
            case .cancelled: summary.cancelled += 1
            }
            summary.bytesBefore += item.outputBytes == nil ? 0 : item.originalBytes ?? 0
            summary.bytesAfter += item.outputBytes ?? 0
        }
        return summary
    }

    /// Suspends until nothing is waiting or working. For tests and scripted runs.
    public func waitUntilIdle() async {
        guard isBusy || running > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: Scheduling

    private func pump() {
        if lane == nil {
            while running < maxConcurrent, let next = items.first(where: { $0.state == .waiting && $0.task == nil }) {
                start(next, lane: nil)
            }
        } else {
            // Take waiting files in order, skipping those whose lane is full.
            var index = 0
            while running < maxConcurrent, index < items.count {
                let item = items[index]
                index += 1
                guard item.state == .waiting, item.task == nil else { continue }
                let name: String?
                if let cached = item.cachedLane {
                    name = cached
                } else {
                    name = lane?(item.input)
                    item.cachedLane = .some(name)
                }
                if let name, let limit = laneLimits[name], runningByLane[name, default: 0] >= max(1, limit) { continue }
                start(item, lane: name)
            }
        }
        checkIdle()
    }

    private func start(_ item: FileQueueItem, lane: String?) {
        running += 1
        if let lane { runningByLane[lane, default: 0] += 1 }
        item.runningLane = lane
        if !wasBusy { onBusy?() }
        wasBusy = true
        item.runs += 1
        item.state = .working(nil)
        let job = FileJob(input: item.input, previousOutput: item.lastOutput)
        let processor = self.processor
        let progress = FileProgress { [weak item] fraction in
            Task { @MainActor in
                guard let item, case .working = item.state else { return }
                item.state = .working(fraction)
            }
        }
        item.task = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<FileOutcome, any Error>
            do {
                try Task.checkCancellation()
                result = .success(try await processor.process(job, progress: progress))
            } catch {
                result = .failure(error)
            }
            await self?.finish(item, result)
        }
    }

    private func finish(_ item: FileQueueItem, _ result: Result<FileOutcome, any Error>) {
        running -= 1
        if let lane = item.runningLane { runningByLane[lane, default: 1] -= 1 }
        item.runningLane = nil
        item.task = nil
        if case .working = item.state {
            switch result {
            case .success(let outcome):
                item.state = .finished(outcome)
            case .failure(let error) where error is CancellationError:
                item.state = .cancelled
            case .failure(let error):
                item.failureIsFinal = (error as? any FileQueueRetryHint)?.isWorthRetrying == false
                item.state = .failed(Self.message(for: error))
            }
        }
        pump()
    }

    private func checkIdle() {
        guard running == 0, !items.contains(where: { $0.state == .waiting }) else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        if wasBusy {
            wasBusy = false
            onIdle?()
        }
        waiters.forEach { $0.resume() }
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError, let description = localized.errorDescription {
            return [description, localized.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        }
        return (error as NSError).localizedDescription
    }
}

/// Errors that know whether trying the same file again could work. Rows that fail with
/// `isWorthRetrying == false` (an unreadable format, a damaged file) show no Try Again and
/// are skipped by retry-all.
public protocol FileQueueRetryHint: Error {
    var isWorthRetrying: Bool { get }
}

/// Totals for the status line.
public struct FileQueueSummary: Equatable, Sendable {
    public var total = 0
    public var remaining = 0
    public var produced = 0
    public var unchanged = 0
    public var failed = 0
    public var cancelled = 0
    /// Sizes of files that produced an output (before and after).
    public var bytesBefore: Int64 = 0
    public var bytesAfter: Int64 = 0

    public var savedBytes: Int64 { max(0, bytesBefore - bytesAfter) }
    public var savedFraction: Double? {
        bytesBefore > 0 ? Double(savedBytes) / Double(bytesBefore) : nil
    }
    public var done: Int { total - remaining }
}
