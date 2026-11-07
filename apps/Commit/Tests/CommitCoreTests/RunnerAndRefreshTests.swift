import Foundation
import os
import Testing
@testable import CommitCore

@Suite struct ProcessRunnerTests {
    let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/sh"), environment: ["PATH": GitEnvironment.guiPath])
    let dir = URL(fileURLWithPath: "/tmp")

    @Test func readsBothPipesWithoutDeadlock() async throws {
        // 2 MB on each pipe: more than a pipe buffer holds, on both at once.
        let result = try await runner.run(GitCommand(["-c", "yes o | head -c 2000000; yes e | head -c 2000000 >&2"], in: dir))
        #expect(result.stdout.count == 2_000_000)
        #expect(result.stderr.count == 2_000_000)
        #expect(result.succeeded)
    }

    @Test func passesStdinExitCodesAndDirectory() async throws {
        let echo = try await runner.run(GitCommand(["-c", "cat; pwd; exit 3"], in: URL(fileURLWithPath: "/usr"), stdin: Data("hello\n".utf8)))
        #expect(echo.stdoutString == "hello\n/usr\n")
        #expect(echo.exitCode == 3)
    }

    @Test func timesOutAndKillsTheWholeGroup() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        // A child of the child holds the pipe open: only a group kill ends it promptly.
        let result = try await runner.run(GitCommand(["-c", "sleep 30 & sleep 30"], in: dir, timeout: .milliseconds(200)))
        #expect(result.timedOut)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func cancellationTerminates() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await runner.run(GitCommand(["-c", "sleep 30"], in: dir)) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(5))
    }

    @Test func streamsAndStopsEarly() async throws {
        var total = 0
        for try await chunk in runner.stream(GitCommand(["-c", "yes line"], in: dir)) {
            total += chunk.count
            if total > 1_000_000 { break }
        }
        #expect(total > 1_000_000)
        await #expect(throws: GitFailure.self) {
            for try await _ in runner.stream(GitCommand(["-c", "echo nope >&2; exit 2"], in: dir)) {}
        }
    }

    @Test func missingExecutableThrows() async {
        let bad = ProcessGitRunner(executable: URL(fileURLWithPath: "/no/such/git"), environment: [:])
        await #expect(throws: SpawnError.self) { _ = try await bad.run(GitCommand(["status"], in: dir)) }
    }

    @Test func readsDoNotTakeTheIndexLock() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        // Touch the file so a locking status would want to refresh the index.
        try repo.write("a.txt", "a\n")
        let index = repo.root.appendingPathComponent(".git/index")
        let before = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        try await Task.sleep(for: .milliseconds(20))
        _ = try await repo.status()
        let after = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        #expect(before == after)
    }
}

