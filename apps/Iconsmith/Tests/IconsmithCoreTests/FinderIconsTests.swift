import AppKit
import Testing
@testable import IconsmithCore

@MainActor @Suite struct FinderIconsTests {
    let icon = NSImage(cgImage: makeImage(width: 64, height: 64), size: NSSize(width: 64, height: 64))
    let a = URL(fileURLWithPath: "/tmp/iconsmith-test/a")
    let b = URL(fileURLWithPath: "/tmp/iconsmith-test/b")

    @Test func applyThenUndoThenRedo() {
        let fake = FakeFileIcons()
        let older = NSImage(size: NSSize(width: 8, height: 8))
        fake.icons[b.path] = older
        let applier = IconApplier(system: fake)
        let change = applier.apply(icon, to: [a, b, a])
        #expect(change.results.count == 2) // duplicates dropped
        #expect(change.results.allSatisfy { $0.outcome == .applied })
        #expect(change.summary == "Applied to 2 items")
        #expect(fake.icons[a.path] === icon)

        _ = applier.restore(change, toBefore: true)
        #expect(fake.icons[a.path] == nil)       // had none: back to default
        #expect(fake.icons[b.path] === older)    // had one: that one comes back

        let redo = applier.restore(change, toBefore: false)
        #expect(redo.allSatisfy { $0.outcome == .restored })
        #expect(fake.icons[a.path] === icon && fake.icons[b.path] === icon)
    }

    @Test func removeSkipsItemsWithoutCustomIcons() {
        let fake = FakeFileIcons()
        fake.icons[a.path] = icon
        let applier = IconApplier(system: fake)
        let change = applier.remove(from: [a, b])
        #expect(change.results[0].outcome == .removed)
        #expect(change.results[1].outcome == .unchanged("No custom icon"))
        #expect(change.summary == "Removed 1 custom icon")
        _ = applier.restore(change, toBefore: true)
        #expect(fake.icons[a.path] === icon)
    }

    @Test func refusalsExplainWhatToDo() {
        let fake = FakeFileIcons()
        let applier = IconApplier(system: fake)
        let cases: [(TargetInfo, String)] = [
            (TargetInfo(exists: false), "moved or deleted"),
            (TargetInfo(isApplication: true, isSystemApp: true), "come with macOS"),
            (TargetInfo(isApplication: true, isWritable: false), "administrator"),
            (TargetInfo(isLocked: true), "locked"),
            (TargetInfo(isWritable: false), "permission"),
            (TargetInfo(isVolume: true, isReadOnlyVolume: true), "read-only"),
        ]
        for (info, phrase) in cases {
            fake.infos[a.path] = info
            let change = applier.apply(icon, to: [a])
            guard case .failed(let message) = change.results[0].outcome else { Issue.record("expected failure"); continue }
            #expect(message.contains(phrase))
            #expect(change.changedCount == 0)
        }
        #expect(fake.setCalls == 0) // refused before touching anything
    }

    @Test func systemRefusalIsReportedPerItem() {
        let fake = FakeFileIcons()
        fake.refuseSet = [b.path]
        fake.infos[b.path] = TargetInfo(isVolume: true)
        let change = IconApplier(system: fake).apply(icon, to: [a, b])
        #expect(change.results[0].outcome == .applied)
        #expect(change.results[1].outcome == .failed("This disk’s format doesn’t keep custom icons."))
        #expect(change.summary == "Applied to 1 item, 1 failed")
    }

    @Test func allowedRootFencesTargets() {
        let fake = FakeFileIcons()
        let applier = IconApplier(system: fake, allowedRoot: URL(fileURLWithPath: "/tmp/iconsmith-test/fence"))
        let inside = URL(fileURLWithPath: "/tmp/iconsmith-test/fence/folder")
        let sneaky = URL(fileURLWithPath: "/tmp/iconsmith-test/fence-other")
        let change = applier.apply(icon, to: [inside, sneaky, URL(fileURLWithPath: "/Users")])
        #expect(change.results.map(\.outcome.isSuccess) == [true, false, false])
        #expect(IconApplier.allowedRoot(environment: ["ICONSMITH_ALLOWED_ROOT": "/tmp/iconsmith-test"]) != nil)
        #expect(IconApplier.allowedRoot(environment: [:]) == nil)
    }

    @Test func finderFlagsParse() {
        var info = [UInt8](repeating: 0, count: 32)
        #expect(FinderInfo.flags(info) & FinderInfo.hasCustomIconFlag == 0)
        info[8] = 0x04
        #expect(FinderInfo.flags(info) & FinderInfo.hasCustomIconFlag != 0)
    }

