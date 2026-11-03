import Foundation
import Testing
@testable import SlopappCore

/// End-to-end against real bundles, zips, ditto and the Security framework, all under
/// /tmp/slopapp-test/unit. Only the network is replaced (file:// URLs).
@Suite(.serialized) struct InstallerTests {
    func installer(teamID: String? = nil, local: Bool = true, downloader: any Downloading = Network(),
                   trash: URL? = nil) -> Installer {
        Installer(
            downloader: downloader, unarchiver: DittoUnarchiver(), files: LocalFiles(trashDirectory: trash),
            signatures: LocalAppLocator(), policy: SignaturePolicy(requiredTeamID: teamID),
            urlPolicy: URLPolicy(allowsLocal: local)
        )
    }

    /// A zip of Tiny <version> and its feed entry.
    func release(_ version: String, in dir: URL, sign: Bool = true, bundleID: String = "app.slopapp.tiny") -> FeedApp {
        let src = dir.appendingPathComponent("src-\(version)-\(UUID().uuidString.prefix(4))", isDirectory: true)
        let app = Fixture.makeApp(in: src, bundleID: bundleID, version: version, sign: sign)
        let zip = dir.appendingPathComponent("Tiny-\(version)-\(UUID().uuidString.prefix(4)).zip")
        Fixture.zip(app, to: zip)
        return Fixture.feedApp(zip: zip, version: version)
    }

    @Test func realSignatureChecks() {
        let dir = Fixture.tempDir("sig")
        let signed = Fixture.makeApp(in: dir.appendingPathComponent("a"))
        let info = CodeSignature.check(signed)
        #expect(info.isValid)
        #expect(info.isAdHoc)
        #expect(info.identifier == "app.slopapp.tiny")
        #expect(info.verifiedTeamID == nil)

        let unsigned = Fixture.makeApp(in: dir.appendingPathComponent("b"), sign: false)
        #expect(!CodeSignature.check(unsigned).isValid)

        let tampered = Fixture.makeApp(in: dir.appendingPathComponent("c"))
        try! Data("changed".utf8).write(to: tampered.appendingPathComponent("Contents/MacOS/Tiny"))
        #expect(!CodeSignature.check(tampered).isValid)
    }

    @Test func installsAVerifiedApp() async throws {
        let dir = Fixture.tempDir("install")
        let feedApp = release("1.0.0", in: dir)
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        let phases = PhaseLog()
        let result = try await installer().install(InstallRequest(app: feedApp, destination: dest), progress: { phases.add($0) })
        #expect(result.verdict == .developmentBuild)
        #expect(LocalAppLocator.readInfo(at: dest)?.version == "1.0.0")
        #expect(CodeSignature.check(dest).isValid)
        #expect(phases.all.first == .downloading(0))
        #expect(phases.all.contains(.verifying))
        #expect(phases.all.last == .installing)
        // Nothing left behind next to the app.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path) == ["Tiny.app"])
    }

    @Test func updatesInPlace() async throws {
        let dir = Fixture.tempDir("update")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        _ = try await installer().install(InstallRequest(app: release("1.0.0", in: dir), destination: dest))
        let old = InstalledCopy(url: dest, info: .app("app.slopapp.tiny", "1.0.0"), location: .managed, signature: CodeSignature.check(dest))
        let quitCalled = Flag()
        _ = try await installer().install(InstallRequest(app: release("1.1.0", in: dir), destination: dest, replacing: old),
                                          beforeReplace: { quitCalled.set() })
        #expect(quitCalled.value)
        #expect(LocalAppLocator.readInfo(at: dest)?.version == "1.1.0")
    }

    @Test func checksumMismatchChangesNothing() async throws {
        let dir = Fixture.tempDir("sha")
        var feedApp = release("1.0.0", in: dir)
        feedApp.sha256 = String(repeating: "0", count: 64)
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        await #expect(throws: InstallError.checksumMismatch) {
            try await installer().install(InstallRequest(app: feedApp, destination: dest))
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func refusesBrokenSignatures() async throws {
        let dir = Fixture.tempDir("badsig")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        await #expect(throws: InstallError.signature(.invalid)) {
            try await installer().install(InstallRequest(app: release("1.0.0", in: dir, sign: false), destination: dest))
        }
        // Tampered after signing.
        let src = dir.appendingPathComponent("tampered", isDirectory: true)
        let app = Fixture.makeApp(in: src)
        try Data("evil".utf8).write(to: app.appendingPathComponent("Contents/MacOS/Tiny"))
        let zip = dir.appendingPathComponent("tampered.zip")
        Fixture.zip(app, to: zip)
        await #expect(throws: InstallError.signature(.invalid)) {
            try await installer().install(InstallRequest(app: Fixture.feedApp(zip: zip), destination: dest))
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func requiredTeamRejectsAdHoc() async throws {
        let dir = Fixture.tempDir("team")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        await #expect(throws: InstallError.signature(.unsignedNotAllowed)) {
            try await installer(teamID: "ABCDE12345").install(InstallRequest(app: release("1.0.0", in: dir), destination: dest))
        }
    }

