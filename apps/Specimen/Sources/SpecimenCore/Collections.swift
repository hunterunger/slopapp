import Foundation

/// Your own tags: names, each holding a set of family names. Flat (no nesting yet).
public struct TagLibrary: Codable, Hashable, Sendable {
    /// Tag name → family names.
    public private(set) var tags: [String: Set<String>]

    public init(tags: [String: Set<String>] = [:]) {
        self.tags = tags
    }

    /// Tag names A to Z.
    public var names: [String] {
        tags.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var isEmpty: Bool { tags.isEmpty }

    /// Trims and collapses whitespace. Empty means "not a valid name".
    public static func normalize(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The existing tag with this name, ignoring case.
    public func existing(_ name: String) -> String? {
        let wanted = LibraryFilter.fold(Self.normalize(name))
        return tags.keys.first { LibraryFilter.fold($0) == wanted }
    }

    /// Adds an empty tag. Returns its name, or the existing tag's name if one matches
    /// (ignoring case); nil for a blank name.
    @discardableResult
    public mutating func create(_ name: String) -> String? {
        let clean = Self.normalize(name)
        guard !clean.isEmpty else { return nil }
        if let existing = existing(clean) { return existing }
        tags[clean] = []
        return clean
    }

    /// A free name like "New Tag", "New Tag 2", …
    public func unusedName(_ base: String = "New Tag") -> String {
        if existing(base) == nil { return base }
        var number = 2
        while existing("\(base) \(number)") != nil { number += 1 }
        return "\(base) \(number)"
    }

    /// Renames a tag. Fails for a blank name or one another tag already has.
    @discardableResult
    public mutating func rename(_ old: String, to new: String) -> Bool {
        let clean = Self.normalize(new)
        guard let families = tags[old], !clean.isEmpty else { return false }
        if clean == old { return true }
        if let other = existing(clean), other != old { return false }
        tags[old] = nil
        tags[clean] = families
        return true
    }

    public mutating func delete(_ name: String) {
        tags[name] = nil
    }

    /// Attaches a tag (creating it if needed) to families.
    public mutating func attach(_ name: String, to families: [String]) {
        guard let tag = create(name) else { return }
        tags[tag, default: []].formUnion(families)
    }

    public mutating func detach(_ name: String, from families: [String]) {
        guard tags[name] != nil else { return }
        tags[name]?.subtract(families)
    }

    public func families(in name: String) -> Set<String> { tags[name] ?? [] }

    /// The tags a family has, A to Z.
    public func tags(of family: String) -> [String] {
        names.filter { tags[$0]?.contains(family) == true }
    }

    public enum Membership: Sendable, Equatable { case none, some, all }

    /// Whether all, some or none of `families` have the tag (checkbox state in the tag panel).
    public func membership(_ name: String, families: [String]) -> Membership {
        guard !families.isEmpty, let members = tags[name] else { return .none }
        let count = families.filter(members.contains).count
        return count == 0 ? .none : count == families.count ? .all : .some
    }

}

/// A saved set of rules. Fonts appear while they match.
public struct SmartCollection: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var rules: SmartRules

    public init(id: UUID = UUID(), name: String, rules: SmartRules = SmartRules()) {
        self.id = id
        self.name = name
        self.rules = rules
    }
}

public struct SmartRules: Codable, Hashable, Sendable {
    public enum State: String, Codable, CaseIterable, Sendable, Identifiable {
        case any, active, temporary, inactive
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .any: "Any"
            case .active: "Active"
            case .temporary: "Active until you quit"
            case .inactive: "Inactive"
            }
        }
    }

    public enum Source: String, Codable, CaseIterable, Sendable, Identifiable {
        case any, yours, macOS
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .any: "Anywhere"
            case .yours: "Your fonts"
            case .macOS: "macOS fonts"
            }
        }
    }

    /// Words every font's name must contain (family, style or PostScript name).
    public var nameContains: String
    public var category: FontCategory?
    public var state: State
    public var source: Source
    public var tag: String?
    public var variableOnly: Bool
    public var favoritesOnly: Bool
    /// Families with at least this many styles (0 = any).
    public var minimumStyles: Int

    public init(nameContains: String = "", category: FontCategory? = nil, state: State = .any, source: Source = .any,
                tag: String? = nil, variableOnly: Bool = false, favoritesOnly: Bool = false, minimumStyles: Int = 0) {
        self.nameContains = nameContains
        self.category = category
        self.state = state
        self.source = source
        self.tag = tag
        self.variableOnly = variableOnly
        self.favoritesOnly = favoritesOnly
        self.minimumStyles = minimumStyles
    }

    /// Rules that match the current sidebar item and search, to save them as a collection.
    public init(sidebar: SidebarItem, search: String) {
        self.init(nameContains: search.trimmingCharacters(in: .whitespaces))
        switch sidebar {
        case .userFonts: source = .yours
        case .systemFonts: source = .macOS
        case .active: state = .active
        case .inactive: state = .inactive
        case .favorites: favoritesOnly = true
        case .variable: variableOnly = true
        case .category(let value): category = value
        case .tag(let name): tag = name
        case .all, .smart, .folder, .document: break
        }
    }

    /// One line for the sidebar's tooltip: "Sans Serif · Active · name contains “grotesk”".
    public var summary: String {
        var parts: [String] = []
        if let category { parts.append(category.title) }
        if state != .any { parts.append(state.title) }
        if source != .any { parts.append(source.title) }
        if let tag { parts.append("tagged “\(tag)”") }
        if variableOnly { parts.append("Variable") }
        if favoritesOnly { parts.append("Favorites") }
        if minimumStyles > 1 { parts.append("\(minimumStyles)+ styles") }
        if !nameContains.isEmpty { parts.append("name contains “\(nameContains)”") }
        return parts.isEmpty ? "Every font" : parts.joined(separator: " · ")
    }
}

