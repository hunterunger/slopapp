import CoreGraphics
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import SquishCore

@Suite struct SquisherTests {
    func bigJPEG(in folder: URL, name: String = "photo.jpg") -> URL {
        writeImage(makeImage(width: 800, height: 600), to: folder.appendingPathComponent(name), type: .jpeg, quality: 1.0)
    }

    @Test func savesSmallerCopyNextToOriginal() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let result = try await Squisher(settings: SquishSettings()).run(input)
        guard case .saved(let url, let bytes) = result else { Issue.record("\(result)"); return }
        #expect(url.lastPathComponent == "photo-small.jpg")
        #expect(bytes == fileSize(url))
        #expect(bytes < fileSize(input))
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func neverWritesABiggerFile() async throws {
        let folder = try makeTempFolder()
        let input = writeImage(makeImage(width: 300, height: 200), to: folder.appendingPathComponent("tiny.jpg"), type: .jpeg, quality: 0.1)
        let store = FakeFileStore()
        let result = try await Squisher(settings: SquishSettings(), files: store).run(input)
        guard case .keptOriginal = result else { Issue.record("\(result)"); return }
        #expect(store.written.isEmpty)
    }

    @Test func numbersNamesThatAreTaken() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let store = FakeFileStore()
        store.seed(folder.appendingPathComponent("photo-small.jpg"))
        let result = try await Squisher(settings: SquishSettings(), files: store).run(input)
        #expect(result.savedURL?.lastPathComponent == "photo-small 2.jpg")
    }

    @Test func retryOverwritesItsOwnEarlierOutput() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let store = FakeFileStore()
        let previous = folder.appendingPathComponent("photo-small.jpg")
        store.seed(previous)
        let result = try await Squisher(settings: SquishSettings(), files: store).run(input, previousOutput: previous)
        #expect(result.savedURL == previous)
        #expect(store.written.count == 1)
        // But never the input itself.
        let again = try await Squisher(settings: SquishSettings(), files: store).run(input, previousOutput: input)
        #expect(again.savedURL != input)
    }

    @Test func replaceTrashesOriginalAndTakesItsName() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let store = FakeFileStore()
        let result = try await Squisher(settings: settings, files: store).run(input)
        #expect(result.savedURL == input)
        #expect(store.trashed == [input])
        #expect(store.written.keys.sorted() == [input.path])
    }

    @Test func replaceLeavesEverythingAloneWhenTrashFails() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let store = FakeFileStore()
        store.failTrash = true
        await #expect(throws: OutputError.self) { try await Squisher(settings: settings, files: store).run(input) }
        #expect(store.written.isEmpty)
    }

    @Test func replaceForReal() async throws {
        let folder = try makeTempFolder()
        let name = "squish-unit-\(UUID().uuidString)"
        let input = bigJPEG(in: folder, name: name + ".jpg")
        let before = fileSize(input)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        settings.format = .heic
        // A stand-in Trash, so tests never touch the user's.
        let trash = folder.appendingPathComponent("Trash")
        let result = try await Squisher(settings: settings, files: SystemFileStore(trashFolder: trash)).run(input)
        #expect(result.savedURL?.lastPathComponent == name + ".heic")
        #expect(!FileManager.default.fileExists(atPath: input.path))
        #expect(fileSize(trash.appendingPathComponent(name + ".jpg")) == before)
        #expect(fileSize(try #require(result.savedURL)) < before)
    }

    @Test func putBackRestoresTheOriginal() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let before = try Data(contentsOf: input)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let trash = folder.appendingPathComponent("Trash")
        let store = SystemFileStore(trashFolder: trash)
        let registry = ReplacementRegistry()
        let result = try await Squisher(settings: settings, files: store, replacements: registry).run(input)
        #expect(result.savedURL == input)
        let replacement = try #require(registry.replacement(outputAt: input))
        #expect(replacement.original == input && replacement.output == input)
        #expect(try Data(contentsOf: input) != before)

        try replacement.putBack(files: store)
        #expect(try Data(contentsOf: input) == before)
        // The compressed copy went to the (stand-in) Trash; a second put-back can't happen.
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).count == 1)
        #expect(throws: OutputError.cantPutBack("photo.jpg")) { try replacement.putBack(files: store) }
    }

    /// Round 2 data-loss bug: replace, compress again twice (once with a new format),
    /// then put back must return the byte-identical original.
    @Test func compressAgainStartsFromTheOriginalAndPutBackIsExact() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let originalMD5 = try md5(input)
        let trash = folder.appendingPathComponent("Trash")
        let store = SystemFileStore(trashFolder: trash)
        let registry = ReplacementRegistry()
        var settings = SquishSettings()
        settings.destination = .replaceOriginal

        let first = try #require(try await Squisher(settings: settings, files: store, replacements: registry).run(input).savedURL)
        let firstMD5 = try md5(first)
        settings.apply(.small)
        let second = try #require(try await Squisher(settings: settings, files: store, replacements: registry)
            .run(first, previousOutput: first).savedURL)
        #expect(second == input)
        #expect(try md5(second) != firstMD5)          // re-encoded…
        #expect(store.isMarkedAsOutput(second))
        let secondSize = fileSize(second)
        settings.apply(.high)
        let third = try #require(try await Squisher(settings: settings, files: store, replacements: registry)
            .run(second, previousOutput: second).savedURL)
        // …from the original, not from the previous copy: High from the original is
        // bigger than the Smallest copy it replaced.
        let thirdSize = fileSize(third)
        #expect(thirdSize > secondSize)
        // Only the original was ever trashed; no look-alike copies.
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path) == ["photo.jpg"])
        #expect(try md5(trash.appendingPathComponent("photo.jpg")) == originalMD5)

        settings.format = .heic
        let fourth = try #require(try await Squisher(settings: settings, files: store, replacements: registry)
            .run(third, previousOutput: third).savedURL)
        #expect(fourth.lastPathComponent == "photo.heic")
        #expect(!FileManager.default.fileExists(atPath: input.path))

        let replacement = try #require(registry.replacement(outputAt: fourth))
        try replacement.putBack(files: store)
        #expect(try md5(input) == originalMD5)
        #expect(!FileManager.default.fileExists(atPath: fourth.path))
    }

    @Test func putBackRefusesAChangedOriginal() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let trash = folder.appendingPathComponent("Trash")
        let store = SystemFileStore(trashFolder: trash)
        let registry = ReplacementRegistry()
        _ = try await Squisher(settings: settings, files: store, replacements: registry).run(input)
        let replacement = try #require(registry.replacement(outputAt: input))
        try Data("not the original".utf8).write(to: replacement.trashed)
        #expect(throws: OutputError.originalChanged("photo.jpg")) { try replacement.putBack(files: store) }
        #expect(FileManager.default.fileExists(atPath: input.path)) // nothing moved
    }

    @Test func putBackAfterFormatChange() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        settings.format = .heic
        let store = SystemFileStore(trashFolder: folder.appendingPathComponent("Trash"))
        let registry = ReplacementRegistry()
        let log = ReplacementLog()
        _ = try await Squisher(settings: settings, files: store, replacements: registry, onReplace: { log.add($0) }).run(input)
        let replacement = try #require(log.all.first)
        #expect(replacement.output.lastPathComponent == "photo.heic")
        try replacement.putBack(files: store)
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(!FileManager.default.fileExists(atPath: replacement.output.path))
    }

    @Test func ourOwnEarlierCopyIsReplacedNotNumbered() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let first = try #require(try await Squisher(settings: SquishSettings()).run(input).savedURL)
        // A new run that doesn't know about the first (e.g. after Clear List).
        let second = try #require(try await Squisher(settings: SquishSettings()).run(input).savedURL)
        #expect(second == first)
        // A user's own file with that name is never overwritten.
        try FileManager.default.removeItem(at: first)
        try Data([1, 2, 3]).write(to: first)
        let third = try #require(try await Squisher(settings: SquishSettings()).run(input).savedURL)
        #expect(third.lastPathComponent == "photo-small 2.jpg")
        #expect(try Data(contentsOf: first) == Data([1, 2, 3]))
    }

    @Test func putBackAsksFirstWhenTheCopyWasEdited() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let originalMD5 = try md5(input)
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let store = SystemFileStore(trashFolder: folder.appendingPathComponent("Trash"))
        let registry = ReplacementRegistry()
        _ = try await Squisher(settings: settings, files: store, replacements: registry).run(input)
        let replacement = try #require(registry.replacement(outputAt: input))
        #expect(!replacement.outputWasEdited(files: store))
        try Data("my edits".utf8).write(to: input)
        #expect(throws: OutputError.outputEdited("photo.jpg")) { try replacement.putBack(files: store) }
        #expect(try Data(contentsOf: input) == Data("my edits".utf8)) // untouched
        try replacement.putBack(files: store, evenIfEdited: true)
        #expect(try md5(input) == originalMD5)
    }

    @Test func registrySurvivesARelaunch() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let originalMD5 = try md5(input)
        let storage = folder.appendingPathComponent("state/replaced.json")
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let store = SystemFileStore(trashFolder: folder.appendingPathComponent("Trash"))
        _ = try await Squisher(settings: settings, files: store, replacements: ReplacementRegistry(storage: storage)).run(input)

        let relaunched = ReplacementRegistry(storage: storage)
        let replacement = try #require(relaunched.replacement(outputAt: input))
        try replacement.putBack(files: store)
        relaunched.remove(replacement)
        #expect(try md5(input) == originalMD5)
        #expect(ReplacementRegistry(storage: storage).all.isEmpty)
    }

    @Test func registryForgetsOriginalsEmptiedFromTheTrash() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let storage = folder.appendingPathComponent("replaced.json")
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        let trash = folder.appendingPathComponent("Trash")
        _ = try await Squisher(settings: settings, files: SystemFileStore(trashFolder: trash),
                               replacements: ReplacementRegistry(storage: storage)).run(input)
        try FileManager.default.removeItem(at: trash)
        #expect(ReplacementRegistry(storage: storage).all.isEmpty)
    }

    @Test func formatSwitchBackLeavesNoOrphans() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        let jpg = try #require(try await Squisher(settings: settings).run(input).savedURL)
        settings.format = .heic
        let heic = try #require(try await Squisher(settings: settings).run(input, previousOutput: jpg).savedURL)
        #expect(!FileManager.default.fileExists(atPath: jpg.path))
        settings.format = .original
        let back = try #require(try await Squisher(settings: settings).run(input, previousOutput: heic).savedURL)
        #expect(back.lastPathComponent == "photo-small.jpg")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["photo-small.jpg", "photo.jpg"])
    }

    @Test func outputsAreMarked() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let out = try #require(try await Squisher(settings: SquishSettings()).run(input).savedURL)
        #expect(SystemFileStore().isMarkedAsOutput(out))
        #expect(!SystemFileStore().isMarkedAsOutput(input))
    }

    @Test func folderDestinationMustExist() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var settings = SquishSettings()
        settings.destination = .folder(folder.appendingPathComponent("gone"))
        await #expect(throws: OutputError.noFolder("gone")) { try await Squisher(settings: settings).run(input) }
        settings.destination = .folder(folder.appendingPathComponent("out"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("out"), withIntermediateDirectories: true)
        let result = try await Squisher(settings: settings).run(input)
        #expect(result.savedURL?.path == folder.appendingPathComponent("out/photo.jpg").path)
    }

    @Test func emptyAndUnknownFilesFail() async throws {
        let folder = try makeTempFolder()
        let empty = folder.appendingPathComponent("empty.png")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        await #expect(throws: SquishError.empty("empty.png")) { try await Squisher(settings: SquishSettings()).run(empty) }
        let text = folder.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: text)
        await #expect(throws: SquishError.self) { try await Squisher(settings: SquishSettings()).run(text) }
    }

    @Test func gifIsSkippedNotFailed() async throws {
        let folder = try makeTempFolder()
        let gif = writeImage(makeImage(width: 40, height: 40), to: folder.appendingPathComponent("a.gif"), type: .gif)
        let result = try await Squisher(settings: SquishSettings()).run(gif)
        guard case .skipped = result else { Issue.record("\(result)"); return }
    }
}

