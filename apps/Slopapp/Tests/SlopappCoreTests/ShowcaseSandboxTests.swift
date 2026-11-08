import Foundation
import Testing
@testable import SlopappCore

@Suite struct ShowcaseSandboxTests {
    let data = URL(fileURLWithPath: "/tmp/slopapp-showcase/data/hero-light", isDirectory: true)

    @Test func normalLaunchesAreUnchanged() {
        let env = ["SLOPAPP_INSTALL_DIR": "/Applications/Slopapp", "SLOPAPP_FEED_URL": "https://example.com/feed.json"]
        #expect(ShowcaseSandbox.environment(env, data: data) == env)
        #expect(ShowcaseSandbox.environment(env.merging(["SLOP_SHOWCASE": "0"]) { $1 }, data: data)["SLOPAPP_INSTALL_DIR"]
            == "/Applications/Slopapp")
        #expect(!ShowcaseSandbox.isActive(["SLOP_SHOWCASE": " "]))
    }

    @Test func everyPathDefaultsIntoTheDataFolder() {
        let env = ShowcaseSandbox.environment(["SLOP_SHOWCASE": "discover"], data: data)
        #expect(env["SLOPAPP_INSTALL_DIR"] == data.path + "/Applications")
        #expect(env["SLOPAPP_TRASH_DIR"] == data.path + "/Trash")
        #expect(env["SLOPAPP_LIBRARY_DIR"] == data.path + "/Library")
        #expect(env["SLOPAPP_STATE_DIR"] == data.path + "/State")
        #expect(env["SLOPAPP_FEED_URL"] == data.path + "/feed/feed.json")
    }

    @Test func keepsPathsInsideAndReplacesPathsOutside() {
        let env = ShowcaseSandbox.environment([
            "SLOP_SHOWCASE": "updates",
            "SLOPAPP_INSTALL_DIR": data.path + "/Apps",
            "SLOPAPP_TRASH_DIR": NSHomeDirectory() + "/.Trash",
            "SLOPAPP_LIBRARY_DIR": data.path + "/../../Library",
            "SLOPAPP_STATE_DIR": "State",
            "SLOPAPP_FEED_URL": "file://" + data.path + "/other/feed.json",
        ], data: data)
        #expect(env["SLOPAPP_INSTALL_DIR"] == data.path + "/Apps")
        #expect(env["SLOPAPP_TRASH_DIR"] == data.path + "/Trash")
        // `..` can't climb out.
        #expect(env["SLOPAPP_LIBRARY_DIR"] == data.path + "/Library")
        #expect(env["SLOPAPP_STATE_DIR"] == data.path + "/State")
        #expect(env["SLOPAPP_FEED_URL"] == data.path + "/other/feed.json")
    }

    @Test func feedMustBeALocalFileInTheDataFolder() {
        for feed in ["https://hunterunger.github.io/slopapp/feed.json", "http://localhost:8765/feed.json",
                     "/Users/someone/feed.json", "file:///tmp/slopapp-showcase/data/hero-lightish/feed.json"] {
            let env = ShowcaseSandbox.environment(["SLOP_SHOWCASE": "app", "SLOPAPP_FEED_URL": feed], data: data)
            #expect(env["SLOPAPP_FEED_URL"] == data.path + "/feed/feed.json", "\(feed)")
        }
    }

    @Test func dataFolderFromTheEnvironment() {
        let temporary = URL(fileURLWithPath: "/var/tmp", isDirectory: true)
        #expect(ShowcaseSandbox.dataDirectory(["SLOP_SHOWCASE_DATA": data.path], temporary: temporary) == data)
        #expect(ShowcaseSandbox.dataDirectory([:], temporary: temporary).path == "/var/tmp/slopapp-showcase")
    }

    @Test func showcaseRootsLookNowhereElse() {
        let roots = InstallRoots.resolve(override: data.appendingPathComponent("Applications"),
                                         home: URL(fileURLWithPath: "/Users/test"), searchesElsewhere: false) { _ in true }
        let locator = FakeLocator()
        locator.infos["/Applications/Clips.app"] = .app("app.slopapp.clips", "0.2.0")
        locator.registered["app.slopapp.clips"] = [URL(fileURLWithPath: "/Applications/Clips.app")]
        #expect(Inventory.copies(of: "app.slopapp.clips", appName: "Clips", roots: roots, locator: locator).isEmpty)
        let installed = data.appendingPathComponent("Applications/Clips.app")
        locator.infos[installed.path] = .app("app.slopapp.clips", "0.1.0")
        #expect(Inventory.copies(of: "app.slopapp.clips", appName: "Clips", roots: roots, locator: locator).map(\.url.path) == [installed.path])
    }

    @Test func waitsOnlyForIconsThatExist() {
        let withIcon = CatalogItem(app: FeedApp(slug: "clips", name: "Clips", tagline: "", iconUrl: URL(string: "file:///f/Clips-icon.png")))
        let planned = CatalogItem(app: FeedApp(slug: "later", name: "Later", tagline: ""))
        let remote = CatalogItem(app: FeedApp(slug: "web", name: "Web", tagline: "", iconUrl: URL(string: "ftp://x/icon.png")))
        let items = [withIcon, planned, remote]
        let allows: (URL) -> Bool = { $0.isFileURL }
        #expect(ShowcaseSandbox.missingIcons(items, allows: allows) { _ in false } == ["clips"])
        #expect(ShowcaseSandbox.missingIcons(items, allows: allows) { $0.id == "clips" }.isEmpty)
    }
}
