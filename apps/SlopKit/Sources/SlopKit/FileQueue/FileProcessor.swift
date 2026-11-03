import Foundation
import os

// FileQueue: the drag-and-drop file queue for drop-in utility apps (design system §2b).
// It knows nothing about the work itself; an app plugs in a `FileProcessor`.
//
//     struct Shrinker: FileProcessor {
//         func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
//             let output = job.input.deletingPathExtension().appendingPathExtension("small.jpg")
//             progress(0.5)
//             let bytes = try await shrink(job.input, to: job.previousOutput ?? output)
//             return .produced(output: job.previousOutput ?? output, bytes: bytes)
//         }
//     }
//
//     @State var queue = FileQueue(processor: Shrinker(), acceptedTypes: [.image])
//     @State var selection = Set<FileQueueItem.ID>()
//     FileQueueView(queue: queue, selection: $selection, dropTitle: "Drop images here")
//
// Pieces: `FileQueue` (model: add, cancel, retry, remove, summary; bounded concurrency,
// work off the main actor), `FileQueueItem` (one observable row), `FileQueueView` (the
// window body), `FileIntake` (folder expansion), `FileQueueText` (sizes and percentages),
// `FileQueueActions` (reveal, choose files). Swap `queue.processor` when settings change;
// finished rows keep their results until retried.

/// Does the work for one file. Called off the main actor, several files at once, so it
/// must be `Sendable` and safe to run concurrently. Honour task cancellation
/// (`try Task.checkCancellation()`) between expensive steps.
public protocol FileProcessor: Sendable {
    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome
}

/// One unit of work handed to a processor.
public struct FileJob: Sendable, Equatable {
    /// The file the user dropped.
    public let input: URL
    /// The output this queue item produced last time, when the user retries it. A
    /// processor may overwrite it instead of making yet another copy.
    public let previousOutput: URL?

    public init(input: URL, previousOutput: URL? = nil) {
        self.input = input
        self.previousOutput = previousOutput
    }
}

/// What happened to a file. Throw an error (ideally `LocalizedError` with a sentence that
/// says what to do next) for failures; these are the non-failure endings.
public enum FileOutcome: Sendable, Equatable {
    /// A new file was written.
    case produced(output: URL, bytes: Int64)
    /// Nothing was written and the original is untouched, with the reason
    /// (e.g. "Already as small as it gets").
    case unchanged(reason: String)
    /// The file was left alone on purpose (e.g. an animated GIF), with the reason.
    case skipped(reason: String)
}

/// Reports a fraction (0...1) back to the queue. Throttled so a processor can call it as
/// often as it likes without flooding the main actor.
public struct FileProgress: Sendable {
    private let sink: @Sendable (Double) -> Void
    private let last = OSAllocatedUnfairLock(initialState: -1.0)

    public init(_ sink: @escaping @Sendable (Double) -> Void) {
        self.sink = sink
    }

    /// A progress reporter that drops everything (tests, previews).
    public static var ignored: FileProgress { FileProgress { _ in } }

    public func callAsFunction(_ fraction: Double) {
        let value = min(max(fraction, 0), 1)
        let send = last.withLock { last -> Bool in
            guard value >= 1 || value - last >= 0.02 || value < last else { return false }
            last = value
            return true
        }
        if send { sink(value) }
    }
}
