import Foundation

/// Lets one write at a time through, in order (research doc, Engine rule 4: mutations go
/// through a per-repo serial queue; reads run in parallel).
actor SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

/// Options for showing a diff.
public struct DiffOptions: Sendable, Equatable {
    public var contextLines: Int
    public var ignoreWhitespace: Bool
    /// Stop a slow diff after this long and redo it with Myers (research: a user's
    /// `diff.algorithm=histogram` can take 10 s on one file).
    public var timeout: Duration

    public init(contextLines: Int = 3, ignoreWhitespace: Bool = false, timeout: Duration = .seconds(2)) {
        self.contextLines = contextLines
        self.ignoreWhitespace = ignoreWhitespace
        self.timeout = timeout
    }
}

/// A diff ready to show.
public struct DiffResult: Sendable, Equatable {
    public var file: FileDiff?
    /// The configured algorithm was too slow; this is Myers.
    public var usedFallback: Bool
    /// Sizes for binary files (bytes), when known.
    public var oldSize: Int64?
    public var newSize: Int64?
    /// An untracked folder (shown as a placeholder, not a diff).
    public var isFolder: Bool

    public init(file: FileDiff?, usedFallback: Bool = false, oldSize: Int64? = nil, newSize: Int64? = nil, isFolder: Bool = false) {
        self.file = file
        self.usedFallback = usedFallback
        self.oldSize = oldSize
        self.newSize = newSize
        self.isFolder = isFolder
    }
}

/// Index entries saved before a stage/unstage, so ⌘Z puts the index back exactly.
public struct IndexSnapshot: Sendable, Equatable {
    public enum Storage: Sendable, Equatable {
        /// `git ls-files -s` lines for these paths; paths not listed weren't in the index.
        case entries(paths: [String], lines: [String])
        /// The whole index as a tree (`git write-tree`).
        case tree(ObjectID)
    }
    public var storage: Storage
}

/// What a file discard saved, so ⌘Z can put it back (the stash also stays in Stashes until then).
public struct DiscardRecord: Sendable, Equatable {
    public var stash: ObjectID
    public var message: String
    /// Restored from the stash's worktree tree.
    public var trackedPaths: [String]
    /// Restored from the stash's untracked tree.
    public var untrackedPaths: [String]
    /// Were deletions; undo deletes them again.
    public var deletedPaths: [String]
    /// The whole working copy (Discard All): undo pops the stash with its index.
    public var isEverything: Bool
}

/// How to reconcile a divergent pull.
public enum PullStrategy: Sendable, Equatable {
    case configured, merge, rebase
}

/// Which history to load.
public enum HistoryScope: Sendable, Equatable {
    /// HEAD plus its upstream (the default).
    case current(upstream: String?)
    /// Every branch, remote branch and tag.
    case all
    /// Particular refs (a branch or tag picked in the sidebar).
    case refs([String])
}

/// Result of a push, for the HUD.
public struct PushOutcome: Sendable, Equatable {
    public var remote: String
    public var setUpstream: Bool
    /// A "create a pull request" URL the remote printed, if any.
    public var pullRequestURL: URL?
}

/// One repository: every git operation Commit performs, as small async methods.
public final class Repository: Sendable {
    public let location: RepositoryLocation
    public let runner: any GitRunner
    private let gate = SerialGate()

    public var root: URL { location.root }
    public var gitDirectory: URL { location.gitDirectory }

    public init(location: RepositoryLocation, runner: any GitRunner) {
        self.location = location
        self.runner = runner
    }

    // MARK: Opening

