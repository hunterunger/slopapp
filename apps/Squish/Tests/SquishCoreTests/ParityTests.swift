import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import SquishCore

@Suite struct ResizeModeTests {
    let landscape = CGSize(width: 4000, height: 3000)

    @Test func eachModeKeepsTheAspectRatio() {
        #expect(ResizeMode.longestEdge(2000).targetSize(for: landscape) == CGSize(width: 2000, height: 1500))
        #expect(ResizeMode.width(1000).targetSize(for: landscape) == CGSize(width: 1000, height: 750))
        #expect(ResizeMode.height(600).targetSize(for: landscape) == CGSize(width: 800, height: 600))
        #expect(ResizeMode.fit(width: 1000, height: 1000).targetSize(for: landscape) == CGSize(width: 1000, height: 750))
        #expect(ResizeMode.fit(width: 4000, height: 600).targetSize(for: landscape) == CGSize(width: 800, height: 600))
        #expect(ResizeMode.percent(25).targetSize(for: landscape) == CGSize(width: 1000, height: 750))
    }

    @Test func neverEnlarges() {
        #expect(ResizeMode.none.targetSize(for: landscape) == nil)
        #expect(ResizeMode.longestEdge(4000).targetSize(for: landscape) == nil)
        #expect(ResizeMode.width(8000).targetSize(for: landscape) == nil)
        #expect(ResizeMode.height(3000).targetSize(for: landscape) == nil)
        #expect(ResizeMode.fit(width: 5000, height: 5000).targetSize(for: landscape) == nil)
    }

    @Test func switchingModesKeepsTheNumber() {
        #expect(ResizeMode.longestEdge(1280).switching(to: .width) == .width(1280))
        #expect(ResizeMode.width(1280).switching(to: .fit) == .fit(width: 1280, height: 1280))
        #expect(ResizeMode.none.switching(to: .percent) == .percent(50))
        #expect(ResizeMode.percent(30).switching(to: .percent) == .percent(30))
    }
}

@Suite struct PresetLibraryTests {
    @Test func builtInsComeFirstAndCantChange() {
        var library = PresetLibrary()
        #expect(library.all.map(\.name) == ["High Quality", "Balanced", "Smallest File"])
        library.update(id: "balanced", options: CompressionOptions.small)
        library.rename(id: "balanced", to: "Mine")
        library.delete(id: "balanced")
        #expect(library.all == CompressionPreset.builtIns)
        #expect(CompressionPreset.balanced.isBuiltIn)
    }

    @Test func addRenameUpdateDelete() {
        var library = PresetLibrary()
        var options = CompressionOptions.balanced
        options.format = .jpeg
        options.resize = .longestEdge(1600)
        let web = library.add(name: "Web", options: options)
        #expect(!web.isBuiltIn)
        #expect(library.preset(id: web.id)?.options.format == .jpeg)
        // Names stay unique (case-insensitively), also against built-ins.
        #expect(library.add(name: "web", options: options).name == "web 2")
        #expect(library.add(name: "Balanced", options: options).name == "Balanced 2")
        #expect(library.add(name: "  ", options: options).name == "My Preset")

        library.rename(id: web.id, to: "Blog")
        #expect(library.preset(id: web.id)?.name == "Blog")
        library.rename(id: web.id, to: "Balanced 2")
        #expect(library.preset(id: web.id)?.name == "Balanced 2 2")

        options.quality = 0.4
        library.update(id: web.id, options: options)
        #expect(library.preset(id: web.id)?.options.quality == 0.4)

        library.delete(id: web.id)
        #expect(library.preset(id: web.id) == nil)
        #expect(library.custom.count == 3)
    }

    @Test func reorders() {
        var library = PresetLibrary()
        let a = library.add(name: "A", options: .balanced)
        let b = library.add(name: "B", options: .balanced)
        let c = library.add(name: "C", options: .balanced)
        library.move(fromOffsets: [2], toOffset: 0)
        #expect(library.custom.map(\.id) == [c.id, a.id, b.id])
        library.move(fromOffsets: [0], toOffset: 3)
        #expect(library.custom.map(\.id) == [a.id, b.id, c.id])
    }

