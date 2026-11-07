import CoreGraphics
import Foundation
import Testing
@testable import ShotsCore

private func shot(_ id: String = "hero", zoom: Double? = nil, menuBar: Bool? = nil, callout: Callout? = nil) -> Shot {
    Shot(id: id, title: "Title", caption: "Caption.", zoom: zoom, menuBar: menuBar, callout: callout)
}

private func ready(_ windows: [ReadyFile.Window]) -> ReadyFile {
    ReadyFile(scene: "hero", appearance: "light", scale: 2, screen: .init(CGRect(x: 0, y: 0, width: 3008, height: 1692)), windows: windows)
}

private func window(_ id: UInt32, _ kind: ReadyFile.Window.Kind = .window, _ rect: CGRect) -> ReadyFile.Window {
    ReadyFile.Window(id: id, kind: kind, frame: .init(rect))
}

@Suite struct ShowcaseFileTests {
    @Test func decodesWithDefaults() throws {
        let json = #"{"shots":[{"id":"hero","title":"A","caption":"B.","size":"1200x760"}]}"#
        let file = try JSONDecoder().decode(ShowcaseFile.self, from: Data(json.utf8))
        #expect(file.version == 1)
        #expect(file.env.isEmpty)
        #expect(file.shots[0].sceneName == "hero")
        try file.validate()
    }

    @Test func rejectsBadSets() {
        #expect(throws: ShowcaseFile.Invalid.self) { try ShowcaseFile(version: 1, shots: []).validate() }
        #expect(throws: ShowcaseFile.Invalid.self) {
            try ShowcaseFile(version: 1, shots: (1...6).map { shot("s\($0)") }).validate()
        }
        #expect(throws: ShowcaseFile.Invalid.self) { try ShowcaseFile(version: 1, shots: [shot("Hero")]).validate() }
        #expect(throws: ShowcaseFile.Invalid.self) { try ShowcaseFile(version: 1, shots: [shot(), shot()]).validate() }
        #expect(throws: ShowcaseFile.Invalid.self) {
            try ShowcaseFile(version: 1, shots: [Shot(id: "a", title: "Wow!", caption: "x")]).validate()
        }
        #expect(throws: ShowcaseFile.Invalid.self) {
            try ShowcaseFile(version: 1, shots: [Shot(id: "a", title: "A", caption: "")]).validate()
        }
        #expect(throws: ShowcaseFile.Invalid.self) {
            try ShowcaseFile(version: 1, shots: [Shot(id: "a", title: "A", caption: "B", size: "big")]).validate()
        }
        #expect(throws: ShowcaseFile.Invalid.self) { try ShowcaseFile(version: 1, shots: [shot(zoom: 9)]).validate() }
    }

    @Test func substitutesTheDataFolder() {
        let file = ShowcaseFile(version: 1, env: ["APP_CONFIG": "{data}/config.json", "APP_DRY_RUN": "1"], shots: [shot()])
        #expect(file.environment(data: "/tmp/x") == ["APP_CONFIG": "/tmp/x/config.json", "APP_DRY_RUN": "1"])
    }

    @Test func manifestNamesFilesByAppearance() throws {
        let entry = ShotManifest.Entry(id: "rules", width: 2880, height: 1800)
        #expect(entry.light == "rules-light.webp")
        #expect(entry.dark1x == "rules-dark@1x.webp")
        let manifest = ShotManifest(slug: "switchboard", appVersion: "0.2.0", showcaseVersion: 1, date: "2026-11-07", shots: [entry])
        let decoded = try JSONDecoder().decode(ShotManifest.self, from: manifest.encoded())
        #expect(decoded == manifest)
    }
}

@Suite struct PaletteTests {
    @Test func parsesHex() {
        #expect(RGB(hex: "#F0407A")?.hex == "#F0407A")
        #expect(RGB(hex: "0A9DBF")?.hex == "#0A9DBF")
        #expect(RGB(hex: "#F0407") == nil)
        #expect(RGB(hex: "zzzzzz") == nil)
    }

