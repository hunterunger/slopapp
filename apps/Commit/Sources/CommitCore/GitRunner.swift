import Foundation
import os

/// One invocation of git: arguments after `git`, where to run it, what to feed it.
public struct GitCommand: Sendable, Equatable {
    public var arguments: [String]
    public var directory: URL
    public var stdin: Data?
    /// Extra environment for this command only (merged over the runner's environment).
    public var environment: [String: String]
    /// Terminate the process after this long. `nil`: no limit (network commands can be
    /// cancelled instead).
    public var timeout: Duration?

    public init(_ arguments: [String], in directory: URL, stdin: Data? = nil,
                environment: [String: String] = [:], timeout: Duration? = nil) {
        self.arguments = arguments
        self.directory = directory
        self.stdin = stdin
        self.environment = environment
        self.timeout = timeout
    }

    /// For logs and "Copy Command": `git status --porcelain=v2 …`.
    public var displayString: String {
        (["git"] + arguments).map { arg in
            arg.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) ? "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'" : arg
        }.joined(separator: " ")
    }
}

/// What a finished git process left behind. Output stays as bytes; decode for display only.
public struct GitResult: Sendable, Equatable {
    public var stdout: Data
    public var stderr: Data
    public var exitCode: Int32
    /// The process was stopped by `timeout`.
    public var timedOut: Bool

    public init(stdout: Data = Data(), stderr: Data = Data(), exitCode: Int32 = 0, timedOut: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// A git process failed. Carries the command and its output so the UI can explain it.
public struct GitFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public var command: GitCommand
    public var result: GitResult

    public init(command: GitCommand, result: GitResult) {
        self.command = command
        self.result = result
    }

    /// stderr, or stdout when stderr is empty (git prints some errors there, e.g. "nothing to commit").
    public var output: String {
        let err = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : err
    }

    public var description: String { "\(command.displayString) exited \(result.exitCode): \(output)" }
}

/// Runs git. The real one spawns processes; tests pass fakes (as Awake fakes `PowerAssertion`).
public protocol GitRunner: Sendable {
    /// Runs to completion and returns the output, whatever the exit code. Cancelling the
    /// calling task terminates the process.
    func run(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)?) async throws -> GitResult

    /// Streams stdout as it arrives (`git log` on a big history). Ending the iteration early
    /// terminates the process. Throws `GitFailure` if git exits non-zero.
    func stream(_ command: GitCommand) -> AsyncThrowingStream<Data, any Error>
}

public extension GitRunner {
    func run(_ command: GitCommand) async throws -> GitResult {
        try await run(command, onStderr: nil)
    }

    /// Runs and throws `GitFailure` on a non-zero exit.
    func checked(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)? = nil) async throws -> GitResult {
        let result = try await run(command, onStderr: onStderr)
        guard result.succeeded else { throw GitFailure(command: command, result: result) }
        return result
    }
}

/// Spawns the git executable with a fixed base environment, in its own process group so
/// cancelling also stops git's children (ssh, hooks, credential helpers). Reads stdout and
/// stderr concurrently (a full pipe would deadlock), writes stdin off the caller's thread,
/// terminates on cancellation or timeout.
public struct ProcessGitRunner: GitRunner {
    public let executable: URL
    public let environment: [String: String]

    /// - Parameter environment: the complete environment for git (see `GitEnvironment`).
    public init(executable: URL, environment: [String: String]) {
        self.executable = executable
        self.environment = environment
    }

