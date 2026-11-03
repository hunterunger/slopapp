import AppKit
import Foundation
import ImageIO
import Testing
@testable import IconsmithCore

@Suite struct SourceTests {
    @Test func loadsPNGWithNameSizeAndEdges() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "logo.png")
        try writePNG(makeImage(width: 300, height: 200), to: url)
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.name == "logo")
        #expect(source.size == CGSize(width: 300, height: 200))
        #expect(!source.isVector)
        #expect(source.isSmall)
        #expect(!source.edges.isTransparent)
        let color = try #require(source.edges.color)
        #expect(color.red > 0.8 && color.green < 0.3)
        #expect(source.folder?.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
    }

    @Test func transparentLogoHasTransparentEdges() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "glyph.png")
        try writePNG(makeImage(width: 1024, height: 1024, transparentEdges: true), to: url)
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.edges.isTransparent)
        #expect(source.edges.hasAlpha)
        #expect(source.edges.color == nil)
        #expect(!source.isSmall)
    }

    @Test func hugeImagesAreDecodedAtMostMaxSize() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "huge.png")
        try writePNG(makeImage(width: 5000, height: 2500), to: url)
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.size == CGSize(width: 2048, height: 1024))
    }

    @Test func loadsSVGAsVector() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "mark.svg")
        try ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#0a8"/></svg>"##
            .write(to: url, atomically: true, encoding: .utf8)
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.isVector)
        #expect(!source.isSmall) // vectors are never "too small"
        #expect(source.edges.isTransparent)
        let image = try #require(IconRenderer(source: source).render(IconStyle(shape: .asIs), pixels: 64))
        #expect(pixel(image, 32, 32).a > 0.99)
        #expect(pixel(image, 1, 1).a < 0.01)
    }

    @Test func loadsPDFFirstPageAsVector() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "art.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
        pdf.fill(box)
        pdf.endPDFPage()
        pdf.closePDF()
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.isVector)
        #expect(abs(source.aspect - 2) < 0.01)
    }

    @Test func icnsUsesLargestImage() throws {
        let dir = try makeTestFolder()
        let iconset = dir.appending(path: "x.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for (points, scale) in IconExporter.macSizes {
            try writePNG(makeImage(width: points * scale, height: points * scale), to: iconset.appending(path: IconExporter.iconsetName(points: points, scale: scale)))
        }
        let icns = dir.appending(path: "x.icns")
        try ExportWriter.compileICNS(iconset: iconset, output: icns)
        let source = try SourceLoader.load(icns, icons: FakeIconProvider())
        #expect(source.size == CGSize(width: 1024, height: 1024))
    }

    @Test func folderAndOtherFilesUseTheirIcon() throws {
        let dir = try makeTestFolder()
        let source = try SourceLoader.load(dir, icons: FakeIconProvider())
        #expect(source.isFileIcon)
        #expect(source.isVector)
        let text = dir.appending(path: "notes.txt")
        try "hi".write(to: text, atomically: true, encoding: .utf8)
        #expect(try SourceLoader.load(text, icons: FakeIconProvider()).isFileIcon)
    }

    @Test func damagedImageGivesClearError() throws {
        let dir = try makeTestFolder()
        let url = dir.appending(path: "broken.png")
        try Data("not a png".utf8).write(to: url)
        #expect(throws: SourceError.unreadable("broken.png")) { try SourceLoader.load(url, icons: FakeIconProvider()) }
        let message = SourceError.unreadable("broken.png").errorDescription ?? ""
        #expect(message.contains("broken.png"))
    }

    @Test func missingFileGivesClearError() {
        let url = URL(fileURLWithPath: "/tmp/iconsmith-test/unit/does-not-exist.png")
        #expect(throws: SourceError.missing("does-not-exist.png")) { try SourceLoader.load(url, icons: FakeIconProvider()) }
    }

    @Test func cmykAndSixteenBitAreNormalized() throws {
        let cmyk = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceCMYK(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        cmyk.setFillColor(CGColor(genericCMYKCyan: 1, magenta: 0, yellow: 0, black: 0, alpha: 1))
        cmyk.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let normalized = try #require(Bitmap.normalized(cmyk.makeImage()!))
        #expect(normalized.bitsPerComponent == 8)
        #expect(normalized.colorSpace?.name == CGColorSpace.sRGB)

        let deep = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 16, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        deep.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        deep.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(Bitmap.normalized(deep.makeImage()!)?.bitsPerComponent == 8)
    }

    @Test func exifOrientationIsApplied() throws {
        // A 40x20 image tagged "rotated 90°" must load as 20x40.
        let dir = try makeTestFolder()
        let url = dir.appending(path: "rotated.jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, makeImage(width: 40, height: 20), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let source = try SourceLoader.load(url, icons: FakeIconProvider())
        #expect(source.size == CGSize(width: 20, height: 40))
    }

    @Test func pastedImageLoads() throws {
        let image = NSImage(cgImage: makeImage(width: 128, height: 128), size: NSSize(width: 128, height: 128))
        let source = try SourceLoader.load(image: image)
        #expect(source.name == "Pasted Image")
        #expect(source.url == nil)
        #expect(source.folder == nil)
        #expect(source.size.width == 128)
    }

    @Test func edgeAnalysisThresholds() {
        // Opaque grey all over.
        let grey = EdgeInfo.analyze(pixels: { _, _ in (128, 128, 128, 255) }, size: 8)
        #expect(!grey.isTransparent && !grey.hasAlpha)
        #expect(abs((grey.color?.red ?? 0) - 128.0 / 255) < 0.01)
        // Fully transparent border.
        let cutout = EdgeInfo.analyze(pixels: { x, y in (1...6).contains(x) && (1...6).contains(y) ? (0, 0, 0, 255) : (0, 0, 0, 0) }, size: 8)
        #expect(cutout.isTransparent && cutout.hasAlpha && cutout.color == nil)
    }
}