    @Test func mixes() {
        #expect(RGB.black.mixed(with: .white, by: 0.5) == RGB(0.5, 0.5, 0.5))
        #expect(RGB.black.mixed(with: .white, by: 2) == .white)
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func readsBrandJSON() throws {
        let nordic = try Nordic.load(brand: Self.repoRoot.appendingPathComponent("brand/brand.json"))
        #expect(nordic.birch.hex == "#F5F0E8")
        #expect(nordic.night.hex == "#24231F")
        #expect(nordic.colour(forCategory: "Utilities").hex == "#5D7E9A")
        // Unknown categories fall back to pine.
        #expect(nordic.colour(forCategory: "Games").hex == "#3F5E4E")
    }

    @Test func readsTheTileFromAnIconSpec() {
        let generator = """
        TILES = {
            "ochre": "#D2A04C", "clay": "#C4704F",
            "fjord": "#5D7E9A",
        }
        ACCENTS = {"lingonberry": "#B9473B"}
        """
        let tiles = Nordic.tiles(inGenerator: generator)
        #expect(tiles.count == 3)
        #expect(tiles["fjord"]?.hex == "#5D7E9A")
        #expect(Nordic.tile(inSpec: ##"SPEC = Spec(name="Snapper", tile=TILES["clay"], main="#C4704F")"##, tiles: tiles)?.hex == "#C4704F")
        #expect(Nordic.tile(inSpec: ##"SPEC = Spec(name="X", tile="#8EA58B")"##, tiles: tiles)?.hex == "#8EA58B")
        #expect(Nordic.tile(inSpec: ##"SPEC = Spec(name="X", tile=TILES["nope"])"##, tiles: tiles) == nil)
        #expect(Nordic.tile(inSpec: "no spec here", tiles: tiles) == nil)
    }

    @Test func findsTheRealAppsTiles() {
        // Every app with an icon spec has a tile colour the composer can read.
        let apps = Self.repoRoot.appendingPathComponent("apps")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
        let specced = names.filter { FileManager.default.fileExists(atPath: apps.appendingPathComponent("\($0)/Icon.py").path) }
        #expect(!specced.isEmpty)
        for name in specced {
            #expect(Nordic.appTile(appDirectory: apps.appendingPathComponent(name), repoRoot: Self.repoRoot) != nil, "\(name)")
        }
    }

    @Test func darkBackdropIsDarkAndLightIsLight() {
        let nordic = Nordic(colours: ["birch": RGB(hex: "#F5F0E8")!, "night": RGB(hex: "#24231F")!])
        let tile = RGB(hex: "#5D7E9A")!
        let light = BackdropPalette(tile: tile, nordic: nordic, dark: false)
        let dark = BackdropPalette(tile: tile, nordic: nordic, dark: true)
        #expect(light.top.luminance > 0.6)
        #expect(light.bottom.luminance > 0.35)
        #expect(dark.top.luminance < 0.08)
        #expect(dark.bottom.luminance < 0.05)
        // A soft wash: the light backdrop is mostly birch, the dark one mostly night.
        #expect(light.top.mixed(with: nordic.birch, by: 0).r > tile.r)
    }
}

@Suite struct CompositionTests {
    @Test func aWindowFillsThreeQuartersOfTheWidth() {
        let composition = Composition.layout(
            ready: ready([window(1, .window, CGRect(x: 900, y: 400, width: 1160, height: 720))]),
            shot: shot(), menuBar: false)
        let rect = composition.windows[0].rect
        #expect(abs(rect.width - 2880 * Composition.targetWidth) <= 1)
        #expect(rect.midX == 1440)
        // A little above centre, for the shadow.
        #expect(rect.midY < 900 && rect.midY > 860)
        #expect(composition.stripHeight == 0)
        #expect(composition.statusItem == nil)
    }

    @Test func bigWindowsShrinkToFit() {
        let composition = Composition.layout(
            ready: ready([window(1, .window, CGRect(x: 0, y: 0, width: 2000, height: 1000))]),
            shot: shot(), menuBar: false)
        #expect(composition.zoom < 1)
        let rect = composition.windows[0].rect
        #expect(rect.width <= 2880 * Composition.fitWidth + 1)
        #expect(rect.height <= 1800 * Composition.fitHeight + 1)
    }

