import Foundation

// How the library window slices the catalog: the category sections in the sidebar, the
// filter chips and sort on grid pages, the featured carousel on Discover, related apps on
// an app page, and the highlight bullets. Pure functions over `CatalogItem`s.

/// The task categories, in sidebar order. Feed categories we don't know yet go after these,
/// alphabetically; apps without one go under "Other".
public enum Categories {
    public static let known = ["Utilities", "Productivity", "Media", "Design", "Developer"]
    public static let other = "Other"

    public static func name(of item: CatalogItem) -> String {
        guard let category = item.app.category?.trimmingCharacters(in: .whitespaces), !category.isEmpty else { return other }
        return category
    }

    /// The categories that have at least one app, in sidebar order.
    public static func ordered(in items: [CatalogItem]) -> [String] {
        let present = Set(items.map(name(of:)))
        let extra = present.subtracting(known).subtracting([other]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return known.filter(present.contains) + extra + (present.contains(other) ? [other] : [])
    }

    /// One line under the category's title.
    public static func blurb(for category: String) -> String {
        switch category {
        case "Utilities": "Small tools that keep your Mac working the way you like."
        case "Productivity": "Get through the day's work with fewer clicks."
        case "Media": "Convert and shrink video, audio and images."
        case "Design": "Pick colors, measure the screen and make icons."
        case "Developer": "Helpers for writing and shipping code."
        default: "More free, open-source Mac apps."
        }
    }
}

/// The chips above a grid page.
public enum CatalogFilter: String, Sendable, CaseIterable, Identifiable {
    case all, available, comingSoon
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .available: "Available"
        case .comingSoon: "Coming Soon"
        }
    }

    public func includes(_ item: CatalogItem) -> Bool {
        switch self {
        case .all: true
        case .available: item.app.isInstallable || item.isInstalled
        case .comingSoon: !item.app.isInstallable && !item.isInstalled
        }
    }
}

/// The sort control at the top right of a grid page.
public enum CatalogSort: String, Sendable, CaseIterable, Identifiable {
    /// Apps you can get first, each group in catalog order (the feed's own ranking).
    case featured
    case name
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .featured: "Featured"
        case .name: "Name"
        }
    }
}

public enum Browse {
    /// A grid page: optionally one category, filtered and sorted.
    public static func apps(_ items: [CatalogItem], category: String? = nil, filter: CatalogFilter = .all,
                            sort: CatalogSort = .featured) -> [CatalogItem] {
        let picked = items.filter { item in
            (category == nil || Categories.name(of: item) == category) && filter.includes(item)
        }
        switch sort {
        case .featured:
            // Stable: available apps first, catalog order within each group.
            return picked.filter(CatalogFilter.available.includes) + picked.filter(CatalogFilter.comingSoon.includes)
        case .name:
            return picked.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        }
    }

    /// The Discover carousel: apps you can install now, ones not on this Mac yet first.
    public static func featured(_ items: [CatalogItem], limit: Int = 5) -> [CatalogItem] {
        let installable = items.filter(\.app.isInstallable)
        let fresh = installable.filter { !$0.isInstalled }
        let rest = installable.filter(\.isInstalled)
        return Array((fresh + rest).prefix(limit))
    }

    /// "More in <Category>" on an app page: same category, available first, never itself.
    public static func related(to item: CatalogItem, in items: [CatalogItem], limit: Int = 4) -> [CatalogItem] {
        let category = Categories.name(of: item)
        let others = items.filter { $0.id != item.id && Categories.name(of: $0) == category }
        return Array(apps(others).prefix(limit))
    }

    /// Short facts under an app's header, from the feed (we have no marketing copy per app).
    public static func highlights(for app: FeedApp, license: String) -> [String] {
        var lines: [String] = []
        if !app.replaces.isEmpty {
            lines.append("An open alternative to \(ListFormat.and(app.replaces))")
        }
        switch app.menuBarOnly {
        case true: lines.append("Lives in your menu bar")
        case false: lines.append("Opens in its own window")
        default: break
        }
        lines.append("Free and open source (\(license))")
        lines.append("No account, no tracking")
        return lines
    }
}

/// Apps the user starred, in the order they were added. Slugs only; apps that leave the
/// catalog are kept (they may come back) but not shown.
public struct FavoriteList: Sendable, Equatable {
    public private(set) var slugs: [String]

    public init(slugs: [String] = []) {
        var seen = Set<String>()
        self.slugs = slugs.filter { seen.insert($0).inserted }
    }

    public func contains(_ slug: String) -> Bool { slugs.contains(slug) }

    public mutating func toggle(_ slug: String) {
        if let index = slugs.firstIndex(of: slug) { slugs.remove(at: index) } else { slugs.append(slug) }
    }

    /// The starred apps that are in the catalog, in the order they were starred.
    public func items(in catalog: [CatalogItem]) -> [CatalogItem] {
        let bySlug = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return slugs.compactMap { bySlug[$0] }
    }

    /// What "Install All" would install: starred, installable, not on this Mac yet.
    public func installable(in catalog: [CatalogItem]) -> [CatalogItem] {
        items(in: catalog).filter { $0.state == .notInstalled }
    }
}

/// Back and Forward through app pages (like a browser): Back pops a page and remembers it,
/// Forward pushes it again, opening a different page forgets what was ahead.
public struct PageHistory: Sendable, Equatable {
    public private(set) var path: [String] = []
    public private(set) var ahead: [String] = []

    public init() {}

    public var canGoBack: Bool { !path.isEmpty }
    public var canGoForward: Bool { !ahead.isEmpty }

    public mutating func open(_ slug: String) {
        guard path.last != slug else { return }
        path.append(slug)
        if ahead.last == slug { ahead.removeLast() } else { ahead = [] }
    }

    public mutating func back() {
        guard let last = path.popLast() else { return }
        ahead.append(last)
    }

    public mutating func forward() {
        guard let next = ahead.popLast() else { return }
        path.append(next)
    }

    /// The navigation stack changed the path itself (its own back button, a swipe).
    public mutating func sync(_ newPath: [String]) {
        guard newPath != path else { return }
        if newPath.count < path.count, Array(path.prefix(newPath.count)) == newPath {
            ahead.append(contentsOf: path.suffix(from: newPath.count).reversed())
        } else {
            ahead = []
        }
        path = newPath
    }

    /// A new sidebar section: no pages, nothing ahead.
    public mutating func reset() {
        path = []
        ahead = []
    }
}
