import CoreGraphics
import Testing
@testable import IconsmithCore

@Suite struct GeometryTests {
    let content = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test func squarePictureFillsContentAtFullSize() {
        let rect = IconGeometry.artRect(aspect: 1, style: IconStyle(), content: content)
        #expect(rect == content)
    }

    @Test func widePictureFitShowsAllOfIt() {
        let rect = IconGeometry.artRect(aspect: 2, style: IconStyle(fill: false), content: content)
        #expect(rect.width == 1)
        #expect(rect.height == 0.5)
        #expect(rect.midY == 0.5)
    }

    @Test func widePictureFillCoversTheArea() {
        let rect = IconGeometry.artRect(aspect: 2, style: IconStyle(fill: true), content: content)
        #expect(rect.height == 1)
        #expect(rect.width == 2)
        #expect(rect.midX == 0.5)
    }

    @Test func tallPictureFitAndFill() {
        let fit = IconGeometry.artRect(aspect: 0.5, style: IconStyle(fill: false), content: content)
        #expect(fit.width == 0.5 && fit.height == 1)
        let fill = IconGeometry.artRect(aspect: 0.5, style: IconStyle(fill: true), content: content)
        #expect(fill.width == 1 && fill.height == 2)
    }

    @Test func scaleAndOffsetMoveAboutTheCentre() {
        let style = IconStyle(scale: 0.5, offset: CGPoint(x: 0.1, y: -0.2))
        let rect = IconGeometry.artRect(aspect: 1, style: style, content: content)
        #expect(abs(rect.width - 0.5) < 1e-9)
        #expect(abs(rect.midX - 0.6) < 1e-9)
        #expect(abs(rect.midY - 0.3) < 1e-9)
    }

    @Test func badAspectFallsBackToSquare() {
        let rect = IconGeometry.artRect(aspect: .nan, style: IconStyle(), content: content)
        #expect(rect == content)
    }

    @Test func macOSTileFollowsApplesGrid() {
        let rect = IconGeometry.contentRect(for: .macOSApp)
        #expect(abs(rect.minX * 1024 - 100) < 1e-9)
        #expect(abs(rect.width * 1024 - 824) < 1e-9)
        #expect(IconGeometry.clipRect(for: .asIs) == nil)
    }

    @Test func logosGetAMarginExceptAsIs() {
        #expect(IconGeometry.contentRect(for: .square, logo: true).width < 1)
        #expect(IconGeometry.contentRect(for: .macOSApp, logo: true).width < IconGeometry.tileRect.width)
        #expect(IconGeometry.contentRect(for: .asIs, logo: true) == IconGeometry.canvas)
    }

    @Test func fullRectMapsVisiblePartOntoTarget() {
        let full = IconRenderer.fullRect(placing: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(full == CGRect(x: -50, y: -50, width: 200, height: 200))
    }

    @Test func hexColors() {
        #expect(RGBA(1, 0.5, 0).hex == "#FF8000")
        #expect(RGBA.black.hex == "#000000")
    }

    @Test func styleClampsOutOfRangeValues() {
        let style = IconStyle(scale: 9, offset: CGPoint(x: 5, y: -5)).clamped()
        #expect(style.scale == IconStyle.scaleRange.upperBound)
        #expect(style.offset == CGPoint(x: IconStyle.offsetLimit, y: -IconStyle.offsetLimit))
    }

    @Test func placementDefaultsDependOnEdges() {
        #expect(IconStyle.placementDefaults(transparentEdges: true) == (1, false))
        #expect(IconStyle.placementDefaults(transparentEdges: false) == (1, true))
    }

    @Test func folderLayoutPutsPictureOnFrontPanel() {
        let layout = FolderLayout(bounds: CGRect(x: 0.04, y: 0.13, width: 0.92, height: 0.74))
        #expect(layout.panel.minY == 0.13)
        #expect(layout.panel.maxY < 0.87)
        #expect(layout.panel.contains(layout.art))
        #expect(abs(layout.art.width - layout.art.height) < 1e-9)
        #expect(abs(layout.art.midX - 0.5) < 1e-9)
    }

    @Test func opaqueBoundsFlipsRowsToBottomUp() {
        // 10x10 with an opaque block at columns 2...5, rows 1...3 (top-down).
        let bounds = FolderLayout.opaqueBounds(alpha: { x, y in (2...5).contains(x) && (1...3).contains(y) ? 255 : 0 },
                                               width: 10, height: 10)
        #expect(bounds == CGRect(x: 0.2, y: 0.6, width: 0.4, height: 0.3))
        #expect(FolderLayout.opaqueBounds(alpha: { _, _ in 0 }, width: 4, height: 4) == nil)
    }
}
