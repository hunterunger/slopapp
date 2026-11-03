import Foundation

/// Opt-in responsiveness probe for benchmarks: `SQUISH_DIAGNOSTICS=/tmp/squish-test/diag.log`.
/// Ticks on the main run loop every 20 ms and records how late each tick was (a stand-in
/// for "how long the UI couldn't respond"). Writes one line per finished batch.
@MainActor
enum Diagnostics {
    private static var path: String? = ProcessInfo.processInfo.environment["SQUISH_DIAGNOSTICS"]
    private static var timer: Timer?
    private static var last = Date()
    private static var worst: TimeInterval = 0
    private static var lateTicks = 0
    private static var ticks = 0
    private static var batchStart: Date?

    static func start() {
        guard path != nil, timer == nil else { return }
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        timer?.tolerance = 0
    }

    private static func tick() {
        let now = Date()
        let lag = now.timeIntervalSince(last) - 0.02
        last = now
        guard batchStart != nil else { return }
        ticks += 1
        worst = max(worst, lag)
        if lag > 0.05 { lateTicks += 1 }
    }

    static func batchStarted() {
        guard path != nil, batchStart == nil else { return }
        batchStart = Date()
        worst = 0; lateTicks = 0; ticks = 0
    }

    static func batchFinished(files: Int) {
        guard let path, let start = batchStart else { return }
        batchStart = nil
        let line = String(format: "%@ files=%d seconds=%.2f worst_main_thread_lag_ms=%.0f ticks_late_over_50ms=%d/%d\n",
                          ISO8601DateFormatter().string(from: Date()), files, Date().timeIntervalSince(start),
                          worst * 1000, lateTicks, ticks)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
        }
    }
}