    @Test func roundTrips() throws {
        var library = PresetLibrary()
        var options = CompressionOptions.small
        options.resize = .percent(50)
        options.pdfGrayscale = true
        library.add(name: "Print", options: options)
        let data = try JSONEncoder().encode(library)
        #expect(try JSONDecoder().decode(PresetLibrary.self, from: data) == library)
    }

    @Test func applyingAPresetLeavesTheDestinationAlone() {
        var s = SquishSettings()
        s.destination = .replaceOriginal
        s.suffix = "-web"
        s.apply(.small)
        #expect(s.destination == .replaceOriginal)
        #expect(s.suffix == "-web")
        #expect(s.options == CompressionOptions.small)
    }
}

@Suite struct ParityImageTests {
    let caps = EncoderCapabilities.system

    func compress(_ url: URL, _ settings: SquishSettings, type: UTType = .jpeg) throws -> Encoded {
        try ImageCompressor.compress(url, inputType: type, settings: settings, capabilities: caps)
    }

    @Test func widthHeightAndPercentModes() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 800, height: 400), to: folder.appendingPathComponent("a.jpg"), type: .jpeg)
        var s = SquishSettings()
        s.resize = .width(400)
        var image = try decoded(try compress(url, s).data)
        #expect(image.width == 400 && image.height == 200)
        s.resize = .height(100)
        image = try decoded(try compress(url, s).data)
        #expect(image.width == 200 && image.height == 100)
        s.resize = .percent(25)
        image = try decoded(try compress(url, s).data)
        #expect(image.width == 200 && image.height == 100)
        s.resize = .fit(width: 300, height: 300)
        image = try decoded(try compress(url, s).data)
        #expect(image.width == 300 && image.height == 150)
    }

    @Test func widthMeansTheDisplayedWidthOfRotatedPhotos() throws {
        let folder = try makeTempFolder()
        // Stored 400×200, shown rotated (portrait 200×400).
        let url = writeImage(makeImage(width: 400, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg,
                             properties: [kCGImagePropertyOrientation: 6])
        var s = SquishSettings()
        s.resize = .width(100)
        let image = try decoded(try compress(url, s).data)
        #expect(image.width == 100 && image.height == 200)
    }

    @Test func removeLocationOnlyKeepsCameraDetails() throws {
        let folder = try makeTempFolder()
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.0, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test Lens"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Calgary", kCGImagePropertyIPTCByline: ["Me"]],
        ]
        let url = writeImage(makeImage(width: 300, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg, properties: props)
        var s = SquishSettings()
        s.metadata = .removeLocation
        let out = imageProperties(try compress(url, s).data)
        #expect(out[kCGImagePropertyGPSDictionary] == nil)
        #expect((out[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String == "Test Lens")
        let iptc = out[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(iptc?[kCGImagePropertyIPTCCity] == nil)
    }

    @Test func progressiveJPEG() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 300, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg)
        var s = SquishSettings()
        s.progressiveJPEG = true
        let jfif = imageProperties(try compress(url, s).data)[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
        #expect(jfif?[kCGImagePropertyJFIFIsProgressive] as? Bool == true)
        s.progressiveJPEG = false
        let plain = imageProperties(try compress(url, s).data)[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
        #expect(plain?[kCGImagePropertyJFIFIsProgressive] as? Bool != true)
    }
}

@Suite struct ParityOutputTests {
    func bigJPEG(in folder: URL) -> URL {
        writeImage(makeImage(width: 800, height: 600), to: folder.appendingPathComponent("photo.jpg"), type: .jpeg, quality: 1.0)
    }

