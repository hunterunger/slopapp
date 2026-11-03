import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Junk")
struct JunkTests {
    func scan(_ fixture: Fixture) -> [String: JunkItem] {
        let items = JunkScanner(environment: fixture.environment, runningBundleIDs: Fixture.runningIDs,
                                appNames: ["com.fixture.Notely": "Notely"]).scan()
        return Dictionary(uniqueKeysWithValues: items.map { (fixture.relative($0.url), $0) })
    }

    @Test func categorisesEverything() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = scan(fixture)
        let L = "home/Library/"
        #expect(items[L + "Caches/com.fixture.Notely"]?.category == .userCaches)
        #expect(items[L + "Caches/com.fixture.Notely"]?.name == "Notely")
        #expect(items[L + "Caches/Homebrew"]?.category == .packageCaches)
        #expect(items[L + "Caches/org.swift.swiftpm"]?.category == .packageCaches)
        #expect(items[L + "Caches/com.apple.dt.Xcode"]?.category == .xcodeCaches)
        #expect(items[L + "Logs/Notely"]?.category == .logs)
        #expect(items[L + "Logs/CoreSimulator/2D3C"]?.category == .logs)
        #expect(items[L + "Logs/DiagnosticReports/Notely-2026-10-01-101010.ips"]?.category == .crashReports)
        #expect(items[L + "Developer/CoreSimulator/Caches/dyld"]?.category == .simulatorCaches)
        #expect(items[L + "Developer/Xcode/UserData/Previews"]?.category == .xcodeCaches)
        #expect(items[L + "Developer/Xcode/DocumentationCache"]?.category == .xcodeCaches)
        #expect(items["home/.npm/_cacache"]?.category == .packageCaches)
        #expect(items["home/.gradle/caches"]?.isRecommended == false)
    }

    @Test func leavesMacOSItemsAlone() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let paths = scan(fixture).keys
        #expect(!paths.contains { $0.contains("com.apple.bird") || $0.contains("com.apple.xpc") })
        #expect(!paths.contains { $0.hasSuffix("Logs/DiagnosticReports") || $0.hasSuffix("Library/Caches") })
        // Every item is something the policy lets Tidy move.
        let policy = TrashPolicy(environment: fixture.environment)
        let items = JunkScanner(environment: fixture.environment).scan()
        #expect(items.allSatisfy { policy.allows($0.url) })
    }

    @Test func riskyItemsStartUnchecked() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = scan(fixture)
        let L = "home/Library/Developer/Xcode/"
        #expect(items["home/Library/Caches/com.fixture.Busybee"]?.isRecommended == false)
        #expect(items["home/Library/Caches/com.fixture.Busybee"]?.note == "App is running")
        #expect(items[L + "Archives/2026-05-01/MyApp 5-1-26, 10.00.xcarchive"]?.isRecommended == false)
        #expect(items[L + "Archives/2026-05-01/MyApp 5-1-26, 10.00.xcarchive"]?.category == .archives)
        #expect(items[L + "iOS DeviceSupport/18.2 (22C150)"]?.isRecommended == false)
        #expect(items[L + "iOS DeviceSupport/17.0 (21A329)"]?.isRecommended == true)
        #expect(items[L + "DerivedData/ModuleCache.noindex"]?.isRecommended == false)
        #expect(items[L + "DerivedData/MyApp-bxkfjqwmzrdhgnaefyeqtgsaulwo"]?.isRecommended == true)
    }

    @Test func derivedDataNames() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let items = scan(fixture)
        let L = "home/Library/Developer/Xcode/DerivedData/"
        #expect(items[L + "MyApp-bxkfjqwmzrdhgnaefyeqtgsaulwo"]?.name == "MyApp")
        let widgets = items[L + "Widgets-aqzkvhtgehdjtuyxtcawbwvhlpqm"]
        #expect(widgets?.name == "Widgets")
        #expect(widgets?.note == "Project not found")
        #expect(JunkScanner.derivedDataName("Odd-name") == "Odd-name")
    }

    @Test func emptyHomeHasNoJunk() throws {
        let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let env = TidyEnvironment.from(environment: ["TIDY_HOME": root.path], realHome: root)
        #expect(JunkScanner(environment: env).scan().isEmpty)
        #expect(LibraryIndex.build(env).entries.isEmpty)
        #expect(AppCatalog.scan(env.applicationDirectories).isEmpty)
    }
}

