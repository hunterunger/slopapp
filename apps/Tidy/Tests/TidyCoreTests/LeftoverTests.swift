import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Leftovers of installed apps")
struct LeftoverTests {
    @Test func findsEveryKindOfNotelyLeftover() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let paths = fixture.leftoverPaths(fixture.app("Notely"))
        let lib = "home/Library/"
        let expected: Set<String> = [
            lib + "Application Support/Notely",
            lib + "Application Support/com.fixture.Notely",
            lib + "Caches/com.fixture.Notely",
            lib + "Caches/com.fixture.Notely.ShipIt",
            lib + "Preferences/com.fixture.Notely.plist",
            lib + "Preferences/com.fixture.NotelyLauncher.plist",
            lib + "Preferences/ByHost/com.fixture.Notely.6F1E2A3B-1111-2222-3333-444455556666.plist",
            lib + "Containers/com.fixture.Notely",
            lib + "Containers/com.fixture.Notely.ShareExtension",
            lib + "Group Containers/ABCDE12345.com.fixture.Notely",
            lib + "Group Containers/group.com.fixture.Notely",
            lib + "Application Scripts/com.fixture.Notely",
            lib + "LaunchAgents/com.fixture.Notely.helper.plist",
            lib + "Saved Application State/com.fixture.Notely.savedState",
            lib + "HTTPStorages/com.fixture.Notely",
            lib + "HTTPStorages/com.fixture.Notely.binarycookies",
            lib + "WebKit/com.fixture.Notely",
            lib + "Cookies/com.fixture.Notely.binarycookies",
            lib + "Logs/Notely",
            lib + "Logs/DiagnosticReports/Notely-2026-10-01-101010.ips",
        ]
        #expect(paths == expected)
    }

    @Test func appBundleComesFirstAndKindsAreGrouped() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = fixture.finder.leftovers(for: fixture.app("Notely"))
        #expect(items.first?.kind == .application)
        #expect(items.first?.reason == .appBundle)
        #expect(items.map(\.kind) == items.map(\.kind).sorted())
        let containers = items.filter { $0.kind == .containers }
        #expect(containers.count == 4)
        #expect(containers.allSatisfy { $0.needsFullDiskAccess })
        #expect(items.filter { !$0.needsFullDiskAccess }.allSatisfy { $0.kind != .containers })
    }

    @Test func moreSpecificBundleIDWins() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let notely = fixture.leftoverPaths(fixture.app("Notely"))
        #expect(!notely.contains { $0.contains("Notely.Mini") || $0.contains("Notely Mini") })
        let mini = fixture.leftoverPaths(fixture.app("Notely Mini"))
        #expect(mini == [
            "home/Library/Application Support/Notely Mini",
            "home/Library/Preferences/com.fixture.Notely.Mini.plist",
            "home/Library/Caches/com.fixture.Notely.Mini",
        ])
    }

    @Test func plainPrefixIsNotABundleIDMatch() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let notely = fixture.leftoverPaths(fixture.app("Notely"))
        #expect(!notely.contains { $0.contains("NotelyPro") })
        #expect(fixture.leftoverPaths(fixture.app("NotelyPro")) == [
            "home/Library/Caches/com.fixture.NotelyPro",
            "home/Library/Application Support/NotelyPro",
        ])
    }

    @Test func commonWordNamesMatchByBundleIDOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.leftoverPaths(fixture.app("Code")) == [
            "home/Library/Application Support/com.fixture.code-editor",
            "home/Library/Preferences/com.fixture.code-editor.plist",
        ])
    }

    @Test func commonAndSharedNamesArePossibleMatchesOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let L = "home/Library/Application Support/"
        #expect(fixture.possiblePaths(fixture.app("Code")) == [L + "Code"])
        #expect(fixture.possiblePaths(fixture.app("Ox")) == [L + "Ox"])
        #expect(fixture.possiblePaths(fixture.app("Tasker")) == [L + "Tasker"])
        #expect(fixture.possiblePaths(fixture.app("Tasker", in: "Setapp")) == [L + "Tasker"])
        #expect(fixture.possiblePaths(fixture.app("Chatter")) == [L + "Electron"])
        // Distinctive, unshared names are full matches, never "possible".
        #expect(fixture.possiblePaths(fixture.app("Notely")).isEmpty)
        #expect(fixture.possiblePaths(fixture.app("Photo Sorter")).isEmpty)
        let tasker = try #require(fixture.finder.leftovers(for: fixture.app("Tasker")).first(where: { $0.reason.isPossibleMatch }))
        guard case .possibleName(_, .sharedWith(let others)) = tasker.reason else {
            Issue.record("expected a shared name, got \(tasker.reason)")
            return
        }
        #expect(others == ["Tasker in Setapp"])
        let code = try #require(fixture.finder.leftovers(for: fixture.app("Code")).first(where: { $0.reason.isPossibleMatch }))
        #expect(code.reason == .possibleName("Code", .commonName))
    }

    @Test func namesMatchExactlyNeverFuzzily() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.leftoverPaths(fixture.app("Photo Sorter")) == [
            "home/Library/Application Support/Photo Sorter",
            "home/Library/Preferences/com.fixture.PhotoSorter.plist",
        ])
    }

    @Test func shortNamesAreNotMatched() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.leftoverPaths(fixture.app("Ox")) == ["home/Library/Preferences/com.fixture.ox.plist"])
    }

    @Test func ambiguousNamesBelongToNobody() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.leftoverPaths(fixture.app("Tasker")) == ["home/Library/Preferences/com.fixture.Tasker.plist"])
        #expect(fixture.leftoverPaths(fixture.app("Tasker", in: "Setapp")) == ["home/Library/Preferences/com.otherdev.Tasker.plist"])
    }

    @Test func launchAgentMatchedByTheProgramItRuns() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = fixture.finder.leftovers(for: fixture.app("Syncer"))
        let byPath = Dictionary(uniqueKeysWithValues: items.map { (fixture.relative($0.url), $0) })
        #expect(byPath["home/Library/LaunchAgents/com.othervendor.syncd.plist"]?.reason == .launchProgram)
        #expect(byPath["home/Library/Application Support/Syncer"]?.reason == .name("Syncer"))
        #expect(byPath["home/Library/Logs/Syncer.log"] != nil)
        // /Library items are listed but need an administrator.
        let daemon = byPath["Library/LaunchDaemons/com.fixture.Syncer.daemon.plist"]
        #expect(daemon?.needsAdmin == true)
        #expect(daemon?.isRemovable(hasFullDiskAccess: true) == false)
        #expect(byPath["Library/PrivilegedHelperTools/com.fixture.Syncer.helper"]?.needsAdmin == true)
        #expect(byPath["Library/Application Support/Syncer"]?.needsAdmin == true)
    }

    @Test func executableNamedElectronDoesNotClaimElectronFolders() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let paths = fixture.leftoverPaths(fixture.app("Chatter"))
        #expect(paths == [
            "home/Library/Application Support/Chatter",
            "home/Library/Caches/com.fixture.Chatter",
            "home/Library/Caches/com.fixture.Chatter.ShipIt",
        ])
    }

    @Test func appleAppsGetNothing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let safari = fixture.app("Safari")
        #expect(safari.isApple)
        #expect(fixture.finder.leftovers(for: safari).isEmpty)
    }

    @Test func nestedAppFoldersAreScanned() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let apps = AppCatalog.scan(fixture.environment.applicationDirectories)
        #expect(apps.count == 13)
        #expect(apps.contains { $0.bundleID == "com.fixture.Grapher" })
        #expect(apps.contains { $0.bundleID == "com.otherdev.Tasker" })
        let grapher = try #require(apps.first { $0.bundleID == "com.fixture.Grapher" })
        #expect(fixture.leftoverPaths(grapher) == [
            "home/Library/Preferences/com.fixture.Grapher.plist",
            "home/Library/Logs/DiagnosticReports/Grapher-2026-08-02-120000.crash",
        ])
    }

    @Test func readsBundleDetailsAndEmbeddedIDs() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let notely = fixture.app("Notely")
        #expect(notely.bundleID == "com.fixture.Notely")
        #expect(notely.version == "2.3.1")
        #expect(Set(notely.embeddedBundleIDs) == ["com.fixture.NotelyLauncher", "com.fixture.Notely.ShareExtension"])
        #expect(AppCatalog.read(fixture.home.appendingPathComponent("Documents")) == nil)
    }

    @Test func droppedAppFromElsewhereIsMatchedToo() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        // A second copy of an installed app: its data is shared, so nothing is claimed.
        let copy = fixture.home.appendingPathComponent("Downloads/Notely.app")
        try FileManager.default.copyItem(at: fixture.app("Notely").url, to: copy)
        let items = fixture.finder.leftovers(for: try #require(AppCatalog.read(copy)))
        #expect(items.filter { !$0.reason.isPossibleMatch }.map(\.kind) == [.application])
        // Same-named folders show up only as possible matches, shared with the installed copy.
        #expect(items.filter { $0.reason.isPossibleMatch }.count == 2)
    }

    @Test func crashReportNames() {
        #expect(LeftoverFinder.isCrashReport("Notely-2026-10-01-101010.ips", of: "Notely"))
        #expect(LeftoverFinder.isCrashReport("Notely_2026-10-01-101010_Mac.crash", of: "Notely"))
        #expect(!LeftoverFinder.isCrashReport("NotelyPro-2026-10-01-101010.ips", of: "Notely"))
        #expect(!LeftoverFinder.isCrashReport("Notely-helper.ips", of: "Notely"))
        #expect(!LeftoverFinder.isCrashReport("Notely-2026-10-01.txt", of: "Notely"))
    }
}

