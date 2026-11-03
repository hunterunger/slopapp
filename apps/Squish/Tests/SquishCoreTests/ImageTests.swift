import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SquishCore

@Suite struct ImageCompressorTests {
    let caps = EncoderCapabilities.system

    @Test func jpegGetsSmallerAndStaysValid() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 600, height: 400), to: folder.appendingPathComponent("a.jpg"), type: .jpeg)
        let out = try ImageCompressor.compress(url, inputType: .jpeg, settings: SquishSettings(), capabilities: caps)
        #expect(out.type == .jpeg)
        #expect(Int64(out.data.count) < fileSize(url))
        let image = try #require(decode(out.data))
        #expect(image.width == 600 && image.height == 400)
    }

    @Test func resizeOnlyShrinksAndKeepsAspect() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 800, height: 400), to: folder.appendingPathComponent("a.png"), type: .png)
        var settings = SquishSettings()
        settings.maxDimension = 200
        let small = try decoded(try ImageCompressor.compress(url, inputType: .png, settings: settings, capabilities: caps).data)
        #expect(small.width == 200 && small.height == 100)
        settings.maxDimension = 5000
        let same = try decoded(try ImageCompressor.compress(url, inputType: .png, settings: settings, capabilities: caps).data)
        #expect(same.width == 800)
    }

    @Test func stripsLocationButKeepsOrientation() throws {
        let folder = try makeTempFolder()
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.0, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test Lens"],
        ]
        let url = writeImage(makeImage(width: 300, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg, properties: props)
        var settings = SquishSettings()
        let stripped = imageProperties(try ImageCompressor.compress(url, inputType: .jpeg, settings: settings, capabilities: caps).data)
        #expect(stripped[kCGImagePropertyGPSDictionary] == nil)
        #expect((stripped[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] == nil)
        #expect(stripped[kCGImagePropertyOrientation] as? Int == 6)

        settings.stripMetadata = false
        let kept = imageProperties(try ImageCompressor.compress(url, inputType: .jpeg, settings: settings, capabilities: caps).data)
        #expect(kept[kCGImagePropertyGPSDictionary] != nil)
        #expect(kept[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func resizingBakesInOrientation() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 400, height: 200), to: folder.appendingPathComponent("a.jpg"), type: .jpeg,
                             properties: [kCGImagePropertyOrientation: 6])
        var settings = SquishSettings()
        settings.maxDimension = 100
        let out = try ImageCompressor.compress(url, inputType: .jpeg, settings: settings, capabilities: caps)
        let image = try #require(decode(out.data))
        // Rotated 90°: now portrait, tagged upright.
        #expect(image.width == 50 && image.height == 100)
        #expect(imageProperties(out.data)[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
    }

    @Test func gifsAndAnimationsAreSkipped() throws {
        let folder = try makeTempFolder()
        let gif = writeImage(makeImage(width: 20, height: 20), to: folder.appendingPathComponent("a.gif"), type: .gif)
        #expect(throws: Skip.self) { try ImageCompressor.compress(gif, inputType: .gif, settings: SquishSettings(), capabilities: caps) }

        let apng = folder.appendingPathComponent("anim.png")
        let dest = CGImageDestinationCreateWithURL(apng as CFURL, UTType.png.identifier as CFString, 2, nil)!
        CGImageDestinationAddImage(dest, makeImage(width: 20, height: 20), nil)
        CGImageDestinationAddImage(dest, makeImage(width: 20, height: 20, flat: true), nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(throws: Skip.self) { try ImageCompressor.compress(apng, inputType: .png, settings: SquishSettings(), capabilities: caps) }
    }

    @Test func unwritableFormatIsSkippedWithAHint() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 20, height: 20), to: folder.appendingPathComponent("a.png"), type: .png)
        let noPNG = EncoderCapabilities(writableTypes: ["public.jpeg"])
        do {
            _ = try ImageCompressor.compress(url, inputType: .png, settings: SquishSettings(), capabilities: noPNG)
            Issue.record("expected a skip")
        } catch let skip as Skip {
            #expect(skip.reason.contains("Format"))
        }
        var settings = SquishSettings()
        settings.format = .webp
        #expect(throws: Skip.self) { try ImageCompressor.compress(url, inputType: .png, settings: settings, capabilities: noPNG) }
    }

    @Test func pngWithAlphaToJPEGIsFlattenedOnWhite() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeStripes([(0, 0, 0, 0)], width: 8, height: 8), to: folder.appendingPathComponent("clear.png"), type: .png)
        var settings = SquishSettings()
        settings.format = .jpeg
        let out = try ImageCompressor.compress(url, inputType: .png, settings: settings, capabilities: caps)
        #expect(out.type == .jpeg)
        let rgba = try decodeRGBA(out.data)
        #expect(rgba.pixels[0] > 240 && rgba.pixels[1] > 240 && rgba.pixels[2] > 240)
    }

    @Test func uncompressedTIFFGetsLZW() throws {
        let folder = try makeTempFolder()
        let url = writeImage(makeImage(width: 300, height: 200, flat: true), to: folder.appendingPathComponent("a.tiff"), type: .tiff)
        let out = try ImageCompressor.compress(url, inputType: .tiff, settings: SquishSettings(), capabilities: caps)
        #expect(out.type == .tiff)
        #expect(Int64(out.data.count) < fileSize(url) / 2)
        #expect(((imageProperties(out.data)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int) == 5)
    }

    @Test func unreadableFileThrows() throws {
        let folder = try makeTempFolder()
        let url = folder.appendingPathComponent("bad.jpg")
        try Data("nope".utf8).write(to: url)
        #expect(throws: SquishError.unreadable("bad.jpg")) {
            try ImageCompressor.compress(url, inputType: .jpeg, settings: SquishSettings(), capabilities: caps)
        }
    }
}