/// Tags and smart collections, in one small readable JSON file (collections.json).
public struct CollectionsStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("collections.json")
    }

    public struct Contents: Codable, Equatable, Sendable {
        public var version = 1
        public var tags: [String: [String]]
        public var smartCollections: [SmartCollection]

        public init(tags: TagLibrary = TagLibrary(), smartCollections: [SmartCollection] = []) {
            self.tags = tags.tags.mapValues { $0.sorted() }
            self.smartCollections = smartCollections
        }

        public var tagLibrary: TagLibrary { TagLibrary(tags: tags.mapValues(Set.init)) }
    }

    /// Missing file: empty. A damaged one is set aside (never silently lost).
    public func load() -> Contents {
        guard let data = try? Data(contentsOf: url) else { return Contents() }
        if let contents = try? JSONDecoder().decode(Contents.self, from: data) { return contents }
        let backup = url.deletingPathExtension().appendingPathExtension("damaged.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return Contents()
    }

    public func save(_ contents: Contents) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(contents).write(to: url, options: .atomic)
    }
}

/// The compare tray: a shortlist that survives clicks elsewhere and relaunches. Holds
/// faces (so a style picked in compare sticks), in the order they were added.
public struct CompareTray: Codable, Hashable, Sendable {
    public private(set) var faceIDs: [String]

    public init(faceIDs: [String] = []) {
        var seen = Set<String>()
        self.faceIDs = faceIDs.filter { seen.insert($0).inserted }
    }

    public var count: Int { faceIDs.count }
    public var isEmpty: Bool { faceIDs.isEmpty }

    /// Whether any of these faces (a card's family or face) is in the tray.
    public func containsAny(_ ids: [String]) -> Bool {
        let set = Set(faceIDs)
        return ids.contains(where: set.contains)
    }

    public mutating func add(_ id: String) {
        if !faceIDs.contains(id) { faceIDs.append(id) }
    }

    public mutating func remove(_ ids: [String]) {
        let set = Set(ids)
        faceIDs.removeAll(where: set.contains)
    }

    /// A card's corner button: out if any of its faces is in, else its representative goes in.
    public mutating func toggle(cardFaceIDs: [String], representative: String) {
        if containsAny(cardFaceIDs) { remove(cardFaceIDs) } else { add(representative) }
    }

    /// Several cards at once (Return on a selection): if every card is in, take them all
    /// out; otherwise add the ones that are missing.
    public mutating func toggle(cards: [(faceIDs: [String], representative: String)]) {
        guard !cards.isEmpty else { return }
        if cards.allSatisfy({ containsAny($0.faceIDs) }) {
            cards.forEach { remove($0.faceIDs) }
        } else {
            for card in cards where !containsAny(card.faceIDs) { add(card.representative) }
        }
    }

    /// Swaps one face for another (compare's style picker), keeping its place.
    public mutating func replace(_ old: String, with new: String) {
        guard let index = faceIDs.firstIndex(of: old) else { return }
        if faceIDs.contains(new) { faceIDs.remove(at: index) } else { faceIDs[index] = new }
    }

    public mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { faceIDs[$0] }
        var rest = faceIDs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(destination - before, 0), rest.count))
        faceIDs = rest
    }

    public mutating func removeAll() { faceIDs = [] }

    /// Drops faces that no longer exist.
    public mutating func prune(existing: Set<String>) {
        faceIDs.removeAll { !existing.contains($0) }
    }
}
