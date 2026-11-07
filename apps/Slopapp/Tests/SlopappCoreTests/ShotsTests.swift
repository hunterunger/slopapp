import Foundation
import Testing
@testable import SlopappCore

@Suite struct ShotFeedTests {
    let base = URL(string: "https://example.com/slopapp/feed.json")!

    func feed(_ shots: String, version: String = #""shotsVersion":"0.2.0-1","#) -> Data {
        Data(#"{"schemaVersion":1,"apps":[{"slug":"snapper","name":"Snapper","tagline":"x",\#(version)"shots":[\#(shots)]}]}"#.utf8)
    }

    let hero = #"{"id":"hero","title":"Mark it up","caption":"Arrows and blur.","light":"shots/snapper/hero-light.webp","dark":"shots/snapper/hero-dark.webp","light1x":"shots/snapper/hero-light@1x.webp","dark1x":"shots/snapper/hero-dark@1x.webp","width":2880,"height":1800}"#

    @Test func parsesShotsWithURLsRelativeToTheFeed() throws {
        let app = try FeedParser.parse(feed(hero), baseURL: base).apps[0]
        #expect(app.shotsVersion == "0.2.0-1")
        let shot = try #require(app.shots.first)
        #expect(shot.title == "Mark it up")
        #expect(shot.url(.light, .full).absoluteString == "https://example.com/slopapp/shots/snapper/hero-light.webp")
        #expect(shot.url(.dark, .page).absoluteString == "https://example.com/slopapp/shots/snapper/hero-dark@1x.webp")
        #expect(shot.accessibilityText == "Mark it up. Arrows and blur.")
    }

    @Test func pageFallsBackToTheMasterWithoutA1xCopy() throws {
        let shot = #"{"id":"a","title":"A","caption":"","light":"a-light.webp","dark":"a-dark.webp"}"#
        let parsed = try #require(try FeedParser.parse(feed(shot), baseURL: base).apps[0].shots.first)
        #expect(parsed.url(.light, .page) == parsed.url(.light, .full))
        #expect(parsed.accessibilityText == "A")
    }

    @Test func badShotsAreDroppedNotTheApp() throws {
        let noDark = #"{"id":"x","title":"X","caption":"","light":"x.webp"}"#
        let apps = try FeedParser.parse(feed(noDark + "," + hero + "," + hero + #","nonsense""#), baseURL: base).apps
        #expect(apps.count == 1)
        #expect(apps[0].shots.map(\.id) == ["hero"])
    }

    @Test func appsWithoutShotsHaveNone() throws {
        let data = Data(#"{"schemaVersion":1,"apps":[{"slug":"a","name":"A","tagline":""},{"slug":"b","name":"B","tagline":"","shots":"oops"}]}"#.utf8)
        let apps = try FeedParser.parse(data, baseURL: base).apps
        #expect(apps.map(\.shots.count) == [0, 0])
        #expect(apps[0].shotsVersion == nil)
    }

    @Test func survivesAnEncodeDecodeRoundTrip() throws {
        let app = try FeedParser.parse(feed(hero), baseURL: base).apps[0]
        let data = try JSONEncoder().encode(Feed(apps: [app]))
        let again = try FeedParser.parse(data, baseURL: nil).apps[0]
        #expect(again.shots == app.shots)
    }
}

@Suite struct GalleryPagingTests {
    @Test func stopsAtTheEnds() {
        var paging = GalleryPaging(count: 3)
        #expect(!paging.canGoBack && paging.canGoForward)
        paging.goBack()
        #expect(paging.index == 0)
        paging.goForward(); paging.goForward(); paging.goForward()
        #expect(paging.index == 2)
        #expect(paging.canGoBack && !paging.canGoForward)
        #expect(paging.position == "3 of 3")
    }

    @Test func jumpsAreClamped() {
        var paging = GalleryPaging(count: 4, index: 9)
        #expect(paging.index == 3)
        paging.go(to: -2)
        #expect(paging.index == 0)
        paging.go(to: 2)
        #expect(paging.position == "3 of 4")
    }

    @Test func emptyAndSingleGalleriesDoNothing() {
        var empty = GalleryPaging(count: 0)
        empty.goForward()
        #expect(empty.index == 0 && !empty.canGoForward && !empty.canGoBack)
        #expect(empty.prefetch.isEmpty)
        #expect(empty.position == "")
        let one = GalleryPaging(count: 1)
        #expect(!one.canGoForward && !one.canGoBack)
        #expect(one.prefetch == [0])
    }

    @Test func prefetchesTheVisibleShotAndItsNeighbours() {
        #expect(GalleryPaging(count: 5, index: 0).prefetch == [0, 1])
        #expect(GalleryPaging(count: 5, index: 2).prefetch == [2, 3, 1])
        #expect(GalleryPaging(count: 5, index: 4).prefetch == [4, 3])
    }
}

@Suite struct ShotCacheTests {
    let caches = URL(fileURLWithPath: "/Users/x/Library/Caches/app.slopapp.slopapp/shots")

    @Test func filesLiveUnderSlugAndVersion() {
        let file = ShotCache.file(in: caches, slug: "snapper", version: "0.2.0-1",
                                  url: URL(string: "https://example.com/shots/snapper/hero-dark@1x.webp")!)
        #expect(file.path == "/Users/x/Library/Caches/app.slopapp.slopapp/shots/snapper/0.2.0-1/hero-dark@1x.webp")
    }

    @Test func feedStringsCantEscapeTheCache() {
        let file = ShotCache.file(in: caches, slug: "../../evil", version: "../x",
                                  url: URL(string: "https://example.com/a/..%2F..%2Fb.webp")!)
        #expect(file.path.hasPrefix(caches.path + "/"))
        #expect(!file.path.contains("/../"))
        #expect(ShotCache.safe("..") == "_")
        #expect(ShotCache.safe("") == "_")
    }

    @Test func olderSetsAreStale() {
        let stale = ShotCache.stale(in: caches, slug: "snapper", version: "0.3.0-1", existing: ["0.2.0-1", "0.3.0-1"])
        #expect(stale.map(\.lastPathComponent) == ["0.2.0-1"])
        #expect(ShotCache.stale(in: caches, slug: "snapper", version: nil, existing: ["0"]).isEmpty)
    }
}
