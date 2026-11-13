import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

@Suite("Browser discovery")
struct DiscoveryTests {
    let apps = [
        InstalledApp(bundleID: "com.google.Chrome", path: "/Applications/Google Chrome.app", name: "Google Chrome"),
        InstalledApp(bundleID: "com.apple.Safari", path: "/Applications/Safari.app", name: "Safari"),
        InstalledApp(bundleID: "com.mitchellh.ghostty", path: "/Applications/Ghostty.app", name: "Ghostty"),
        InstalledApp(bundleID: "app.slopapp.switchboard", path: "/Applications/Switchboard.app", name: "Switchboard"),
        InstalledApp(bundleID: "app.loshadki.openin-setapp", path: "/Applications/Setapp/OpenIn.app", name: "OpenIn"),
        InstalledApp(bundleID: "com.google.Chrome", path: "/Users/me/Downloads/Google Chrome.app", name: "Google Chrome"),
    ]

    @Test("Only known browsers count; ourselves excluded; duplicates collapse to /Applications")
    func classify() {
        let (browsers, others) = BrowserDiscovery.classify(apps, excluding: "app.slopapp.switchboard")
        #expect(browsers.map(\.bundleID) == ["com.apple.Safari", "com.google.Chrome"])
        #expect(browsers[1].path == "/Applications/Google Chrome.app")
        #expect(others.map(\.name) == ["Ghostty"])  // OpenIn is a link router: never offered
    }

    @Test("Duplicate order doesn't matter")
    func duplicateOrder() {
        let (browsers, _) = BrowserDiscovery.classify(apps.reversed(), excluding: nil)
        #expect(browsers.first { $0.bundleID == "com.google.Chrome" }?.path == "/Applications/Google Chrome.app")
    }

    @Test("Default targets mirror the browsers")
    func defaults() {
        let (browsers, _) = BrowserDiscovery.classify(apps, excluding: nil)
        let targets = BrowserDiscovery.defaultTargets(from: browsers)
        #expect(targets.map(\.appName) == ["Safari", "Google Chrome"])
        #expect(targets.allSatisfy { !$0.isHidden && $0.profile == nil })
    }

    @Test("Families")
    func families() {
        #expect(BrowserCatalog.family(for: "com.google.chrome") == .chromium(dataDirectory: "Google/Chrome"))
        #expect(BrowserCatalog.family(for: "org.mozilla.firefox") == .firefox)
        #expect(BrowserCatalog.family(for: "com.example.unknown") == .other)
        #expect(BrowserCatalog.family(for: "com.google.Chrome").supportsProfiles)
        #expect(!BrowserCatalog.family(for: "company.thebrowser.Browser").supportsProfiles)
        // Safari: private windows and profiles through its File menu (Accessibility).
        #expect(BrowserCatalog.family(for: "com.apple.Safari").supportsPrivateWindow)
        #expect(BrowserCatalog.family(for: "com.apple.Safari").windowsNeedAccessibility)
        #expect(!BrowserCatalog.family(for: "com.google.Chrome").windowsNeedAccessibility)
    }

    @Test("Link routers are recognised")
    func routers() {
        #expect(BrowserCatalog.isLinkRouter("app.loshadki.openin-setapp"))
        #expect(BrowserCatalog.isLinkRouter("com.sindresorhus.Velja"))
        #expect(!BrowserCatalog.isLinkRouter("com.google.Chrome"))
    }

    @Test("Catalog has no duplicate bundle IDs")
    func catalogUnique() {
        let ids = BrowserCatalog.known.map { $0.bundleID.lowercased() }
        #expect(Set(ids).count == ids.count)
    }
}

@Suite("Chromium profiles")
struct ProfileTests {
    func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("Uses the browser's own order when present")
    func ordered() throws {
        let json = """
        {"profile":{"info_cache":{
            "Default":{"name":"Personal"},
            "Profile 1":{"name":"Work"},
            "Profile 3":{"name":"  "}
        },"profiles_order":["Profile 1","Default","Profile 3"]}}
        """
        let profiles = try ChromiumProfiles.parse(data(json))
        #expect(profiles == [
            BrowserProfile(directory: "Profile 1", name: "Work"),
            BrowserProfile(directory: "Default", name: "Personal"),
            BrowserProfile(directory: "Profile 3", name: "Profile 3"),
        ])
    }

    @Test("Without an order: Default first, then natural folder order")
    func unordered() throws {
        let json = """
        {"profile":{"info_cache":{
            "Profile 10":{"name":"Ten"}, "Profile 2":{"name":"Two"}, "Default":{"name":"Me"}
        }}}
        """
        #expect(try ChromiumProfiles.parse(data(json)).map(\.directory) == ["Default", "Profile 2", "Profile 10"])
    }

    @Test("Odd entries are skipped, not fatal")
    func oddEntries() throws {
        let json = #"{"profile":{"info_cache":{"../evil":{"name":"x"},"Default":"not-an-object","":{}}}}"#
        #expect(try ChromiumProfiles.parse(data(json)) == [BrowserProfile(directory: "Default", name: "Default")])
    }

    @Test("Unexpected formats throw .unreadable")
    func unreadable() {
        #expect(throws: ChromiumProfiles.Failure.unreadable) { try ChromiumProfiles.parse(data("not json")) }
        #expect(throws: ChromiumProfiles.Failure.unreadable) { try ChromiumProfiles.parse(data("{}")) }
        #expect(throws: ChromiumProfiles.Failure.unreadable) { try ChromiumProfiles.parse(data(#"{"profile":{"info_cache":[]}}"#)) }
    }

    @Test("Loading from disk: found and missing")
    func load() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "sbtest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appending(path: "Library/Application Support/Google/Chrome")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data(#"{"profile":{"info_cache":{"Default":{"name":"Me"}}}}"#).write(to: dir.appending(path: "Local State"))
        #expect(try ChromiumProfiles.load(dataDirectory: "Google/Chrome", home: home).map(\.name) == ["Me"])
        #expect(throws: ChromiumProfiles.Failure.notFound) { try ChromiumProfiles.load(dataDirectory: "Nope", home: home) }
    }

    @Test func directoryNames() {
        #expect(ChromiumProfiles.isValidDirectoryName("Profile 1"))
        #expect(ChromiumProfiles.isValidDirectoryName("Default"))
        #expect(!ChromiumProfiles.isValidDirectoryName("../x"))
        #expect(!ChromiumProfiles.isValidDirectoryName(" "))
        #expect(!ChromiumProfiles.isValidDirectoryName(".."))
    }
}

