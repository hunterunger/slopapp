import Foundation

/// A configured remote (`git remote -v`).
public struct Remote: Sendable, Equatable, Identifiable, Hashable {
    public var name: String
    public var fetchURL: String
    /// Only when it differs from the fetch URL (`remote.<name>.pushurl`).
    public var pushURL: String?

    public var id: String { name }

    public init(name: String, fetchURL: String, pushURL: String? = nil) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }

    /// Parses `git remote -v`: "origin\thttps://… (fetch)\norigin\thttps://… (push)".
    public static func parse(_ output: String) -> [Remote] {
        var order: [String] = []
        var fetch: [String: String] = [:], push: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = parts[0]
            var rest = parts[1]
            var isPush = false
            if rest.hasSuffix(" (push)") { isPush = true; rest.removeLast(7) } else if rest.hasSuffix(" (fetch)") { rest.removeLast(8) }
            if !order.contains(name) { order.append(name) }
            if isPush { push[name] = rest } else { fetch[name] = rest }
        }
        return order.map { name in
            let f = fetch[name] ?? push[name] ?? ""
            let p = push[name]
            return Remote(name: name, fetchURL: f, pushURL: p == f ? nil : p)
        }
    }
}

/// Names people type for remotes and tags, checked before git sees them.
public enum RefNameRules {
    /// The rules `git check-ref-format` applies, in a sentence. `noun`: "Branch", "Tag", "Remote".
    public static func problem(with name: String, noun: String, allowSlash: Bool = true) -> String? {
        if name.isEmpty { return "Enter a name." }
        if name.contains(where: { $0.isWhitespace }) { return "\(noun) names can't contain spaces." }
        if !allowSlash && name.contains("/") { return "\(noun) names can't contain “/”." }
        let forbidden: [Character] = ["~", "^", ":", "?", "*", "[", "\\"]
        if name.contains(where: { forbidden.contains($0) }) { return "\(noun) names can't contain ~ ^ : ? * [ or \\." }
        if name.contains("..") { return "\(noun) names can't contain “..”." }
        if name.contains("@{") { return "\(noun) names can't contain “@{”." }
        if name == "@" { return "“@” isn't a valid name." }
        if name.hasPrefix("-") { return "\(noun) names can't start with a hyphen." }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.contains("//") { return "Slashes must separate words." }
        if name.hasSuffix(".") || name.hasSuffix(".lock") { return "\(noun) names can't end with “.” or “.lock”." }
        if name.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return "Parts of a name can't start with “.”." }
        if name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return "\(noun) names can't contain control characters." }
        return nil
    }
}

/// What removing a remote took with it, so ⌘Z can put it back without touching the network:
/// its config, the branches that tracked it, and its remote-tracking refs.
public struct RemovedRemote: Sendable, Equatable {
    public var name: String
    /// `git config --get-regexp` lines: "remote.origin.url https://…".
    public var config: [String]
    /// Refs under refs/remotes/<name>/: (full name, object).
    public var refs: [(String, String)]

    public static func == (a: RemovedRemote, b: RemovedRemote) -> Bool {
        a.name == b.name && a.config == b.config && a.refs.map(\.0) == b.refs.map(\.0) && a.refs.map(\.1) == b.refs.map(\.1)
    }
}

/// A tag, for undoing a delete: its name and the object it pointed at (the tag object for
/// annotated tags, so the message survives).
public struct DeletedTag: Sendable, Equatable {
    public var name: String
    public var object: String
}

public extension Repository {
    // MARK: Remotes

    func remoteList() async throws -> [Remote] {
        Remote.parse(try await read(["remote", "-v"]).stdoutString)
    }

    func addRemote(name: String, url: String) async throws {
        try await exclusive { try await self.write(["remote", "add", "--", name, url], environment: Self.english) }
    }

    func renameRemote(_ old: String, to new: String) async throws {
        try await exclusive { try await self.write(["remote", "rename", "--", old, new], environment: Self.english) }
    }

    func setRemoteURL(_ name: String, url: String) async throws {
        try await exclusive {
            try await self.write(["remote", "set-url", "--", name, url], environment: Self.english)
            // A separate push URL would silently keep pushing to the old address.
            _ = try await self.runner.run(self.command(["config", "--unset-all", "remote.\(name).pushurl"]))
        }
    }

