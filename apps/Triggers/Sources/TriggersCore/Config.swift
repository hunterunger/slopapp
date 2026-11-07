import Foundation

/// Where a binding applies.
public enum Scope: Hashable, Codable, Sendable {
    case allApps
    /// The built-in group of web browsers.
    case browsers
    case app(bundleID: String)

    public var bundleID: String? {
        if case .app(let id) = self { return id }
        return nil
    }
}

/// One input mapped to one action, in one scope.
public struct TriggerBinding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var trigger: Trigger
    public var action: Action
    public var scope: Scope
    public var isEnabled: Bool

    public init(id: UUID = UUID(), trigger: Trigger, action: Action, scope: Scope, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.scope = scope
        self.isEnabled = isEnabled
    }
}

/// An app in the editor's sidebar.
public struct AppEntry: Identifiable, Hashable, Codable, Sendable {
    public var bundleID: String
    public var name: String
    /// "Use all-apps triggers here". Off for games, remote desktops and VMs.
    public var usesAllAppsTriggers: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, usesAllAppsTriggers: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.usesAllAppsTriggers = usesAllAppsTriggers
    }
}

/// Everything Triggers stores. Plain JSON with a schema version.
public struct Config: Hashable, Codable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    public var bindings: [TriggerBinding]
    public var apps: [AppEntry]

    public init(bindings: [TriggerBinding] = [], apps: [AppEntry] = []) {
        self.schemaVersion = Config.currentSchema
        self.bindings = bindings
        self.apps = apps
    }

    public func app(_ bundleID: String) -> AppEntry? { apps.first { $0.bundleID == bundleID } }

    /// Adds the app to the sidebar if it isn't there yet.
    public mutating func addApp(bundleID: String, name: String) {
        guard app(bundleID) == nil else { return }
        apps.append(AppEntry(bundleID: bundleID, name: name))
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether all-apps (and Browsers) bindings apply in this app.
    public func usesAllAppsTriggers(in bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return app(bundleID)?.usesAllAppsTriggers ?? true
    }

    public mutating func setUsesAllAppsTriggers(_ value: Bool, in bundleID: String, name: String) {
        if let index = apps.firstIndex(where: { $0.bundleID == bundleID }) {
            apps[index].usesAllAppsTriggers = value
        } else {
            addApp(bundleID: bundleID, name: name)
            setUsesAllAppsTriggers(value, in: bundleID, name: name)
        }
    }

    public func bindings(in scope: Scope) -> [TriggerBinding] { bindings.filter { $0.scope == scope } }

    public var enabledBindings: [TriggerBinding] { bindings.filter(\.isEnabled) }
}

/// The built-in Browsers group.
public enum BrowserGroup {
    public static let bundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.kagi.kagimacOS", "app.zen-browser.zen", "com.duckduckgo.macos.browser",
        "org.chromium.Chromium", "com.openai.atlas", "net.imput.helium",
    ]

    public static func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