    @Test func corruptZip() async throws {
        let dir = Fixture.tempDir("corrupt")
        let zip = dir.appendingPathComponent("Tiny.zip")
        try Data(repeating: 0x50, count: 4096).write(to: zip)
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        await #expect(throws: InstallError.damagedArchive) {
            try await installer().install(InstallRequest(app: Fixture.feedApp(zip: zip), destination: dest))
        }
    }

    @Test func wrongBundleOrVersionInsideTheZip() async throws {
        let dir = Fixture.tempDir("mismatch")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        var other = release("1.0.0", in: dir, bundleID: "com.someone.else")
        other.bundleId = "app.slopapp.tiny"
        await #expect(throws: InstallError.bundleMismatch) {
            try await installer().install(InstallRequest(app: other, destination: dest))
        }
        var lying = release("1.0.0", in: dir)
        lying.version = "2.0.0"
        await #expect(throws: InstallError.versionMismatch(found: "1.0.0")) {
            try await installer().install(InstallRequest(app: lying, destination: dest))
        }
    }

    @Test func offlineAndMissingDownloads() async throws {
        let dir = Fixture.tempDir("offline")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        let feedApp = release("1.0.0", in: dir)
        await #expect(throws: InstallError.offline) {
            try await installer(downloader: FailingDownloader(error: .offline)).install(InstallRequest(app: feedApp, destination: dest))
        }
        var missing = feedApp
        missing.downloadUrl = dir.appendingPathComponent("nope.zip")
        await #expect(throws: InstallError.notFound) {
            try await installer().install(InstallRequest(app: missing, destination: dest))
        }
    }

    @Test func cancellingADownloadLeavesNothing() async throws {
        let dir = Fixture.tempDir("cancel")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        let app = release("1.0.0", in: dir)
        let task = Task {
            try await installer(downloader: HangingDownloader()).install(InstallRequest(app: app, destination: dest))
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path).isEmpty)
    }

    @Test func productionRefusesNonHTTPSDownloads() async throws {
        let dir = Fixture.tempDir("https")
        await #expect(throws: InstallError.insecureURL) {
            try await installer(local: false).install(InstallRequest(app: release("1.0.0", in: dir), destination: dir.appendingPathComponent("A/Tiny.app")))
        }
    }

    @Test func tooNewMacOS() async throws {
        let dir = Fixture.tempDir("macos")
        var app = release("1.0.0", in: dir)
        app.minimumMacOS = "99.0"
        await #expect(throws: InstallError.requiresNewerMacOS("99.0")) {
            try await installer().install(InstallRequest(app: app, destination: dir.appendingPathComponent("A/Tiny.app")))
        }
    }

    @Test func refusingToQuitLeavesTheOldCopy() async throws {
        let dir = Fixture.tempDir("running")
        let dest = dir.appendingPathComponent("Applications/Tiny.app")
        _ = try await installer().install(InstallRequest(app: release("1.0.0", in: dir), destination: dest))
        await #expect(throws: InstallError.appWouldNotQuit) {
            try await installer().install(InstallRequest(app: release("1.1.0", in: dir), destination: dest),
                                          beforeReplace: { throw InstallError.appWouldNotQuit })
        }
        #expect(LocalAppLocator.readInfo(at: dest)?.version == "1.0.0")
    }

    @Test func uninstallMovesAppAndDataToTrashAndPutsBack() throws {
        let dir = Fixture.tempDir("uninstall")
        let trash = dir.appendingPathComponent("Trash", isDirectory: true)
        let library = dir.appendingPathComponent("Library", isDirectory: true)
        let app = Fixture.makeApp(in: dir.appendingPathComponent("Applications"))
        let support = library.appendingPathComponent("Application Support/app.slopapp.tiny", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        let prefs = library.appendingPathComponent("Preferences/app.slopapp.tiny.plist")
        try Data("{}".utf8).write(to: prefs)
        let copy = InstalledCopy(url: app, info: .app("app.slopapp.tiny", "1.0.0"), location: .managed)
        let uninstaller = Uninstaller(files: LocalFiles(trashDirectory: trash), library: library)

        let keepData = try uninstaller.uninstall(copy, removeData: false)
        #expect(keepData.moved.count == 1)
        #expect(FileManager.default.fileExists(atPath: support.path))
        try uninstaller.putBack(keepData)
        #expect(FileManager.default.fileExists(atPath: app.path))

        let all = try uninstaller.uninstall(copy, removeData: true)
        #expect(all.moved.count == 3)
        #expect(all.removedPreferences)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        #expect(!FileManager.default.fileExists(atPath: support.path))
        #expect(!FileManager.default.fileExists(atPath: prefs.path))
        try uninstaller.putBack(all)
        #expect(FileManager.default.fileExists(atPath: prefs.path))
    }

    @Test func checksumOfAKnownFile() throws {
        let file = Fixture.tempDir("hash").appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try Checksum.sha256(file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [InstallPhase] = []
    func add(_ phase: InstallPhase) { lock.withLock { phases.append(phase) } }
    var all: [InstallPhase] { lock.withLock { phases } }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    func set() { lock.withLock { isSet = true } }
    var value: Bool { lock.withLock { isSet } }
}
