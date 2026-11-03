import CoreGraphics
import Foundation
import Testing
@testable import SlopKit

@Suite("Selection geometry")
struct SelectionGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func dragInAnyDirectionGivesTheSameRect() {
        let a = SelectionGeometry.rect(anchor: CGPoint(x: 100, y: 100), current: CGPoint(x: 300, y: 250), modifiers: [], bounds: bounds)
        let b = SelectionGeometry.rect(anchor: CGPoint(x: 300, y: 250), current: CGPoint(x: 100, y: 100), modifiers: [], bounds: bounds)
        #expect(a == CGRect(x: 100, y: 100, width: 200, height: 150))
        #expect(a == b)
    }

    @Test func shiftMakesItSquareTowardsThePointer() {
        let rect = SelectionGeometry.rect(anchor: CGPoint(x: 500, y: 500), current: CGPoint(x: 400, y: 560), modifiers: .square, bounds: bounds)
        #expect(rect == CGRect(x: 400, y: 500, width: 100, height: 100))
    }

    @Test func optionGrowsFromTheCenter() {
        let rect = SelectionGeometry.rect(anchor: CGPoint(x: 500, y: 400), current: CGPoint(x: 550, y: 420), modifiers: .fromCenter, bounds: bounds)
        #expect(rect == CGRect(x: 450, y: 380, width: 100, height: 40))
    }

    @Test func squareAndCenterCombine() {
        let rect = SelectionGeometry.rect(anchor: CGPoint(x: 500, y: 400), current: CGPoint(x: 520, y: 450), modifiers: [.square, .fromCenter], bounds: bounds)
        #expect(rect == CGRect(x: 450, y: 350, width: 100, height: 100))
    }

    @Test func clampsToTheScreen() {
        let rect = SelectionGeometry.rect(anchor: CGPoint(x: 900, y: 700), current: CGPoint(x: 1200, y: 900), modifiers: [], bounds: bounds)
        #expect(rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func snapsToWholePoints() {
        let rect = SelectionGeometry.rect(anchor: CGPoint(x: 10.4, y: 10.6), current: CGPoint(x: 20.5, y: 30.2), modifiers: [], bounds: bounds)
        #expect(rect == CGRect(x: 10, y: 11, width: 11, height: 19))
    }

    @Test func tinySelectionsAreClicks() {
        #expect(!SelectionGeometry.isUsable(CGRect(x: 0, y: 0, width: 2, height: 100)))
        #expect(!SelectionGeometry.isUsable(.zero))
        #expect(SelectionGeometry.isUsable(CGRect(x: 0, y: 0, width: 3, height: 3)))
    }

    @Test func holdingSpaceMovesTheWholeSelection() {
        var drag = SelectionDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 200, y: 150), moving: false)
        drag.update(to: CGPoint(x: 250, y: 170), moving: true)
        #expect(drag.anchor == CGPoint(x: 150, y: 120))
        #expect(drag.rect(bounds: bounds) == CGRect(x: 150, y: 120, width: 100, height: 50))
        drag.update(to: CGPoint(x: 300, y: 170), moving: false)
        #expect(drag.rect(bounds: bounds).width == 150)
    }

    @Test func movedStaysInside() {
        let moved = SelectionGeometry.moved(CGRect(x: 950, y: 10, width: 40, height: 40), by: CGVector(dx: 30, dy: -30), within: bounds)
        #expect(moved == CGRect(x: 960, y: 0, width: 40, height: 40))
    }

    @Test func arrowNudges() {
        #expect(SelectionGeometry.nudge(for: .left, large: false) == CGVector(dx: -1, dy: 0))
        #expect(SelectionGeometry.nudge(for: .up, large: true) == CGVector(dx: 0, dy: 10))
        #expect(ArrowKey(keyCode: 125) == .down)
        #expect(ArrowKey(keyCode: 0) == nil)
    }

    @Test func sizeLabel() {
        #expect(SelectionGeometry.sizeLabel(CGRect(x: 0, y: 0, width: 640, height: 480)) == "640 × 480")
    }

    @Test func labelGoesBelowOrInside() {
        let size = CGSize(width: 80, height: 20)
        let below = SelectionGeometry.labelOrigin(size: size, for: CGRect(x: 100, y: 300, width: 200, height: 100), bounds: bounds)
        #expect(below.y < 300)
        let atBottom = SelectionGeometry.labelOrigin(size: size, for: CGRect(x: 100, y: 0, width: 200, height: 100), bounds: bounds)
        #expect(atBottom.y >= 0)
        #expect(atBottom.x + size.width <= bounds.maxX)
    }

    @Test func magnifierFlipsNearEdges() {
        let size = CGSize(width: 120, height: 140)
        let middle = SelectionGeometry.magnifierOrigin(size: size, pointer: CGPoint(x: 500, y: 400), bounds: bounds)
        #expect(middle.x > 500 && middle.y < 400)
        let corner = SelectionGeometry.magnifierOrigin(size: size, pointer: CGPoint(x: 980, y: 20), bounds: bounds)
        #expect(corner.x < 980 && corner.y > 20)
    }
}

