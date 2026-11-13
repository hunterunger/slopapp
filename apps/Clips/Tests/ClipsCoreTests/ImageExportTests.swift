import Foundation
import ImageIO
import Testing
@testable import ClipsCore

@Suite struct ImageExportTests {
    private let created = Date(timeIntervalSince1970: 1_794_306_735) // 2026-11-10 10:32:15 UTC
    private let utc = TimeZone(identifier: "UTC")!

    @Test func namesLikeAScreenshot() {
        #expect(ImageExport.fileName(created: created, type: PasteboardType.png, timeZone: utc)
            == "Image 2026-11-10 at 10.32.15.png")
    }

    @Test func keepsStoredFormatsExceptTIFF() {
        #expect(ImageExport.fileExtension(forType: PasteboardType.jpeg) == "jpeg")
        #expect(ImageExport.fileExtension(forType: PasteboardType.heic) == "heic")
        #expect(ImageExport.fileExtension(forType: PasteboardType.tiff) == "png")
        #expect(ImageExport.fileExtension(forType: nil) == "png")
    }

    @Test func writesMatchingDataAsIs() {
        let png = makePNG(width: 4, height: 3)
        let data = ImageExport.fileData(for: Representation(type: PasteboardType.png, data: png), fileExtension: "png")
        #expect(data == png)
    }

    @Test func convertsTIFFToPNG() throws {
        let tiff = try reencode(makePNG(width: 5, height: 2), as: PasteboardType.tiff)
        let data = try #require(ImageExport.fileData(for: Representation(type: PasteboardType.tiff, data: tiff),
                                                     fileExtension: "png"))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG signature
        #expect(ImageInfo.pixelSize(of: data) == (5, 2))
    }

    @Test func picksTheImageRepresentation() {
        let reps = [Representation(type: PasteboardType.string, data: Data("x".utf8)),
                    Representation(type: PasteboardType.jpeg, data: Data([1]))]
        #expect(ImageExport.image(in: reps)?.type == PasteboardType.jpeg)
    }

    @Test func unreadableDataGivesNothing() {
        #expect(ImageExport.fileData(for: Representation(type: PasteboardType.tiff, data: Data([1, 2, 3])),
                                     fileExtension: "png") == nil)
    }

    private func reencode(_ data: Data, as type: String) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
