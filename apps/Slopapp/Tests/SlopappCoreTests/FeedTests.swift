import Foundation
import Testing
@testable import SlopappCore

@Suite struct FeedTests {
    let base = URL(string: "https://example.com/slopapp/feed.json")!

    func json(_ apps: String, schema: Int = 1) -> Data {
        Data(#"{"schemaVersion": \#(schema), "generatedAt": "2026-11-02T10:00:00.000Z", "apps": [\#(apps)]}"#.utf8)
    }

    let awake = #"{"slug":"awake","name":"Awake","tagline":"Keep awake.","replaces":["Lungo","Amphetamine"],"version":"0.1.0","build":1,"bundleId":"app.slopapp.awake","downloadUrl":"https://github.com/x/releases/download/awake-v0.1.0/Awake.zip","sha256":"39777BF073AD784AA3FBFD72D1838CF26BFC1DC84F3197F5066360140886B68F","size":989552}"#

    @Test func parsesBuiltAndPlannedApps() throws {
        let feed = try FeedParser.parse(json(awake + #",{"slug":"clips","name":"Clips","tagline":"History.","status":"planned"}"#), baseURL: base)
        #expect(feed.apps.count == 2)
        #expect(feed.generatedAt != nil)
        let a = feed.apps[0]
        #expect(a.isInstallable)
        #expect(a.sha256 == "39777bf073ad784aa3fbfd72d1838cf26bfc1dc84f3197f5066360140886b68f") // lowercased
        #expect(a.alternativeText == "An open alternative to Lungo and Amphetamine.")
        #expect(!feed.apps[1].isInstallable)
    }

    @Test func resolvesRelativeURLsAgainstTheFeed() throws {
        let local = URL(fileURLWithPath: "/tmp/slopapp-test/feed/feed.json")
        let feed = try FeedParser.parse(json(#"{"slug":"a","name":"A","tagline":"","downloadUrl":"A.zip","iconUrl":"A-icon.png"}"#), baseURL: local)
        #expect(feed.apps[0].downloadUrl?.path == "/tmp/slopapp-test/feed/A.zip")
        #expect(feed.apps[0].iconUrl?.isFileURL == true)
    }

    @Test func dropsMalformedEntriesAndDuplicates() throws {
        let feed = try FeedParser.parse(json(awake + #",{"name":"no slug"},"#+awake), baseURL: base)
        #expect(feed.apps.map(\.slug) == ["awake"])
    }

    @Test func refusesNewerSchemaAndGarbage() {
        #expect(throws: FeedError.unsupportedSchema(2)) { try FeedParser.parse(json(awake, schema: 2), baseURL: base) }
        #expect(throws: FeedError.unreadable) { try FeedParser.parse(Data("<html>".utf8), baseURL: base) }
        #expect(throws: FeedError.unreadable) { try FeedParser.parse(Data(#"{"apps": 3}"#.utf8), baseURL: base) }
    }

    @Test func installableNeedsAWellFormedChecksum() {
        var app = FeedApp(slug: "a", name: "A", tagline: "", version: "1", bundleId: "x", downloadUrl: base, sha256: "abc")
        #expect(!app.isInstallable)
        app.sha256 = String(repeating: "a", count: 64)
        #expect(app.isInstallable)
        app.status = "planned"
        #expect(!app.isInstallable)
    }

    @Test func listFormatting() {
        #expect(ListFormat.and([]) == "")
        #expect(ListFormat.and(["A"]) == "A")
        #expect(ListFormat.and(["A", "B", "C"]) == "A, B and C")
    }
}

@Suite struct VersionTests {
    @Test func comparesNumerically() {
        #expect(AppVersion("0.1.10") > AppVersion("0.1.9"))
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(AppVersion("1.0.0", build: 2) > AppVersion("1.0.0", build: 1))
        #expect(AppVersion("2.0b3") == AppVersion("2.0.0"))
        #expect(AppVersion("1.2", build: "x") == AppVersion("1.2", build: 0))
    }

    @Test func minimumMacOS() {
        let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)
        #expect(meetsMinimum("14.0", system: sonoma))
        #expect(!meetsMinimum("15.0", system: sonoma))
        #expect(meetsMinimum(nil, system: sonoma))
    }
}

@Suite struct ScheduleTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func atMostEverySixHours() {
        let schedule = UpdateSchedule()
        #expect(schedule.isDue(lastCheck: nil, now: now))
        #expect(!schedule.isDue(lastCheck: now.addingTimeInterval(-5 * 3600), now: now))
        #expect(schedule.isDue(lastCheck: now.addingTimeInterval(-6 * 3600), now: now))
        #expect(schedule.delay(lastCheck: now.addingTimeInterval(-5 * 3600), now: now) == 3600)
    }

    @Test func futureTimestampCountsAsDue() {
        #expect(UpdateSchedule().isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}