    public func run(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)?) async throws -> GitResult {
        try Task.checkCancellation()
        let child = ChildProcess()
        let outBuffer = LockedData(), errBuffer = LockedData()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GitResult, any Error>) in
                do {
                    try child.start(executable: executable, arguments: command.arguments,
                                    environment: environment.merging(command.environment) { _, new in new },
                                    directory: command.directory, stdin: command.stdin,
                                    onStdout: { outBuffer.append($0) },
                                    onStderr: { errBuffer.append($0); onStderr?($0) },
                                    onExit: { status in
                                        if child.wasCancelled {
                                            continuation.resume(throwing: CancellationError())
                                        } else {
                                            continuation.resume(returning: GitResult(
                                                stdout: outBuffer.data, stderr: errBuffer.data,
                                                exitCode: status, timedOut: child.didTimeOut))
                                        }
                                    })
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                if let timeout = command.timeout { child.timeOut(after: timeout) }
            }
        } onCancel: {
            child.cancel()
        }
    }

    public func stream(_ command: GitCommand) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let child = ChildProcess()
            let errBuffer = LockedData()
            continuation.onTermination = { reason in
                if case .cancelled = reason { child.cancel() }
            }
            do {
                try child.start(executable: executable, arguments: command.arguments,
                                environment: environment.merging(command.environment) { _, new in new },
                                directory: command.directory, stdin: nil,
                                onStdout: { continuation.yield($0) },
                                onStderr: { errBuffer.append($0) },
                                onExit: { status in
                                    if child.wasCancelled {
                                        continuation.finish(throwing: CancellationError())
                                    } else if status != 0 {
                                        continuation.finish(throwing: GitFailure(
                                            command: command, result: GitResult(stderr: errBuffer.data, exitCode: status)))
                                    } else {
                                        continuation.finish()
                                    }
                                })
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

/// Couldn't start a process at all (missing executable, bad directory).
public struct SpawnError: Error, Sendable, Equatable, CustomStringConvertible {
    public var errno: Int32
    public var path: String
    public var description: String { "Couldn't run \(path): \(String(cString: strerror(errno)))" }
}

/// One child process started with posix_spawn in a new process group. Calls `onExit` once,
/// after both pipes have closed and the process has been reaped.
final class ChildProcess: @unchecked Sendable {
    private struct Flags {
        var pid: pid_t = 0
        var cancelled = false
        var timedOut = false
        var exited = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: Flags())

    var wasCancelled: Bool { lock.withLock { $0.cancelled } }
    var didTimeOut: Bool { lock.withLock { $0.timedOut } }

    /// Timeouts and kill escalation run here (a private serial queue always gets a thread).
    private static let timers = DispatchQueue(label: "Commit process timers", qos: .userInitiated)

    func start(executable: URL, arguments: [String], environment: [String: String], directory: URL,
               stdin: Data?, onStdout: @escaping @Sendable (Data) -> Void,
               onStderr: @escaping @Sendable (Data) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws {
        var outFDs: [Int32] = [0, 0], errFDs: [Int32] = [0, 0], inFDs: [Int32] = [-1, -1]
        guard pipe(&outFDs) == 0, pipe(&errFDs) == 0 else { throw SpawnError(errno: errno, path: executable.path) }
        if stdin != nil { guard pipe(&inFDs) == 0 else { throw SpawnError(errno: errno, path: executable.path) } }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if stdin != nil {
            posix_spawn_file_actions_adddup2(&actions, inFDs[0], 0)
        } else {
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, outFDs[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errFDs[1], 2)
        for fd in [outFDs[0], outFDs[1], errFDs[0], errFDs[1], inFDs[0], inFDs[1]] where fd > 2 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setpgroup(&attributes, 0)
        // Default signal handlers and an empty mask in the child, whatever ours are.
        var allSignals = sigset_t(), noSignals = sigset_t()
        sigfillset(&allSignals); sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF
                                                    | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var spawned: pid_t = 0
        let status = posix_spawn(&spawned, executable.path, &actions, &attributes, argv, envp)
        close(outFDs[1]); close(errFDs[1])
        if stdin != nil { close(inFDs[0]) }
        guard status == 0 else {
            close(outFDs[0]); close(errFDs[0])
            if stdin != nil { close(inFDs[1]) }
            throw SpawnError(errno: status, path: executable.path)
        }
        let pid = spawned
        let cancelNow = lock.withLock { flags -> Bool in
            flags.pid = pid
            return flags.cancelled
        }

        if let stdin {
            let fd = inFDs[1]
            let writer = Thread {
                stdin.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                        if n < 0 { if errno == EINTR { continue }; break }
                        offset += n
                    }
                }
                close(fd)
            }
            writer.start()
        }
        // One thread per child: poll both pipes until they close, then reap the process.
        // (Blocking reads on the shared GCD pool can starve it when many run at once.)
        let outFD = outFDs[0], errFD = errFDs[0]
        let reader = Thread { [self] in
            Self.pump(out: outFD, err: errFD, onStdout: onStdout, onStderr: onStderr)
            var raw: Int32 = 0
            while waitpid(pid, &raw, 0) < 0 && errno == EINTR {}
            lock.withLock { $0.exited = true }
            // WIFEXITED / WEXITSTATUS / WTERMSIG by hand (the macros aren't imported).
            let signal = raw & 0x7f
            onExit(signal == 0 ? (raw >> 8) & 0xff : 128 + signal)
        }
        reader.stackSize = 256 * 1024
        reader.start()
        if cancelNow { signalGroup() }
    }

    private static func pump(out: Int32, err: Int32, onStdout: (Data) -> Void, onStderr: (Data) -> Void) {
        let size = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        defer { buffer.deallocate() }
        var fds = [pollfd(fd: out, events: Int16(POLLIN), revents: 0), pollfd(fd: err, events: Int16(POLLIN), revents: 0)]
        var open = 2
        while open > 0 {
            let ready = poll(&fds, 2, -1)
            if ready < 0 { if errno == EINTR { continue }; break }
            for i in 0..<2 where fds[i].fd >= 0 && fds[i].revents != 0 {
                let n = read(fds[i].fd, buffer, size)
                if n > 0 {
                    let chunk = Data(bytes: buffer, count: n)
                    if i == 0 { onStdout(chunk) } else { onStderr(chunk) }
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    close(fds[i].fd)
                    fds[i].fd = -1
                    open -= 1
                }
            }
        }
        for f in fds where f.fd >= 0 { close(f.fd) }
    }

    func cancel() {
        lock.withLock { $0.cancelled = true }
        signalGroup()
    }

    func timeOut(after duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        Self.timers.asyncAfter(deadline: .now() + seconds) { [self] in
            let running = lock.withLock { flags -> Bool in
                guard flags.pid != 0, !flags.exited else { return false }
                flags.timedOut = true
                return true
            }
            if running { signalGroup() }
        }
    }

    /// SIGTERM to the whole process group (git and anything it started), then SIGKILL if
    /// it's still there a second later.
    private func signalGroup() {
        let pid = lock.withLock { $0.exited ? 0 : $0.pid }
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        Self.timers.asyncAfter(deadline: .now() + 1) { [self] in
            let stillThere = lock.withLock { !$0.exited }
            if stillThere { kill(-pid, SIGKILL) }
        }
    }
}

/// Thread-safe byte buffer for pipe readers.
final class LockedData: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())
    func append(_ chunk: Data) { lock.withLock { $0.append(chunk) } }
    var data: Data { lock.withLock { $0 } }
}