@MainActor
@Suite struct RefreshSchedulerTests {
    @Test func coalescesABurstIntoOneRefresh() async throws {
        var runs = 0
        let scheduler = RefreshScheduler(debounce: .milliseconds(30), minimumInterval: .milliseconds(60)) { runs += 1 }
        for _ in 0..<100 { scheduler.signal() }
        // Wait for the refresh (a loaded machine can be slow to schedule it), then make sure
        // no second one follows.
        for _ in 0..<100 where runs == 0 { try await Task.sleep(for: .milliseconds(30)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(runs == 1)
        #expect(scheduler.isIdle)
    }

    @Test func aStormRunsAtMostTwiceASecondAndSettles() async throws {
        var runs = 0
        let scheduler = RefreshScheduler(debounce: .milliseconds(50), minimumInterval: .milliseconds(500)) {
            runs += 1
            try? await Task.sleep(for: .milliseconds(80)) // a status run
        }
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < .milliseconds(1500) {
            scheduler.signal()
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(runs <= 4) // 1.5 s → at most 2 a second (+1 for the first)
        try await Task.sleep(for: .milliseconds(800))
        #expect(scheduler.isIdle)
        let settled = runs
        try await Task.sleep(for: .milliseconds(300))
        #expect(runs == settled)
    }

    @Test func eventsDuringARefreshQueueExactlyOneMore() async throws {
        var runs = 0
        let scheduler = RefreshScheduler(debounce: .milliseconds(10), minimumInterval: .milliseconds(10)) {
            runs += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        scheduler.refreshNow()
        try await Task.sleep(for: .milliseconds(20))
        for _ in 0..<50 { scheduler.signal() }
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs == 2)
    }
}

@Suite struct ClassifierTests {
    @Test func classifiesRepositoryPaths() {
        let c = RepoEventClassifier(root: URL(fileURLWithPath: "/nonexistent/r"), gitDirectory: URL(fileURLWithPath: "/nonexistent/r/.git"))
        #expect(c.classify("/nonexistent/r/Sources/") == .worktree)
        #expect(c.classify("/nonexistent/r") == .worktree)
        #expect(c.classify("/nonexistent/r/.git") == .gitState)
        #expect(c.classify("/nonexistent/r/.git/refs/heads/") == .gitState)
        #expect(c.classify("/nonexistent/r/.git/objects/ab/") == .ignore)
        #expect(c.classify("/nonexistent/r/.git/logs/refs/heads") == .ignore)
        #expect(c.classify("/nonexistent/other/file") == .ignore)
        #expect(c.classify("/nonexistent/rr/file") == .ignore)
        // /tmp is a symlink; events arrive with the real path.
        let tmp = RepoEventClassifier(root: URL(fileURLWithPath: "/tmp"), gitDirectory: URL(fileURLWithPath: "/tmp/.git"))
        #expect(tmp.classify("/private/tmp/x") == .worktree)
    }
}

/// FSEvents on a real repository, end to end with the scheduler and a spying runner.
@MainActor
@Suite(.serialized) struct WatcherTests {
    final class Counter: @unchecked Sendable {
        let lock = OSAllocatedUnfairLock(initialState: 0)
        func add() { lock.withLock { $0 += 1 } }
        func reset() { lock.withLock { $0 = 0 } }
        var value: Int { lock.withLock { $0 } }
    }

    @Test func anEditOnDiskIsSeenQuickly() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        let classifier = RepoEventClassifier(root: repo.root, gitDirectory: repo.root.appendingPathComponent(".git"))
        var seen: [String] = []
        var refreshedAt: ContinuousClock.Instant?
        let clock = ContinuousClock()
        let scheduler = RefreshScheduler {
            seen = (try? await repo.status().unstaged.map(\.path)) ?? []
            refreshedAt = clock.now
        }
        let watcher = FileWatcher(paths: [repo.root.path]) { paths in
            let relevant = paths.contains { classifier.classify($0) != .ignore }
            if relevant { Task { @MainActor in scheduler.signal() } }
        }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300)) // let the stream start
        let wrote = clock.now
        try repo.write("a.txt", "changed\n")
        for _ in 0..<40 where refreshedAt == nil { try await Task.sleep(for: .milliseconds(50)) }
        let at = try #require(refreshedAt)
        #expect(seen == ["a.txt"])
        #expect(at - wrote < .milliseconds(1500))
        print("COMMIT_PERF edit_to_refresh_ms=\(String(format: "%.0f", millis(at - wrote)))")
    }

    @Test func aStormOfWritesCostsAFewStatusRuns() async throws {
        let repo = try TestRepo()
        try repo.write("seed.txt", "s\n")
        try repo.commitAll("Start")
        let statusRuns = Counter()
        let spy = SpyRunner(inner: repo.runner) { command in
            if command.arguments.contains("status") { statusRuns.add() }
        }
        let repository = Repository(location: repo.repository.location, runner: spy)
        let classifier = RepoEventClassifier(root: repo.root, gitDirectory: repo.root.appendingPathComponent(".git"))
        let scheduler = RefreshScheduler { _ = try? await repository.status() }
        let watcher = FileWatcher(paths: [repo.root.path]) { paths in
            if paths.contains(where: { classifier.classify($0) != .ignore }) { Task { @MainActor in scheduler.signal() } }
        }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        // 3,000 files over about a second and a half, in 30 folders.
        for batch in 0..<30 {
            for i in 0..<100 { try repo.write("storm/d\(batch)/f\(i).txt", "x\n") }
            try await Task.sleep(for: .milliseconds(50))
        }
        let stormSeconds = millis(clock.now - start) / 1000
        try await Task.sleep(for: .milliseconds(1500))
        let runs = statusRuns.value
        #expect(scheduler.isIdle)
        #expect(Double(runs) <= (stormSeconds + 1.5) * 2 + 1)
        let settled = runs
        try await Task.sleep(for: .milliseconds(1000))
        #expect(statusRuns.value == settled) // idle again: no more git
        print("COMMIT_PERF storm_seconds=\(String(format: "%.1f", stormSeconds)) status_runs=\(runs)")
    }
}

/// Wraps a runner and reports every command.
struct SpyRunner: GitRunner {
    let inner: any GitRunner
    let onCommand: @Sendable (GitCommand) -> Void

    func run(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)?) async throws -> GitResult {
        onCommand(command)
        return try await inner.run(command, onStderr: onStderr)
    }

    func stream(_ command: GitCommand) -> AsyncThrowingStream<Data, any Error> {
        onCommand(command)
        return inner.stream(command)
    }
}
