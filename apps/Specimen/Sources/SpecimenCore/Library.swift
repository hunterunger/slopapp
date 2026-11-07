import Foundation

/// A family of faces, grouped by `kCTFontFamilyNameAttribute`.
public struct FontFamily: Hashable, Sendable, Identifiable {
    public var name: String
    public var displayName: String
    /// Sorted by weight, then width, then upright before italic.
    public var faces: [FontFace]
    public var category: FontCategory

    public var id: String { name }

    public init(name: String, faces: [FontFace], categoryOverride: FontCategory? = nil) {
        self.name = name
        self.faces = faces.sorted(by: FontFamily.styleOrder)
        self.displayName = faces.first?.displayFamilyName ?? name
        self.category = categoryOverride ?? FontFamily.representative(of: self.faces)?.category ?? .other
    }

    public var representative: FontFace? { FontFamily.representative(of: faces) }
    public var state: ActivationState { ActivationState(faces: faces) }
    public var isVariable: Bool { faces.contains(where: \.isVariable) }
    /// Every face ships with macOS.
    public var isSystem: Bool { faces.allSatisfy { $0.location == .system } }
    /// The newest file date among its faces ("date added" for sorting).
    public var dateAdded: Date? { faces.compactMap(\.fileModified).max() }
    /// The first foundry any face names.
    public var foundry: String? { representative?.foundry ?? faces.lazy.compactMap(\.foundry).first }
    /// CSS weights from lightest to heaviest ("300–700" in the list).
    public var weightRange: ClosedRange<Int>? {
        let weights = faces.map(\.cssWeight)
        guard let low = weights.min(), let high = weights.max() else { return nil }
        return low...high
    }

    /// The face closest to Regular (ties: alphabetical style name).
    public static func representative(of faces: [FontFace]) -> FontFace? {
        faces.min { a, b in
            let da = a.distanceFromRegular, db = b.distanceFromRegular
            if da != db { return da < db }
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            return a.styleName.localizedStandardCompare(b.styleName) == .orderedAscending
        }
    }

    static func styleOrder(_ a: FontFace, _ b: FontFace) -> Bool {
        if a.weight != b.weight { return a.weight < b.weight }
        if a.width != b.width { return a.width < b.width }
        if a.isItalic != b.isItalic { return !a.isItalic }
        return a.styleName.localizedStandardCompare(b.styleName) == .orderedAscending
    }