    @Test func zoomIsCappedByTheCanvas() {
        // Three quarters of the width would be 1.35×; the shot asks for 1.5×, which fits.
        let panel = window(1, .panel, CGRect(x: 0, y: 0, width: 800, height: 400))
        let zoomed = Composition.layout(ready: ready([panel]), shot: shot(zoom: 1.5), menuBar: false)
        #expect(zoomed.zoom == 1.5)
        #expect(zoomed.windows[0].rect.size == CGSize(width: 2400, height: 1200))
        let capped = Composition.layout(ready: ready([panel]), shot: shot(zoom: 3), menuBar: false)
        #expect(capped.zoom < 3)
        #expect(capped.windows[0].rect.height <= 1800 * Composition.fitHeight + 1)
    }

    @Test func smallPanelsGrowUntilTheHeightRunsOut() {
        // Too tall to reach three quarters of the width: as tall as the canvas allows.
        let tall = Composition.layout(ready: ready([window(1, .panel, CGRect(x: 0, y: 0, width: 480, height: 508))]),
                                      shot: shot(), menuBar: false)
        #expect(tall.windows[0].rect.height <= 1800 * Composition.fitHeight + 1)
        #expect(tall.windows[0].rect.height >= 1800 * Composition.fitHeight - 2)
        // A tiny panel stops at the magnification limit, so it stays sharp.
        let tiny = Composition.layout(ready: ready([window(1, .panel, CGRect(x: 0, y: 0, width: 200, height: 120))]),
                                      shot: shot(), menuBar: false)
        #expect(tiny.zoom == Composition.maxMagnification)
        // A shot's own zoom is a floor, not a cap.
        let floored = Composition.layout(ready: ready([window(1, .panel, CGRect(x: 0, y: 0, width: 200, height: 120))]),
                                         shot: shot(zoom: 1.2), menuBar: false)
        #expect(floored.zoom == Composition.maxMagnification)
    }

    @Test func theGrowingMenuBarStaysInTheHeight() {
        let composition = Composition.layout(
            ready: ready([window(1, .panel, CGRect(x: 16, y: 1214, width: 300, height: 166)),
                          window(2, .panel, CGRect(x: 16, y: 1392, width: 300, height: 188)),
                          window(9, .statusItem, CGRect(x: 0, y: 0, width: 34, height: 24))]),
            shot: shot(), menuBar: true)
        let bottom = composition.windows.map(\.rect.maxY).max() ?? 0
        let top = composition.windows.map(\.rect.minY).min() ?? 0
        #expect(top > composition.stripHeight)
        #expect(bottom - top <= (1800 - composition.stripHeight) * Composition.fitHeight + 2)
    }

    @Test func windowsKeepTheirArrangement() {
        let composition = Composition.layout(
            ready: ready([window(1, .window, CGRect(x: 100, y: 100, width: 800, height: 500)),
                          window(2, .panel, CGRect(x: 700, y: 450, width: 300, height: 200))]),
            shot: shot(), menuBar: false)
        let back = composition.windows[0].rect, front = composition.windows[1].rect
        #expect(front.minX - back.minX == 600 * 2 * composition.zoom)
        #expect(front.minY - back.minY == 350 * 2 * composition.zoom)
    }

    @Test func menuBarAppsGetAStripWithTheirIcon() {
        let composition = Composition.layout(
            ready: ready([window(1, .panel, CGRect(x: 1000, y: 600, width: 300, height: 360)),
                          window(9, .statusItem, CGRect(x: 2600, y: 0, width: 38, height: 30))]),
            shot: shot(zoom: 1), menuBar: true)
        // The strip and its icon grow with the zoom (a zoomed panel reads as a zoomed screen).
        let scale = min(max(composition.zoom, 1), 2)
        #expect(composition.stripHeight == (30 * scale).rounded() * 2)
        let item = composition.statusItem
        #expect(item?.window.id == 9)
        #expect(item?.rect.size == CGSize(width: (38 * scale * 2).rounded(), height: (30 * scale * 2).rounded()))
        #expect(composition.windows.count == 1)
        // The panel is centred under the strip, not hanging from it.
        #expect(composition.statusItemPressed == false)
        #expect(composition.windows[0].rect.minY > 60)
    }

