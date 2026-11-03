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
    case all, favorites, active, inactive, variable
    case category(FontCategory)

    public static var libraryItems: [SidebarItem] { [.all, .favorites, .active, .inactive, .variable] }
    public static var categoryItems: [SidebarItem] { FontCategory.allCases.map { .category($0) } }

    public var title: String {
        switch self {
        case .all: "All Fonts"
        case .favorites: "Favorites"
        case .active: "Active"
        case .inactive: "Inactive"
        case .variable: "Variable"
        case .category(let category): category.title
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star"
        case .active: "checkmark.circle"
        case .inactive: "circle.slash"
        case .variable: "slider.horizontal.3"
        case .category(let category): category.systemImage
        }
    }

    /// A stable string for UserDefaults.
    public var storageKey: String {
        switch self {
        case .category(let category): "category.\(category.rawValue)"
        default: title
        }
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("category."), let category = FontCategory(rawValue: String(storageKey.dropFirst(9))) {
            self = .category(category)
            return
        }
        guard let item = SidebarItem.libraryItems.first(where: { $0.title == storageKey }) else { return nil }
        self = item
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

/// The filters in effect. One sidebar item plus search, nothing else to learn.
public struct LibraryQuery: Sendable, Equatable {
    public var sidebar: SidebarItem
    public var search: String
    public var showSystemFonts: Bool
    public var groupByFamily: Bool
    public var favorites: Set<String>

    public init(sidebar: SidebarItem = .all, search: String = "", showSystemFonts: Bool = true,
                groupByFamily: Bool = true, favorites: Set<String> = []) {
        self.sidebar = sidebar
        self.search = search
        self.showSystemFonts = showSystemFonts
        self.groupByFamily = groupByFamily
        self.favorites = favorites
    }
}

public enum LibraryFilter {
    /// The cards to show for `query`, in family order.
    public static func items(in families: [FontFamily], query: LibraryQuery) -> [GridEntry] {
        let tokens = searchTokens(query.search)
        var result: [GridEntry] = []
        for family in families {
            if case .favorites = query.sidebar, !query.favorites.contains(family.name) { continue }
            if case .category(let category) = query.sidebar, family.category != category { continue }
            let familyMatches = tokens.isEmpty || matches(tokens, in: family.name + " " + family.displayName)
            let faces = family.faces.filter { face in
                if !query.showSystemFonts && face.location == .system { return false }
                switch query.sidebar {
                case .active where !face.isEnabled: return false
                case .inactive where face.isEnabled: return false
                case .variable where !face.isVariable: return false
                default: break
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

    /// Family counts per sidebar item (ignoring search), so the sidebar reads the same while you type.
    public static func counts(in families: [FontFamily], query: LibraryQuery) -> [SidebarItem: Int] {
        var base = query
        base.search = ""
        base.groupByFamily = true
        var counts: [SidebarItem: Int] = [:]
        for item in SidebarItem.libraryItems + SidebarItem.categoryItems {
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
