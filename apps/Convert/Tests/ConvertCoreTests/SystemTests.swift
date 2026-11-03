import ConvertFixtures
import Foundation
import Testing
@testable import ConvertCore

@MainActor
final class FakeBlocker: SleepBlocker {
    var holds = 0
    var releases = 0
    var isHeld = false
    func hold(reason: String) -> Bool {
        if !isHeld { holds += 1 }
        isHeld = true
        return true
    }
    func release() {
        if isHeld { releases += 1 }
        isHeld = false
    }
}

@MainActor
@Suite struct KeepAwakeTests {
    @Test func holdsOnlyWhileBusy() {
        let fake = FakeBlocker()
        let awake = KeepAwake(blocker: fake)
        awake.update(busy: true)
        awake.update(busy: true)
        #expect(fake.isHeld && fake.holds == 1 && awake.isHolding)
        awake.update(busy: false)
        #expect(!fake.isHeld && fake.releases == 1)
        awake.update(busy: false)
        #expect(fake.releases == 1)
    }
}

/// Records scratch files so tests can check they're always cleaned up.
final class RecordingFileStore: FileStore, @unchecked Sendable {
    let real = SystemFileStore()
    private let lock = NSLock()
    private var _made: [URL] = []
    private var _cleaned = 0
    var made: [URL] { lock.withLock { _made } }
    var cleaned: Int { lock.withLock { _cleaned } }

    func size(of url: URL) -> Int64? { real.size(of: url) }
    func fileExists(_ url: URL) -> Bool { real.fileExists(url) }
    func isDirectory(_ url: URL) -> Bool { real.isDirectory(url) }
    func isWritableDirectory(_ url: URL) -> Bool { real.isWritableDirectory(url) }
    func scratch(for fileName: String, near folder: URL) throws -> (url: URL, cleanup: @Sendable () -> Void) {
        let scratch = try real.scratch(for: fileName, near: folder)
        lock.withLock { _made.append(scratch.url) }
        return (scratch.url, { [self] in
            scratch.cleanup()
            lock.withLock { _cleaned += 1 }
        })
    }
    func moveExclusive(_ source: URL, to target: URL) throws { try real.moveExclusive(source, to: target) }
    func replace(_ target: URL, with source: URL) throws { try real.replace(target, with: source) }
    func copyDates(from source: URL, to target: URL) { real.copyDates(from: source, to: target) }
}

@Suite struct ScratchTests {
    @Test func scratchIsCleanedUpOnSuccessFailureAndCancel() async throws {
        let store = RecordingFileStore()
        let input = try videoFixture { $0.width = 1280; $0.height = 720; $0.seconds = 4; $0.codec = .hevc }
        var c = Converter(settings: ConvertSettings())
        c.files = store
        _ = try await c.run(input)
        // A failure after writing (the GIF target refused by a fake capability check
        // happens before writing, so use a silent clip's audio-only target instead).
        let silent = try videoFixture("silent.mov") { $0.audioTracks = 0 }
        var audioOnly = c
        audioOnly.settings.video = .audioWAV
        await #expect(throws: ConvertError.self) { try await audioOnly.run(silent) }
        let task = Task { try await c.run(input) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        _ = await task.result
        #expect(store.cleaned == store.made.count)
        for url in store.made {
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        }
    }

    @Test func scratchIsOnTheSameVolumeAndHidden() throws {
        let folder = try makeTempFolder()
        let scratch = try SystemFileStore().scratch(for: "a.mp4", near: folder)
        defer { scratch.cleanup() }
        #expect(scratch.url.lastPathComponent == "a.mp4")
        #expect(!scratch.url.path.hasPrefix(folder.path))
        let volume = { (url: URL) in try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject }
        #expect(volume(scratch.url.deletingLastPathComponent()) == volume(folder))
    }
}

@Suite struct GIFStreamTests {
    @Test func changedRegionFindsTheDifference() {
        let w = 10, h = 8
        let a = [UInt8](repeating: 100, count: w * h * 4)
        var b = a
        #expect(GIFStreamWriter.changedRegion(a, b, width: w, height: h) == nil)
        // Small noise is ignored.
        b[0] = 104
        #expect(GIFStreamWriter.changedRegion(a, b, width: w, height: h) == nil)
        b[(3 * w + 2) * 4] = 200
        b[(5 * w + 6) * 4 + 1] = 0
        #expect(GIFStreamWriter.changedRegion(a, b, width: w, height: h) == CGRect(x: 2, y: 3, width: 5, height: 3))
    }

    @Test func mostlyStillClipsMakeSmallGIFs() async throws {
        // The fixture's bar moves across a still background: only the bar's area is stored.
        let input = try videoFixture { $0.width = 640; $0.height = 360; $0.seconds = 2 }
        let result = try report(try await converter { $0.video = .gif }.run(input))
        let fullFrames = 24 * 640 * 360 / 4 // a rough floor for 24 full LZW frames
        #expect(result.bytes < Int64(fullFrames))
    }
}
