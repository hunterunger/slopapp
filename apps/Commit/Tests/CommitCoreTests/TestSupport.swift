import Foundation
import os
@testable import CommitCore

/// A throwaway repository under /tmp/commit-test, with its own HOME and global config so
/// the owner's git config, credentials and hooks never play a part.
struct TestRepo: Sendable {
    let root: URL
    let home: URL
    let runner: ProcessGitRunner
    let repository: Repository

    static let base = URL(fileURLWithPath: "/tmp/commit-test", isDirectory: true)

    /// The environment every test git process gets.
    static func environment(home: URL, extra: [String: String] = [:]) -> [String: String] {
        var env = GitEnvironment(base: [
            "HOME": home.path,
            "PATH": GitEnvironment.guiPath,
            "GIT_CONFIG_GLOBAL": home.appendingPathComponent(".gitconfig").path,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_DATE": "2026-01-05T10:00:00Z",
            "GIT_COMMITTER_DATE": "2026-01-05T10:00:00Z",
        ]).variables()
        env.merge(extra) { _, new in new }
        return env
    }

    static func makeDirectory(_ name: String = "repo") throws -> URL {
        let dir = base.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    /// A new repository with an identity configured (unless `identity` is false).
    init(name: String = "repo", identity: Bool = true, initialize: Bool = true, extraEnvironment: [String: String] = [:]) throws {
        let container = try Self.makeDirectory(name)
        home = container.appendingPathComponent("home", isDirectory: true)
        root = container.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var config = "[init]\n\tdefaultBranch = main\n[protocol \"file\"]\n\tallow = always\n"
        if identity { config += "[user]\n\tname = Test Person\n\temail = test@example.com\n" }
        try config.write(to: home.appendingPathComponent(".gitconfig"), atomically: true, encoding: .utf8)
        runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/usr/bin/git"),
                                  environment: Self.environment(home: home, extra: extraEnvironment))
        repository = Repository(location: RepositoryLocation(root: root, gitDirectory: root.appendingPathComponent(".git")),
                                runner: runner)
        if initialize { try sh("init", "-q") }
    }

    /// Runs git synchronously in the repo (test setup only). Throws on failure.
    @discardableResult
    func sh(_ arguments: String..., stdin: String? = nil, allowFailure: Bool = false) throws -> String {
        try git(arguments, stdin: stdin.map { Data($0.utf8) }, allowFailure: allowFailure)
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL? = nil, stdin: Data? = nil, allowFailure: Bool = false) throws -> String {
        let result = try Self.syncRun(arguments, in: directory ?? root, environment: runner.environment, stdin: stdin)
        if !allowFailure && !result.succeeded {
            throw GitFailure(command: GitCommand(arguments, in: directory ?? root), result: result)
        }
        return result.stdoutString
    }

    /// Plain blocking Process run for test setup (no Swift concurrency involved, so it can't
    /// starve the test pool).
    static func syncRun(_ arguments: [String], in directory: URL, environment: [String: String], stdin: Data? = nil,
                        executable: String = "/usr/bin/git") throws -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("commit-test-\(UUID().uuidString).out")
        let err = FileManager.default.temporaryDirectory.appendingPathComponent("commit-test-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: err) }
        process.standardOutput = try FileHandle(forWritingTo: out)
        process.standardError = try FileHandle(forWritingTo: err)
        if let stdin {
            let input = FileManager.default.temporaryDirectory.appendingPathComponent("commit-test-\(UUID().uuidString).in")
            try stdin.write(to: input)
            process.standardInput = try FileHandle(forReadingFrom: input)
            defer { try? FileManager.default.removeItem(at: input) }
            try process.run()
            process.waitUntilExit()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        return GitResult(stdout: (try? Data(contentsOf: out)) ?? Data(), stderr: (try? Data(contentsOf: err)) ?? Data(),
                         exitCode: process.terminationStatus)
    }

    func write(_ path: String, _ content: String) throws {
        try write(path, Data(content.utf8))
    }

    func write(_ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func read(_ path: String) -> String? {
        FileManager.default.contents(atPath: root.appendingPathComponent(path).path).map { String(decoding: $0, as: UTF8.self) }
    }

    func readData(_ path: String) -> Data? {
        FileManager.default.contents(atPath: root.appendingPathComponent(path).path)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// The file as stored in the index.
    func indexContent(_ path: String) throws -> Data {
        let result = try Self.syncRun(["show", ":\(path)"], in: root, environment: runner.environment)
        guard result.succeeded else { throw GitFailure(command: GitCommand(["show"], in: root), result: result) }
        return result.stdout
    }

    func commitAll(_ message: String) throws {
        try sh("add", "-A")
        try sh("commit", "-q", "-m", message)
    }

    func status() async throws -> WorkingTreeStatus { try await repository.status() }

    func entry(_ path: String) async throws -> StatusEntry {
        guard let e = try await status().entries.first(where: { $0.path == path }) else {
            throw GitFailure(command: GitCommand(["status"], in: root), result: GitResult(stderr: Data("no entry \(path)".utf8), exitCode: 1))
        }
        return e
    }

    /// A bare remote next to the repo, added as origin.
    func addBareRemote(name: String = "origin") throws -> URL {
        let remote = root.deletingLastPathComponent().appendingPathComponent("\(name).git", isDirectory: true)
        try git(["init", "-q", "--bare", remote.path], in: root.deletingLastPathComponent())
        try sh("remote", "add", name, remote.path)
        return remote
    }

    /// A second clone of `remote` sharing this repo's environment (another person's machine).
    func clone(_ remote: URL, as name: String) throws -> URL {
        let target = root.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        try git(["clone", "-q", remote.path, target.path], in: root.deletingLastPathComponent())
        return target
    }
}

/// Median wall time of `runs` executions, in milliseconds.
func medianMillis(runs: Int = 5, _ body: () throws -> Void) rethrows -> Double {
    var times: [Double] = []
    let clock = ContinuousClock()
    for _ in 0..<runs {
        let d = try clock.measure(body)
        times.append(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
    }
    return times.sorted()[runs / 2]
}

func millis(_ d: Duration) -> Double {
    Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000
}

/// Release builds are several times faster than the debug builds `swift test` makes.
func budget(release: Double, debug: Double) -> Double {
    #if DEBUG
    return debug * ciSlack
    #else
    return release * ciSlack
    #endif
}

/// Shared CI runners are much slower than a real Mac: time budgets get 4x headroom there.
let ciSlack: Double = ProcessInfo.processInfo.environment["CI"] == nil ? 1 : 4

/// The fixture folder, if make-fixtures.sh has been run.
func fixture(_ name: String) -> URL? {
    let url = URL(fileURLWithPath: "/tmp/commit-fixtures/\(name)", isDirectory: true)
    return FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) ? url : nil
}

/// A runner for fixtures: real git, no global or system config.
func fixtureRunner() -> ProcessGitRunner {
    let home = URL(fileURLWithPath: "/tmp/commit-test/fixture-home", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return ProcessGitRunner(executable: URL(fileURLWithPath: "/usr/bin/git"),
                            environment: TestRepo.environment(home: home, extra: ["GIT_CONFIG_GLOBAL": "/dev/null"]))
}
