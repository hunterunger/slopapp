import Foundation

/// An app whose copies Clips never records.
public struct IgnoredApp: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Password managers and keychains, ignored out of the box. Most also mark their copies
    /// as concealed; this catches the ones that don't.
    public static let presets: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords"),
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleID: "com.1password.1password", name: "1Password"),
        IgnoredApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        IgnoredApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        IgnoredApp(bundleID: "org.keepassxc.keepassxc", name: "KeePassXC"),
        IgnoredApp(bundleID: "com.dashlane.dashlanephonefinal", name: "Dashlane"),
        IgnoredApp(bundleID: "in.sinew.Enpass-Desktop", name: "Enpass"),
        IgnoredApp(bundleID: "com.lastpass.LastPass", name: "LastPass"),
        IgnoredApp(bundleID: "me.proton.pass.electron", name: "Proton Pass"),
        IgnoredApp(bundleID: "com.markmcguill.strongbox.mac", name: "Strongbox"),
    ]

    /// Encodes a list for UserDefaults.
    public static func encode(_ apps: [IgnoredApp]) -> Data {
        (try? JSONEncoder().encode(apps)) ?? Data()
    }

    /// Decodes a stored list, falling back to the presets when nothing valid is stored.
    public static func decode(_ data: Data?) -> [IgnoredApp] {
        guard let data, let apps = try? JSONDecoder().decode([IgnoredApp].self, from: data) else { return presets }
        return apps
    }
}

/// Other clipboard managers and the shortcut each uses out of the box, so Clips can warn
/// when its shortcut would collide with one that's running. macOS doesn't report hotkey
/// collisions between apps, so this is the best signal available.
public struct KnownShortcutOwner: Sendable, Equatable {
    public var bundleIDPrefix: String
    public var name: String
    /// Key character and modifier symbols, e.g. "⇧⌘V".
    public var shortcut: String

    public static let all: [KnownShortcutOwner] = [
        KnownShortcutOwner(bundleIDPrefix: "com.wiheads.paste", name: "Paste", shortcut: "⇧⌘V"),
        KnownShortcutOwner(bundleIDPrefix: "org.p0deje.Maccy", name: "Maccy", shortcut: "⇧⌘C"),
        KnownShortcutOwner(bundleIDPrefix: "com.runningwithcrayons.Alfred", name: "Alfred", shortcut: "⌥⌘C"),
    ]

    /// Running apps (by bundle id) that use `shortcut` by default.
    public static func conflicts(for shortcut: String, runningBundleIDs: [String]) -> [KnownShortcutOwner] {
        all.filter { owner in
            owner.shortcut == shortcut && runningBundleIDs.contains { $0.hasPrefix(owner.bundleIDPrefix) }
        }
    }

    /// Running apps that also record the clipboard (whatever their shortcut).
    public static func running(in runningBundleIDs: [String]) -> [KnownShortcutOwner] {
        all.filter { owner in runningBundleIDs.contains { $0.hasPrefix(owner.bundleIDPrefix) } }
    }
}

/// Shortcuts other apps commonly use that a global hotkey would steal.
public enum ShortcutAdvice {
    /// A short warning for well-known app shortcuts, or nil.
    public static func appConflict(for shortcut: String) -> String? {
        switch shortcut {
        case "⌘V", "⌘C", "⌘X", "⌘Z", "⌘A": "This is a standard editing shortcut. Every app would lose it."
        case "⇧⌘V": "Many apps use ⇧⌘V for Paste and Match Style."
        case "⌥⇧⌘V": "Many apps use ⌥⇧⌘V for Paste and Match Style."
        case "⌥⌘V": "Finder uses ⌥⌘V to move copied files."
        default: nil
        }
    }
}