@Suite struct PaletteTests {
    @Test func fewColorsAreKeptExactly() throws {
        let colors: [(UInt8, UInt8, UInt8, UInt8)] = [(255, 0, 0, 255), (0, 128, 255, 255), (10, 20, 30, 0), (200, 100, 50, 128)]
        let image = makeStripes(colors)
        let data = try #require(ImageCompressor.palettePNG(image, colors: 256))
        let decodedImage = try decodeRGBA(data)
        let original = try #require(RGBAImage(image))
        #expect(decodedImage.pixels == original.pixels)
        // 4 colors -> 2-bit palette PNG with a tRNS chunk.
        let props = imageProperties(data)
        #expect(props[kCGImagePropertyDepth] as? Int == 2)
        #expect(props[kCGImagePropertyHasAlpha] as? Bool == true)
    }

    @Test func manyColorsAreReducedToThePaletteSize() throws {
        let image = makeImage(width: 128, height: 96, alpha: true)
        let rgba = try #require(RGBAImage(image))
        let result = PaletteQuantizer.quantize(rgba, maxColors: 64)
        #expect(result.palette.count <= 64)
        #expect(result.indices.count == 128 * 96)
        #expect(result.indices.allSatisfy { Int($0) < result.palette.count })
        // Transparent entries come first.
        let firstOpaque = result.palette.firstIndex { $0[3] == 255 } ?? result.palette.count
        #expect(result.palette[firstOpaque...].allSatisfy { $0[3] == 255 })
        // Still looks like the image: average error stays small.
        let data = try #require(PalettePNGWriter.encode(result, width: 128, height: 96, colorSpace: rgba.colorSpace))
        let back = try decodeRGBA(data)
        var error = 0
        for i in 0..<back.pixels.count { error += abs(Int(back.pixels[i]) - Int(rgba.pixels[i])) }
        #expect(Double(error) / Double(back.pixels.count) < 12)
    }

    @Test func dominantFlatColorIsExactAndNotDithered() throws {
        // A big flat background with a noisy gradient patch.
        let width = 200, height = 100
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(makeImage(width: 80, height: 80), in: CGRect(x: 110, y: 10, width: 80, height: 80))
        let rgba = try #require(RGBAImage(ctx.makeImage()!))
        let result = PaletteQuantizer.quantize(rgba, maxColors: 32)
        let corner = Int(result.indices[0])
        let bg = SIMD4<UInt8>(rgba.pixels[0], rgba.pixels[1], rgba.pixels[2], rgba.pixels[3])
        #expect(result.palette[corner] == bg)
        // Every background pixel in the left half maps to the same entry.
        for y in 0..<height { for x in 0..<100 { #expect(Int(result.indices[y * width + x]) == corner) } }
    }
}