    /// Finds the repository containing `url` (a subfolder opens its top level). Refuses bare
    /// repositories and folders inside `.git`.
    public static func locate(_ url: URL, runner: any GitRunner) async throws -> RepositoryLocation {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OpenProblem.missing(url)
        }
        let result = try await runner.run(GitCommand(
            ["rev-parse", "--is-bare-repository", "--is-inside-git-dir", "--absolute-git-dir", "--show-toplevel"],
            in: url, timeout: .seconds(10)))
        let lines = result.stdoutString.split(separator: "\n").map(String.init)
        if !result.succeeded {
            let err = result.stderrString
            if lines.count > 1, lines[0] == "false", lines[1] == "true" { throw OpenProblem.insideGitDirectory(url) }
            if err.contains("not a git repository") { throw OpenProblem.notARepository(url) }
            if lines.first == "true" { throw OpenProblem.bare(url) }
            if err.contains("must be run in a work tree") || err.contains("this operation must be run in a work tree") {
                throw OpenProblem.bare(url)
            }
            throw OpenProblem.git(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lines.first == "true" { throw OpenProblem.bare(url) }
        if lines.count > 1, lines[1] == "true" { throw OpenProblem.insideGitDirectory(url) }
        guard lines.count >= 4 else { throw OpenProblem.notARepository(url) }
        return RepositoryLocation(root: URL(fileURLWithPath: lines[3], isDirectory: true),
                                  gitDirectory: URL(fileURLWithPath: lines[2], isDirectory: true))
    }

    /// `git init` in a folder (offered when a chosen folder isn't a repository).
    public static func initialize(_ url: URL, runner: any GitRunner) async throws {
        _ = try await runner.checked(GitCommand(["init", "--quiet"], in: url))
    }

    // MARK: Commands

    func command(_ arguments: [String], stdin: Data? = nil, environment: [String: String] = [:],
                 timeout: Duration? = nil) -> GitCommand {
        GitCommand(["-c", "core.quotepath=false", "-c", "color.ui=false"] + arguments, in: root,
                   stdin: stdin, environment: environment, timeout: timeout)
    }

    /// English messages for commands whose errors we recognise.
    static let english = ["LC_ALL": "C", "LANG": "C"]

    @discardableResult
    func read(_ arguments: [String], stdin: Data? = nil, timeout: Duration? = nil) async throws -> GitResult {
        try await runner.checked(command(arguments, stdin: stdin, timeout: timeout))
    }

    @discardableResult
    func write(_ arguments: [String], stdin: Data? = nil, environment: [String: String] = [:],
               onStderr: (@Sendable (Data) -> Void)? = nil) async throws -> GitResult {
        try await runner.checked(command(arguments, stdin: stdin, environment: environment), onStderr: onStderr)
    }

    /// Runs `body` with no other write in between.
    @discardableResult
    public func exclusive<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await gate.acquire()
        do {
            let value = try await body()
            await gate.release()
            return value
        } catch {
            await gate.release()
            throw error
        }
    }

    // MARK: Status and diffs

    public func status(includeUntracked: Bool = true) async throws -> WorkingTreeStatus {
        let result = try await read(["status", "--porcelain=v2", "-z", "--branch",
                                     includeUntracked ? "--untracked-files=normal" : "--untracked-files=no"])
        return StatusParser.parse(result.stdout)
    }

    static let diffFlags = ["--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
                            "--src-prefix=a/", "--dst-prefix=b/"]

    /// The diff of one changed file: staged (index vs HEAD) or unstaged (worktree vs index;
    /// untracked files against nothing).
    public func diff(for entry: StatusEntry, staged: Bool, options: DiffOptions = DiffOptions()) async throws -> DiffResult {
        if entry.isUntracked && entry.path.hasSuffix("/") { return DiffResult(file: nil, isFolder: true) }
        var arguments = ["diff"] + Self.diffFlags + ["-U\(options.contextLines)"]
        if options.ignoreWhitespace { arguments.append("--ignore-all-space") }
        var paths = [entry.path]
        var acceptsExitOne = false
        if entry.isConflicted {
            // A normal two-way diff against "ours", so the conflict markers show as added lines.
            arguments.append("-2")
        } else if entry.isUntracked && !staged {
            arguments.append("--no-index")
            paths = ["/dev/null", entry.path]
            acceptsExitOne = true
        } else if staged {
            arguments += ["--cached", "-M"]
            if let original = entry.originalPath { paths.append(original) }
        }
        var result = try await runDiff(arguments + ["--"] + paths, acceptsExitOne: acceptsExitOne, timeout: options.timeout)
        var usedFallback = false
        if result.timedOut {
            usedFallback = true
            result = try await runDiff(arguments + ["--diff-algorithm=myers", "--"] + paths, acceptsExitOne: acceptsExitOne, timeout: nil)
        }
        var diff = DiffResult(file: DiffParser.parseSingle(result.stdout), usedFallback: usedFallback)
        if let file = diff.file, file.isBinary {
            (diff.oldSize, diff.newSize) = await binarySizes(for: entry, staged: staged)
        }
        return diff
    }

