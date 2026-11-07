import Foundation

/// One row of the library window's sidebar. Laid out like the original's: the main pages,
/// then All Apps with its categories under it, then Updates as the last row.
public enum SidebarItem: Hashable, Identifiable, Sendable {
    case discover, installed, updates, favorites, allApps
    case category(String)

    /// The pages above All Apps, in sidebar order.
    public static let top: [SidebarItem] = [.discover, .installed, .favorites]

    /// Every row, top to bottom, for the categories that have apps.
    public static func order(categories: [String]) -> [SidebarItem] {
        top + [.allApps] + categories.map(SidebarItem.category) + [.updates]
    }

    /// The row an arrow key lands on: one up or down, stopping at the ends. With nothing
    /// selected, down starts at the top and up at the bottom.
    public static func moved(from current: SidebarItem?, by step: Int, categories: [String]) -> SidebarItem? {
        let rows = order(categories: categories)
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(of: current) else {
            return step >= 0 ? rows.first : rows.last
        }
        return rows[min(max(index + step, 0), rows.count - 1)]
    }

    public var id: String {
        switch self {
        case .category(let name): "category:\(name)"
        default: title
        }
    }

    public var title: String {
        switch self {
        case .discover: "Discover"
        case .installed: "Installed"
        case .updates: "Updates"
        case .favorites: "Favorites"
        case .allApps: "All Apps"
        case .category(let name): name
        }
    }

    /// A filled glyph (SF Symbol name), or nil for categories (they're text only).
    public var symbol: String? {
        switch self {
        case .discover: "star.fill"
        case .installed: "checkmark.circle.fill"
        case .updates: "arrow.down.circle.fill"
        case .favorites: "heart.fill"
        case .allApps: "square.grid.2x2.fill"
        case .category: nil
        }
    }

    /// Indented under All Apps.
    public var isCategory: Bool {
        if case .category = self { return true }
        return false
    }
}

/// The status item at the right of the content header: what the update check knows.
public struct HeaderStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case checking, updates, upToDate, offline, unknown }

    public let kind: Kind
    public let title: String
    /// SF Symbol name; nil while checking (a spinner shows instead).
    public let symbol: String?

    public init(updates: Int, isChecking: Bool, hasError: Bool, hasCatalog: Bool) {
        if isChecking {
            (kind, title, symbol) = (.checking, "Checking…", nil)
        } else if updates > 0 {
            (kind, title, symbol) = (.updates, updates == 1 ? "1 Update" : "\(updates) Updates", "arrow.down.circle.fill")
        } else if hasError {
            (kind, title, symbol) = (.offline, "Can't Check", "wifi.exclamationmark")
        } else if hasCatalog {
            (kind, title, symbol) = (.upToDate, "Up to Date", "checkmark")
        } else {
            (kind, title, symbol) = (.unknown, "Not Checked", "clock")
        }
    }
}