@Suite("Screen coordinates")
struct ScreenCoordinatesTests {
    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let flipped = ScreenCoordinates.flip(rect, primaryHeight: 900)
        #expect(flipped == CGRect(x: 10, y: 840, width: 30, height: 40))
        #expect(ScreenCoordinates.flip(flipped, primaryHeight: 900) == rect)
    }

    @Test func localToPixelsOnRetina() {
        // A 100×50 pt box 10 pt from the left and 20 pt from the bottom of a 1440×900 screen.
        let pixels = ScreenCoordinates.pixelRect(local: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                 screenSize: CGSize(width: 1440, height: 900), scale: 2)
        #expect(pixels == CGRect(x: 20, y: 1660, width: 200, height: 100))
    }

    @Test func pixelPoint() {
        let point = ScreenCoordinates.pixelPoint(local: CGPoint(x: 10.7, y: 899.6), screenSize: CGSize(width: 1440, height: 900), scale: 2)
        #expect(point == CGPoint(x: 21, y: 0))
    }

    @Test func quartzToLocalOnASecondScreen() {
        // Secondary screen to the right of a 1440×900 primary, 1920×1080, bottoms aligned.
        let screen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let window = CGRect(x: 1540, y: -80, width: 400, height: 300) // Quartz: top-left based
        let local = ScreenCoordinates.local(fromQuartz: window, screenFrame: screen, primaryHeight: 900)
        #expect(local == CGRect(x: 100, y: 680, width: 400, height: 300))
    }
}

@Suite("Window picking")
struct WindowPickerTests {
    func window(_ id: UInt32, pid: Int32 = 10, layer: Int = 0, alpha: Double = 1, _ frame: CGRect, owner: String = "App") -> WindowInfo {
        WindowInfo(id: id, ownerPID: pid, ownerName: owner, layer: layer, alpha: alpha, frame: frame)
    }

