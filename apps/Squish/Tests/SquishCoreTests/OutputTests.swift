import Foundation
import Testing
@testable import SquishCore

@Suite struct OutputPlannerTests {
    let input = URL(fileURLWithPath: "/Users/me/Pictures/Trip/photo.JPG")

    @Test func alongsideAddsSuffixAndKeepsFolder() {
        let url = OutputPlanner.preferredURL(for: input, ext: "JPG", settings: SquishSettings())
        #expect(url.path == "/Users/me/Pictures/Trip/photo-small.JPG")
    }

    @Test func emptyOrUnsafeSuffixFallsBack() {
        var settings = SquishSettings()
        settings.suffix = "   "
        #expect(OutputPlanner.preferredURL(for: input, ext: "jpg", settings: settings).lastPathComponent == "photo-small.jpg")
        settings.suffix = " web/2:x "
        #expect(OutputPlanner.preferredURL(for: input, ext: "jpg", settings: settings).lastPathComponent == "photoweb-2-x.jpg")
    }

    @Test func folderKeepsNameButAddsSuffixInSameFolder() {
        var settings = SquishSettings()
        settings.destination = .folder(URL(fileURLWithPath: "/tmp/out"))
        #expect(OutputPlanner.preferredURL(for: input, ext: "jpg", settings: settings).path == "/tmp/out/photo.jpg")
        settings.destination = .folder(URL(fileURLWithPath: "/Users/me/Pictures/Trip/"))
        #expect(OutputPlanner.preferredURL(for: input, ext: "jpg", settings: settings).lastPathComponent == "photo-small.jpg")
    }

    @Test func replaceUsesOriginalPathWithNewExtension() {
        var settings = SquishSettings()
        settings.destination = .replaceOriginal
        #expect(OutputPlanner.preferredURL(for: input, ext: "JPG", settings: settings) == input)
        #expect(OutputPlanner.preferredURL(for: input, ext: "heic", settings: settings).lastPathComponent == "photo.heic")
    }

    @Test func candidatesNumberLikeFinder() {
        let list = OutputPlanner.candidates(for: URL(fileURLWithPath: "/a/photo-small.jpg"), limit: 4)
        #expect(list.map(\.lastPathComponent) == ["photo-small.jpg", "photo-small 2.jpg", "photo-small 3.jpg", "photo-small 4.jpg"])
    }

    @Test func extensionKeepsUserSpellingWhenTypeIsSame() {
        #expect(SquishTypes.fileExtension(for: .jpeg, keeping: "JPEG") == "JPEG")
        #expect(SquishTypes.fileExtension(for: .heic, keeping: "png") == "heic")
        #expect(SquishTypes.fileExtension(for: .jpeg, keeping: "png") == "jpg")
    }
}

@Suite struct SystemFileStoreTests {
    @Test func createNeverClobbers() throws {
        let folder = try makeTempFolder()
        let url = folder.appendingPathComponent("a.bin")
        let store = SystemFileStore()
        try store.create(Data([1, 2, 3]), at: url)
        #expect(throws: OutputError.exists) { try store.create(Data([9]), at: url) }
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        // No temp files left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.bin"])
    }

    @Test func overwriteAndMove() throws {
        let folder = try makeTempFolder()
        let a = folder.appendingPathComponent("a.bin"), b = folder.appendingPathComponent("b.bin")
        let store = SystemFileStore()
        try store.create(Data([1]), at: a)
        try store.overwrite(Data([2, 2]), at: a)
        #expect(try store.size(of: a) == 2)
        try store.create(Data([3]), at: b)
        #expect(throws: OutputError.exists) { try store.move(a, to: b) }
        try store.move(a, to: folder.appendingPathComponent("c.bin"))
        #expect(!store.fileExists(a))
    }

    @Test func missingFolderSaysSo() {
        let url = URL(fileURLWithPath: "/tmp/squish-test/unit/does-not-exist-\(UUID())/a.bin")
        #expect(throws: OutputError.self) { try SystemFileStore().create(Data([1]), at: url) }
    }
}

@Suite struct SettingsTests {
    @Test func presetsGetSmaller() {
        var s = SquishSettings()
        let presets = [CompressionPreset.high, .balanced, .small]
        let qualities = presets.map { p -> Double in s.apply(p); return s.imageQuality }
        #expect(qualities == qualities.sorted(by: >))
        let dpis = presets.map { p -> Int in s.apply(p); return s.pdf.resolution }
        #expect(dpis == dpis.sorted(by: >))
        s.apply(.high)
        #expect(s.pngMode == .lossless)
        s.apply(.balanced)
        #expect(s.pngMode == .palette(colors: 256))
        #expect(s.presetID == "balanced")
    }

    @Test func valuesAreClamped() {
        var s = SquishSettings()
        s.quality = 5
        s.pdfResolution = 10
        s.pdfQuality = 0
        #expect(s.imageQuality == 1)
        #expect(s.pdf.resolution == 50)
        #expect(s.pdf.quality == 0.1)
    }

    @Test func roundTripsAndToleratesMissingKeys() throws {
        var s = SquishSettings()
        s.apply(.small)
        s.resize = .fit(width: 1600, height: 900)
        s.destination = .subfolder("Web")
        s.format = .heic
        s.metadata = .removeLocation
        s.pdfGrayscale = true
        s.keepFileDates = true
        s.pngColors = nil
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(SquishSettings.self, from: data) == s)
        let partial = try JSONDecoder().decode(SquishSettings.self, from: Data(#"{"quality":0.9,"format":"nonsense"}"#.utf8))
        #expect(partial.quality == 0.9)
        #expect(partial.format == .original)
        #expect(partial.stripMetadata)
    }

    @Test func settingsFromVersion01Migrate() throws {
        let old = #"{"preset":"small","maxDimension":1920,"stripMetadata":false,"format":"jpeg","suffix":"-web","destination":{"alongside":{}}}"#
        let s = try JSONDecoder().decode(SquishSettings.self, from: Data(old.utf8))
        #expect(s.options == CompressionOptions(quality: 0.55, pngColors: 128, resize: .longestEdge(1920), format: .jpeg,
                                                metadata: .keepAll, pdfResolution: 96, pdfQuality: 0.5))
        #expect(s.presetID == "small")
        #expect(s.suffix == "-web")
        let custom = try JSONDecoder().decode(SquishSettings.self, from: Data(#"{"preset":"custom","customQuality":0.95,"customPDFResolution":300}"#.utf8))
        #expect(custom.quality == 0.95 && custom.pdfResolution == 300 && custom.pngColors == nil)
    }

    @Test func formatChoicesFollowTheEncoder() {
        let caps = EncoderCapabilities(writableTypes: ["public.jpeg", "public.png"])
        #expect(caps.formatChoices == [.original, .jpeg, .png])
        #expect(EncoderCapabilities.system.formatChoices.contains(.heic))
    }
}

@Suite struct OutputFilterTests {
    @Test func skipsOnlyFilesSquishTagged() throws {
        let folder = try makeTempFolder()
        let names = ["a.jpg", "a-small.jpg", "holiday-small.png", "tagged.jpg"]
        let urls = try names.map { name -> URL in
            let url = folder.appendingPathComponent(name)
            try Data([1]).write(to: url)
            return url
        }
        SystemFileStore().markAsOutput(urls[3])
        let (keep, skipped) = OutputFilter.split(urls)
        // Names alone never count: a user's own "-small" files are compressed.
        #expect(keep.map(\.lastPathComponent) == ["a.jpg", "a-small.jpg", "holiday-small.png"])
        #expect(skipped == 1)
    }
}