    /// Groups faces into families, sorted by display name.
    public static func group(_ faces: [FontFace], overrides: [String: FontCategory] = [:]) -> [FontFamily] {
        Dictionary(grouping: faces, by: \.familyName)
            .map { FontFamily(name: $0.key, faces: $0.value, categoryOverride: overrides[$0.key]) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

/// What the sidebar can show.
public enum SidebarItem: Hashable, Codable, Sendable {
    case all, userFonts, systemFonts, favorites, active, inactive, variable
    case category(FontCategory)
    case tag(String)
    case smart(UUID)

    public static var libraryItems: [SidebarItem] { [.all, .userFonts, .systemFonts, .active, .inactive, .favorites, .variable] }
    public static var categoryItems: [SidebarItem] { FontCategory.allCases.map { .category($0) } }

    /// The built-in title. Tags show their name; smart collections are named by the app.
    public var title: String {
        switch self {
        case .all: "All Fonts"
        case .userFonts: "Your Fonts"
        case .systemFonts: "macOS Fonts"
        case .favorites: "Favorites"
        case .active: "Active"
        case .inactive: "Inactive"
        case .variable: "Variable"
        case .category(let category): category.title
        case .tag(let name): name
        case .smart: "Smart Collection"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .userFonts: "person"
        case .systemFonts: "apple.logo"
        case .favorites: "star"
        case .active: "checkmark.circle"
        case .inactive: "circle.slash"
        case .variable: "slider.horizontal.3"
        case .category(let category): category.systemImage
        case .tag: "tag"
        case .smart: "gearshape"
        }
    }

    /// A stable string for UserDefaults.
    public var storageKey: String {
        switch self {
        case .category(let category): "category.\(category.rawValue)"
        case .tag(let name): "tag.\(name)"
        case .smart(let id): "smart.\(id.uuidString)"
        default: title
        }
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("category."), let category = FontCategory(rawValue: String(storageKey.dropFirst(9))) {
            self = .category(category)
            return
        }
        if storageKey.hasPrefix("tag."), storageKey.count > 4 {
            self = .tag(String(storageKey.dropFirst(4)))
            return
        }
        if storageKey.hasPrefix("smart."), let id = UUID(uuidString: String(storageKey.dropFirst(6))) {
            self = .smart(id)
            return
        }
        guard let item = SidebarItem.libraryItems.first(where: { $0.title == storageKey }) else { return nil }
        self = item
    }
}

/// How the grid and list are ordered.
public struct LibrarySort: Codable, Hashable, Sendable {
    public enum Key: String, Codable, CaseIterable, Sendable, Identifiable {
        case name, recentlyAdded, styles, category, foundry

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .name: "Name"
            case .recentlyAdded: "Date Added"
            case .styles: "Number of Styles"
            case .category: "Category"
            case .foundry: "Foundry"
            }
        }

        /// The natural first direction: newest and biggest first, names A to Z.
        public var defaultAscending: Bool { self != .recentlyAdded && self != .styles }
    }

    public var key: Key
    public var ascending: Bool

    public init(key: Key = .name, ascending: Bool? = nil) {
        self.key = key
        self.ascending = ascending ?? key.defaultAscending
    }

    /// Choosing the current key again flips the direction (like a column header).
    public func choosing(_ newKey: Key) -> LibrarySort {
        newKey == key ? LibrarySort(key: key, ascending: !ascending) : LibrarySort(key: newKey)
    }

    public var storageKey: String { "\(key.rawValue).\(ascending ? "up" : "down")" }

    public init?(storageKey: String) {
        let parts = storageKey.split(separator: ".")
        guard parts.count == 2, let key = Key(rawValue: String(parts[0])) else { return nil }
        self.init(key: key, ascending: parts[1] == "up")
    }

    /// Sorts families. Ties fall back to the name, always A to Z.
    public func sorted(_ families: [FontFamily]) -> [FontFamily] {
        if key == .name { return ascending ? families : families.reversed() }
        func byName(_ a: FontFamily, _ b: FontFamily) -> Bool {
            a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        func compare(_ a: FontFamily, _ b: FontFamily) -> ComparisonResult {
            switch key {
            case .name: return a.displayName.localizedStandardCompare(b.displayName)
            case .recentlyAdded:
                let da = a.dateAdded ?? .distantPast, db = b.dateAdded ?? .distantPast
                return da == db ? .orderedSame : (da < db ? .orderedAscending : .orderedDescending)
            case .styles:
                return a.faces.count == b.faces.count ? .orderedSame : (a.faces.count < b.faces.count ? .orderedAscending : .orderedDescending)
            case .category:
                let ia = FontCategory.allCases.firstIndex(of: a.category) ?? 0, ib = FontCategory.allCases.firstIndex(of: b.category) ?? 0
                return ia == ib ? .orderedSame : (ia < ib ? .orderedAscending : .orderedDescending)
            case .foundry:
                // Fonts without a foundry go last either way.
                switch (a.foundry, b.foundry) {
                case (nil, nil): return .orderedSame
                case (nil, _): return ascending ? .orderedDescending : .orderedAscending
                case (_, nil): return ascending ? .orderedAscending : .orderedDescending
                case let (fa?, fb?): return fa.localizedStandardCompare(fb)
                }
            }
        }
        return families.sorted { a, b in
            let result = compare(a, b)
            if result == .orderedSame { return byName(a, b) }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

/// One card in the grid: a family (or a single face when styles aren't grouped).
public struct GridEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var family: FontFamily
    /// The family's faces that pass the current filters (just one when ungrouped).
    public var faces: [FontFace]
    public var representative: FontFace

    public var title: String {
        faces.count == 1 && family.faces.count > 1 && id.hasPrefix("face:")
            ? "\(family.displayName) \(representative.styleName)" : family.displayName
    }
}

/// The filters in effect: one sidebar item plus search (and, optionally, coverage).
public struct LibraryQuery: Sendable, Equatable {
    public var sidebar: SidebarItem
    public var search: String
    public var showSystemFonts: Bool
    public var groupByFamily: Bool
    public var favorites: Set<String>
    public var tags: TagLibrary
    public var smartCollections: [SmartCollection]
    public var sort: LibrarySort
    /// Faces hidden because they can't show the preview text ("hide fonts that can't show this text").
    public var hiddenFaceIDs: Set<String>

    public init(sidebar: SidebarItem = .all, search: String = "", showSystemFonts: Bool = true,
                groupByFamily: Bool = true, favorites: Set<String> = [], tags: TagLibrary = TagLibrary(),
                smartCollections: [SmartCollection] = [], sort: LibrarySort = LibrarySort(),
                hiddenFaceIDs: Set<String> = []) {
        self.sidebar = sidebar
        self.search = search
        self.showSystemFonts = showSystemFonts
        self.groupByFamily = groupByFamily
        self.favorites = favorites
        self.tags = tags
        self.smartCollections = smartCollections
        self.sort = sort
        self.hiddenFaceIDs = hiddenFaceIDs
    }
}

public enum LibraryFilter {
    /// The cards to show for `query`, in the query's sort order.
    public static func items(in families: [FontFamily], query: LibraryQuery) -> [GridEntry] {
        let tokens = searchTokens(query.search)
        let smart: SmartCollection? = {
            if case .smart(let id) = query.sidebar { return query.smartCollections.first { $0.id == id } }
            return nil
        }()
        if case .smart = query.sidebar, smart == nil { return [] }
        let smartTokens = smart.map { searchTokens($0.rules.nameContains) } ?? []
        let tagged: Set<String>? = {
            if case .tag(let name) = query.sidebar { return query.tags.families(in: name) }
            return nil
        }()
        let smartTagged = smart?.rules.tag.map { query.tags.families(in: $0) }
        var result: [GridEntry] = []
        for family in query.sort.sorted(families) {
            if case .favorites = query.sidebar, !query.favorites.contains(family.name) { continue }
            if case .category(let category) = query.sidebar, family.category != category { continue }
            if let tagged, !tagged.contains(family.name) { continue }
            if let smart, !smartFamilyPasses(family, rules: smart.rules, query: query, tagged: smartTagged) { continue }
            let familyText = family.name + " " + family.displayName
            let familyMatches = tokens.isEmpty || matches(tokens, in: familyText)
            let familySmartMatches = smartTokens.isEmpty || matches(smartTokens, in: familyText)
            let faces = family.faces.filter { face in
                if !query.showSystemFonts && face.location == .system { return false }
                if query.hiddenFaceIDs.contains(face.id) { return false }
                switch query.sidebar {
                case .active where !face.isEnabled: return false
                case .inactive where face.isEnabled: return false
                case .variable where !face.isVariable: return false
                case .userFonts where face.location == .system: return false
                case .systemFonts where face.location != .system: return false
                default: break
                }
                if let smart {
                    guard smartFacePasses(face, rules: smart.rules) else { return false }
                    if !familySmartMatches, !matches(smartTokens, in: faceHaystack(face, family: family)) { return false }
                }
                return familyMatches || matches(tokens, in: faceHaystack(face, family: family))
            }
            guard !faces.isEmpty else { continue }
            if query.groupByFamily {
                let representative = FontFamily.representative(of: faces) ?? faces[0]
                result.append(GridEntry(id: "family:\(family.name)", family: family, faces: faces, representative: representative))
            } else {
                for face in faces {
                    result.append(GridEntry(id: "face:\(face.id)", family: family, faces: [face], representative: face))
                }
            }
        }
        return result
    }

    static func smartFamilyPasses(_ family: FontFamily, rules: SmartRules, query: LibraryQuery, tagged: Set<String>?) -> Bool {
        if rules.favoritesOnly, !query.favorites.contains(family.name) { return false }
        if let category = rules.category, family.category != category { return false }
        if let tagged, !tagged.contains(family.name) { return false }
        if family.faces.count < rules.minimumStyles { return false }
        return true
    }

    static func smartFacePasses(_ face: FontFace, rules: SmartRules) -> Bool {
        switch rules.state {
        case .any: break
        case .active: if !face.isEnabled { return false }
        case .inactive: if face.isEnabled { return false }
        }
        switch rules.source {
        case .any: break
        case .yours: if face.location == .system { return false }
        case .macOS: if face.location != .system { return false }
        }
        if rules.variableOnly, !face.isVariable { return false }
        return true
    }

    /// The sidebar items that get a count.
    public static func countedItems(tags: TagLibrary, smartCollections: [SmartCollection]) -> [SidebarItem] {
        SidebarItem.libraryItems + SidebarItem.categoryItems + tags.names.map { .tag($0) } + smartCollections.map { .smart($0.id) }
    }

    /// Family counts per sidebar item (ignoring search and coverage), so the sidebar reads
    /// the same while you type.
    public static func counts(in families: [FontFamily], query: LibraryQuery) -> [SidebarItem: Int] {
        var base = query
        base.search = ""
        base.groupByFamily = true
        base.hiddenFaceIDs = []
        base.sort = LibrarySort()
        var counts: [SidebarItem: Int] = [:]
        for item in countedItems(tags: query.tags, smartCollections: query.smartCollections) {
            base.sidebar = item
            counts[item] = items(in: families, query: base).count
        }
        return counts
    }

    static func faceHaystack(_ face: FontFace, family: FontFamily) -> String {
        "\(family.name) \(family.displayName) \(face.styleName) \(face.postScriptName) \(face.fullName)"
    }

    /// Case-, diacritic- and width-insensitive words.
    public static func searchTokens(_ text: String) -> [String] {
        fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(_ tokens: [String], in haystack: String) -> Bool {
        let folded = fold(haystack)
        return tokens.allSatisfy { folded.contains($0) }
    }

    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Finder-style type-to-jump: the first item whose title starts with `prefix`, otherwise
    /// the first one that sorts after it.
    public static func typeAheadIndex(_ prefix: String, in titles: [String]) -> Int? {
        let needle = fold(prefix)
        guard !needle.isEmpty, !titles.isEmpty else { return nil }
        if let exact = titles.firstIndex(where: { fold($0).hasPrefix(needle) }) { return exact }
        return titles.firstIndex { fold($0).localizedStandardCompare(needle) == .orderedDescending } ?? titles.count - 1
    }
}