@Suite("Leftovers of deleted apps")
struct OrphanTests {
    @Test func findsOnlyTrulyOrphanedApps() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let groups = OrphanFinder(finder: fixture.finder).find()
        // net.activetool.Daemon looks orphaned but was written today, so it's left alone.
        #expect(groups.map(\.bundleID) == ["com.goneware.OldEditor", "io.retired.Snapz"])
        let old = try #require(groups.first)
        #expect(old.displayName == "OldEditor")
        #expect(Set(old.items.map { fixture.relative($0.url) }) == [
            "home/Library/Application Support/com.goneware.OldEditor",
            "home/Library/Caches/com.goneware.OldEditor",
            "home/Library/Preferences/com.goneware.OldEditor.plist",
            "home/Library/Saved Application State/com.goneware.OldEditor.savedState",
            "home/Library/Containers/com.goneware.OldEditor",
            "home/Library/HTTPStorages/com.goneware.OldEditor",
            "home/Library/LaunchAgents/com.goneware.OldEditor.updater.plist",
        ])
    }

    @Test func recentlyChangedItemsAreOrphansOnlyLater() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let later = OrphanFinder(finder: fixture.finder, now: Date().addingTimeInterval(8 * 86_400)).find()
        #expect(later.map(\.bundleID) == ["net.activetool.Daemon", "com.goneware.OldEditor", "io.retired.Snapz"])
    }

    @Test func embeddedThirdPartyIDsDontCount() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let notely = fixture.app("Notely").url
        let sparkle = notely.appendingPathComponent("Contents/XPCServices/Installer.xpc/Contents")
        try FileManager.default.createDirectory(at: sparkle, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.sparkle-project.InstallerLauncher"],
                                           format: .xml, options: 0).write(to: sparkle.appendingPathComponent("Info.plist"))
        #expect(!fixture.app("Notely").embeddedBundleIDs.contains("org.sparkle-project.InstallerLauncher"))
    }

    @Test func appsInTheTrashKeepTheirLeftoversVisible() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        // Uninstall Syncer's app bundle only, as if it were dragged to the Trash.
        let service = TrashService(environment: fixture.environment)
        let moved = service.moveToTrash([(fixture.app("Syncer").url, 0)])
        #expect(moved.failures.isEmpty)
        let finder = fixture.finder
        let trashed = AppCatalog.scan([fixture.trash])
        let groups = OrphanFinder(finder: finder, trashedApps: trashed).find()
        let syncer = try #require(groups.first { $0.bundleID == "com.fixture.Syncer" })
        #expect(syncer.displayName == "Syncer")
        let paths = Set(syncer.items.map { fixture.relative($0.url) })
        #expect(paths == [
            "home/Library/Application Support/Syncer",
            "home/Library/Logs/Syncer.log",
            "Library/LaunchDaemons/com.fixture.Syncer.daemon.plist",
            "Library/PrivilegedHelperTools/com.fixture.Syncer.helper",
            "Library/Application Support/Syncer",
        ])
        // Admin-owned ones are listed, locked.
        #expect(syncer.items.filter(\.needsAdmin).count == 3)
        // Without the bundle in the Trash, the same-vendor rule keeps them out.
        #expect(!OrphanFinder(finder: finder).find().contains { $0.bundleID == "com.fixture.Syncer" })
    }

    @Test func trashedCopyOfAnInstalledAppIsIgnored() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.copyItem(at: fixture.app("Notely").url, to: fixture.trash.appendingPathComponent("Notely.app"))
        let groups = OrphanFinder(finder: fixture.finder, trashedApps: AppCatalog.scan([fixture.trash])).find()
        #expect(groups.map(\.bundleID) == ["com.goneware.OldEditor", "io.retired.Snapz"])
    }

    @Test func appInstalledElsewhereIsNotAnOrphan() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let groups = OrphanFinder(finder: fixture.finder, isInstalledElsewhere: { $0 == "com.goneware.OldEditor" }).find()
        #expect(groups.map(\.bundleID) == ["io.retired.Snapz"])
    }

    @Test func runningAppIsNotAnOrphan() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let groups = OrphanFinder(finder: fixture.finder, runningBundleIDs: ["io.retired.Snapz"]).find()
        #expect(groups.map(\.bundleID) == ["com.goneware.OldEditor"])
    }

    @Test func noOrphansWhenTheAppComesBack() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let apps = AppCatalog.scan(fixture.environment.applicationDirectories)
            + [InstalledApp(url: URL(fileURLWithPath: "/x/OldEditor.app"), bundleID: "com.goneware.OldEditor", name: "OldEditor")]
        let finder = LeftoverFinder(apps: apps, index: LibraryIndex.build(fixture.environment))
        #expect(OrphanFinder(finder: finder).find().map(\.bundleID) == ["io.retired.Snapz"])
    }
}

