import Foundation

/// One row of history: kept small so 100,000 of them stay well under the memory budget
/// (hashes packed, author names interned, subject only).
public struct CommitRow: Sendable, Equatable, Identifiable {
    public var id: ObjectID
    public var parents: [ObjectID]
    /// Index into `AuthorTable`.
    public var author: Int32
    /// Author time, seconds since 1970.
    public var timestamp: Int64
    public var subject: String
    /// `%D`: "HEAD -> main, origin/main, tag: v1.0" (empty for most rows).
    public var decorations: String

    public init(id: ObjectID, parents: [ObjectID], author: Int32, timestamp: Int64, subject: String, decorations: String) {
        self.id = id
        self.parents = parents
        self.author = author
        self.timestamp = timestamp
        self.subject = subject
        self.decorations = decorations
    }

    public var isMerge: Bool { parents.count > 1 }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    /// The decorations as labels, in git's order.
    public var refLabels: [RefLabel] { RefLabel.parse(decorations) }
}

/// A label on a history row.
public struct RefLabel: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable { case head, localBranch, remoteBranch, tag }
    public var kind: Kind
    public var name: String
    /// HEAD points at this branch.
    public var isCurrent: Bool

    public init(kind: Kind, name: String, isCurrent: Bool = false) {
        self.kind = kind
        self.name = name
        self.isCurrent = isCurrent
    }

    /// Parses `%D` as printed with `--decorate=full`: "HEAD -> refs/heads/main,
    /// refs/remotes/origin/main, tag: refs/tags/v1".
    public static func parse(_ decorations: String) -> [RefLabel] {
        guard !decorations.isEmpty else { return [] }
        var labels: [RefLabel] = []
        for raw in decorations.components(separatedBy: ", ") {
            var name = raw
            var current = false
            if name == "HEAD" {
                labels.append(RefLabel(kind: .head, name: "HEAD"))
                continue
            }
            if name.hasPrefix("HEAD -> ") { name = String(name.dropFirst(8)); current = true }
            if name.hasPrefix("tag: ") { name = String(name.dropFirst(5)) }
            if name.hasPrefix("refs/heads/") {
                labels.append(RefLabel(kind: .localBranch, name: String(name.dropFirst(11)), isCurrent: current))
            } else if name.hasPrefix("refs/remotes/") {
                let short = String(name.dropFirst(13))
                if !short.hasSuffix("/HEAD") { labels.append(RefLabel(kind: .remoteBranch, name: short)) }
            } else if name.hasPrefix("refs/tags/") {
                labels.append(RefLabel(kind: .tag, name: String(name.dropFirst(10))))
            }
        }
        return labels
    }
}

/// Author names and emails, stored once each.
public struct AuthorTable: Sendable {
    public private(set) var names: [String] = []
    public private(set) var emails: [String] = []
    private var index: [String: Int32] = [:]

    public init() {}

    public mutating func intern(name: String, email: String) -> Int32 {
        let key = name + "\u{1}" + email
        if let existing = index[key] { return existing }
        let id = Int32(names.count)
        names.append(name)
        emails.append(email)
        index[key] = id
        return id
    }

    public func name(_ id: Int32) -> String { names.indices.contains(Int(id)) ? names[Int(id)] : "" }
    public func email(_ id: Int32) -> String { emails.indices.contains(Int(id)) ? emails[Int(id)] : "" }
}

/// Parses `git log -z --format=<LogParser.format>` as it streams in.
public struct LogParser: Sendable {
    /// hash, parents, author name, author email, author time, decorations, subject.
    public static let format = "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s"

    public private(set) var authors = AuthorTable()
    private var pending = Data()

    public init() {}

