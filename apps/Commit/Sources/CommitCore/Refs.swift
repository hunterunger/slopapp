import Foundation

/// A branch or tag from `git for-each-ref`.
public struct GitRef: Sendable, Equatable, Identifiable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable { case local, remote, tag }

    /// Full name: refs/heads/main.
    public var fullName: String
    public var kind: Kind
    public var target: ObjectID?
    /// Full upstream name (refs/remotes/origin/main) for local branches that track one.
    public var upstream: String?
    public var isHead: Bool
    /// A tag with its own message (an annotated tag). `target` is the commit it points at.
    public var isAnnotated: Bool

    public init(fullName: String, kind: Kind, target: ObjectID?, upstream: String? = nil, isHead: Bool = false,
                isAnnotated: Bool = false) {
        self.fullName = fullName
        self.kind = kind
        self.target = target
        self.upstream = upstream
        self.isHead = isHead
        self.isAnnotated = isAnnotated
    }

    public var id: String { fullName }

    /// main, origin/main, v1.0.
    public var name: String {
        switch kind {
        case .local: String(fullName.dropFirst("refs/heads/".count))
        case .remote: String(fullName.dropFirst("refs/remotes/".count))
        case .tag: String(fullName.dropFirst("refs/tags/".count))
        }
    }

    /// "origin" for origin/feature/x.
    public var remoteName: String? {
        guard kind == .remote else { return nil }
        return name.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    /// "feature/x" for origin/feature/x.
    public var nameOnRemote: String? {
        guard kind == .remote else { return nil }
        let parts = name.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }

    /// Short upstream: origin/main.
    public var upstreamName: String? {
        upstream.map { $0.hasPrefix("refs/remotes/") ? String($0.dropFirst(13)) : $0 }
    }
}

public struct RefList: Sendable, Equatable {
    public var local: [GitRef] = []
    public var remote: [GitRef] = []
    public var tags: [GitRef] = []

    public init(local: [GitRef] = [], remote: [GitRef] = [], tags: [GitRef] = []) {
        self.local = local
        self.remote = remote
        self.tags = tags
    }

    public var current: GitRef? { local.first(where: \.isHead) }
    public var remoteNames: [String] {
        var seen = Set<String>()
        return remote.compactMap(\.remoteName).filter { seen.insert($0).inserted }
    }

    /// `git for-each-ref --format=<format> refs/heads refs/remotes refs/tags`.
    public static let format = "--format=%(refname)%1f%(objectname)%1f%(upstream)%1f%(HEAD)%1f%(symref)%1f%(*objectname)"

    public static func parse(_ data: Data) -> RefList {
        var list = RefList()
        for line in data.split(separator: 10) {
            let fields = line.split(separator: 0x1f, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            guard fields.count >= 5 else { continue }
            let name = fields[0]
            guard fields[4].isEmpty else { continue } // symbolic refs (origin/HEAD)
            let target = ObjectID(hex: fields[1])
            if name.hasPrefix("refs/heads/") {
                list.local.append(GitRef(fullName: name, kind: .local, target: target,
                                         upstream: fields[2].isEmpty ? nil : fields[2], isHead: fields[3] == "*"))
            } else if name.hasPrefix("refs/remotes/") {
                list.remote.append(GitRef(fullName: name, kind: .remote, target: target))
            } else if name.hasPrefix("refs/tags/") {
                // Annotated tags: point at the commit (the peeled object), not the tag object.
                let peeled = fields.count > 5 ? ObjectID(hex: fields[5]) : nil
                list.tags.append(GitRef(fullName: name, kind: .tag, target: peeled ?? target, isAnnotated: peeled != nil))
            }
        }
        return list
    }

    /// Case-insensitive substring filter on the short name.
    public static func filter(_ refs: [GitRef], _ query: String) -> [GitRef] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return refs }
        return refs.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// A stash entry from `git stash list`.
public struct StashEntry: Sendable, Equatable, Identifiable, Hashable {
    public var id: ObjectID
    /// stash@{0}
    public var selector: String
    /// "On main: WIP: scratch file"
    public var summary: String
    public var date: Date

    public init(id: ObjectID, selector: String, summary: String, date: Date) {
        self.id = id
        self.selector = selector
        self.summary = summary
        self.date = date
    }

    /// The message without git's "On main: " / "WIP on main: " prefix.
    public var message: String {
        for prefix in ["On ", "WIP on "] where summary.hasPrefix(prefix) {
            if let colon = summary.range(of: ": ") { return String(summary[colon.upperBound...]) }
        }
        return summary
    }

    /// The branch the stash was made on.
    public var branch: String? {
        for prefix in ["On ", "WIP on "] where summary.hasPrefix(prefix) {
            let rest = summary.dropFirst(prefix.count)
            if let colon = rest.range(of: ": ") { return String(rest[..<colon.lowerBound]) }
        }
        return nil
    }

    public static let format = "--format=%H%x1f%gd%x1f%gs%x1f%ct"

    public static func parse(_ data: Data) -> [StashEntry] {
        data.split(separator: 0).compactMap { record in
            let fields = record.split(separator: 0x1f, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            guard fields.count == 4, let id = ObjectID(hex: fields[0].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return StashEntry(id: id, selector: fields[1], summary: fields[2],
                              date: Date(timeIntervalSince1970: TimeInterval(Int(fields[3]) ?? 0)))
        }
    }
}

/// Branch names people type, checked the way `git check-ref-format --branch` would before
/// we even ask git (instant feedback in the sheet).
public enum BranchName {
    /// nil when fine, otherwise a short reason.
    public static func problem(with name: String) -> String? {
        if name.isEmpty { return "Enter a name." }
        if name.contains(where: { $0.isWhitespace }) { return "Branch names can't contain spaces." }
        let forbidden: [Character] = ["~", "^", ":", "?", "*", "[", "\\"]
        if name.contains(where: { forbidden.contains($0) }) { return "Branch names can't contain ~ ^ : ? * [ or \\." }
        if name.contains("..") { return "Branch names can't contain “..”." }
        if name.contains("@{") { return "Branch names can't contain “@{”." }
        if name == "@" { return "“@” isn't a valid branch name." }
        if name.hasPrefix("-") { return "Branch names can't start with a hyphen." }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.contains("//") { return "Slashes must separate words." }
        if name.hasSuffix(".") || name.hasSuffix(".lock") { return "Branch names can't end with “.” or “.lock”." }
        if name.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return "Parts of a branch name can't start with “.”." }
        if name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return "Branch names can't contain control characters." }
        return nil
    }

    /// Turns typed text into a likely branch name: spaces become hyphens.
    public static func suggest(from typed: String) -> String {
        typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
    }
}
