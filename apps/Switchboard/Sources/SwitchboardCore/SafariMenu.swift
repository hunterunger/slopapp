import Foundation

/// A menu item as Accessibility reports it, without the live element. The app reads Safari's
/// File menu into these; the matching below is pure, so it's tested with made-up menus.
public struct MenuItemSnapshot: Equatable, Sendable {
    public var title: String
    /// The shortcut's key ("N"), if any.
    public var commandKey: String?
    /// Accessibility's modifier mask: 0 = ⌘ only, +1 ⇧, +2 ⌥, +4 ⌃, +8 no ⌘.
    public var modifiers: Int
    public var isEnabled: Bool
    public var children: [MenuItemSnapshot]

    public init(_ title: String, key: String? = nil, modifiers: Int = 0, isEnabled: Bool = true, children: [MenuItemSnapshot] = []) {
        self.title = title
        self.commandKey = key
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.children = children
    }

    public static let shiftMask = 1
}

/// Which kind of Safari window a link needs. Safari has no API for either: Switchboard picks
/// the item from Safari's File menu (with Accessibility), then hands Safari the link, which
/// opens in the front window, the new one.
public enum SafariWindowRequest: Equatable, Sendable {
    case privateWindow
    /// A profile, by the name Safari shows ("Work").
    case profile(String)
}

public enum SafariMenu {
    /// Indexes into the File menu's items (and a submenu's) of the item to press, or nil.
    ///
    /// - Private window: the item whose shortcut is ⇧⌘N. Shortcuts don't depend on the
    ///   language, titles do.
    /// - Profile: with profiles, File ▸ New Window is a submenu with one "New <name> Window"
    ///   item per profile. The item whose title, minus what all of them share, is the name.
    public static func path(for request: SafariWindowRequest, inFileMenu items: [MenuItemSnapshot]) -> [Int]? {
        switch request {
        case .privateWindow:
            return firstPath(in: items) { item in
                item.commandKey?.uppercased() == "N" && item.modifiers == MenuItemSnapshot.shiftMask && item.isEnabled
            }
        case .profile(let name):
            let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !wanted.isEmpty, let (submenuIndex, submenu) = profileSubmenu(in: items) else { return nil }
            let names = profileNames(in: submenu)
            if let exact = names.firstIndex(where: { $0?.lowercased() == wanted }) {
                return [submenuIndex, exact]
            }
            // A name Safari shortened or decorated: a whole-word match in the title.
            if let loose = submenu.indices.first(where: { titleContainsWord(submenu[$0].title, wanted) && submenu[$0].isEnabled }) {
                return [submenuIndex, loose]
            }
            return nil
        }
    }

    /// The profile names in Safari's File ▸ New Window submenu, for "Find Profiles". Empty
    /// when Safari has no profiles (New Window is a plain item then).
    public static func profileNames(inFileMenu items: [MenuItemSnapshot]) -> [String] {
        guard let (_, submenu) = profileSubmenu(in: items) else { return [] }
        return profileNames(in: submenu).compactMap { $0 }
    }

    /// The submenu of File that holds the ⌘N "new window" item: New Window ▸ (profiles).
    private static func profileSubmenu(in items: [MenuItemSnapshot]) -> (Int, [MenuItemSnapshot])? {
        for (index, item) in items.enumerated() where item.children.count >= 2 {
            let hasNewWindow = item.children.contains { $0.commandKey?.uppercased() == "N" && $0.modifiers == 0 }
            if hasNewWindow { return (index, item.children) }
        }
        return nil
    }

    /// Each item's title with the words every titled item shares at the start and end taken
    /// off ("New Work Window" → "Work"). nil for separators and untitled items.
    static func profileNames(in submenu: [MenuItemSnapshot]) -> [String?] {
        let titled = submenu.map { $0.title.trimmingCharacters(in: .whitespaces) }
        let words = titled.filter { !$0.isEmpty }.map { $0.split(separator: " ").map(String.init) }
        guard words.count >= 2 else {
            return titled.map { $0.isEmpty ? nil : $0 }
        }
        let shortest = words.map(\.count).min() ?? 0
        var prefix = 0
        while prefix < shortest - 1, words.allSatisfy({ $0[prefix] == words[0][prefix] }) { prefix += 1 }
        var suffix = 0
        while suffix < shortest - 1 - prefix,
              words.allSatisfy({ $0[$0.count - 1 - suffix] == words[0][words[0].count - 1 - suffix] }) { suffix += 1 }
        return titled.map { title in
            guard !title.isEmpty else { return nil }
            let parts = title.split(separator: " ").map(String.init)
            guard parts.count > prefix + suffix else { return title }
            let name = parts[prefix..<(parts.count - suffix)].joined(separator: " ")
            return name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'‘’«»„"))
        }
    }

    private static func titleContainsWord(_ title: String, _ word: String) -> Bool {
        let tokens = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let wanted = word.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !wanted.isEmpty, tokens.count >= wanted.count else { return false }
        for start in 0...(tokens.count - wanted.count) where Array(tokens[start..<(start + wanted.count)]) == wanted {
            return true
        }
        return false
    }

    private static func firstPath(in items: [MenuItemSnapshot], where match: (MenuItemSnapshot) -> Bool) -> [Int]? {
        for (index, item) in items.enumerated() {
            if match(item) { return [index] }
            if let inner = firstPath(in: item.children, where: match) { return [index] + inner }
        }
        return nil
    }
}
