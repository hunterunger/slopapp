import Foundation

/// How a browser handles profiles and private windows from the command line.
public enum BrowserFamily: Equatable, Sendable {
    /// Chromium-based. `dataDirectory` is relative to ~/Library/Application Support and holds
    /// "Local State" (the profile list). nil when the browser's profiles can't be targeted.
    case chromium(dataDirectory: String?)
    case firefox
    case safari
    /// A browser with no command-line profile or private support we know of.
    case other

    public var supportsProfiles: Bool {
        if case .chromium(let dir) = self { return dir != nil }
        return false
    }

    public var supportsPrivateWindow: Bool {
        switch self {
        case .chromium, .firefox: true
        case .safari, .other: false
        }
    }
}

/// A browser we recognise by bundle ID. Apps that merely register `https` (terminals, IDEs,
/// login helpers) aren't browsers; they're hidden unless the user adds them.
public struct KnownBrowser: Equatable, Sendable {
    public let bundleID: String
    public let family: BrowserFamily
}

public enum BrowserCatalog {
    /// Ordered roughly by popularity; the default list follows this order.
    public static let known: [KnownBrowser] = [
        KnownBrowser(bundleID: "com.apple.Safari", family: .safari),
        KnownBrowser(bundleID: "com.google.Chrome", family: .chromium(dataDirectory: "Google/Chrome")),
        KnownBrowser(bundleID: "org.mozilla.firefox", family: .firefox),
        KnownBrowser(bundleID: "company.thebrowser.Browser", family: .chromium(dataDirectory: nil)), // Arc
        KnownBrowser(bundleID: "com.microsoft.edgemac", family: .chromium(dataDirectory: "Microsoft Edge")),
        KnownBrowser(bundleID: "com.brave.Browser", family: .chromium(dataDirectory: "BraveSoftware/Brave-Browser")),
        KnownBrowser(bundleID: "company.thebrowser.dia", family: .chromium(dataDirectory: nil)),
        KnownBrowser(bundleID: "app.zen-browser.zen", family: .firefox),
        KnownBrowser(bundleID: "com.kagi.kagimacOS", family: .other), // Orion
        KnownBrowser(bundleID: "com.vivaldi.Vivaldi", family: .chromium(dataDirectory: "Vivaldi")),
        KnownBrowser(bundleID: "com.operasoftware.Opera", family: .chromium(dataDirectory: nil)),
        KnownBrowser(bundleID: "com.operasoftware.OperaGX", family: .chromium(dataDirectory: nil)),
        KnownBrowser(bundleID: "com.duckduckgo.macos.browser", family: .other),
        KnownBrowser(bundleID: "org.chromium.Chromium", family: .chromium(dataDirectory: "Chromium")),
        KnownBrowser(bundleID: "net.imput.helium", family: .chromium(dataDirectory: "net.imput.helium")),
        KnownBrowser(bundleID: "ai.perplexity.comet", family: .chromium(dataDirectory: nil)),
        KnownBrowser(bundleID: "com.google.Chrome.beta", family: .chromium(dataDirectory: "Google/Chrome Beta")),
        KnownBrowser(bundleID: "com.google.Chrome.dev", family: .chromium(dataDirectory: "Google/Chrome Dev")),
        KnownBrowser(bundleID: "com.google.Chrome.canary", family: .chromium(dataDirectory: "Google/Chrome Canary")),
        KnownBrowser(bundleID: "com.microsoft.edgemac.Beta", family: .chromium(dataDirectory: "Microsoft Edge Beta")),
        KnownBrowser(bundleID: "com.microsoft.edgemac.Dev", family: .chromium(dataDirectory: "Microsoft Edge Dev")),
        KnownBrowser(bundleID: "com.brave.Browser.beta", family: .chromium(dataDirectory: "BraveSoftware/Brave-Browser-Beta")),
        KnownBrowser(bundleID: "com.brave.Browser.nightly", family: .chromium(dataDirectory: "BraveSoftware/Brave-Browser-Nightly")),
        KnownBrowser(bundleID: "org.mozilla.firefoxdeveloperedition", family: .firefox),
        KnownBrowser(bundleID: "org.mozilla.nightly", family: .firefox),
        KnownBrowser(bundleID: "org.librewolf", family: .firefox),
        KnownBrowser(bundleID: "net.waterfox.waterfox", family: .firefox),
        KnownBrowser(bundleID: "org.torproject.torbrowser", family: .other),
        KnownBrowser(bundleID: "com.apple.SafariTechnologyPreview", family: .safari),
        KnownBrowser(bundleID: "org.mozilla.floorp", family: .firefox),
    ]

    public static func browser(for bundleID: String) -> KnownBrowser? {
        known.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    public static func family(for bundleID: String) -> BrowserFamily {
        browser(for: bundleID)?.family ?? .other
    }

    /// Other link routers. Handing links between routers invites loops, so they're never offered.
    public static let linkRouters: Set<String> = [
        "app.loshadki.openin", "app.loshadki.openin-setapp", "app.loshadki.openin4",
        "com.sindresorhus.velja", "se.johnste.finicky", "com.choosyosx.choosy",
        "com.browserosaurus", "com.danielkoster.browserfairy", "com.nicklockwood.bumpr",
        "com.zhuowei.Choosy", "app.slopapp.switchboard",
    ]

    public static func isLinkRouter(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return linkRouters.contains { $0.lowercased() == id } || id.hasPrefix("app.loshadki.openin")
    }

    public static func rank(of bundleID: String) -> Int {
        known.firstIndex { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame } ?? Int.max
    }
}

/// An app found on this Mac that can open web links.
public struct InstalledApp: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var path: String
    public var name: String

    public init(bundleID: String, path: String, name: String) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
    }
}

public enum BrowserDiscovery {
    /// Splits apps that can open https links into real browsers (known list, popularity
    /// order) and everything else. Excludes Switchboard itself, other link routers, and duplicate bundle IDs
    /// (keeps the copy in /Applications over others).
    public static func classify(_ apps: [InstalledApp], excluding ownBundleID: String?)
        -> (browsers: [InstalledApp], others: [InstalledApp])
    {
        var byID: [String: InstalledApp] = [:]
        for app in apps {
            let key = app.bundleID.lowercased()
            if let own = ownBundleID, key == own.lowercased() { continue }
            if BrowserCatalog.isLinkRouter(app.bundleID) { continue }
            if let existing = byID[key], preference(existing.path) <= preference(app.path) { continue }
            byID[key] = app
        }
        let unique = Array(byID.values)
        let browsers = unique.filter { BrowserCatalog.browser(for: $0.bundleID) != nil }
            .sorted { BrowserCatalog.rank(of: $0.bundleID) < BrowserCatalog.rank(of: $1.bundleID) }
        let others = unique.filter { BrowserCatalog.browser(for: $0.bundleID) == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (browsers, others)
    }

    /// Lower is better: /Applications, then ~/Applications, then anything else.
    static func preference(_ path: String) -> Int {
        if path.hasPrefix("/Applications/") { return 0 }
        if path.contains("/Applications/") { return 1 }
        return 2
    }

    /// Default targets for a fresh install: one per real browser.
    public static func defaultTargets(from browsers: [InstalledApp]) -> [Target] {
        browsers.map { Target(bundleID: $0.bundleID, appPath: $0.path, appName: $0.name) }
    }
}
