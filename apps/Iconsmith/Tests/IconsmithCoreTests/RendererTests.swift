import AppKit
import Testing
@testable import IconsmithCore

@Suite struct RendererTests {
    @Test func macOSAppTileHasMarginsAndFilledCentre() throws {
        let renderer = IconRenderer(source: rasterSource())
        let image = try #require(renderer.render(IconStyle(shape: .macOSApp), pixels: 256))
        #expect(image.width == 256)
        #expect(pixel(image, 2, 2).a < 0.05)         // outside the tile
        #expect(pixel(image, 128, 128).a > 0.99)     // inside the tile
        #expect(pixel(image, 30, 30).a < 0.5)        // the rounded corner is cut
    }

    @Test func squareIsFullBleedAndCircleCutsCorners() throws {
        let renderer = IconRenderer(source: rasterSource())
        let square = try #require(renderer.render(IconStyle(shape: .square), pixels: 64))
        #expect(pixel(square, 0, 0).a > 0.99)
        let circle = try #require(renderer.render(IconStyle(shape: .circle), pixels: 64))
        #expect(pixel(circle, 1, 1).a < 0.01)
        #expect(pixel(circle, 32, 32).a > 0.99)
    }

    @Test func asIsKeepsTransparency() throws {
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true))
        let image = try #require(renderer.render(IconStyle(shape: .asIs, background: .color, color: .black), pixels: 64))
        #expect(pixel(image, 1, 1).a < 0.01) // background ignored for As Is
        #expect(pixel(image, 32, 32).a > 0.99)
    }

    @Test func automaticBackgroundResolution() {
        let opaque = IconRenderer(source: rasterSource())
        #expect(opaque.background(for: IconStyle(shape: .square))?.red ?? 0 > 0.8) // edge colour
        let logo = IconRenderer(source: rasterSource(transparentEdges: true))
        #expect(logo.background(for: IconStyle(shape: .macOSApp)) == .white)
        #expect(logo.background(for: IconStyle(shape: .circle)) == .white)   // every shape shows
        #expect(logo.background(for: IconStyle(shape: .square)) == .white)
        #expect(logo.background(for: IconStyle(shape: .asIs)) == nil)
        #expect(logo.background(for: IconStyle(shape: .square, background: .none)) == nil)
        #expect(logo.background(for: IconStyle(shape: .square, background: .color, color: .black)) == .black)
        #expect(logo.background(for: IconStyle(shape: .folder, background: .color, color: .black)) == nil)
    }

    @Test func colourBackgroundFillsBehindTransparentLogo() throws {
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true))
        let style = IconStyle(shape: .square, background: .color, color: RGBA(0, 1, 0))
        let image = try #require(renderer.render(style, pixels: 64))
        let corner = pixel(image, 1, 1)
        #expect(corner.a > 0.99 && corner.g > 0.99 && corner.r < 0.01)
    }

    @Test func opaqueRenderHasNoAlphaAndFillsWhite() throws {
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true))
        let style = IconStyle(shape: .macOSApp, background: .none)
        #expect(renderer.opaqueNeedsFill(style))
        let image = try #require(renderer.render(style, pixels: 64, opaque: true))
        #expect(image.alphaInfo == .noneSkipLast)
        let corner = pixel(image, 0, 0)
        #expect(corner.r > 0.99 && corner.g > 0.99 && corner.b > 0.99)
        #expect(!IconRenderer(source: rasterSource()).opaqueNeedsFill(IconStyle()))
    }

    @Test func logoMarginsAreTrimmedSoTheLogoFillsTheShape() throws {
        // The test logo is a disc filling the middle half; trimmed, it spans the square's
        // content area (76% of the canvas) instead of half of it.
        let source = rasterSource(width: 512, height: 512, transparentEdges: true)
        let bounds = source.contentBounds
        #expect(abs(bounds.width - 0.5) < 0.03 && abs(bounds.midX - 0.5) < 0.01)
        let image = try #require(IconRenderer(source: source).render(IconStyle(shape: .square, fill: false, background: .none), pixels: 100))
        #expect(pixel(image, 50, 14).a > 0.9)   // top of the disc, near the 12% margin
        #expect(pixel(image, 50, 8).a < 0.1)    // the margin itself
        // As Is keeps the original margins.
        let asIs = try #require(IconRenderer(source: source).render(IconStyle(shape: .asIs, fill: false), pixels: 100))
        #expect(pixel(asIs, 50, 20).a < 0.1)
    }

    @Test func offsetMovesThePicture() throws {
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true))
        let centred = try #require(renderer.render(IconStyle(shape: .asIs, scale: 1, fill: false), pixels: 100))
        #expect(pixel(centred, 50, 50).a > 0.99)
        let moved = try #require(renderer.render(IconStyle(shape: .asIs, scale: 1, offset: CGPoint(x: 0.4, y: 0), fill: false), pixels: 100))
        #expect(pixel(moved, 50, 50).a < 0.01)
        #expect(pixel(moved, 90, 50).a > 0.99)
    }

    @Test @MainActor func folderShapeDrawsOnSystemFolder() throws {
        let folder = FolderArt.system()
        #expect(folder.image != nil)
        #expect(folder.layout.panel.contains(folder.layout.art))
        let renderer = IconRenderer(source: rasterSource(), folder: folder)
        let image = try #require(renderer.render(IconStyle(shape: .folder), pixels: 256))
        // The picture's red sits in the middle of the front panel; the corners stay clear.
        let middle = pixel(image, Int(folder.layout.art.minX * 256) + 4, 256 - Int(folder.layout.art.midY * 256))
        #expect(middle.r > 0.8 && middle.b < 0.3)
        #expect(pixel(image, 0, 0).a < 0.05)
    }

    @Test func multiResolutionImageHasEverySize() {
        let image = IconRenderer(source: rasterSource()).multiResolutionImage(IconStyle())
        let widths = Set(image.representations.map(\.pixelsWide))
        #expect(widths == [16, 32, 64, 128, 256, 512, 1024])
    }

    @Test func smallSizesAreDrawnAtTheirOwnPixelSize() throws {
        let image = try #require(IconRenderer(source: rasterSource()).render(IconStyle(), pixels: 16))
        #expect(image.width == 16 && image.height == 16)
    }
}