    @Test func aStripCanBeTurnedOffPerShot() {
        let composition = Composition.layout(
            ready: ready([window(1, .window, CGRect(x: 0, y: 0, width: 800, height: 500)),
                          window(9, .statusItem, CGRect(x: 2600, y: 0, width: 38, height: 24))]),
            shot: shot(menuBar: false), menuBar: true)
        #expect(composition.stripHeight == 0)
        #expect(composition.statusItem == nil)
    }

    @Test func calloutsMagnifyNextToTheirDetail() throws {
        let callout = Callout(x: 1000, y: 600, width: 100, height: 50, zoom: 2)
        let composition = Composition.layout(
            ready: ready([window(1, .window, CGRect(x: 0, y: 0, width: 1160, height: 720))]),
            shot: shot(zoom: 1, callout: callout), menuBar: false)
        let placement = try #require(composition.callout)
        let rect = composition.windows[0].rect
        #expect(placement.source == CGRect(x: rect.minX + 2000, y: rect.minY + 1200, width: 200, height: 100))
        #expect(placement.target.size == CGSize(width: 400, height: 200))
        #expect(placement.crop == CGRect(x: 2000, y: 1200, width: 200, height: 100))
        // Bottom-right detail, mostly to the right: the callout reaches past the right edge.
        #expect(placement.target.maxX > rect.maxX)
        #expect(placement.target.maxX <= 2880 - Composition.calloutMargin * 2)
    }
}

@Suite struct RenderTests {
    let nordic = Nordic(colours: ["birch": RGB(hex: "#F5F0E8")!, "night": RGB(hex: "#24231F")!])

    private func solid(_ size: CGSize, _ colour: RGB) -> CGImage {
        let context = Render.canvas(size)!
        context.setFillColor(colour.cgColor())
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: Render.sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
    }

    @Test func composesAWindowWithItsShadowOnTheBackdrop() throws {
        let palette = BackdropPalette(tile: RGB(hex: "#C4704F")!, nordic: nordic, dark: false)
        let size = CGSize(width: 720, height: 450)
        let ready = ready([window(1, .window, CGRect(x: 0, y: 0, width: 150, height: 100))])
        let composition = Composition.layout(ready: ready, shot: shot(), menuBar: false, size: size, pointScale: 0.5)
        let image = try #require(Render.compose(composition, captures: [1: solid(CGSize(width: 300, height: 200), .white)], palette: palette))
        #expect(image.width == 720 && image.height == 450)
        let rect = composition.windows[0].rect
        // The window is drawn upright and unchanged.
        let inside = pixel(image, Int(rect.midX), Int(rect.midY))
        #expect(inside.0 == 255 && inside.1 == 255 && inside.2 == 255)
        // Below the window is darker than the same distance above it (the shadow falls down).
        let below = pixel(image, Int(rect.midX), Int(rect.maxY) + 4)
        let above = pixel(image, Int(rect.midX), Int(rect.minY) - 4)
        #expect(below.0 + below.1 + below.2 < above.0 + above.1 + above.2)
        // The corner of the canvas is backdrop, opaque.
        #expect(pixel(image, 2, 2).3 == 255)
    }

    @Test func darkAndLightBackdropsDiffer() throws {
        let tile = RGB(hex: "#5D7E9A")!
        let size = CGSize(width: 64, height: 40)
        func render(_ dark: Bool) -> CGImage {
            let context = Render.canvas(size)!
            Render.backdrop(BackdropPalette(tile: tile, nordic: nordic, dark: dark), in: context, size: size)
            return context.makeImage()!
        }
        let light = pixel(render(false), 32, 20), dark = pixel(render(true), 32, 20)
        #expect(light.0 + light.1 + light.2 > 500)
        #expect(dark.0 + dark.1 + dark.2 < 200)
    }
}