    /// Removes a remote and returns what's needed to put it back.
    func removeRemote(_ name: String) async throws -> RemovedRemote {
        try await exclusive {
            let pattern = "^remote\\.\(NSRegularExpression.escapedPattern(for: name))\\."
            let remoteConfig = try await self.runner.run(self.command(["config", "--local", "--get-regexp", pattern])).stdoutString
            var lines = remoteConfig.split(whereSeparator: \.isNewline).map(String.init)
            // Branches that track it lose branch.<b>.remote/.merge too.
            let branchConfig = try await self.runner.run(self.command(["config", "--local", "--get-regexp", "^branch\\..*\\.(remote|merge|pushremote)$"])).stdoutString
            let branchLines = branchConfig.split(whereSeparator: \.isNewline).map(String.init)
            let tracking = Set(branchLines.compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] == name, parts[0].hasSuffix(".remote") || parts[0].hasSuffix(".pushremote") else { return nil }
                return String(parts[0].dropLast(parts[0].hasSuffix(".pushremote") ? 11 : 7))
            })
            lines += branchLines.filter { line in tracking.contains { line.hasPrefix($0 + ".") } }
            let refsOutput = try await self.read(["for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes/\(name)/"]).stdoutString
            let refs = refsOutput.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
                let parts = line.split(separator: " ").map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
            try await self.write(["remote", "remove", "--", name], environment: Self.english)
            return RemovedRemote(name: name, config: lines, refs: refs)
        }
    }

    /// Undo Remove Remote.
    func restoreRemote(_ removed: RemovedRemote) async throws {
        try await exclusive {
            for line in removed.config {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                try await self.write(["config", "--local", "--add", parts[0], parts[1]])
            }
            for (ref, object) in removed.refs {
                try await self.write(["update-ref", ref, object])
            }
        }
    }

    // MARK: Tags

    /// Creates a tag at `commit`: annotated when there's a message (signed too if the user's
    /// config says so), lightweight otherwise.
    func createTag(_ name: String, at commit: ObjectID, message: String?) async throws {
        try await exclusive {
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await self.write(["tag", "-a", "--file=-", "--", name, commit.hex], stdin: Data(message.utf8), environment: Self.english)
            } else {
                try await self.write(["tag", "--", name, commit.hex], environment: Self.english)
            }
        }
    }

    func deleteTag(_ name: String) async throws -> DeletedTag {
        try await exclusive {
            let object = try await self.read(["rev-parse", "--verify", "refs/tags/\(name)"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            try await self.write(["tag", "-d", "--", name], environment: Self.english)
            return DeletedTag(name: name, object: object)
        }
    }

    func restoreTag(_ tag: DeletedTag) async throws {
        try await exclusive { try await self.write(["update-ref", "refs/tags/\(tag.name)", tag.object, ""]) }
    }

    /// The tag's message (annotated tags), nil for lightweight ones.
    func tagMessage(_ name: String) async -> String? {
        guard let type = try? await read(["cat-file", "-t", "refs/tags/\(name)"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines),
              type == "tag" else { return nil }
        return try? await read(["tag", "-l", "--format=%(contents)", "--", name]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pushTag(_ name: String, to remote: String, onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws {
        try await write(["push", "--progress", remote, "refs/tags/\(name):refs/tags/\(name)"], environment: Self.english,
                        onStderr: Self.progressHandler(onProgress))
    }

    func pushAllTags(to remote: String, onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws {
        try await write(["push", "--progress", "--tags", remote], environment: Self.english, onStderr: Self.progressHandler(onProgress))
    }

    func deleteRemoteTag(_ name: String, on remote: String) async throws {
        try await write(["push", "--progress", remote, ":refs/tags/\(name)"], environment: Self.english)
    }

    /// Force push the current branch, only if the remote is still where we last saw it.
    func forcePush(onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws {
        try await exclusive {
            try await self.write(["push", "--progress", "--force-with-lease"], environment: Self.english,
                                 onStderr: Self.progressHandler(onProgress))
        }
    }
}

// MARK: Clone

/// What someone typed or pasted as a repository address.
public enum CloneAddress {
    /// Trims it, and drops a pasted "git clone " in front.
    public static func normalize(_ typed: String) -> String {
        var s = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("git clone ") { s = String(s.dropFirst(10)).trimmingCharacters(in: .whitespaces) }
        // A pasted command may carry options or a folder after the URL; keep the URL.
        let words = s.split(separator: " ").map(String.init)
        if words.count > 1 {
            s = words.first(where: { looksLikeAddress($0) }) ?? words.first(where: { !$0.hasPrefix("-") }) ?? s
        }
        return s
    }

    static func looksLikeAddress(_ s: String) -> Bool {
        s.contains("://") || isSCPLike(s) || s.hasPrefix("/") || s.hasPrefix("~")
    }

    /// nil when it looks like something git can clone.
    public static func problem(with typed: String) -> String? {
        let s = normalize(typed)
        if s.isEmpty { return "Enter the repository's address." }
        if let scheme = s.range(of: "://").map({ String(s[..<$0.lowerBound]).lowercased() }) {
            let known = ["https", "http", "ssh", "git", "file", "git+ssh", "ssh+git"]
            if !known.contains(scheme) { return "Commit can clone https://, ssh:// and git@host:path addresses." }
            if URLComponents(string: s)?.host?.isEmpty ?? true, scheme != "file" { return "That address has no server name." }
            return nil
        }
        if isSCPLike(s) || s.hasPrefix("/") || s.hasPrefix("~") { return nil }
        return "Enter an address like https://example.com/owner/project.git or git@example.com:owner/project.git."
    }

    /// git@github.com:owner/repo.git
    static func isSCPLike(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let host = s[..<colon]
        return !host.isEmpty && !host.contains("/") && s.index(after: colon) < s.endIndex
    }

    /// The folder name git would use: the last path part without ".git".
    public static func suggestedName(for typed: String) -> String {
        var s = normalize(typed)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        let separators: Set<Character> = ["/", ":"]
        let name = s.split(whereSeparator: { separators.contains($0) }).last.map(String.init) ?? ""
        let cleaned = name.replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty || cleaned.contains("@") ? "repository" : cleaned
    }
}

/// Where a clone goes, and why it can't go there.
public struct CloneDestination: Sendable, Equatable {
    public var parent: URL
    public var name: String

    public init(parent: URL, name: String) {
        self.parent = parent
        self.name = name
    }

    public var url: URL { parent.appendingPathComponent(name, isDirectory: true) }

    public func problem(fileManager: FileManager = .default) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a folder name." }
        if trimmed.contains("/") || trimmed.contains(":") { return "Folder names can't contain “/” or “:”." }
        if trimmed.hasPrefix(".") { return "Choose a name that doesn't start with a dot." }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The folder \(parent.lastPathComponent) doesn't exist."
        }
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            let empty = isDirectory.boolValue && ((try? fileManager.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false)
            if !empty { return "There's already something called “\(trimmed)” in \(parent.lastPathComponent)." }
        }
        return nil
    }
}

public extension Repository {
    /// Clones `address` into `destination`. Cancelling stops git and removes the half-made folder.
    static func clone(_ address: String, into destination: CloneDestination, submodules: Bool, runner: any GitRunner,
                      onProgress: (@Sendable (GitProgress) -> Void)? = nil) async throws -> URL {
        let target = destination.url
        let existedBefore = FileManager.default.fileExists(atPath: target.path)
        var arguments = ["clone", "--progress"]
        if submodules { arguments.append("--recurse-submodules") }
        arguments += ["--", CloneAddress.normalize(address), target.path]
        let command = GitCommand(arguments, in: destination.parent, environment: english)
        do {
            let result = try await runner.run(command, onStderr: progressHandler(onProgress))
            guard result.succeeded else { throw GitFailure(command: command, result: result) }
            return target
        } catch {
            // git removes its own junk on failure and on SIGTERM; make sure, for SIGKILL.
            if !existedBefore, FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: target)
            }
            throw error
        }
    }
}
