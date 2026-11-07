import Foundation

/// One character of porcelain status: what changed in the index (staged) or the worktree.
public enum ChangeKind: Character, Sendable, Equatable {
    case unmodified = "."
    case modified = "M"
    case typeChanged = "T"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case updatedUnmerged = "U"
    case untracked = "?"

    /// Plain words for VoiceOver and tooltips.
    public var label: String {
        switch self {
        case .unmodified: "Unmodified"
        case .modified: "Modified"
        case .typeChanged: "Type changed"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .updatedUnmerged: "Conflicted"
        case .untracked: "New"
        }
    }
}

/// A file in `git status --porcelain=v2`.
public struct StatusEntry: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case ordinary
        case renamed(from: String)
        case copied(from: String)
        case unmerged(conflict: String)
        case untracked
        case ignored
    }

    public var path: String
    public var kind: Kind
    /// X: index vs HEAD.
    public var staged: ChangeKind
    /// Y: worktree vs index.
    public var unstaged: ChangeKind
    public var isSubmodule: Bool
    /// File modes (octal strings) in HEAD, index, worktree; empty for untracked.
    public var modes: [String]
    /// Object names in HEAD and the index; empty for untracked.
    public var hashes: [String]

    public var id: String { path }

    public init(path: String, kind: Kind, staged: ChangeKind, unstaged: ChangeKind,
                isSubmodule: Bool = false, modes: [String] = [], hashes: [String] = []) {
        self.path = path
        self.kind = kind
        self.staged = staged
        self.unstaged = unstaged
        self.isSubmodule = isSubmodule
        self.modes = modes
        self.hashes = hashes
    }

    public var isConflicted: Bool { if case .unmerged = kind { true } else { false } }
    public var isUntracked: Bool { kind == .untracked }
    /// Shows in the Staged section.
    public var hasStagedChanges: Bool { !isConflicted && !isUntracked && kind != .ignored && staged != .unmodified }
    /// Shows in the Changes section.
    public var hasUnstagedChanges: Bool { isUntracked || (!isConflicted && unstaged != .unmodified) }

    public var originalPath: String? {
        switch kind {
        case .renamed(let from), .copied(let from): from
        default: nil
        }
    }

    /// File name and its folder, split for display ("Sources/App/main.swift" → "main.swift", "Sources/App").
    public var nameAndFolder: (name: String, folder: String) {
        Self.split(path)
    }

    public static func split(_ path: String) -> (name: String, folder: String) {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return (trimmed, "") }
        return (String(trimmed[trimmed.index(after: slash)...]), String(trimmed[..<slash]))
    }
}

/// The `# branch.*` headers.
public struct BranchStatus: Sendable, Equatable {
    /// nil when the repository has no commits yet ("(initial)").
    public var head: ObjectID?
    /// nil when HEAD is detached.
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int

    public init(head: ObjectID? = nil, branch: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0) {
        self.head = head
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }

    public var isDetached: Bool { branch == nil }
    public var isUnborn: Bool { head == nil }
}

public struct WorkingTreeStatus: Sendable, Equatable {
    public var branch: BranchStatus
    public var entries: [StatusEntry]

    public init(branch: BranchStatus = BranchStatus(), entries: [StatusEntry] = []) {
        self.branch = branch
        self.entries = entries
    }

    public var staged: [StatusEntry] { entries.filter(\.hasStagedChanges) }
    public var unstaged: [StatusEntry] { entries.filter(\.hasUnstagedChanges) }
    public var conflicted: [StatusEntry] { entries.filter(\.isConflicted) }
    public var isClean: Bool { entries.allSatisfy { $0.kind == .ignored } }
    /// Files with any change (each counted once).
    public var changedCount: Int { entries.filter { $0.kind != .ignored }.count }
}

/// Parses `git status --porcelain=v2 -z --branch`.
public enum StatusParser {
    public static func parse(_ data: Data) -> WorkingTreeStatus {
        var status = WorkingTreeStatus()
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var i = 0
        while i < fields.count {
            let field = fields[i]
            i += 1
            guard let first = field.first else { continue }
            let line = String(decoding: field, as: UTF8.self)
            switch first {
            case UInt8(ascii: "#"):
                parseHeader(line, into: &status.branch)
            case UInt8(ascii: "1"):
                // 1 XY sub mH mI mW hH hI path
                let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count == 9 else { continue }
                status.entries.append(entry(xy: parts[1], sub: parts[2], modes: parts[3...5], hashes: parts[6...7],
                                            path: String(parts[8]), kind: .ordinary))
            case UInt8(ascii: "2"):
                // 2 XY sub mH mI mW hH hI Xscore path NUL origPath
                let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard parts.count == 10, i < fields.count else { continue }
                let original = String(decoding: fields[i], as: UTF8.self)
                i += 1
                let isCopy = parts[8].first == "C"
                status.entries.append(entry(xy: parts[1], sub: parts[2], modes: parts[3...5], hashes: parts[6...7],
                                            path: String(parts[9]),
                                            kind: isCopy ? .copied(from: original) : .renamed(from: original)))
            case UInt8(ascii: "u"):
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count == 11 else { continue }
                var e = entry(xy: parts[1], sub: parts[2], modes: parts[3...6], hashes: parts[7...9], path: String(parts[10]),
                              kind: .unmerged(conflict: String(parts[1])))
                e.staged = .updatedUnmerged
                e.unstaged = .updatedUnmerged
                status.entries.append(e)
            case UInt8(ascii: "?"):
                status.entries.append(StatusEntry(path: String(line.dropFirst(2)), kind: .untracked,
                                                  staged: .unmodified, unstaged: .untracked))
            case UInt8(ascii: "!"):
                status.entries.append(StatusEntry(path: String(line.dropFirst(2)), kind: .ignored,
                                                  staged: .unmodified, unstaged: .unmodified))
            default:
                continue
            }
        }
        return status
    }

    private static func entry(xy: Substring, sub: Substring, modes: ArraySlice<Substring>, hashes: ArraySlice<Substring>, path: String,
                              kind: StatusEntry.Kind) -> StatusEntry {
        let chars = Array(xy)
        let x = chars.count > 0 ? ChangeKind(rawValue: chars[0]) ?? .modified : .unmodified
        let y = chars.count > 1 ? ChangeKind(rawValue: chars[1]) ?? .modified : .unmodified
        return StatusEntry(path: path, kind: kind, staged: x, unstaged: y, isSubmodule: sub.first == "S",
                           modes: modes.map(String.init), hashes: hashes.map(String.init))
    }

    private static func parseHeader(_ line: String, into branch: inout BranchStatus) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return }
        let value = parts[2...].joined(separator: " ")
        switch parts[1] {
        case "branch.oid":
            branch.head = value == "(initial)" ? nil : ObjectID(hex: value)
        case "branch.head":
            branch.branch = value == "(detached)" ? nil : value
        case "branch.upstream":
            branch.upstream = value
        case "branch.ab":
            for token in parts[2...] {
                if token.hasPrefix("+") { branch.ahead = Int(token.dropFirst()) ?? 0 }
                if token.hasPrefix("-") { branch.behind = Int(token.dropFirst()) ?? 0 }
            }
        default:
            break
        }
    }
}
