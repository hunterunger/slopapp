import Foundation
import os

/// Test hooks, all off unless an environment variable turns them on:
///
/// - `COMMIT_OPEN=/path/to/repo[:/other]`: open these repositories at launch (scripted
///   walkthroughs and perf runs; `open -a Commit <folder>` does the same).
/// - `COMMIT_NO_SHELL_PATH=1`: don't run the login shell to find its PATH.
/// - `COMMIT_RESET_RECENTS=1`: start with an empty recents list (screenshots).
/// - `COMMIT_SECTION=changes|history|stashes`: open repositories on that section (screenshots).
/// - `COMMIT_SELECT=path`: select that changed file (its unstaged row if it has one).
/// - `COMMIT_LOG=/path/file.log`: append timings (open → status shown, history first page…).
///
/// Use `GIT_CONFIG_GLOBAL=/tmp/…` (git's own variable) to keep a test run away from the real
/// global git config: Commit passes its environment on to git.
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.commit", category: "timing")
    private static let environment = ProcessInfo.processInfo.environment
    static let openAtLaunch: [URL] = (environment["COMMIT_OPEN"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    static let skipShellPath = environment["COMMIT_NO_SHELL_PATH"] == "1"
    static let section = environment["COMMIT_SECTION"]
    static let select = environment["COMMIT_SELECT"]
    static let resetRecents = environment["COMMIT_RESET_RECENTS"] == "1"
    private static let logFile = environment["COMMIT_LOG"].map { URL(fileURLWithPath: $0) }

    static func record(_ line: String) {
        logger.debug("\(line, privacy: .public)")
        guard let logFile else { return }
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: logFile)
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> String {
        let d = ContinuousClock.now - start
        return String(format: "%.0f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }
}
