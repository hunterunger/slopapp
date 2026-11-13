import Foundation

/// Who last changed each line of a file (`git blame --porcelain`).
public struct Blame: Sendable, Equatable {
    public struct Commit: Sendable, Equatable {
        public var id: ObjectID
        public var authorName: String
        public var authorEmail: String
        public var authorTime: Date
        public var summary: String
        /// The commit before this one that touched the file, and the file's name there (for
        /// "Blame the Previous Version").
        public var previous: ObjectID?
        public var previousPath: String?
        /// The file's name in this commit (it may have been renamed since).
        public var path: String
        /// The oldest commit blame looked at (a root commit, or the edge of a range).
        public var isBoundary: Bool

        /// Lines not committed yet show git's all-zero hash.
        public var isUncommitted: Bool { id.isZero }
    }

    public struct Line: Sendable, Equatable {
        /// Index into `commits`.
        public var commit: Int
        /// Line number in the commit that last changed it.
        public var originalLine: Int
        /// Line number in the blamed version (1-based).
        public var line: Int
        public var text: String
    }

    public var commits: [Commit]
    public var lines: [Line]

    public init(commits: [Commit] = [], lines: [Line] = []) {
        self.commits = commits
        self.lines = lines
    }

    public func commit(of line: Line) -> Commit { commits[line.commit] }

    /// Whether `index` starts a run of lines from one commit (the gutter shows it once per run).
    public func startsRun(_ index: Int) -> Bool {
        index == 0 || lines[index - 1].commit != lines[index].commit
    }

    /// Parses `git blame --porcelain` (also `--line-porcelain`): a header line per blamed line
    /// ("<hash> <orig> <final> [<count>]"), the commit's details the first time it appears, then
    /// the line's text after a tab.
    public static func parse(_ data: Data) -> Blame {
        var blame = Blame()
        var index: [ObjectID: Int] = [:]
        var current: Int?
        var originalLine = 0, finalLine = 0
        var expectingHeader = true
        for raw in data.split(separator: 10, omittingEmptySubsequences: false) {
            if raw.first == 9 { // \t: the line's text
                guard let c = current else { continue }
                var text = Data(raw.dropFirst())
                if text.last == 13 { text.removeLast() }
                blame.lines.append(Line(commit: c, originalLine: originalLine, line: finalLine,
                                        text: String(decoding: text, as: UTF8.self)))
                expectingHeader = true
                continue
            }
            let line = String(decoding: raw, as: UTF8.self)
            if expectingHeader {
                let parts = line.split(separator: " ")
                guard parts.count >= 3, let id = ObjectID(hex: String(parts[0])) else { continue }
                originalLine = Int(parts[1]) ?? 0
                finalLine = Int(parts[2]) ?? 0
                if let existing = index[id] {
                    current = existing
                } else {
                    blame.commits.append(Commit(id: id, authorName: "", authorEmail: "", authorTime: Date(timeIntervalSince1970: 0),
                                                summary: "", previous: nil, previousPath: nil, path: "", isBoundary: false))
                    index[id] = blame.commits.count - 1
                    current = blame.commits.count - 1
                }
                expectingHeader = false
                continue
            }
            guard let c = current else { continue }
            let (key, value) = split(line)
            switch key {
            case "author": blame.commits[c].authorName = value
            case "author-mail": blame.commits[c].authorEmail = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            case "author-time": blame.commits[c].authorTime = Date(timeIntervalSince1970: TimeInterval(Int(value) ?? 0))
            case "summary": blame.commits[c].summary = value
            case "boundary": blame.commits[c].isBoundary = true
            case "filename": blame.commits[c].path = value
            case "previous":
                let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
                blame.commits[c].previous = parts.first.flatMap(ObjectID.init(hex:))
                blame.commits[c].previousPath = parts.count > 1 ? parts[1] : nil
            default: break
            }
        }
        return blame
    }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (String(line[..<space]), String(line[line.index(after: space)...]))
    }
}