    private func runDiff(_ arguments: [String], acceptsExitOne: Bool, timeout: Duration?) async throws -> GitResult {
        let cmd = command(arguments, timeout: timeout)
        let result = try await runner.run(cmd)
        if result.timedOut { return result }
        guard result.exitCode == 0 || (acceptsExitOne && result.exitCode == 1) else {
            throw GitFailure(command: cmd, result: result)
        }
        return result
    }

    private func binarySizes(for entry: StatusEntry, staged: Bool) async -> (Int64?, Int64?) {
        func blobSize(_ hash: String?) async -> Int64? {
            guard let hash, !hash.allSatisfy({ $0 == "0" }) else { return nil }
            guard let r = try? await read(["cat-file", "-s", hash]) else { return nil }
            return Int64(r.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        func fileSize() -> Int64? {
            let attributes = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(entry.path).path)
            return (attributes?[.size] as? NSNumber)?.int64Value
        }
        let head = entry.hashes.count > 0 ? entry.hashes[0] : nil
        let index = entry.hashes.count > 1 ? entry.hashes[1] : nil
        if staged { return (await blobSize(head), await blobSize(index)) }
        if entry.isUntracked { return (nil, fileSize()) }
        return (await blobSize(index), entry.unstaged == .deleted ? nil : fileSize())
    }

    // MARK: Staging

    /// Saves the index entries for `paths` (for undo).
    public func snapshotIndex(paths: [String]) async throws -> IndexSnapshot {
        let result = try await read(["ls-files", "-s", "-z", "--"] + paths)
        let lines = result.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return IndexSnapshot(storage: .entries(paths: paths, lines: lines))
    }

    /// Saves the whole index (for undoing Stage All / Unstage All).
    public func snapshotWholeIndex() async throws -> IndexSnapshot? {
        guard let result = try? await read(["write-tree"]),
              let tree = ObjectID(hex: result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return IndexSnapshot(storage: .tree(tree))
    }

    /// Puts the index back as it was in `snapshot`.
    public func restoreIndex(_ snapshot: IndexSnapshot) async throws {
        try await exclusive {
            switch snapshot.storage {
            case .tree(let tree):
                try await self.write(["read-tree", tree.hex])
            case .entries(let paths, let lines):
                let present = Set(lines.compactMap { line -> String? in
                    guard let tab = line.firstIndex(of: "\t") else { return nil }
                    return String(line[line.index(after: tab)...])
                })
                let absent = paths.filter { !present.contains($0) && !$0.hasSuffix("/") }
                if !absent.isEmpty {
                    try await self.write(["update-index", "--force-remove", "-z", "--stdin"],
                                         stdin: Data(absent.joined(separator: "\0").utf8 + [0]))
                }
                // Remove whatever is under untracked folders that were added.
                for folder in paths where folder.hasSuffix("/") && !present.contains(where: { $0.hasPrefix(folder) }) {
                    try await self.write(["rm", "-r", "-q", "--cached", "--ignore-unmatch", "--", folder])
                }
                if !lines.isEmpty {
                    // ls-files -s: "mode hash stage\tpath" → index-info takes the same format.
                    try await self.write(["update-index", "-z", "--index-info"],
                                         stdin: Data(lines.joined(separator: "\0").utf8 + [0]))
                }
            }
        }
    }

    /// Stages whole files (also deletions and new files). Conflicted files: marks them resolved.
    public func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await exclusive { try await self.write(["add", "-A", "--"] + paths) }
    }

    public func unstage(paths: [String], headExists: Bool) async throws {
        guard !paths.isEmpty else { return }
        try await exclusive {
            if headExists {
                try await self.write(["restore", "--staged", "--"] + paths)
            } else {
                try await self.write(["rm", "-r", "-q", "--cached", "--"] + paths)
            }
        }
    }

    public func stageAll() async throws {
        try await exclusive { try await self.write(["add", "-A"]) }
    }

    public func unstageAll(headExists: Bool) async throws {
        try await exclusive {
            if headExists {
                try await self.write(["reset", "-q"])
            } else {
                try await self.write(["rm", "-r", "-q", "--cached", "."])
            }
        }
    }

    /// Applies a patch from `PatchBuilder`: to the index (`cached`) or the working tree,
    /// forwards or in reverse.
    public func apply(_ patch: Data, cached: Bool, reverse: Bool) async throws {
        var arguments = ["apply", "--recount", "--whitespace=nowarn"]
        if cached { arguments.append("--cached") }
        if reverse { arguments.append("-R") }
        arguments.append("-")
        let finalArguments = arguments
        try await exclusive { try await self.write(finalArguments, stdin: patch, environment: Self.english) }
    }

    // MARK: Discard

    /// Discards changes to files, saving them in a stash first (so they're in Stashes and ⌘Z
    /// can restore them). `keepStaged`: discard only what isn't staged (the Changes list).
    public func discard(_ entries: [StatusEntry], keepStaged: Bool, date: Date = Date()) async throws -> DiscardRecord {
        let paths = entries.map(\.path)
        let message = "Discarded \(Self.describe(paths)) (\(Self.stamp(date)))"
        return try await exclusive {
            try await self.write(["stash", "push", "--include-untracked", "-m", message, "--"] + paths,
                                 environment: Self.english)
            let stash = try await self.resolve("refs/stash")
            if keepStaged {
                let staged = entries.filter(\.hasStagedChanges)
                let deletions = staged.filter { $0.staged == .deleted }.map(\.path)
                let restorable = staged.filter { $0.staged != .deleted }.map(\.path)
                if !restorable.isEmpty {
                    try await self.write(["restore", "--source=\(stash.hex)^2", "--staged", "--worktree", "--"] + restorable)
                }
                if !deletions.isEmpty {
                    try await self.write(["rm", "-q", "--ignore-unmatch", "--"] + deletions)
                }
            }
            return DiscardRecord(
                stash: stash, message: message,
                trackedPaths: entries.filter { !$0.isUntracked && $0.unstaged != .deleted && !(!keepStaged && $0.staged == .deleted) }.map(\.path),
                untrackedPaths: entries.filter(\.isUntracked).map(\.path),
                deletedPaths: entries.filter { !$0.isUntracked && ($0.unstaged == .deleted || (!keepStaged && $0.staged == .deleted)) }.map(\.path),
                isEverything: false)
        }
    }

    /// Discards everything (staged, unstaged, untracked) into one stash.
    public func discardAll(date: Date = Date()) async throws -> DiscardRecord {
        let message = "Discarded all changes (\(Self.stamp(date)))"
        return try await exclusive {
            try await self.write(["stash", "push", "--include-untracked", "-m", message], environment: Self.english)
            let stash = try await self.resolve("refs/stash")
            return DiscardRecord(stash: stash, message: message, trackedPaths: [], untrackedPaths: [], deletedPaths: [],
                                 isEverything: true)
        }
    }

    /// Puts discarded changes back and removes their stash.
    public func undoDiscard(_ record: DiscardRecord) async throws {
        try await exclusive {
            if record.isEverything {
                let selector = try await self.stashSelector(for: record.stash)
                try await self.write(["stash", "pop", "--index", "--quiet", selector], environment: Self.english)
                return
            }
            if !record.trackedPaths.isEmpty {
                try await self.write(["restore", "--source=\(record.stash.hex)", "--worktree", "--"] + record.trackedPaths)
            }
            if !record.untrackedPaths.isEmpty {
                try await self.write(["restore", "--source=\(record.stash.hex)^3", "--worktree", "--"] + record.untrackedPaths)
            }
            for path in record.deletedPaths {
                try? FileManager.default.removeItem(at: self.root.appendingPathComponent(path))
            }
            if let selector = try? await self.stashSelector(for: record.stash) {
                try await self.write(["stash", "drop", "--quiet", selector])
            }
        }
    }

    static func describe(_ paths: [String]) -> String {
        let names = paths.map { StatusEntry.split($0).name }
        switch names.count {
        case 0: return "nothing"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) more"
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    // MARK: Committing

    public struct Identity: Sendable, Equatable {
        public var name: String?
        public var email: String?
        public var isComplete: Bool { !(name ?? "").isEmpty && !(email ?? "").isEmpty }

        public init(name: String? = nil, email: String? = nil) {
            self.name = name
            self.email = email
        }
    }

    public func identity() async -> Identity {
        async let name = try? read(["config", "--get", "user.name"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        async let email = try? read(["config", "--get", "user.email"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return await Identity(name: name, email: email)
    }

    /// Saves name and email to the user's global git config (or this repository's).
    public func setIdentity(name: String, email: String, global: Bool) async throws {
        let scope = global ? "--global" : "--local"
        try await write(["config", scope, "user.name", name])
        try await write(["config", scope, "user.email", email])
    }

    /// Commits the index with `message`. Returns the new HEAD.
    public func commit(message: String, amend: Bool) async throws -> ObjectID {
        var arguments = ["commit", "--file=-"]
        if amend { arguments.append("--amend") }
        let finalArguments = arguments
        return try await exclusive {
            try await self.write(finalArguments, stdin: Data(message.utf8))
            return try await self.resolve("HEAD")
        }
    }

    /// The last commit's full message (for Amend).
    public func headMessage() async throws -> String {
        try await read(["log", "-1", "--format=%B"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HEAD is already on its upstream (amending would rewrite a pushed commit).
    public func isHeadPushed() async -> Bool {
        guard let result = try? await runner.run(command(["merge-base", "--is-ancestor", "HEAD", "@{upstream}"])) else { return false }
        return result.exitCode == 0
    }

    /// Moves the branch back to `commit`, keeping the changes staged (Undo Commit). nil
    /// empties the branch again (undoing a first commit).
    public func softReset(to commit: ObjectID?) async throws {
        try await exclusive {
            if let commit {
                try await self.write(["reset", "--soft", "-q", commit.hex])
            } else {
                try await self.write(["update-ref", "-d", "HEAD"])
            }
        }
    }

    public func resolve(_ revision: String) async throws -> ObjectID {
        let result = try await read(["rev-parse", "--verify", "--quiet", revision + "^{commit}"])
        guard let id = ObjectID(hex: result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GitFailure(command: command(["rev-parse", revision]), result: result)
        }
        return id
    }

    // MARK: Branches

    public func refs() async throws -> RefList {
        RefList.parse(try await read(["for-each-ref", RefList.format, "refs/heads", "refs/remotes", "refs/tags"]).stdout)
    }

    public func switchBranch(_ name: String) async throws {
        try await exclusive { try await self.write(["switch", "--no-guess", name], environment: Self.english) }
    }

    /// Checks out a remote branch: the local branch of the same name if there is one,
    /// otherwise a new local branch tracking it.
    public func switchToRemote(_ ref: GitRef, localBranches: [GitRef]) async throws -> String {
        guard let local = ref.nameOnRemote else { throw OpenProblem.git("Not a remote branch.") }
        if localBranches.contains(where: { $0.name == local }) {
            try await switchBranch(local)
        } else {
            try await exclusive {
                try await self.write(["switch", "--track", "-c", local, ref.name], environment: Self.english)
            }
        }
        return local
    }

    /// Stashes local changes (with untracked files), switches, and brings the changes back.
    /// Returns false when they didn't come back cleanly (the stash is kept).
    public func stashAndSwitch(to name: String, remote: GitRef? = nil, localBranches: [GitRef] = []) async throws -> Bool {
        try await exclusive {
            try await self.write(["stash", "push", "--include-untracked", "-m", "Switching to \(name)"],
                                 environment: Self.english)
        }
        if let remote {
            _ = try await switchToRemote(remote, localBranches: localBranches)
        } else {
            try await switchBranch(name)
        }
        return try await exclusive {
            let result = try await self.runner.run(self.command(["stash", "pop", "--index", "--quiet"], environment: Self.english))
            if result.succeeded { return true }
            // Try without restoring the index split before giving up.
            let retry = try await self.runner.run(self.command(["stash", "pop", "--quiet"], environment: Self.english))
            return retry.succeeded
        }
    }

    public func createBranch(_ name: String, from start: ObjectID?, checkout: Bool) async throws {
        try await exclusive {
            var arguments = checkout ? ["switch", "-c", name] : ["branch", name]
            if let start { arguments.append(start.hex) }
            try await self.write(arguments, environment: Self.english)
        }
    }

    /// Deletes a local branch (safe delete unless `force`). Returns its tip for undo.
    public func deleteBranch(_ ref: GitRef, force: Bool) async throws -> ObjectID? {
        try await exclusive {
            try await self.write(["branch", force ? "-D" : "-d", ref.name], environment: Self.english)
            return ref.target
        }
    }

    public func restoreBranch(_ name: String, at tip: ObjectID) async throws {
        try await exclusive { try await self.write(["branch", name, tip.hex]) }
    }

    public func remotes() async throws -> [String] {
        try await read(["remote"]).stdoutString.split(separator: "\n").map(String.init)
    }

    // MARK: Sync

    public func fetch(onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws {
        try await write(["fetch", "--all", "--prune", "--progress"], environment: Self.english,
                        onStderr: Self.progressHandler(onProgress))
    }

    public func pull(strategy: PullStrategy, autostash: Bool, onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws {
        var arguments = ["pull", "--progress"]
        switch strategy {
        case .configured: break
        case .merge: arguments.append("--no-rebase")
        case .rebase: arguments.append("--rebase")
        }
        if autostash { arguments.append("--autostash") }
        let finalArguments = arguments
        try await exclusive {
            try await self.write(finalArguments, environment: Self.english, onStderr: Self.progressHandler(onProgress))
        }
    }

    /// Remembers the choice for this repository (`pull.rebase`).
    public func rememberPullStrategy(_ strategy: PullStrategy) async throws {
        guard strategy != .configured else { return }
        try await write(["config", "--local", "pull.rebase", strategy == .rebase ? "true" : "false"])
    }

    /// Pushes the current branch. Without an upstream it's pushed to `remote` and tracked.
    public func push(branch: String, upstream: String?, remote: String,
                     onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws -> PushOutcome {
        let arguments: [String]
        if upstream != nil {
            arguments = ["push", "--progress"]
        } else {
            arguments = ["push", "--progress", "--set-upstream", remote, "HEAD:refs/heads/\(branch)"]
        }
        let result = try await exclusive {
            try await self.write(arguments, environment: Self.english, onStderr: Self.progressHandler(onProgress))
        }
        let pushedTo = upstream?.split(separator: "/").first.map(String.init) ?? remote
        return PushOutcome(remote: pushedTo, setUpstream: upstream == nil,
                           pullRequestURL: Self.pullRequestURL(in: result.stderrString))
    }

    /// "remote: Create a pull request for 'x' on GitHub by visiting:\nremote:   https://…"
    static func pullRequestURL(in output: String) -> URL? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        for (i, line) in lines.enumerated() where line.lowercased().contains("pull request") || line.lowercased().contains("merge request") {
            for candidate in lines[i...].prefix(3) {
                if let range = candidate.range(of: #"https://\S+"#, options: .regularExpression) {
                    return URL(string: String(candidate[range]))
                }
            }
        }
        return nil
    }

    static func progressHandler(_ onProgress: (@Sendable (GitProgress) -> Void)?) -> (@Sendable (Data) -> Void)? {
        guard let onProgress else { return nil }
        return { chunk in
            if let progress = GitProgress.parse(String(decoding: chunk, as: UTF8.self)) { onProgress(progress) }
        }
    }

    // MARK: Stashes

    public func stashes() async throws -> [StashEntry] {
        guard (try? await resolve("refs/stash")) != nil else { return [] }
        return StashEntry.parse(try await read(["stash", "list", "-z", StashEntry.format]).stdout)
    }

    public func stash(message: String, includeUntracked: Bool) async throws {
        var arguments = ["stash", "push"]
        if includeUntracked { arguments.append("--include-untracked") }
        if !message.trimmingCharacters(in: .whitespaces).isEmpty { arguments += ["-m", message] }
        let finalArguments = arguments
        try await exclusive { try await self.write(finalArguments, environment: Self.english) }
    }

    /// Applies (or pops) a stash, restoring what was staged.
    public func applyStash(_ entry: StashEntry, pop: Bool) async throws {
        try await exclusive {
            let selector = try await self.stashSelector(for: entry.id)
            let first = try await self.runner.run(self.command(["stash", pop ? "pop" : "apply", "--index", "--quiet", selector],
                                                               environment: Self.english))
            if first.succeeded { return }
            // --index refuses when the staged part doesn't apply; fall back to the plain apply.
            if first.stderrString.contains("Conflicts in index") || first.stderrString.contains("--index") {
                try await self.write(["stash", pop ? "pop" : "apply", "--quiet", selector], environment: Self.english)
                return
            }
            throw GitFailure(command: self.command(["stash", pop ? "pop" : "apply", selector]), result: first)
        }
    }

    public func dropStash(_ entry: StashEntry) async throws {
        try await exclusive {
            let selector = try await self.stashSelector(for: entry.id)
            try await self.write(["stash", "drop", "--quiet", selector])
        }
    }

    /// Puts a dropped stash back (Undo Drop).
    public func restoreStash(_ entry: StashEntry) async throws {
        try await exclusive { try await self.write(["stash", "store", "-m", entry.summary, entry.id.hex]) }
    }

    /// The current `stash@{n}` of a stash commit (indexes move as stashes come and go).
    func stashSelector(for id: ObjectID) async throws -> String {
        let entries = StashEntry.parse(try await read(["stash", "list", "-z", StashEntry.format]).stdout)
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw OpenProblem.git("That stash is no longer there.")
        }
        return entry.selector
    }

    // MARK: History

    /// Streams `git log` rows for `scope`, newest first, in topological order.
    public func history(scope: HistoryScope, limit: Int? = nil) -> AsyncThrowingStream<Data, any Error> {
        var arguments = ["log", "-z", "--topo-order", "--decorate=full", LogParser.format]
        if let limit { arguments.append("-n\(limit)") }
        switch scope {
        case .current(let upstream):
            arguments.append("HEAD")
            if let upstream { arguments.append(upstream) }
        case .all:
            arguments += ["--branches", "--remotes", "--tags", "HEAD"]
        case .refs(let names):
            arguments += names
        }
        arguments.append("--")
        return runner.stream(command(arguments))
    }

    public func commitDetail(_ id: ObjectID) async throws -> CommitDetail {
        let result = try await read(["show", "-s", "--decorate=full", CommitDetail.format, id.hex])
        guard let detail = CommitDetail.parse(result.stdout) else { throw OpenProblem.git("Couldn't read commit \(id.short).") }
        return detail
    }

    /// git's empty tree (diffs of root commits).
    public func emptyTree() async throws -> String {
        try await read(["hash-object", "-t", "tree", "/dev/null"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files changed by a commit, against its first parent (or nothing, for a root commit).
    public func changedFiles(in id: ObjectID, parent: ObjectID?) async throws -> [ChangedFile] {
        let base: String
        if let parent { base = parent.hex } else { base = try await emptyTree() }
        let result = try await read(["diff-tree", "-r", "-z", "--name-status", "-M", base, id.hex])
        return ChangedFile.parseNameStatus(result.stdout)
    }

    /// One file's diff in a commit.
    public func diff(of file: ChangedFile, in id: ObjectID, parent: ObjectID?, options: DiffOptions = DiffOptions()) async throws -> DiffResult {
        let base: String
        if let parent { base = parent.hex } else { base = try await emptyTree() }
        var arguments = ["diff"] + Self.diffFlags + ["-U\(options.contextLines)", "-M"]
        if options.ignoreWhitespace { arguments.append("--ignore-all-space") }
        let paths = [file.path] + (file.originalPath.map { [$0] } ?? [])
        var result = try await runDiff(arguments + [base, id.hex, "--"] + paths, acceptsExitOne: false, timeout: options.timeout)
        var fallback = false
        if result.timedOut {
            fallback = true
            result = try await runDiff(arguments + ["--diff-algorithm=myers", base, id.hex, "--"] + paths, acceptsExitOne: false, timeout: nil)
        }
        return DiffResult(file: DiffParser.parseSingle(result.stdout), usedFallback: fallback)
    }

    /// Files in a stash: tracked changes against the commit it was made on, plus its
    /// untracked files.
    public func stashFiles(_ entry: StashEntry) async throws -> [ChangedFile] {
        var files = ChangedFile.parseNameStatus(try await read(["diff-tree", "-r", "-z", "--name-status", "-M",
                                                                "\(entry.id.hex)^1", entry.id.hex]).stdout)
        if (try? await resolve("\(entry.id.hex)^3")) != nil {
            let untracked = try await read(["ls-tree", "-r", "-z", "--name-only", "\(entry.id.hex)^3"]).stdout
            for name in untracked.split(separator: 0) {
                files.append(ChangedFile(path: String(decoding: name, as: UTF8.self), change: .untracked, fromUntrackedStash: true))
            }
        }
        return files
    }

    public func stashDiff(_ entry: StashEntry, file: ChangedFile, options: DiffOptions = DiffOptions()) async throws -> DiffResult {
        if file.fromUntrackedStash {
            let commit = try await resolve("\(entry.id.hex)^3")
            return try await diff(of: ChangedFile(path: file.path, change: .added), in: commit, parent: nil, options: options)
        }
        let parent = try await resolve("\(entry.id.hex)^1")
        return try await diff(of: file, in: entry.id, parent: parent, options: options)
    }

    // MARK: In-progress operations

    public func inProgressOperation() -> InProgressOperation? {
        InProgressOperation.detect(gitDirectory: gitDirectory)
    }

    public func continueOperation(_ operation: InProgressOperation) async throws {
        try await exclusive {
            if operation == .merge {
                try await self.write(["commit", "--no-edit"])
            } else {
                try await self.write([operation.subcommand, "--continue"], environment: ["GIT_EDITOR": "true"])
            }
        }
    }

    public func abortOperation(_ operation: InProgressOperation) async throws {
        try await exclusive { try await self.write([operation.subcommand, "--abort"], environment: Self.english) }
    }

    /// Whether a conflicted file still has conflict markers.
    public func hasConflictMarkers(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path) else { return false }
        return ConflictMarkers.present(in: data)
    }
}
