import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Environment")
struct EnvironmentTests {
    let realHome = URL(fileURLWithPath: "/Users/someone")

    @Test func realModeUsesTheRealMac() {
        let env = TidyEnvironment.from(environment: [:], realHome: realHome)
        #expect(!env.isTestMode)
        #expect(env.home.path == "/Users/someone")
        #expect(env.applicationDirectories.map(\.path) == ["/Applications", "/Users/someone/Applications"])
        #expect(env.systemLibrary?.path == "/Library")
        #expect(env.trashDirectory == nil)
        #expect(env.usesLaunchServices)
    }

    @Test func anyVariableSwitchesToTestMode() {
        let env = TidyEnvironment.from(environment: ["TIDY_HOME": "/tmp/tidy-test/home"], realHome: realHome)
        #expect(env.isTestMode)
        #expect(env.applicationDirectories.map(\.path) == ["/tmp/tidy-test/home/Applications"])
        #expect(env.trashDirectory?.path == "/tmp/tidy-test/home/.Trash")
        #expect(env.systemLibrary == nil)
        #expect(!env.usesLaunchServices)
        #expect(env.warnings.isEmpty)
    }

    @Test func testModeNeverFallsBackToTheRealHome() {
        let env = TidyEnvironment.from(environment: ["TIDY_TRASH_DIR": "/tmp/tidy-test/Trash"], realHome: realHome)
        #expect(env.isTestMode)
        #expect(env.home.path == "/var/empty")
        #expect(!env.warnings.isEmpty)
        #expect(!env.applicationDirectories.contains { $0.path == "/Applications" })
    }

    @Test func parsesListsAndRunningIDs() {
        let env = TidyEnvironment.from(environment: [
            "TIDY_HOME": "/tmp/h", "TIDY_APPS_DIRS": "/tmp/a:/tmp/b", "TIDY_RUNNING_IDS": "com.a.b, com.c.d",
        ], realHome: realHome)
        #expect(env.applicationDirectories.map(\.path) == ["/tmp/a", "/tmp/b"])
        #expect(env.simulatedRunningBundleIDs == ["com.a.b", "com.c.d"])
    }
}

@Suite("Trash policy")
struct PolicyTests {
    @Test func allowsItemsInsideTheFixture() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        let L = fixture.library
        for path in ["Caches/com.fixture.Notely", "Preferences/com.fixture.Notely.plist",
                     "Preferences/ByHost/com.fixture.Notely.6F1E2A3B-1111-2222-3333-444455556666.plist",
                     "Developer/Xcode/DerivedData/MyApp-bxkfjqwmzrdhgnaefyeqtgsaulwo", "Caches/com.apple.dt.Xcode",
                     "Logs/DiagnosticReports/Notely-2026-10-01-101010.ips"] {
            #expect(policy.allows(L.appendingPathComponent(path)), "\(path)")
        }
        #expect(policy.allows(fixture.applications.appendingPathComponent("Notely.app")))
        #expect(policy.allows(fixture.applications.appendingPathComponent("Utilities/Grapher.app")))
        #expect(policy.allows(fixture.home.appendingPathComponent("Downloads/Installer-2024.dmg")))
        #expect(policy.allows(fixture.home.appendingPathComponent(".npm/_cacache")))
        #expect(policy.allows(fixture.systemLibrary.appendingPathComponent("LaunchDaemons/com.fixture.Syncer.daemon.plist")))
    }

    @Test func refusesStructuralFolders() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        let L = fixture.library
        for path in ["", "Caches", "Preferences", "Preferences/ByHost", "Logs/DiagnosticReports", "Developer",
                     "Developer/Xcode/DerivedData", "Developer/Xcode/Archives", "Developer/CoreSimulator/Caches",
                     "Application Support"] {
            #expect(throws: TrashRefusal.protectedFolder) { try policy.check(L.appendingPathComponent(path)) }
        }
        #expect(throws: TrashRefusal.protectedFolder) { try policy.check(fixture.home.appendingPathComponent("Documents")) }
        #expect(throws: TrashRefusal.protectedFolder) { try policy.check(fixture.home.appendingPathComponent(".npm")) }
        #expect(throws: TrashRefusal.protectedFolder) { try policy.check(fixture.trash.appendingPathComponent("x")) }
        #expect(throws: TrashRefusal.outsideAllowedFolders) { try policy.check(fixture.home) }
        #expect(throws: TrashRefusal.outsideAllowedFolders) { try policy.check(fixture.systemLibrary.appendingPathComponent("LaunchDaemons")) }
    }

    @Test func refusesAppleItems() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        #expect(throws: TrashRefusal.appleItem) { try policy.check(fixture.library.appendingPathComponent("Preferences/com.apple.dock.plist")) }
        #expect(throws: TrashRefusal.appleItem) { try policy.check(fixture.library.appendingPathComponent("Caches/com.apple.bird")) }
        #expect(throws: TrashRefusal.appleItem) {
            try policy.check(fixture.library.appendingPathComponent("Group Containers/group.com.apple.notes"))
        }
    }

    @Test func refusesEverythingOutsideTheFixture() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        let realHome = FileManager.default.homeDirectoryForCurrentUser
        for url in [realHome.appendingPathComponent("Library/Caches/com.example.App"),
                    URL(fileURLWithPath: "/Applications/Notely.app"), URL(fileURLWithPath: "/Library/LaunchDaemons/x.plist"),
                    URL(fileURLWithPath: "/System/Applications/Notes.app"), URL(fileURLWithPath: "/tmp/tidy-test")] {
            #expect(throws: TrashRefusal.outsideAllowedFolders, "\(url.path)") { try policy.check(url) }
        }
        #expect(!policy.allows(URL(fileURLWithPath: "/")))
        #expect(throws: TrashRefusal.notAnApp) { try policy.check(fixture.applications.appendingPathComponent("Setapp")) }
        #expect(throws: TrashRefusal.notAnApp) {
            try policy.check(fixture.applications.appendingPathComponent("Notely.app/Contents/Info.plist"))
        }
    }

    @Test func dotDotAndSymlinksCannotEscape() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        let escape = URL(fileURLWithPath: fixture.library.path + "/Caches/../../../../../../etc/hosts")
        #expect(!policy.allows(escape))
        // A folder in Caches that links to somewhere else: its contents aren't in Caches.
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("data"), withIntermediateDirectories: true)
        let link = fixture.library.appendingPathComponent("Caches/linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!policy.allows(link.appendingPathComponent("data")))
        // The link itself may go (it's moved as a link; the target stays).
        #expect(policy.allows(link))
    }

    @Test func realModeProtectsTheRealHomeLayout() {
        let env = TidyEnvironment.from(environment: [:], realHome: URL(fileURLWithPath: "/Users/someone"))
        let policy = TrashPolicy(environment: env)
        #expect(policy.allows(URL(fileURLWithPath: "/Users/someone/Library/Caches/com.example.App")))
        #expect(policy.allows(URL(fileURLWithPath: "/Applications/Example.app")))
        #expect(!policy.allows(URL(fileURLWithPath: "/Applications/Example Folder/readme.txt")))
        #expect(!policy.allows(URL(fileURLWithPath: "/Users/someone/Library/Mail")))
        #expect(!policy.allows(URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents")))
        #expect(!policy.allows(URL(fileURLWithPath: "/System/Library/Caches/x")))
        #expect(!policy.allows(URL(fileURLWithPath: "/Users/other/Library/Caches/x")))
        #expect(!policy.allows(URL(fileURLWithPath: "/Library/Caches")))
    }
}

