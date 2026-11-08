import Foundation
import Testing
@testable import SlopappCore

/// A catalog entry: installable when it has a version, else planned.
private func app(_ slug: String, _ category: String?, installable: Bool = true, replaces: [String] = [],
                 menuBar: Bool? = nil) -> FeedApp {
    FeedApp(slug: slug, name: slug.capitalized, tagline: "\(slug) does a thing.", category: category, replaces: replaces,
            menuBarOnly: menuBar, version: installable ? "1.0.0" : nil, build: 1, bundleId: "app.slopapp.\(slug)",
            downloadUrl: installable ? URL(string: "https://x/\(slug).zip") : nil,
            sha256: installable ? String(repeating: "a", count: 64) : nil)
}

private func installed(_ app: FeedApp, version: String = "1.0.0") -> CatalogItem {
    CatalogItem(app: app, copies: [InstalledCopy(url: URL(fileURLWithPath: "/A/\(app.name).app"),
                                                 info: .app(app.bundleId ?? "", version), location: .managed)])
}

@Suite struct BrowseTests {
    let clips = CatalogItem(app: app("clips", "Productivity"))
    let awake = CatalogItem(app: app("awake", "Utilities"))
    let tidy = CatalogItem(app: app("tidy", "Utilities", installable: false))
    let quit = CatalogItem(app: app("quit", "Utilities"))
    let paper = CatalogItem(app: app("paper", nil, installable: false))
    let lab = CatalogItem(app: app("lab", "Science"))

    var all: [CatalogItem] { [clips, tidy, awake, paper, lab, quit] }

    @Test func categoriesFollowTheSidebarOrderThenExtrasThenOther() {
        #expect(Categories.ordered(in: all) == ["Utilities", "Productivity", "Science", "Other"])
        #expect(Categories.ordered(in: []) == [])
        #expect(Categories.name(of: paper) == "Other")
        #expect(!Categories.blurb(for: "Utilities").isEmpty)
    }

    @Test func featuredSortPutsAvailableAppsFirstInCatalogOrder() {
        let utilities = Browse.apps(all, category: "Utilities")
        #expect(utilities.map(\.id) == ["awake", "quit", "tidy"])
        #expect(Browse.apps(all, sort: .name).map(\.id) == ["awake", "clips", "lab", "paper", "quit", "tidy"])
    }

    @Test func filtersSplitAvailableFromComingSoon() {
        #expect(Browse.apps(all, filter: .comingSoon).map(\.id) == ["tidy", "paper"])
        #expect(Browse.apps(all, category: "Utilities", filter: .available).map(\.id) == ["awake", "quit"])
        // Installed but no longer downloadable still counts as available (it's on this Mac).
        let orphan = installed(app("old", "Utilities", installable: false))
        #expect(CatalogFilter.available.includes(orphan))
        #expect(!CatalogFilter.comingSoon.includes(orphan))
    }

    @Test func featuredPrefersAppsNotInstalledYet() {
        let here = installed(clips.app)
        let picks = Browse.featured([here, tidy, awake, quit], limit: 5)
        #expect(picks.map(\.id) == ["awake", "quit", "clips"])
        #expect(Browse.featured([here, awake, quit], limit: 2).map(\.id) == ["awake", "quit"])
        #expect(Browse.featured([tidy, paper]).isEmpty)
    }

    @Test func relatedAppsShareTheCategoryAndSkipItself() {
        #expect(Browse.related(to: awake, in: all).map(\.id) == ["quit", "tidy"])
        #expect(Browse.related(to: awake, in: all, limit: 1).map(\.id) == ["quit"])
        #expect(Browse.related(to: lab, in: all).isEmpty)
    }

    @Test func highlightsComeFromTheFeed() {
        let lines = Browse.highlights(for: app("clips", "Productivity", replaces: ["Paste", "Maccy"], menuBar: true), license: "MIT")
        #expect(lines == ["An open alternative to Paste and Maccy", "Lives in your menu bar",
                          "Free and open source (MIT)", "No account, no tracking"])
        let plain = Browse.highlights(for: app("paper", nil), license: "MIT")
        #expect(plain == ["Free and open source (MIT)", "No account, no tracking"])
        #expect(Browse.highlights(for: app("x", nil, menuBar: false), license: "MIT").first == "Opens in its own window")
    }
}

@Suite struct FavoriteListTests {
    @Test func togglesAndKeepsTheOrderTheyWereAdded() {
        var list = FavoriteList(slugs: ["b", "a", "b"])
        #expect(list.slugs == ["b", "a"])
        list.toggle("c")
        list.toggle("b")
        #expect(list.slugs == ["a", "c"])
        #expect(list.contains("c") && !list.contains("b"))
    }

    @Test func showsOnlyAppsInTheCatalogAndInstallsOnlyMissingOnes() {
        let one = CatalogItem(app: app("one", "Utilities"))
        let two = installed(app("two", "Utilities"))
        let soon = CatalogItem(app: app("soon", "Utilities", installable: false))
        let list = FavoriteList(slugs: ["gone", "soon", "two", "one"])
        #expect(list.items(in: [one, two, soon]).map(\.id) == ["soon", "two", "one"])
        #expect(list.installable(in: [one, two, soon]).map(\.id) == ["one"])
    }
}

@Suite struct PageHistoryTests {
    let discover = Page(.discover)
    let installed = Page(.installed)

    @Test func startsOnDiscoverWithNothingToGoBackTo() {
        let history = PageHistory()
        #expect(history.current == discover)
        #expect(!history.canGoBack && !history.canGoForward)
    }

    @Test func backReturnsToTheSidebarPageBefore() {
        var history = PageHistory()
        history.go(to: installed)
        history.go(to: Page(.category("Utilities")))
        #expect(history.canGoBack)
        history.back()
        #expect(history.current == installed)
        history.back()
        #expect(history.current == discover && !history.canGoBack)
        history.back()
        #expect(history.current == discover)
    }

    @Test func appPagesAndSidebarPagesShareOneHistory() {
        var history = PageHistory()
        history.go(to: Page(.discover, app: "clips"))
        history.go(to: Page(.discover, app: "tidy"))     // a related app, from Clips's page
        history.go(to: installed)
        history.back()
        #expect(history.current == Page(.discover, app: "tidy"))
        history.back()
        #expect(history.current == Page(.discover, app: "clips"))
        history.forward()
        history.forward()
        #expect(history.current == installed && !history.canGoForward)
    }

    @Test func theSamePageTwiceIsOneStep() {
        var history = PageHistory()
        history.go(to: installed)
        history.go(to: installed)
        history.back()
        #expect(history.current == discover && !history.canGoBack)
    }

    @Test func goingSomewhereNewForgetsWhatWasAhead() {
        var history = PageHistory()
        history.go(to: installed)
        history.go(to: Page(.updates))
        history.back()
        history.back()
        #expect(history.ahead == [Page(.updates), installed])
        history.go(to: installed)                        // the page that was next: keep the rest
        #expect(history.ahead == [Page(.updates)])
        history.go(to: Page(.favorites))
        #expect(history.ahead.isEmpty && history.behind == [discover, installed])
    }

    @Test func remembersALimitedNumberOfPages() {
        var history = PageHistory()
        for i in 0..<(PageHistory.limit + 50) { history.go(to: Page(.discover, app: "app\(i)")) }
        #expect(history.behind.count == PageHistory.limit)
    }
}
