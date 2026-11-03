import Foundation
import Testing
@testable import SlopappCore

@Suite struct InventoryTests {
    let home = URL(fileURLWithPath: "/Users/test")

    @Test func installFolderPrefersWritableApplications() {
        let roots = InstallRoots.resolve(override: nil, home: home, isWritable: { $0.path == "/Applications" })
        #expect(roots.installDirectory.path == "/Applications/Slopapp")
        #expect(roots.managedDirectories.map(\.path) == ["/Users/test/Applications/Slopapp"])
        let fallback = InstallRoots.resolve(override: nil, home: home, isWritable: { _ in false })
        #expect(fallback.installDirectory.path == "/Users/test/Applications/Slopapp")
    }

    @Test func overrideIsTheOnlyModifiableFolder() {
        let dir = URL(fileURLWithPath: "/tmp/slopapp-test/Applications")
        let roots = InstallRoots.resolve(override: dir, home: home, isWritable: { _ in true })
        #expect(roots.installDirectory == dir)
        #expect(roots.location(of: dir.appendingPathComponent("Awake.app")) == .managed)
        #expect(roots.location(of: URL(fileURLWithPath: "/Applications/Awake.app")) == .elsewhere)
    }

    @Test func classifiesLocations() {
        let roots = InstallRoots.resolve(override: nil, home: home, isWritable: { _ in true })
        #expect(roots.location(of: URL(fileURLWithPath: "/Applications/Slopapp/Awake.app")) == .managed)
        #expect(roots.location(of: URL(fileURLWithPath: "/Users/test/Applications/Slopapp/Awake.app")) == .managed)
        #expect(roots.location(of: URL(fileURLWithPath: "/Applications/Awake.app")) == .applications)
        #expect(roots.location(of: URL(fileURLWithPath: "/Users/test/code/build/Awake.app")) == .elsewhere)
    }

    @Test func findsCopiesBestFirstAndSkipsOtherBundlesAndTrash() {
        let roots = InstallRoots.resolve(override: nil, home: home, isWritable: { _ in true })
        let locator = FakeLocator()
        let id = "app.slopapp.awake"
        locator.infos["/Applications/Slopapp/Awake.app"] = .app(id, "0.1.0")
        locator.infos["/Users/test/build/Awake.app"] = .app(id, "0.2.0")
        locator.infos["/Applications/Awake.app"] = .app("com.other.awake", "9")
        locator.infos["/Users/test/.Trash/Awake.app"] = .app(id, "0.3.0")
        locator.registered[id] = [
            URL(fileURLWithPath: "/Users/test/build/Awake.app"),
            URL(fileURLWithPath: "/Applications/Slopapp/Awake.app"),
            URL(fileURLWithPath: "/Users/test/.Trash/Awake.app"),
        ]
        let copies = Inventory.copies(of: id, appName: "Awake", roots: roots, locator: locator)
        #expect(copies.map(\.url.path) == ["/Applications/Slopapp/Awake.app", "/Users/test/build/Awake.app"])
        #expect(copies.map(\.location) == [.managed, .elsewhere])
    }
}

@Suite struct CatalogTests {
    let installable = FeedApp(slug: "awake", name: "Awake", tagline: "Keep your Mac awake.", category: "Utilities",
                              replaces: ["Amphetamine"], version: "0.2.0", build: 2, bundleId: "app.slopapp.awake",
                              downloadUrl: URL(string: "https://x/Awake.zip"), sha256: String(repeating: "0", count: 64))

    func copy(_ version: String, _ location: CopyLocation, build: String = "1") -> InstalledCopy {
        InstalledCopy(url: URL(fileURLWithPath: "/x/Awake.app"), info: .app("app.slopapp.awake", version, build), location: location)
    }

    @Test func states() {
        #expect(CatalogItem(app: installable).state == .notInstalled)
        #expect(CatalogItem(app: FeedApp(slug: "c", name: "C", tagline: "")).state == .comingSoon)
        #expect(CatalogItem(app: installable, copies: [copy("0.1.0", .managed)]).state == .updateAvailable)
        #expect(CatalogItem(app: installable, copies: [copy("0.2.0", .applications, build: "2")]).state == .installed)
        // A newer local build is never "updated" backwards.
        #expect(CatalogItem(app: installable, copies: [copy("0.3.0", .managed)]).state == .installed)
    }

    @Test func copiesElsewhereAreNeverUpdatedInPlace() {
        let item = CatalogItem(app: installable, copies: [copy("0.1.0", .elsewhere)])
        #expect(item.state == .installed)
        #expect(item.isOnlyElsewhere)
        #expect(item.newerVersionForElsewhereCopy)
        let plan = InstallRequest.plan(for: item, roots: InstallRoots(installDirectory: URL(fileURLWithPath: "/tmp/A"), managedDirectories: [], applicationsDirectories: []))
        #expect(plan.destination.path == "/tmp/A/Awake.app")
        #expect(plan.replacing == nil)
    }

    @Test func updatesReplaceInPlace() {
        let item = CatalogItem(app: installable, copies: [copy("0.1.0", .applications)])
        let plan = InstallRequest.plan(for: item, roots: InstallRoots(installDirectory: URL(fileURLWithPath: "/tmp/A"), managedDirectories: [], applicationsDirectories: []))
        #expect(plan.destination.path == "/x/Awake.app")
        #expect(plan.replacing != nil)
    }

    @Test func searchMatchesNameTaglineCategoryAndWhatItReplaces() {
        let item = CatalogItem(app: installable)
        #expect(item.matches("awake"))
        #expect(item.matches("amphet"))
        #expect(item.matches("keep mac"))
        #expect(item.matches("utilities"))
        #expect(!item.matches("clipboard"))
        #expect(item.matches("  "))
    }

    @Test func builderLeavesOutTheHubAndCountsUpdates() {
        var hub = installable
        hub.slug = "slopapp"
        hub.hub = true
        let feed = Feed(apps: [installable, hub])
        let items = CatalogBuilder.items(feed: feed) { _ in [copy("0.1.0", .managed)] }
        #expect(items.map(\.app.slug) == ["awake"])
        #expect(CatalogBuilder.updates(in: items).count == 1)
        #expect(CatalogBuilder.installed(in: items).count == 1)
    }

    @Test func recommendedAppsAreTheAgreedSix() {
        #expect(RecommendedApp.all.map(\.name) == ["Rectangle", "Maccy", "IINA", "Keka", "AlDente", "Stats"])
        #expect(RecommendedApp.all.allSatisfy { $0.website.scheme == "https" })
    }
}