@Suite("Moving to the Trash")
struct TrashServiceTests {
    @Test func movesToTheFixtureTrashAndPutsBack() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let fm = FileManager.default
        let app = fixture.applications.appendingPathComponent("Notely.app")
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        let result = service.moveToTrash([(app, 10), (prefs, 5)], stopIfFirstFails: true)
        #expect(result.failures.isEmpty)
        #expect(result.bytes == 15)
        #expect(!fm.fileExists(atPath: app.path))
        #expect(fm.fileExists(atPath: fixture.trash.appendingPathComponent("Notely.app").path))

        let back = service.putBack(result.moved)
        #expect(back.failures.isEmpty)
        #expect(fm.fileExists(atPath: app.path))
        #expect(fm.fileExists(atPath: prefs.path))
    }

    @Test func nameClashesInTheTrashGetNumbers() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let trasher = FolderTrasher(folder: fixture.trash)
        let a = fixture.library.appendingPathComponent("Caches/com.fixture.Notely")
        let b = fixture.library.appendingPathComponent("Containers/com.fixture.Notely")
        #expect(try trasher.moveToTrash(a).lastPathComponent == "com.fixture.Notely")
        #expect(try trasher.moveToTrash(b).lastPathComponent == "com.fixture.Notely 2")
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        try FileManager.default.copyItem(at: prefs, to: fixture.trash.appendingPathComponent("com.fixture.Notely.plist"))
        #expect(try trasher.moveToTrash(prefs).lastPathComponent == "com.fixture.Notely 2.plist")
    }

    @Test func refusedItemsStayAndAreReported() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let caches = fixture.library.appendingPathComponent("Caches")
        let result = service.moveToTrash([(caches, 0)])
        #expect(result.moved.isEmpty)
        #expect(result.failures.first?.message == TrashRefusal.protectedFolder.description)
        #expect(FileManager.default.fileExists(atPath: caches.path))
    }

    @Test func stopsWhenTheAppCantBeMoved() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let missing = fixture.applications.appendingPathComponent("Gone.app")
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        let result = service.moveToTrash([(missing, 0), (prefs, 0)], stopIfFirstFails: true)
        #expect(result.stoppedEarly)
        #expect(result.failures.first?.message == "It's no longer there.")
        #expect(FileManager.default.fileExists(atPath: prefs.path))
    }

    @Test func adminOnlyItemsFailWithAClearMessage() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let daemon = fixture.systemLibrary.appendingPathComponent("LaunchDaemons/com.fixture.Syncer.daemon.plist")
        let result = service.moveToTrash([(daemon, 0)])
        #expect(result.failures.first?.message.contains("permission") == true)
        #expect(FileManager.default.fileExists(atPath: daemon.path))
    }

    @Test func putBackDoesNotOverwrite() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        let result = service.moveToTrash([(prefs, 0)])
        FileManager.default.createFile(atPath: prefs.path, contents: Data("new".utf8))
        let back = service.putBack(result.moved)
        #expect(back.restored.isEmpty)
        #expect(back.failures.first?.message == "Something with the same name is already there.")
        #expect(try String(contentsOf: prefs, encoding: .utf8) == "new")

        // Keep Both: the trashed copy goes back next to the new one.
        let both = service.putBack(result.moved, keepBoth: true)
        #expect(both.failures.isEmpty)
        let restored = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely (restored).plist")
        #expect(both.restored.first?.original == restored)
        #expect(FileManager.default.fileExists(atPath: restored.path))
        #expect(try String(contentsOf: prefs, encoding: .utf8) == "new")
    }
}
