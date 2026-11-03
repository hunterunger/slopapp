import Foundation

public struct ShortcutError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var description: String { message }

    public static func couldntRun(_ name: String) -> ShortcutError {
        ShortcutError(message: "Couldn't run “\(name)”. Check it in the Shortcuts app.")
    }
    public static func timedOut(_ name: String) -> ShortcutError {
        ShortcutError(message: "“\(name)” took too long and was stopped. Check it in the Shortcuts app.")
    }
    public static let couldntList = ShortcutError(message: "Couldn't read your shortcuts. Is the Shortcuts app installed?")
}

/// Runs shortcuts with the public `shortcuts` command-line tool (macOS 12+). No permission
/// needed; a shortcut may ask for its own the first time it runs.
public struct CommandShortcutRunner: ShortcutRunner {
    public var executable: URL
    public var timeout: TimeInterval

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"), timeout: TimeInterval = 60) {
        self.executable = executable
        self.timeout = timeout
    }

    public func list() async throws -> [String] {
        let result = try await Self.execute(executable, ["list"], timeout: timeout)
        guard result.status == 0, !result.timedOut else { throw ShortcutError.couldntList }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func run(_ name: String) async throws {
        let result: ProcessResult
        do {
            result = try await Self.execute(executable, ["run", name], timeout: timeout)
        } catch {
            throw ShortcutError.couldntRun(name)
        }
        if result.timedOut { throw ShortcutError.timedOut(name) }
        if result.status != 0 { throw ShortcutError.couldntRun(name) }
    }

    public struct ProcessResult: Sendable {
        public var status: Int32
        public var output: String
        public var timedOut: Bool
    }

    /// Runs a command off the main thread, reading its output as it goes (so a chatty
    /// command can't fill the pipe and hang), and terminates it after `timeout`.
    public static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let box = ProcessBox(process)
                let watchdog = DispatchWorkItem {
                    if box.process.isRunning {
                        box.markTimedOut()
                        box.process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self),
                    timedOut: box.timedOut
                ))
            }
        }
    }

    /// Process isn't Sendable; the watchdog only reads `isRunning` and calls `terminate()`,
    /// both thread-safe, and `timedOut` is guarded by a lock.
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        private let lock = NSLock()
        private var didTimeOut = false
        init(_ process: Process) { self.process = process }
        func markTimedOut() { lock.withLock { didTimeOut = true } }
        var timedOut: Bool { lock.withLock { didTimeOut } }
    }
}