/// One commit in a file's history (`git log --follow`).
public struct FileHistoryEntry: Sendable, Equatable, Identifiable {
    public var id: ObjectID
    public var parents: [ObjectID]
    public var authorName: String
    public var authorEmail: String
    public var date: Date
    public var subject: String
    /// The file's path in this commit.
    public var path: String
    /// Its path before, when this commit renamed or copied it.
    public var originalPath: String?
    public var change: ChangeKind

    public var changedFile: ChangedFile { ChangedFile(path: path, originalPath: originalPath, change: change) }

    /// `git log --follow -z --name-status -M <format> -- path`.
    public static let format = "--format=%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s"

    /// Parses the output: each record starts with \x1e; the formatted fields end with a NUL,
    /// then (after a newline) the name-status fields, NUL separated.
    public static func parse(_ data: Data) -> [FileHistoryEntry] {
        var entries: [FileHistoryEntry] = []
        for record in data.split(separator: 0x1e) {
            guard let end = record.firstIndex(of: 0) else { continue }
            let header = String(decoding: record[record.startIndex..<end], as: UTF8.self)
            let fields = header.split(separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, let id = ObjectID(hex: fields[0]) else { continue }
            var rest = record[record.index(after: end)...]
            while rest.first == 10 { rest = rest.dropFirst() }
            let files = ChangedFile.parseNameStatus(Data(rest))
            let file = files.last
            entries.append(FileHistoryEntry(
                id: id,
                parents: fields[1].split(separator: " ").compactMap { ObjectID(hex: String($0)) },
                authorName: fields[2], authorEmail: fields[3],
                date: Date(timeIntervalSince1970: TimeInterval(Int(fields[4]) ?? 0)),
                subject: fields[5],
                path: file?.path ?? "", originalPath: file?.originalPath, change: file?.change ?? .modified))
        }
        return entries
    }
}

public extension Repository {
    /// Blame for `path` at `revision` (nil: the working copy, uncommitted lines included).
    func blame(_ path: String, at revision: ObjectID?, ignoreWhitespace: Bool = false) async throws -> Blame {
        var arguments = ["blame", "--porcelain"]
        if ignoreWhitespace { arguments.append("-w") }
        if let revision { arguments.append(revision.hex) }
        arguments += ["--", path]
        return Blame.parse(try await read(arguments, timeout: .seconds(60)).stdout)
    }

    /// Every commit that changed `path`, newest first, following renames.
    func fileHistory(_ path: String, limit: Int = 5_000) async throws -> [FileHistoryEntry] {
        let result = try await read(["log", "--follow", "-z", "--name-status", "-M", "-n\(limit)",
                                     FileHistoryEntry.format, "HEAD", "--", path], timeout: .seconds(60))
        return FileHistoryEntry.parse(result.stdout)
    }

    /// The working copy of `path` against HEAD (staged and unstaged together).
    func diffAgainstHead(_ path: String, options: DiffOptions = DiffOptions()) async throws -> DiffResult {
        var arguments = ["diff"] + Self.diffFlags + ["-U\(options.contextLines)"]
        if options.ignoreWhitespace { arguments.append("--ignore-all-space") }
        let result = try await read(arguments + ["HEAD", "--", path], timeout: .seconds(30))
        return DiffResult(file: DiffParser.parseSingle(result.stdout))
    }

    /// Whether the working copy of `path` differs from HEAD (the "Current Version" row).
    func hasUncommittedChanges(_ path: String) async -> Bool {
        guard let result = try? await runner.run(command(["diff", "--quiet", "HEAD", "--", path])) else { return false }
        return result.exitCode == 1
    }
}

extension ObjectID {
    /// git's 0000000… (uncommitted lines in blame).
    public var isZero: Bool { w0 == 0 && w1 == 0 && w2 == 0 && w3 == 0 }
}
