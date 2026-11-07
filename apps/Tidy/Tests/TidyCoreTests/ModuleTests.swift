import CoreGraphics
import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Trash bins")
struct TrashBinTests {
    @Test func listsWhatsInTheTrashButNotDSStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let scan = TrashBinScanner(environment: fixture.environment).scan()
        #expect(scan.unreadable.isEmpty)
        #expect(Set(scan.items.map(\.name)) == ["Old invoice.pdf", "project-backup.zip", "Screenshots"])
        #expect(scan.items.first { $0.name == "Screenshots" }?.isDirectory == true)
    }

    @Test func emptyingErasesExactlyTheListedItemsIncludingReadOnlyFolders() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashBinService(environment: fixture.environment)
        let items = TrashBinScanner(environment: fixture.environment).scan().items
        // Something put in the Trash after the scan stays.
        try Data("new".utf8).write(to: fixture.trash.appendingPathComponent("added later.txt"))
        let result = service.erase(items.map { ($0.url, 10) })
        #expect(result.failures.isEmpty)
        #expect(result.erased.count == 3)
        #expect(result.bytes == 30)
        let left = try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).sorted()
        #expect(left == [".DS_Store", "added later.txt"])
    }

    @Test func refusesAnythingNotDirectlyInTheTrash() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashBinService(environment: fixture.environment)
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        let deep = fixture.trash.appendingPathComponent("Screenshots/Screen 1.png")
        let result = service.erase([(prefs, 0), (deep, 0), (fixture.trash, 0),
                                    (fixture.trash.appendingPathComponent("../home"), 0)])
        #expect(result.erased.isEmpty)
        #expect(result.failures.count == 4)
        #expect(FileManager.default.fileExists(atPath: prefs.path))
        #expect(FileManager.default.fileExists(atPath: deep.path))
        #expect(FileManager.default.fileExists(atPath: fixture.home.path))
    }

    @Test func realModeUsesTheHomeTrash() {
        let env = TidyEnvironment.from(environment: [:], realHome: URL(fileURLWithPath: "/Users/someone"))
        #expect(env.trashBins.map(\.path) == ["/Users/someone/.Trash"])
        #expect(env.maintenanceLog == nil)
    }

    @Test func unreadableTrashIsReported() throws {
        let fixture = try makeFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.trash.path)
            fixture.cleanUp()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.trash.path)
        let scan = TrashBinScanner(environment: fixture.environment).scan()
        #expect(scan.items.isEmpty)
        #expect(scan.unreadable.map(\.lastPathComponent) == ["Trash"])
    }
}

@Suite("Background items")
struct BackgroundItemTests {
    func scanner(_ fixture: Fixture) -> BackgroundItemScanner {
        // Programs under the fixture are checked for real; anything else counts as missing,
        // except /bin/sh, so results don't depend on this Mac.
        let root = fixture.root.path
        return BackgroundItemScanner(environment: fixture.environment, apps: AppCatalog.scan(fixture.environment.applicationDirectories)) { path in
            path == "/bin/sh" || (path.hasPrefix(root) && FileManager.default.fileExists(atPath: path))
        }
    }