@Suite("Launch plans")
struct LaunchPlanTests {
    let link = url("https://example.com/a?b=1")

    @Test("Plain browsers get the fast open path")
    func plain() {
        let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
        #expect(LaunchPlan.make(for: safari, url: link) == LaunchPlan(appPath: "/Applications/Safari.app", method: .openURL(link), activates: true))
        #expect(LaunchPlan.make(for: safari, url: link, background: true)?.activates == false)
        var bg = safari; bg.opensInBackground = true
        #expect(LaunchPlan.make(for: bg, url: link)?.activates == false)
        // Safari private windows come from its File menu, never a plain (non-private) open.
        var priv = safari; priv.privateWindow = true
        #expect(LaunchPlan.make(for: priv, url: link)?.method == .safariWindow(.privateWindow, link))
        #expect(LaunchPlan.make(for: priv, url: link)?.needsAccessibility == true)
    }

    @Test("Chromium profiles and private windows use arguments")
    func chromium() {
        var chrome = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
                            profile: BrowserProfile(directory: "Profile 1", name: "Work"))
        #expect(LaunchPlan.make(for: chrome, url: link)?.method == .launchWithArguments(["--profile-directory=Profile 1", link.absoluteString]))
        chrome.privateWindow = true
        #expect(LaunchPlan.make(for: chrome, url: link)?.method == .launchWithArguments(["--profile-directory=Profile 1", "--incognito", link.absoluteString]))
    }

    @Test("Firefox private window")
    func firefox() {
        let ff = Target(bundleID: "org.mozilla.firefox", appPath: "/Applications/Firefox.app", appName: "Firefox", privateWindow: true)
        #expect(LaunchPlan.make(for: ff, url: link)?.method == .launchWithArguments(["-private-window", link.absoluteString]))
    }
}

@Suite("Duplicate deliveries")
struct DeduplicatorTests {
    @Test func dedup() {
        var d = Deduplicator(window: 0.4)
        let a = url("https://example.com/a"), b = url("https://example.com/b")
        let results = [
            d.accept(a, at: 10.0),  // first: handled
            d.accept(a, at: 10.1),  // same link, too soon: duplicate
            d.accept(b, at: 10.2),  // different link
            d.accept(a, at: 10.3),  // a again after b: allowed
            d.accept(a, at: 11.0),  // same link, after the window
            d.accept(a, at: 5.0),   // clock went backwards: never drop
        ]
        #expect(results == [true, false, true, true, true, true])
    }
}

@Suite("Source app")
struct SourceAppTests {
    @Test func outermost() {
        #expect(SourceApp.outermostAppPath("/Applications/Slack.app/Contents/Frameworks/Slack Helper.app") == "/Applications/Slack.app")
        #expect(SourceApp.outermostAppPath("/Applications/Mail.app") == "/Applications/Mail.app")
        #expect(SourceApp.outermostAppPath("/usr/bin/open") == nil)
    }
}

@Suite("Config storage")
struct ConfigStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sbtest-\(UUID().uuidString)/config.json")
    }

    @Test("Round trip")
    func roundTrip() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ConfigStore(fileURL: file)
        #expect(store.load() == .fresh)
        let t = Target(bundleID: "com.google.Chrome", appPath: "/A.app", appName: "Chrome", profile: BrowserProfile(directory: "Default", name: "Me"))
        let config = Config(
            targets: [t],
            rules: [Rule(host: "*.example.com", sourceApp: SourceAppMatch(bundleID: "x", name: "X"), modifiers: [.command], action: .open(targetID: t.id)), Rule(path: "/j", action: .ask)],
            fallback: .open(targetID: t.id), askModifiers: [.control, .option], didSeedTargets: true
        )
        try store.save(config)
        #expect(store.load() == .loaded(config))
    }

    @Test("A broken file is moved aside, not overwritten")
    func broken() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: file)
        let result = ConfigStore(fileURL: file).load()
        guard case .recovered(let backup) = result else { Issue.record("expected recovery"); return }
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

@Suite("Targets")
struct TargetTests {
    @Test func names() {
        var t = Target(bundleID: "com.google.Chrome", appPath: "/A.app", appName: "Google Chrome")
        #expect(t.displayName == "Google Chrome")
        #expect(t.shortName == "Google Chrome")
        t.profile = BrowserProfile(directory: "Profile 1", name: "Work")
        #expect(t.displayName == "Google Chrome (Work)")
        #expect(t.shortName == "Work")
        t.privateWindow = true
        #expect(t.displayName == "Google Chrome (Work, Private)")
    }

    @Test func sameDestination() {
        let a = Target(bundleID: "com.google.Chrome", appPath: "/A.app", appName: "C", profile: BrowserProfile(directory: "Default", name: "x"))
        var b = a; b.id = UUID(); b.isHidden = true
        #expect(a.isSameDestination(as: b))
        b.privateWindow = true
        #expect(!a.isSameDestination(as: b))
    }
}