    /// Adds a chunk of output and returns the rows it completed.
    public mutating func feed(_ chunk: Data) -> [CommitRow] {
        pending.append(chunk)
        var rows: [CommitRow] = []
        var consumed = pending.startIndex
        pending.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var recordStart = 0
            for i in 0..<bytes.count where bytes[i] == 0 {
                if let row = parseRecord(UnsafeBufferPointer(rebasing: bytes[recordStart..<i])) { rows.append(row) }
                recordStart = i + 1
            }
            consumed = pending.startIndex + recordStart
        }
        pending.removeSubrange(pending.startIndex..<consumed)
        return rows
    }

    /// Call at the end of the stream: parses a last record without a trailing NUL.
    public mutating func finish() -> [CommitRow] {
        guard !pending.isEmpty else { return [] }
        let data = pending
        pending = Data()
        let row = data.withUnsafeBytes { raw in parseRecord(raw.bindMemory(to: UInt8.self)) }
        return row.map { [$0] } ?? []
    }

    private mutating func parseRecord(_ record: UnsafeBufferPointer<UInt8>) -> CommitRow? {
        var fields: [UnsafeBufferPointer<UInt8>] = []
        fields.reserveCapacity(7)
        var start = 0
        // Skip a leading newline some git versions put between records.
        while start < record.count, record[start] == 10 { start += 1 }
        var fieldStart = start
        for i in start..<record.count where record[i] == 0x1f && fields.count < 6 {
            fields.append(UnsafeBufferPointer(rebasing: record[fieldStart..<i]))
            fieldStart = i + 1
        }
        fields.append(UnsafeBufferPointer(rebasing: record[fieldStart..<record.count]))
        guard fields.count == 7, let id = ObjectID(ascii: fields[0]) else { return nil }
        var parents: [ObjectID] = []
        if !fields[1].isEmpty {
            var s = 0
            let p = fields[1]
            for i in 0...p.count where i == p.count || p[i] == 32 {
                if i > s, let parent = ObjectID(ascii: UnsafeBufferPointer(rebasing: p[s..<i])) { parents.append(parent) }
                s = i + 1
            }
        }
        let author = authors.intern(name: String(decoding: fields[2], as: UTF8.self),
                                    email: String(decoding: fields[3], as: UTF8.self))
        var time: Int64 = 0
        for b in fields[4] where b >= 48 && b <= 57 { time = time * 10 + Int64(b - 48) }
        return CommitRow(id: id, parents: parents, author: author, timestamp: time,
                         subject: String(decoding: fields[6], as: UTF8.self),
                         decorations: String(decoding: fields[5], as: UTF8.self))
    }
}

/// Full details for the commit detail pane.
public struct CommitDetail: Sendable, Equatable {
    public var id: ObjectID
    public var parents: [ObjectID]
    public var authorName: String
    public var authorEmail: String
    public var authorDate: Date
    public var committerName: String
    public var committerEmail: String
    public var commitDate: Date
    public var decorations: String
    public var message: String

    /// `git show -s --format=<format>`.
    public static let format = "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%ct%x1f%D%x1f%B"

    public static func parse(_ data: Data) -> CommitDetail? {
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.split(separator: "\u{1f}", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count == 10, let id = ObjectID(hex: String(parts[0])) else { return nil }
        return CommitDetail(
            id: id,
            parents: parts[1].split(separator: " ").compactMap { ObjectID(hex: String($0)) },
            authorName: String(parts[2]), authorEmail: String(parts[3]),
            authorDate: Date(timeIntervalSince1970: TimeInterval(Int(parts[4]) ?? 0)),
            committerName: String(parts[5]), committerEmail: String(parts[6]),
            commitDate: Date(timeIntervalSince1970: TimeInterval(Int(parts[7]) ?? 0)),
            decorations: String(parts[8]),
            message: String(parts[9]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var subject: String { message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
    public var body: String {
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

/// A file changed by a commit or stash (`git diff-tree --name-status -z`).
public struct ChangedFile: Sendable, Equatable, Identifiable, Hashable {
    public var path: String
    public var originalPath: String?
    public var change: ChangeKind
    /// Which tree it comes from in a stash: the untracked part has its own commit.
    public var fromUntrackedStash: Bool

    public init(path: String, originalPath: String? = nil, change: ChangeKind, fromUntrackedStash: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.change = change
        self.fromUntrackedStash = fromUntrackedStash
    }

    public var id: String { (fromUntrackedStash ? "u:" : "") + path }

    /// Parses `--name-status -z` output: "M\0path\0", "R100\0old\0new\0".
    public static func parseNameStatus(_ data: Data) -> [ChangedFile] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var files: [ChangedFile] = []
        var i = 0
        while i < fields.count {
            let status = fields[i]
            i += 1
            guard let letter = status.first else { continue }
            let kind = ChangeKind(rawValue: letter) ?? .modified
            if letter == "R" || letter == "C" {
                guard i + 1 < fields.count else { break }
                files.append(ChangedFile(path: fields[i + 1], originalPath: fields[i], change: kind))
                i += 2
            } else {
                guard i < fields.count else { break }
                files.append(ChangedFile(path: fields[i], change: kind))
                i += 1
            }
        }
        return files
    }
}
