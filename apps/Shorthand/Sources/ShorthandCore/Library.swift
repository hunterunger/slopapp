import Foundation

/// How an abbreviation's case is matched.
public enum CaseMode: String, Codable, Sendable, CaseIterable {
    /// Only exactly as written.
    case exact
    /// Any case; the expansion follows it: `addr` as written, `Addr` capitalised, `ADDR` in capitals.
    case adapt
}

public struct Snippet: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var groupID: UUID
    /// Optional label; lists show the first line of the content when it's empty.
    public var name: String
    public var abbreviation: String
    /// The text with its placeholders. For a formatted snippet it's the plain text of
    /// `richText`, character for character (images are U+FFFC), so offsets line up.
    public var content: String
    /// Formatted text and images (RTFD), or nil for a plain-text snippet.
    public var richText: Data?
    public var caseMode: CaseMode
    public var useCount: Int
    public var lastUsed: Date?
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), groupID: UUID, name: String = "", abbreviation: String, content: String, richText: Data? = nil,
                caseMode: CaseMode = .exact, useCount: Int = 0, lastUsed: Date? = nil, created: Date = Date(), modified: Date? = nil) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.abbreviation = abbreviation
        self.content = content
        self.richText = richText
        self.caseMode = caseMode
        self.useCount = useCount
        self.lastUsed = lastUsed
        self.created = created
        self.modified = modified ?? created
    }

    public var isFormatted: Bool { richText != nil }

    /// The content without images, for lists and search.
    public var plainContent: String { richText == nil ? content : content.filter { $0 != attachmentCharacter } }

    /// The name, or the content's first non-empty line.
    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let line = plainContent.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        if line.isEmpty { return content.contains(attachmentCharacter) ? "Image" : "Empty snippet" }
        return line
    }
}

public struct SnippetGroup: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
    }
}

/// Every snippet and group. Every snippet belongs to exactly one group; there's always at
/// least one group.
public struct Library: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let defaultGroupName = "Snippets"

    public var version: Int
    public var groups: [SnippetGroup]
    public var snippets: [Snippet]

    public init(groups: [SnippetGroup] = [], snippets: [Snippet] = []) {
        self.version = Self.currentVersion
        self.groups = groups
        self.snippets = snippets
        normalize()
    }

    /// Ensures a default group exists and every snippet points at a real group.
    public mutating func normalize() {
        if groups.isEmpty { groups = [SnippetGroup(name: Self.defaultGroupName)] }
        let ids = Set(groups.map(\.id))
        let fallback = groups[0].id
        for index in snippets.indices where !ids.contains(snippets[index].groupID) {
            snippets[index].groupID = fallback
        }
    }

    public var defaultGroupID: UUID { groups[0].id }

    public func group(_ id: UUID) -> SnippetGroup? { groups.first { $0.id == id } }

    public func snippet(_ id: UUID) -> Snippet? { snippets.first { $0.id == id } }

    /// The snippet `{snippet:…}` means: the exact abbreviation, in any group (a group that's
    /// off is a good place for parts that shouldn't expand on their own).
    public func snippet(abbreviation: String) -> Snippet? {
        guard !abbreviation.isEmpty else { return nil }
        return snippets.first { $0.abbreviation == abbreviation }
    }

    /// For the resolver: finds included snippets in this library.
    public var lookup: (String) -> Snippet? {
        var byAbbreviation: [String: Snippet] = [:]
        for snippet in snippets where !snippet.abbreviation.isEmpty && byAbbreviation[snippet.abbreviation] == nil {
            byAbbreviation[snippet.abbreviation] = snippet
        }
        return { byAbbreviation[$0] }
    }

    public func snippets(in groupID: UUID?) -> [Snippet] {
        guard let groupID else { return snippets }
        return snippets.filter { $0.groupID == groupID }
    }

    /// Snippets that can expand: in an enabled group, with a valid abbreviation and content.
    public var expandable: [Snippet] {
        let enabled = Set(groups.filter(\.isEnabled).map(\.id))
        return snippets.filter {
            enabled.contains($0.groupID) && AbbreviationRules.validate($0.abbreviation) == nil && !$0.content.isEmpty
        }
    }

    // MARK: Editing

    @discardableResult
    public mutating func addSnippet(_ snippet: Snippet) -> Snippet {
        var snippet = snippet
        if group(snippet.groupID) == nil { snippet.groupID = defaultGroupID }
        snippets.append(snippet)
        return snippet
    }

    public mutating func update(_ snippet: Snippet, now: Date = Date()) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var snippet = snippet
        if snippet != snippets[index] { snippet.modified = now }
        snippets[index] = snippet
    }

    /// A copy right after the original, abbreviation left empty so it can't clash.
    @discardableResult
    public mutating func duplicate(_ id: UUID, now: Date = Date()) -> Snippet? {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = snippets[index]
        copy.id = UUID()
        copy.abbreviation = ""
        copy.name = copy.name.isEmpty ? "" : copy.name + " copy"
        copy.useCount = 0
        copy.lastUsed = nil
        copy.created = now
        copy.modified = now
        snippets.insert(copy, at: index + 1)
        return copy
    }

    /// Removes snippets; returns them with their positions so undo can put them back.
    public mutating func removeSnippets(_ ids: Set<UUID>) -> [(index: Int, snippet: Snippet)] {
        let removed = snippets.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, snippet: $0.element) }
        snippets.removeAll { ids.contains($0.id) }
        return removed
    }

    public mutating func restore(_ removed: [(index: Int, snippet: Snippet)]) {
        for entry in removed.sorted(by: { $0.index < $1.index }) {
            snippets.insert(entry.snippet, at: min(entry.index, snippets.count))
        }
        normalize()
    }

    @discardableResult
    public mutating func addGroup(named name: String) -> SnippetGroup {
        let group = SnippetGroup(name: uniqueGroupName(name))
        groups.append(group)
        return group
    }

    public func uniqueGroupName(_ base: String) -> String {
        let names = Set(groups.map { $0.name.lowercased() })
        if !names.contains(base.lowercased()) { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    public mutating func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        groups[index].name = trimmed
    }

    public mutating func setGroup(_ id: UUID, enabled: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isEnabled = enabled
    }

    /// What deleting a group took away, for undo.
    public struct RemovedGroup: Sendable {
        public var index: Int
        public var group: SnippetGroup
        public var snippets: [(index: Int, snippet: Snippet)]
    }

    /// Removes a group and its snippets. The last group can't be removed.
    public mutating func removeGroup(_ id: UUID) -> RemovedGroup? {
        guard groups.count > 1, let index = groups.firstIndex(where: { $0.id == id }) else { return nil }
        let group = groups.remove(at: index)
        let removed = removeSnippets(Set(snippets.filter { $0.groupID == id }.map(\.id)))
        return RemovedGroup(index: index, group: group, snippets: removed)
    }

    public mutating func restore(_ removed: RemovedGroup) {
        groups.insert(removed.group, at: min(removed.index, groups.count))
        restore(removed.snippets)
    }

    public mutating func move(_ ids: Set<UUID>, to groupID: UUID) {
        guard group(groupID) != nil else { return }
        for index in snippets.indices where ids.contains(snippets[index].id) { snippets[index].groupID = groupID }
    }

    /// Counts one use (for search ranking). Nothing about what was typed around it.
    public mutating func recordUse(_ id: UUID, at date: Date) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[index].useCount += 1
        snippets[index].lastUsed = date
    }
}
