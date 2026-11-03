import Foundation
import Observation

/// Runs a tool's computation: right away for small inputs, or debounced on a background
/// thread for large ones (or slow tools like regex), cancelling the previous run.
@MainActor
@Observable
final class LiveJob {
    /// True while a background run has taken longer than a moment. Drives the spinner.
    private(set) var isBusy = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Inputs below this many UTF-8 bytes are computed synchronously.
    static let syncLimit = 64 * 1024

    func run<Output: Sendable>(
        background: Bool,
        debounce: Duration = .milliseconds(120),
        work: @escaping @Sendable (_ isCancelled: @Sendable () -> Bool) -> Output,
        apply: @escaping @MainActor (Output) -> Void
    ) {
        task?.cancel()
        task = nil
        if !background {
            isBusy = false
            apply(work { false })
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let spinner = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { self?.isBusy = true }
            }
            let job = Task.detached(priority: .userInitiated) { work { Task.isCancelled } }
            let output = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            spinner.cancel()
            guard !Task.isCancelled else { return }
            self?.isBusy = false
            apply(output)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isBusy = false
    }
}

/// Roughly how big a string is, in O(1): UTF-8 bytes for native strings, UTF-16 units for
/// strings bridged from AppKit (like a text view's contents). `utf8.count` on a bridged
/// 50 MB string would transcode all of it on the main thread.
func approximateSize(_ text: String) -> Int {
    text.utf8.withContiguousStorageIfAvailable { $0.count } ?? (text as NSString).length
}

/// True when the text is empty or only whitespace; only scans small texts.
func isBlank(_ text: String) -> Bool {
    if text.isEmpty { return true }
    guard approximateSize(text) < 4096 else { return false }
    return text.allSatisfy(\.isWhitespace)
}