    @Test func listsAgentsAndDaemonsWithOwnersAndBrokenOnes() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = Dictionary(uniqueKeysWithValues: scanner(fixture).launchItems().map { ($0.label, $0) })
        #expect(items["com.apple.fixture.example"] == nil)
        #expect(items["com.fixture.Notely.helper"]?.appName == "Notely")
        #expect(items["com.fixture.Notely.helper"]?.isBroken == false)
        #expect(items["com.fixture.Notely.helper"]?.runsAtLoad == true)
        // Owner found through the program inside the app, despite another vendor's label.
        #expect(items["com.othervendor.syncd"]?.appName == "Syncer")
        #expect(items["com.goneware.OldEditor.updater"]?.isBroken == true)
        #expect(items["com.goneware.OldEditor.updater"]?.appName == nil)
        #expect(items["com.toolmaker.agent"]?.isBroken == false)
        #expect(items["com.toolmaker.agent"]?.displayName == "sh")
        let daemon = try #require(items["com.fixture.Syncer.daemon"])
        #expect(daemon.scope == .systemDaemon)
        #expect(daemon.scope.needsAdmin)
        #expect(daemon.appName == "Syncer")
        #expect(items["com.fixture.Notely.helper"]?.scope == .userAgent)
    }

    @Test func userAgentsSortFirst() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let scopes = scanner(fixture).launchItems().map(\.scope)
        #expect(scopes == scopes.sorted())
        #expect(scopes.first == .userAgent)
    }

    @Test func userAgentsCanBeMovedToTheTrashSystemOnesCant() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = scanner(fixture).launchItems()
        let policy = TrashPolicy(environment: fixture.environment)
        let user = try #require(items.first { $0.label == "com.goneware.OldEditor.updater" })
        #expect(policy.allows(user.url))
        let service = TrashService(environment: fixture.environment)
        let daemon = try #require(items.first { $0.label == "com.fixture.Syncer.daemon" })
        let result = service.moveToTrash([(daemon.url, 0)])
        #expect(result.moved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: daemon.url.path))
    }

    @Test func appLoginItemsComeFromAppBundles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = scanner(fixture).appLoginItems()
        #expect(items.map(\.name) == ["Notely Launcher"])
        #expect(items.first?.appName == "Notely")
        #expect(items.first?.bundleID == "com.fixture.NotelyLauncher")
    }

    @Test func parsesLaunchctlList() {
        let output = "PID\tStatus\tLabel\n123\t0\tcom.acme.agent\n-\t78\tcom.acme.idle\n"
        let loaded = LaunchctlStatusReader.parse(output)
        #expect(loaded.count == 2)
        #expect(loaded["com.acme.agent"] == .some(123))
        #expect(loaded["com.acme.idle"] == .some(nil))
    }
}

@Suite("Maintenance")
struct MaintenanceTests {
    @Test func everyTaskRunsFixedSystemCommands() {
        for task in MaintenanceTask.allCases {
            #expect(!task.commands.isEmpty)
            for command in task.commands {
                #expect(command[0].hasPrefix("/usr/bin/"))
                #expect(!command.joined().contains("\""))
            }
        }
        #expect(MaintenanceTask.flushDNS.needsAdmin)
        #expect(!MaintenanceTask.resetQuickLook.needsAdmin)
    }

    @Test func noSpeedOrMemoryClaims() {
        for task in MaintenanceTask.allCases {
            let text = (task.title + " " + task.detail).lowercased()
            for word in ["speed", "ram", "memory", "faster", "optimi", "boost"] {
                #expect(!text.contains(word), "\(task.title) mentions \(word)")
            }
        }
    }

    @Test func testModeRecordsInsteadOfRunning() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let log = try #require(fixture.environment.maintenanceLog)
        #expect(log.path.hasPrefix(fixture.root.path))
        let runner = RecordingTaskRunner(log: log)
        try runner.run(.resetQuickLook)
        try runner.run(.flushDNS)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" resetQuickLook"))
        #expect(lines[1].hasSuffix(" flushDNS"))
    }

    @Test func simulatedFailuresAndCancel() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let log = try #require(fixture.environment.maintenanceLog)
        #expect(throws: TaskError.cancelled) { try RecordingTaskRunner(log: log, failing: ["cancel"]).run(.flushDNS) }
        #expect(throws: (any Error).self) { try RecordingTaskRunner(log: log, failing: ["clearFontCaches"]).run(.clearFontCaches) }
        try RecordingTaskRunner(log: log, failing: ["cancel"]).run(.resetQuickLook)
    }
}