    @Test func picksTheFrontMostWindowUnderThePointer() {
        let windows = [
            window(1, CGRect(x: 0, y: 0, width: 200, height: 200)),
            window(2, CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        #expect(WindowPicker.window(at: CGPoint(x: 50, y: 50), in: windows, excludingPID: nil)?.id == 1)
        #expect(WindowPicker.window(at: CGPoint(x: 500, y: 50), in: windows, excludingPID: nil)?.id == 2)
        #expect(WindowPicker.window(at: CGPoint(x: 900, y: 50), in: windows, excludingPID: nil) == nil)
    }

    @Test func skipsOurOwnPanelsMenusAndInvisibleWindows() {
        let windows = [
            window(1, pid: 99, CGRect(x: 0, y: 0, width: 300, height: 300)),
            window(2, layer: 25, CGRect(x: 0, y: 0, width: 300, height: 300)),
            window(3, alpha: 0, CGRect(x: 0, y: 0, width: 300, height: 300)),
            window(4, CGRect(x: 0, y: 0, width: 20, height: 300)),
            window(5, CGRect(x: 0, y: 0, width: 300, height: 300), owner: "Window Server"),
            window(6, CGRect(x: 0, y: 0, width: 300, height: 300)),
        ]
        #expect(WindowPicker.window(at: CGPoint(x: 10, y: 10), in: windows, excludingPID: 99)?.id == 6)
    }

    @Test func desktopIconWindowsAreFindersBelowNormalLevel() {
        #expect(DesktopIcons.isDesktopIconWindow(bundleID: "com.apple.finder", layer: -2147483603))
        #expect(!DesktopIcons.isDesktopIconWindow(bundleID: "com.apple.finder", layer: 0))
        #expect(!DesktopIcons.isDesktopIconWindow(bundleID: "com.apple.dock", layer: -2147483603))
    }

}

@Suite("Window shadow")
struct WindowShadowTests {
    @Test func padsAndKeepsTheWindowPixelPerfect() throws {
        let window = TestImages.solid(width: 200, height: 100, red: 0, green: 0, blue: 1)
        let output = try #require(WindowShadow.apply(to: window, scale: 2))
        let padded = WindowShadow.paddedSize(width: 200, height: 100, scale: 2)
        #expect(output.width == padded.width && output.height == padded.height)
        #expect(output.width == 200 + 176 && output.height == 100 + 180)
        // The window itself is untouched (blue), the far corner is transparent, and there's
        // shadow just below the window.
        let inside = TestImages.pixel(output, x: 88 + 100, y: 60 + 50)
        #expect(inside.b > 240 && inside.r < 10 && inside.a == 255)
        #expect(TestImages.pixel(output, x: 0, y: 0).a == 0)
        #expect(TestImages.pixel(output, x: 88 + 100, y: 60 + 100 + 30).a > 20)
    }
}

@Suite("Test-mode privacy mask")
struct PrivacyMaskTests {
    /// Fails if any pixel outside the kept rects is not fully transparent black.
    static func leaks(_ image: CGImage, keep: [CGRect]) -> Int {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Cross-check the public helper against this independent count.
        let viaBuffer = PixelBuffer(image)!.visiblePixels(outside: keep)
        var leaked = 0
        for y in 0..<image.height {
            for x in 0..<image.width where !keep.contains(where: { $0.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }) {
                let i = (y * image.width + x) * 4
                if data[i] != 0 || data[i + 1] != 0 || data[i + 2] != 0 || data[i + 3] != 0 { leaked += 1 }
            }
        }
        #expect(viaBuffer == leaked)
        return leaked
    }

    @Test func nothingOutsideTheSceneSurvives() throws {
        let screen = TestImages.solid(width: 120, height: 80, red: 1, green: 1, blue: 1)
        let scene = CGRect(x: 30, y: 20, width: 50, height: 40)
        let masked = try #require(PrivacyMask.apply(to: screen, keeping: [scene]))
        #expect(Self.leaks(masked, keep: [scene]) == 0)
        // The scene itself is untouched.
        let inside = TestImages.pixel(masked, x: 50, y: 30)
        #expect(inside.r == 255 && inside.a == 255)
        // And the check really catches a leak in an unmasked capture.
        #expect(Self.leaks(screen, keep: [scene]) > 0)
    }

    @Test func fractionalAndOffscreenRectsDontLeak() throws {
        let screen = TestImages.solid(width: 100, height: 100, red: 0, green: 1, blue: 0)
        let keep = [CGRect(x: 10.4, y: 10.6, width: 20.3, height: 20.2), CGRect(x: 90, y: 90, width: 50, height: 50)]
        let masked = try #require(PrivacyMask.apply(to: screen, keeping: keep))
        #expect(Self.leaks(masked, keep: keep) == 0)
    }

    @Test func keepingNothingBlanksEverything() throws {
        let screen = TestImages.solid(width: 40, height: 30, red: 1, green: 0, blue: 0)
        let masked = try #require(PrivacyMask.apply(to: screen, keeping: []))
        #expect(Self.leaks(masked, keep: []) == 0)
    }
}

@Suite("Pixel buffer and frozen displays")
struct PixelBufferTests {
    @Test func readsPixelsTopDown() throws {
        // Top half red, bottom half blue.
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 2, width: 4, height: 2))
        let pixels = try #require(PixelBuffer(context.makeImage()!))
        #expect(pixels.rgba(x: 1, y: 0).r == 255)
        #expect(pixels.rgba(x: 1, y: 3).b == 255)
        #expect(pixels.rgba(x: 9, y: 9).a == 0)
        #expect(pixels.luminance(x: 0, y: 0) > pixels.luminance(x: 0, y: 3))
    }

    @Test func frozenDisplayMapsPointsToPixels() {
        let image = TestImages.solid(width: 2880, height: 1800, red: 1, green: 1, blue: 1)
        let frozen = FrozenDisplay(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), image: image)
        #expect(frozen.scale == 2)
        #expect(frozen.pixelRect(local: CGRect(x: 0, y: 0, width: 10, height: 10)) == CGRect(x: 0, y: 1780, width: 20, height: 20))
        #expect(frozen.crop(local: CGRect(x: 0, y: 0, width: 10, height: 10))?.width == 20)
    }
}

enum TestImages {
    static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        PixelBuffer(image)!.rgba(x: x, y: y)
    }
}
