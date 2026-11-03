import Foundation
import SlopKit
import SquishCore

/// Plugs the compressor into SlopKit's file queue.
struct SquishProcessor: FileProcessor {
    let squisher: Squisher
    /// Told which file is starting, so the app knows which settings each row used.
    var onStart: @Sendable (URL) -> Void = { _ in }

    /// Stands in until the app model has built the real one.
    static let placeholder = SquishProcessor(squisher: Squisher(settings: SquishSettings()))

    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        onStart(job.input)
        let result = try await squisher.run(job.input, previousOutput: job.previousOutput) { progress($0) }
        switch result {
        case .saved(let url, let bytes): return .produced(output: url, bytes: bytes)
        case .keptOriginal(let reason): return .unchanged(reason: reason)
        case .skipped(let reason): return .skipped(reason: reason)
        }
    }
}