    @Test func subfolderIsCreatedNextToTheOriginal() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        var s = SquishSettings()
        s.destination = .subfolder("Web/../Ready")
        let out = try #require(try await Squisher(settings: s).run(input).savedURL)
        #expect(out.path == folder.appendingPathComponent("Web-..-Ready/photo.jpg").path)
        #expect(FileManager.default.fileExists(atPath: input.path))
        // Again: overwrites its own copy rather than numbering.
        let again = try #require(try await Squisher(settings: s).run(input, previousOutput: out).savedURL)
        #expect(again == out)
    }

    @Test func subfolderNamesAreCleaned() {
        #expect(Destination.cleanSubfolderName("  ") == "Compressed")
        #expect(Destination.cleanSubfolderName(".hidden") == "hidden")
        #expect(Destination.cleanSubfolderName("a/b:c") == "a-b-c")
    }

    @Test func keepsFileDatesWhenAsked() async throws {
        let folder = try makeTempFolder()
        let input = bigJPEG(in: folder)
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: input.path)
        var s = SquishSettings()
        s.keepFileDates = true
        let out = try #require(try await Squisher(settings: s).run(input).savedURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: out.path)
        #expect((attributes[.modificationDate] as? Date) == old)
        #expect((attributes[.creationDate] as? Date) == old)

        s.keepFileDates = false
        let fresh = try #require(try await Squisher(settings: s).run(input, previousOutput: out).savedURL)
        let modified = try FileManager.default.attributesOfItem(atPath: fresh.path)[.modificationDate] as? Date
        #expect(modified != old)
    }
}

@Suite struct ParityPDFTests {
    func makePDF(_ url: URL, image: CGImage, pages: Int = 2) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: CGRect(x: 36, y: 36, width: 540, height: 720))
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// The color of a page's center, rendered.
    func centerColor(_ url: URL) throws -> (Int, Int, Int) {
        let page = try #require(PDFDocument(url: url)?.page(at: 0)?.pageRef)
        let ctx = CGContext(data: nil, width: 61, height: 79, bitsPerComponent: 8, bytesPerRow: 61 * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.scaleBy(x: 0.1, y: 0.1)
        ctx.drawPDFPage(page)
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = 39 * 61 * 4 + 30 * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    @Test func grayscaleTurnsPagesGray() async throws {
        try #require(PDFCompressor.canGrayscale)
        let folder = try makeTempFolder()
        let url = folder.appendingPathComponent("color.pdf")
        makePDF(url, image: makeImage(width: 1700, height: 2200))
        let before = try centerColor(url)
        #expect(abs(before.0 - before.2) > 30)   // colorful to start with
        var s = SquishSettings()
        s.pdfGrayscale = true
        let out = try #require(try await Squisher(settings: s).run(url).savedURL)
        let after = try centerColor(out)
        #expect(abs(after.0 - after.1) <= 6 && abs(after.1 - after.2) <= 6)
        #expect(PDFDocument(url: out)?.pageCount == 2)
    }

    @Test func filterCarriesGrayscaleOnlyWhenAsked() {
        let plain = PDFCompressor.filterProperties(PDFSettings(resolution: 144, quality: 0.7))
        #expect((plain["FilterData"] as? [String: Any])?["FilterProfileArray"] == nil)
        let gray = PDFCompressor.filterProperties(PDFSettings(resolution: 144, quality: 0.7, grayscale: true))
        #expect(((gray["FilterData"] as? [String: Any])?["FilterProfileArray"] as? [Data])?.isEmpty == false)
    }

    @Test func factsCountPagesAndImages() throws {
        let folder = try makeTempFolder()
        let url = folder.appendingPathComponent("scan.pdf")
        makePDF(url, image: makeImage(width: 200, height: 300), pages: 3)
        let facts = try #require(FileFacts.read(url))
        #expect(facts.pageCount == 3)
        #expect(facts.imageCount == 3)
        #expect(facts.summary == "PDF · 3 pages · 3 images")
    }
}

@Suite struct FileFactsTests {
    @Test func imageSizeIsAsDisplayed() throws {
        let folder = try makeTempFolder()
        let plain = writeImage(makeImage(width: 400, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg)
        #expect(FileFacts.read(plain)?.summary == "JPEG · 400 × 200")
        let rotated = writeImage(makeImage(width: 400, height: 200), to: folder.appendingPathComponent("b.png"), type: .png,
                                 properties: [kCGImagePropertyOrientation: 6])
        #expect(FileFacts.read(rotated)?.summary == "PNG · 200 × 400")
    }
}
