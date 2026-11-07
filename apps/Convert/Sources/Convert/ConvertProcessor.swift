import ConvertCore
import Foundation
import SlopKit

/// Tells the app what a conversion is doing, for the row's details.
struct ConvertEvents: Sendable {
    /// The file's kind (once read), the target title and the settings signature it runs with.
    var started: @Sendable (URL, MediaKind, String, String) -> Void
    var finished: @Sendable (URL, ConversionReport?) -> Void

    static let ignored = ConvertEvents(started: { _, _, _, _ in }, finished: { _, _ in })
}

/// Plugs the converter into the generic file queue.
struct ConvertProcessor: FileProcessor {
    let converter: Converter
    let events: ConvertEvents
    var restore: RestoreBook?
    /// Each file's own format, trim, turn and sound choice, read when it starts.
    var options: OptionsBook?

    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        switch restore?.take(job.input) {
        case .outcome(let outcome)?: return outcome
        case .failed(let message, let final)?: throw RestoredFailure(message: message, isWorthRetrying: !final)
        case .cancelled?: throw CancellationError()
        case nil: break
        }
        let (events, input, settings) = (events, job.input, converter.settings)
        let own = options?.options(for: input) ?? FileOptions()
        let result = try await converter.run(input, options: own, replacing: job.previousOutput, started: { kind in
            events.started(input, kind, settings.applying(own).targetTitle(for: kind), settings.signature(for: kind, options: own))
        }, progress: { progress($0) })
        switch result {
        case .converted(let report):
            events.finished(input, report)
            return .produced(output: report.output, bytes: report.bytes)
        case .unchanged(let reason):
            events.finished(input, nil)
            return .unchanged(reason: reason)
        }
    }
}

/// Unreadable formats and damaged files show no Try Again.
extension ConvertError: FileQueueRetryHint {
    public var isWorthRetrying: Bool { !isFinal }
}

/// Rows taken off the list, kept so Undo can put them back as they were without converting
/// anything again. The processor checks it before doing any work.
final class RestoreBook: @unchecked Sendable {
    enum Entry: Sendable {
        case outcome(FileOutcome)
        case failed(String, final: Bool)
        case cancelled
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func store(_ entry: Entry, for url: URL) {
        lock.withLock { entries[url.standardizedFileURL.path] = entry }
    }

    /// Takes the entry for `url`, if any (each is used once).
    func take(_ url: URL) -> Entry? {
        lock.withLock { entries.removeValue(forKey: url.standardizedFileURL.path) }
    }

    func forget(_ url: URL) {
        lock.withLock { _ = entries.removeValue(forKey: url.standardizedFileURL.path) }
    }
}

/// Every file's own options, shared between the window (which edits them) and the
/// processor (which reads them off the main actor when a file starts).
final class OptionsBook: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: FileOptions] = [:]

    func options(for url: URL) -> FileOptions {
        lock.withLock { entries[url.standardizedFileURL.path] } ?? FileOptions()
    }

    func set(_ options: FileOptions, for url: URL) {
        lock.withLock {
            let key = url.standardizedFileURL.path
            if options.isEmpty { entries.removeValue(forKey: key) } else { entries[key] = options }
        }
    }
}

/// A restored failure: the row says what it said before.
struct RestoredFailure: LocalizedError, FileQueueRetryHint {
    let message: String
    let isWorthRetrying: Bool
    var errorDescription: String? { message }
}
