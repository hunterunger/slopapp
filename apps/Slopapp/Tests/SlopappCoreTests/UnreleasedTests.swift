import Foundation
import Testing
@testable import SlopappCore

/// Apps with no release in the feed yet ("planned", no bundle id) that are on this Mac anyway.
@Suite struct UnreleasedTests {
    let home = URL(fileURLWithPath: "/Users/test")
    /// What older feeds list for a built app without a release: no bundle id, no download.
    let squish = FeedApp(slug: "squish", name: "Squish", tagline: "Smaller files.", status: "planned")

    func scan(_ feed: Feed, namespace: String?, locator: FakeLocator) -> [CatalogItem] {
        let roots = InstallRoots.resolve(override: nil, home: home, isWritable: { _ in true })
        return CatalogBuilder.items(feed: feed, bundleIDNamespace: namespace) { app in
            Inventory.copies(of: app.bundleId ?? "", appName: app.name, roots: roots, locator: locator)
        }
    }

    @Test func installedCopyOfAnUnreleasedAppIsFoundAndOpenable() throws {
        let locator = FakeLocator()
        locator.infos["/Applications/Slopapp/Squish.app"] = .app("app.slopapp.squish", "0.1.0")
        let items = scan(Feed(apps: [squish]), namespace: "app.slopapp", locator: locator)
        let item = try #require(items.first)
        #expect(item.app.bundleId == "app.slopapp.squish")
        #expect(item.primary?.url.path == "/Applications/Slopapp/Squish.app")
        #expect(!item.app.isInstallable)
        // .installed is what puts Open on the card, the app page and the menus.
        #expect(item.state == .installed)
        #expect(!item.hasUpdate(for: item.primary!))
        #expect(IconSource.of(item, allows: { _ in true }) == .installed(URL(fileURLWithPath: "/Applications/Slopapp/Squish.app")))
    }

    @Test func notOnThisMacStaysComingSoon() {
        let items = scan(Feed(apps: [squish]), namespace: "app.slopapp", locator: FakeLocator())
        #expect(items.first?.state == .comingSoon)
        #expect(items.first.map { IconSource.of($0, allows: { _ in true }) } == .some(nil))
    }

    @Test func aCopyWithAnotherBundleIDIsNotTaken() {
        let locator = FakeLocator()
        locator.infos["/Applications/Squish.app"] = .app("com.someone.squish", "2.0")
        let items = scan(Feed(apps: [squish]), namespace: "app.slopapp", locator: locator)
        #expect(items.first?.isInstalled == false)
    }

    @Test func withoutANamespaceNothingIsGuessed() {
        let locator = FakeLocator()
        locator.infos["/Applications/Slopapp/Squish.app"] = .app("app.slopapp.squish", "0.1.0")
        let items = scan(Feed(apps: [squish]), namespace: nil, locator: locator)
        #expect(items.first?.app.bundleId == nil)
        #expect(items.first?.state == .comingSoon)
    }

    @Test func theFeedsOwnBundleIDWins() {
        var app = squish
        app.bundleId = "app.slopapp.squish-beta"
        let locator = FakeLocator()
        locator.infos["/Applications/Slopapp/Squish.app"] = .app("app.slopapp.squish-beta", "0.1.0")
        let items = scan(Feed(apps: [app]), namespace: "app.slopapp", locator: locator)
        #expect(items.first?.app.bundleId == "app.slopapp.squish-beta")
        #expect(items.first?.state == .installed)
    }

    @Test func expectedBundleIDs() {
        #expect(CatalogBuilder.expectedBundleID(slug: "squish", namespace: "app.slopapp") == "app.slopapp.squish")
        #expect(CatalogBuilder.expectedBundleID(slug: "pdf-tools", namespace: "app.slopapp") == "app.slopapp.pdf-tools")
        #expect(CatalogBuilder.expectedBundleID(slug: "a.b", namespace: "app.slopapp") == nil)
        #expect(CatalogBuilder.expectedBundleID(slug: "", namespace: "app.slopapp") == nil)
        #expect(CatalogBuilder.expectedBundleID(slug: "x", namespace: "app..slopapp") == nil)
        #expect(CatalogBuilder.expectedBundleID(slug: "x", namespace: "") == nil)
        #expect(CatalogBuilder.namespace(ofBundleID: "app.slopapp.slopapp") == "app.slopapp")
        #expect(CatalogBuilder.namespace(ofBundleID: "slopapp") == nil)
        #expect(CatalogBuilder.namespace(ofBundleID: nil) == nil)
    }
}

@Suite struct IconSourceTests {
    let url = URL(fileURLWithPath: "/Applications/Slopapp/Awake.app")
    let released = FeedApp(slug: "awake", name: "Awake", tagline: "", version: "0.2.0", build: 2, bundleId: "app.slopapp.awake",
                           iconUrl: URL(string: "https://example.com/Awake-icon.png"))

    @Test func installedCopyWinsOverTheFeedIcon() {
        let item = CatalogItem(app: released, copies: [InstalledCopy(url: url, info: .app("app.slopapp.awake", "0.1.0"), location: .managed)])
        #expect(IconSource.of(item, allows: { _ in true }) == .installed(url))
        #expect(IconSource.memoryKey(for: item) == "awake@/Applications/Slopapp/Awake.app#0.1.0")
    }

    @Test func feedIconWhenNotInstalledAndAllowed() {
        let item = CatalogItem(app: released)
        #expect(IconSource.of(item, allows: { _ in true }) == .remote(released.iconUrl!, cacheName: "awake-0.2.0.png"))
        #expect(IconSource.of(item, allows: { _ in false }) == nil)
        #expect(IconSource.memoryKey(for: item) == "awake#0.2.0")
    }

    @Test func installedCacheNameFollowsTheCopy() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = IconSource.installedCacheName(slug: "awake", url: url, version: "0.1.0", build: "1", modified: date)
        #expect(name == IconSource.installedCacheName(slug: "awake", url: url, version: "0.1.0", build: "1", modified: date))
        #expect(name.hasPrefix(IconSource.installedCachePrefix("awake")) && name.hasSuffix(".png"))
        // A rebuild at the same version, a new version, another copy: a new render.
        #expect(name != IconSource.installedCacheName(slug: "awake", url: url, version: "0.1.0", build: "1", modified: date + 1))
        #expect(name != IconSource.installedCacheName(slug: "awake", url: url, version: "0.2.0", build: "1", modified: date))
        #expect(name != IconSource.installedCacheName(slug: "awake", url: URL(fileURLWithPath: "/Applications/Awake.app"),
                                                      version: "0.1.0", build: "1", modified: date))
        // Sweeping "awake" renders never touches another app whose slug starts the same.
        let other = IconSource.installedCacheName(slug: "awake-pro", url: url, version: "1", build: "1", modified: date)
        #expect(!other.hasPrefix(IconSource.installedCachePrefix("awake")))
    }
}