@Suite struct PDFTests {
    func makePDF(_ url: URL, image: CGImage?, pages: Int = 2) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            if let image { ctx.draw(image, in: CGRect(x: 36, y: 36, width: 540, height: 720)) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    @Test func imagesInsideShrinkAndPagesStay() async throws {
        let folder = try makeTempFolder()
        let url = folder.appendingPathComponent("scan.pdf")
        makePDF(url, image: makeImage(width: 1700, height: 2200))
        let result = try await Squisher(settings: SquishSettings()).run(url)
        let out = try #require(result.savedURL)
        #expect(fileSize(out) < fileSize(url) / 2)
        #expect(PDFDocument(url: out)?.pageCount == 2)
    }

    @Test func lockedPDFSaysWhatToDo() async throws {
        let folder = try makeTempFolder()
        let plain = folder.appendingPathComponent("plain.pdf")
        makePDF(plain, image: makeImage(width: 200, height: 200), pages: 1)
        let locked = folder.appendingPathComponent("locked.pdf")
        PDFDocument(url: plain)!.write(to: locked, withOptions: [.userPasswordOption: "a", .ownerPasswordOption: "b"])
        await #expect(throws: SquishError.lockedPDF("locked.pdf")) { try await Squisher(settings: SquishSettings()).run(locked) }

        let protected = folder.appendingPathComponent("protected.pdf")
        PDFDocument(url: plain)!.write(to: protected, withOptions: [.ownerPasswordOption: "b"])
        let result = try await Squisher(settings: SquishSettings()).run(protected)
        guard case .skipped = result else { Issue.record("\(result)"); return }
    }

    @Test func filterUsesPresetResolution() {
        var s = SquishSettings()
        s.apply(.small)
        let props = PDFCompressor.filterProperties(s.pdf)
        let image = ((props["FilterData"] as? [String: Any])?["ColorSettings"] as? [String: Any])?["ImageSettings"] as? [String: Any]
        let scale = image?["ImageScaleSettings"] as? [String: Any]
        #expect(scale?["ImageResolution"] as? Int == 96)
        #expect(image?["Compression Quality"] as? Double == 0.5)
    }
}

extension SquishResult {
    var savedURL: URL? {
        if case .saved(let url, _) = self { return url }
        return nil
    }
}

final class ReplacementLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Replacement] = []
    var all: [Replacement] { lock.withLock { items } }
    func add(_ r: Replacement) { lock.withLock { items.append(r) } }
}