    /// The real system effect, only on items created under /tmp/iconsmith-test.
    @Test func realFolderAndFileRoundTrip() throws {
        let dir = try makeTestFolder()
        let folder = dir.appending(path: "Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = dir.appending(path: "notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let system = WorkspaceFileIcons()
        let applier = IconApplier(system: system, allowedRoot: URL(fileURLWithPath: "/tmp/iconsmith-test").resolvingSymlinksInPath())
        let image = IconRenderer(source: rasterSource()).multiResolutionImage(IconStyle())

        let change = applier.apply(image, to: [folder, file])
        #expect(change.results.allSatisfy { $0.outcome == .applied })
        #expect(system.hasCustomIcon(folder) && system.hasCustomIcon(file))
        #expect(FileManager.default.fileExists(atPath: folder.path + "/Icon\r"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello") // contents untouched

        _ = applier.restore(change, toBefore: true)
        #expect(!system.hasCustomIcon(folder) && !system.hasCustomIcon(file))

        _ = applier.apply(image, to: [folder])
        let removal = applier.remove(from: [folder, file])
        #expect(removal.results.map(\.outcome) == [.removed, .unchanged("No custom icon")])
        #expect(!system.hasCustomIcon(folder))

        // Undoing the removal puts the earlier custom icon back.
        _ = applier.restore(removal, toBefore: true)
        #expect(system.hasCustomIcon(folder))
        _ = applier.remove(from: [folder])
        #expect(!system.hasCustomIcon(folder))
    }

    @Test func blockedAppChangePointsToAppManagement() {
        let fake = FakeFileIcons()
        fake.infos[a.path] = TargetInfo(isApplication: true)
        fake.refuseSet = [a.path]
        let change = IconApplier(system: fake).apply(icon, to: [a])
        #expect(change.results[0].needsAppManagement)
        #expect(change.results[0].outcome.message.contains("App Management"))
        // A user's own app that macOS lets us change is just applied.
        fake.refuseSet = []
        #expect(IconApplier(system: fake).apply(icon, to: [a]).results[0].outcome == .applied)
    }

    @Test func realLockedFileIsRefusedAndOwnAppBundleChanges() throws {
        let dir = try makeTestFolder()
        let locked = dir.appending(path: "locked.txt")
        try "x".write(to: locked, atomically: true, encoding: .utf8)
        var values = URLResourceValues()
        values.isUserImmutable = true
        var lockedURL = locked
        try lockedURL.setResourceValues(values)
        defer { values.isUserImmutable = false; try? lockedURL.setResourceValues(values) }
        let app = dir.appending(path: "Fake.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let applier = IconApplier(system: WorkspaceFileIcons())
        let image = IconRenderer(source: rasterSource()).multiResolutionImage(IconStyle())
        let change = applier.apply(image, to: [locked, dir.appending(path: "Fake.app"), dir.appending(path: "gone")])
        let messages = change.results.map(\.outcome.message)
        #expect(messages[0].contains("locked"))
        #expect(messages[1] == "Icon applied")
        #expect(messages[2].contains("moved or deleted"))
        #expect(change.changedCount == 1)
        // Apple's own apps are refused before anything is touched.
        #expect(WorkspaceFileIcons().info(URL(fileURLWithPath: "/System/Applications/Calculator.app")).isSystemApp)
        let removal = applier.remove(from: [dir.appending(path: "Fake.app")])
        #expect(removal.results.first?.outcome == .removed)
    }
}

/// Opt-in: a disk image mounted under /tmp/iconsmith-test (see the research doc's build
/// notes). `ICONSMITH_TEST_VOLUME=/tmp/iconsmith-test/mnt swift test --filter volume`
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ICONSMITH_TEST_VOLUME"] != nil))
func volumeIconRoundTrip() throws {
    let path = try #require(ProcessInfo.processInfo.environment["ICONSMITH_TEST_VOLUME"])
    #expect(path.hasPrefix("/tmp/iconsmith-test/"))
    let volume = URL(fileURLWithPath: path)
    let system = WorkspaceFileIcons()
    #expect(system.info(volume).isVolume)
    let applier = IconApplier(system: system, allowedRoot: URL(fileURLWithPath: "/tmp/iconsmith-test").resolvingSymlinksInPath())
    let image = IconRenderer(source: rasterSource()).multiResolutionImage(IconStyle())
    let change = applier.apply(image, to: [volume])
    print("volume apply:", change.results.map(\.outcome))
    if change.results.first?.outcome == .applied {
        #expect(FileManager.default.fileExists(atPath: volume.appending(path: ".VolumeIcon.icns").path))
        let removal = applier.remove(from: [volume])
        #expect(removal.results.first?.outcome == .removed)
        #expect(!system.hasCustomIcon(volume))
    }
}