@Suite("Large and old files")
struct LargeFileTests {
    let unit: Int64 = 1_000

    @Test func findsLargeFilesAndSkipsPackagesHiddenAndLibrary() throws {
        let fixture = try makeFixture(unit: unit)
        defer { fixture.cleanUp() }
        let files = try #require(LargeFileScanner.forHome(fixture.environment, minimumSize: 25 * unit).scan())
        #expect(files.map(\.name) == ["Linux.iso", "Installer-2024.dmg", "Trip to the coast.mov", "project-2023.zip",
                                      "Interview recording.m4a", "Panorama.tiff"])
        #expect(files.first?.size == 1_200 * unit)
    }

    @Test func kinds() throws {
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.dmg")) == .diskImage)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.pkg")) == .diskImage)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.zip")) == .archive)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.mov")) == .video)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.m4a")) == .audio)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.tiff")) == .image)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.pdf")) == .document)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b")) == .other)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/b.iso")) == .diskImage)
    }

    @Test func filtersBySizeAgeAndKind() throws {
        let now = Date()
        let fixture = try makeFixture(unit: unit, now: now)
        defer { fixture.cleanUp() }
        let files = try #require(LargeFileScanner.forHome(fixture.environment, minimumSize: 10 * unit).scan())
        #expect(files.count == 7)
        let big = LargeFileFilter(minimumSize: 100 * unit).apply(files, now: now)
        #expect(big.map(\.name) == ["Linux.iso", "Installer-2024.dmg", "Trip to the coast.mov"])
        let old = LargeFileFilter(minimumSize: 10 * unit, olderThan: 365 * 86_400).apply(files, now: now)
        #expect(Set(old.map(\.name)) == ["Installer-2024.dmg", "project-2023.zip", "Panorama.tiff"])
        let videos = LargeFileFilter(minimumSize: 0, kind: .video).apply(files, now: now)
        #expect(videos.map(\.name) == ["Trip to the coast.mov"])
    }

    @Test func lastOpenedCountsWhenNewer() {
        let old = Date(timeIntervalSince1970: 0)
        let recent = Date(timeIntervalSince1970: 1_000_000)
        #expect(LargeFile(url: URL(fileURLWithPath: "/a.zip"), size: 1, modified: old, lastOpened: recent).lastUsed == recent)
        #expect(LargeFile(url: URL(fileURLWithPath: "/a.zip"), size: 1, modified: recent, lastOpened: old).lastUsed == recent)
    }

    @Test func cancelledScanReturnsNil() async throws {
        let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/cancel-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for i in 0..<3_000 { fm.createFile(atPath: root.appendingPathComponent("f\(i)").path, contents: Data([1])) }
        let scanner = LargeFileScanner(root: root, minimumSize: 1)
        let task = Task.detached { () -> [LargeFile]? in
            withUnsafeCurrentTask { $0?.cancel() }
            return scanner.scan()
        }
        #expect(await task.value == nil)
        #expect(scanner.scan()?.count == 3_000)
    }
}

@Suite("Disk usage")
struct DiskUsageTests {
    @Test func measuresFoldersAndCountsHardLinksOnce() throws {
        let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/usage-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data(repeating: 1, count: 100_000).write(to: root.appendingPathComponent("a/one.bin"))
        try Data(repeating: 2, count: 50_000).write(to: root.appendingPathComponent("a/b/two.bin"))
        try fm.linkItem(at: root.appendingPathComponent("a/one.bin"), to: root.appendingPathComponent("a/b/link.bin"))
        let usage = try #require(DiskUsage.measure(root))
        #expect(usage.files == 2)
        #expect(usage.bytes >= 150_000)
        #expect(usage.bytes < 250_000)
        let file = try #require(DiskUsage.measure(root.appendingPathComponent("a/one.bin")))
        #expect(file.files == 1 && file.bytes >= 100_000)
        #expect(DiskUsage.measure(root.appendingPathComponent("missing")) == nil)
    }

    @Test func formatting() {
        #expect(ByteFormat.string(0) == "0 KB")
        #expect(ByteFormat.string(1_500_000) == "1.5 MB")
    }
}