@Suite struct ErrorWordingTests {
    static let all: [SquishError] = [.unreadable("Holiday.jpg"), .empty("Holiday.jpg"),
                                     .encodeFailed("Holiday.jpg"), .lockedPDF("Holiday.jpg")]

    /// Rows show the name already; the message shouldn't repeat it, and should say what to do.
    @Test(arguments: all) func messageLeavesOutTheNameAndSaysWhatToDo(_ error: SquishError) {
        let text = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        #expect(!text.contains("Holiday"))
        #expect(error.recoverySuggestion?.isEmpty == false)
        // Fits a 300 pt list row in three caption lines.
        #expect(text.count <= 80)
    }

    @Test func onlyEncodeFailuresAreWorthRetrying() {
        #expect(Self.all.filter(\.isWorthRetrying) == [.encodeFailed("Holiday.jpg")])
    }
}

@Suite struct MemoryBudgetTests {
    @Test func heavyFilesRunAloneLightOnesTogether() async {
        let budget = MemoryBudget(limit: 100)
        await budget.acquire(30)
        await budget.acquire(30)
        #expect(await budget.inUse == 60)
        // Over the limit: waits for everything else, then runs alone.
        let heavy = Task { await budget.acquire(500); return await budget.inUse }
        try? await Task.sleep(for: .milliseconds(30))
        await budget.release(30)
        await budget.release(30)
        #expect(await heavy.value == 100)
        await budget.release(500)
        #expect(await budget.inUse == 0)
    }

    @Test func estimatesFollowTheEncoder() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 1000, height: 1000), to: folder.appendingPathComponent("a.jpg"), type: .jpeg)
        var s = SquishSettings()
        let jpeg = MemoryBudget.estimate(for: url, kind: .image(.jpeg), settings: s, fileBytes: 1)
        s.format = .avif
        let avif = MemoryBudget.estimate(for: url, kind: .image(.jpeg), settings: s, fileBytes: 1)
        s.maxDimension = 500
        let smallAVIF = MemoryBudget.estimate(for: url, kind: .image(.jpeg), settings: s, fileBytes: 1)
        #expect(jpeg < avif && smallAVIF < avif)
        #expect(MemoryBudget.estimate(for: url, kind: .pdf, settings: s, fileBytes: 50 << 20) == 400 << 20)
    }
}
