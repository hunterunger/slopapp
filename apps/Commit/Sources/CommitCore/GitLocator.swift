import Foundation

/// A git version, compared numerically ("2.39.5 (Apple Git-154)" → 2.39.5).
public struct GitVersion: Comparable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    /// The oldest git we support. Everything Commit runs is older than this.
    public static let minimum = GitVersion(2, 35)

    /// Parses `git --version` output.
    public init?(versionOutput: String) {
        guard let range = versionOutput.range(of: #"\d+\.\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        let parts = versionOutput[range].split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        self.init(parts[0], parts[1], parts.count > 2 ? parts[2] : 0)
    }

    public static func < (a: GitVersion, b: GitVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// What the locator needs from the system, so tests can fake it.
public protocol GitProbe: Sendable {
    func isExecutable(_ path: String) -> Bool
    /// `xcode-select -p` succeeds (the command line tools or Xcode are installed). Without
    /// them, `/usr/bin/git` is a shim that pops Apple's install dialog.
    func hasDeveloperTools() async -> Bool
    /// `<path> --version` output, or nil if it didn't run.
    func versionOutput(of path: String) async -> String?
}

/// The git Commit will use, and why it isn't usable when it isn't.
public enum GitInstallation: Sendable, Equatable {
    case found(path: String, version: GitVersion)
    /// No developer tools and no other git: offer Install Command Line Tools….
    case missing
    /// Found but older than `GitVersion.minimum`.
    case tooOld(path: String, version: GitVersion)
    /// The override in Settings doesn't point at a working git.
    case badOverride(path: String)

    public var path: String? {
        switch self {
        case .found(let path, _), .tooOld(let path, _): path
        default: nil
        }
    }
}

/// Finds the user's git: the Settings override, then `/usr/bin/git` (only when the
/// developer tools are installed), then Homebrew's and /usr/local's.
public struct GitLocator: Sendable {
    public static let fallbackPaths = ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
    let probe: any GitProbe

    public init(probe: any GitProbe) {
        self.probe = probe
    }

    public func locate(override: String?) async -> GitInstallation {
        if let override, !override.isEmpty {
            guard probe.isExecutable(override), let version = await version(of: override) else {
                return .badOverride(path: override)
            }
            return classify(path: override, version: version)
        }
        var candidates: [String] = []
        if probe.isExecutable("/usr/bin/git"), await probe.hasDeveloperTools() {
            candidates.append("/usr/bin/git")
        }
        candidates += Self.fallbackPaths.filter { probe.isExecutable($0) }
        for path in candidates {
            if let version = await version(of: path) { return classify(path: path, version: version) }
        }
        return .missing
    }

    private func version(of path: String) async -> GitVersion? {
        guard let output = await probe.versionOutput(of: path) else { return nil }
        return GitVersion(versionOutput: output)
    }

    private func classify(path: String, version: GitVersion) -> GitInstallation {
        version < .minimum ? .tooOld(path: path, version: version) : .found(path: path, version: version)
    }
}

/// The real probe: file checks and short-lived processes with a timeout.
public struct SystemGitProbe: GitProbe {
    public init() {}

    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func hasDeveloperTools() async -> Bool {
        guard let result = try? await Self.quickRun("/usr/bin/xcode-select", ["-p"]) else { return false }
        return result.succeeded
    }

    public func versionOutput(of path: String) async -> String? {
        guard let result = try? await Self.quickRun(path, ["--version"]), result.succeeded else { return nil }
        return result.stdoutString
    }

    static func quickRun(_ path: String, _ arguments: [String]) async throws -> GitResult {
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: path),
                                      environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        return try await runner.run(GitCommand(arguments, in: URL(fileURLWithPath: "/"), timeout: .seconds(5)))
    }
}