@Suite("Mail downloads")
struct MailDownloadTests {
    @Test func onlyWithFullDiskAccessAndEditedOnesStartUnchecked() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let without = JunkScanner(environment: fixture.environment).scan()
        #expect(!without.contains { $0.category == .mailDownloads })
        let items = JunkScanner(environment: fixture.environment, includesProtected: true).scan().filter { $0.category == .mailDownloads }
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        #expect(byName.keys.sorted() == ["Contract draft.docx", "Invoice 2026-09.pdf"])
        #expect(byName["Invoice 2026-09.pdf"]?.isRecommended == true)
        #expect(byName["Contract draft.docx"]?.isRecommended == false)
    }

    @Test func policyAllowsMailDownloadsContentsOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let policy = TrashPolicy(environment: fixture.environment)
        let folder = JunkScanner.mailDownloadsFolder(in: fixture.library)
        #expect(policy.allows(folder.appendingPathComponent("6A1B2C3D-0000-4000-8000-000000000001")))
        #expect(!policy.allows(folder))
        #expect(!policy.allows(fixture.library.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail")))
        #expect(!policy.allows(fixture.library.appendingPathComponent("Containers/com.apple.mail")))
        #expect(!policy.allows(folder.appendingPathComponent("com.apple.something")))
    }
}

@Suite("Space map")
struct SpaceMapTests {
    @Test func sizesAddUpAndSmallItemsFoldIntoOther() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let root = try #require(SpaceScanner(root: fixture.home, minimumListedSize: 100_000).scan())
        let library = try #require(root.children.first { $0.name == "Library" })
        #expect(library.isDirectory)
        // Sizes are what's on disk, and a folder is at least the sum of what it lists.
        let listed = root.children.reduce(0) { $0 + $1.size } + root.otherSize
        #expect(root.size >= listed)
        #expect(root.children.map(\.size) == root.children.map(\.size).sorted(by: >))
        #expect(root.children.allSatisfy { $0.size >= 100_000 })
        // Agrees with DiskUsage.
        #expect(library.size == DiskUsage.measure(library.url)?.bytes)
    }

    @Test func packagesAreOneItem() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let root = try #require(SpaceScanner(root: fixture.applications, minimumListedSize: 1).scan())
        let notely = try #require(root.children.first { $0.name == "Notely.app" })
        #expect(notely.isPackage)
        #expect(notely.children.isEmpty)
        #expect(!notely.canOpen)
        #expect(notely.size >= 3_400_000)
    }

    @Test func excludedFoldersAreSkippedAndMarkPartial() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let excluded = SpaceScanner.protectedFolders(in: fixture.home)
        let root = try #require(SpaceScanner(root: fixture.home, excluded: excluded, minimumListedSize: 1).scan())
        #expect(root.isPartial)
        #expect(!root.children.contains { $0.name == "Documents" })
        let library = try #require(root.children.first { $0.name == "Library" })
        #expect(!library.children.contains { $0.name == "Containers" })
        #expect(library.children.contains { $0.name == "Caches" })
    }

    @Test func findLocatesNestedNodes() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let root = try #require(SpaceScanner(root: fixture.home, minimumListedSize: 1).scan())
        let caches = fixture.library.appendingPathComponent("Caches")
        #expect(root.find(caches)?.name == "Caches")
        #expect(root.find(URL(fileURLWithPath: "/somewhere/else")) == nil)
    }

    @Test func missingRootGivesNothing() {
        #expect(SpaceScanner(root: URL(fileURLWithPath: "/tmp/tidy-test/does-not-exist")).scan() == nil)
    }
}

@Suite("Treemap")
struct TreemapTests {
    @Test func areasMatchValuesAndFillTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.layout(values, in: rect)
        let total = values.reduce(0, +)
        for (value, r) in zip(values, rects) {
            let expected = value / total * Double(rect.width * rect.height)
            #expect(abs(Double(r.width * r.height) - expected) < 1)
            #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(r))
        }
        // No overlaps.
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height < 0.5)
            }
        }
    }

    @Test func shapesStayReasonablySquare() {
        let rects = Treemap.layout([6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        for r in rects {
            let ratio = max(r.width / r.height, r.height / r.width)
            #expect(ratio < 4)
        }
    }

    @Test func zeroValuesAndEmptyInput() {
        #expect(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        let rects = Treemap.layout([0, 5], in: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(rects[0] == .zero)
        #expect(rects[1] == CGRect(x: 0, y: 0, width: 10, height: 10))
    }
}