@Suite("Match rules")
struct MatchRuleTests {
    @Test func bundleIDMatching() {
        #expect(BundleID.matches("com.acme.Widget", "com.acme.widget"))
        #expect(BundleID.matches("com.acme.Widget.helper", "com.acme.Widget"))
        #expect(!BundleID.matches("com.acme.WidgetPro", "com.acme.Widget"))
        #expect(!BundleID.matches("com.acme", "com.acme.Widget"))
    }

    @Test func groupContainers() {
        #expect(BundleID.groupContainerID("ABCDE12345.com.acme.Widget") == "com.acme.Widget")
        #expect(BundleID.groupContainerID("group.com.acme.Widget") == "com.acme.Widget")
        #expect(BundleID.groupContainerID("ABCDE12345.group.com.acme") == "com.acme")
        #expect(BundleID.groupContainerID("abcde12345.com.acme.Widget") == "abcde12345.com.acme.Widget")
    }

    @Test func bundleIDShape() {
        #expect(BundleID.looksLikeBundleID("com.acme.Widget"))
        #expect(BundleID.looksLikeBundleID("io.acme.my-app_2"))
        #expect(!BundleID.looksLikeBundleID("com.acme"))
        #expect(!BundleID.looksLikeBundleID("Photo Sorter"))
        #expect(!BundleID.looksLikeBundleID("homebrew.mxcl.postgresql@16"))
        #expect(!BundleID.looksLikeBundleID("1com.acme.x"))
        #expect(!BundleID.looksLikeBundleID("com..x"))
    }

    @Test func stems() {
        #expect(BundleID.stem("com.acme.Widget.plist") == "com.acme.Widget")
        #expect(BundleID.stem("com.acme.Widget.savedState") == "com.acme.Widget")
        #expect(BundleID.stem("com.acme.Widget.binarycookies") == "com.acme.Widget")
        #expect(BundleID.stem("com.acme.Widget") == "com.acme.Widget")
    }

    @Test(arguments: ["Code", "Notes", "Mail", "Electron", "Ox", "Go", "123", "  Data  ", "Google", "Helper", "Arc"])
    func genericNamesAreNotDistinctive(name: String) {
        #expect(!NameRules.isDistinctive(name))
    }

    @Test(arguments: ["Notely", "Photo Sorter", "Firefox", "Zed Preview", "Bear"])
    func distinctiveNames(name: String) {
        #expect(NameRules.isDistinctive(name))
    }
}
