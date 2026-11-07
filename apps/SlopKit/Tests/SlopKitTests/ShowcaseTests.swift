import CoreGraphics
import Foundation
import Testing
@testable import SlopKit

@Suite struct ShowcaseRequestTests {
    @Test func noSceneMeansNoShowcase() {
        #expect(ShowcaseRequest.parse([:]) == nil)
        #expect(ShowcaseRequest.parse(["SLOP_SHOWCASE": ""]) == nil)
        #expect(ShowcaseRequest.parse(["SLOP_SHOWCASE": "0"]) == nil)
        #expect(ShowcaseRequest.parse(["SLOP_SHOWCASE": "  "]) == nil)
    }

    @Test func parsesEveryVariable() throws {
        let request = try #require(ShowcaseRequest.parse([
            "SLOP_SHOWCASE": "hero",
            "SLOP_SHOWCASE_SIZE": "1280x800",
            "SLOP_SHOWCASE_READY": "/tmp/x/ready.json",
            "SLOP_SHOWCASE_DATA": "/tmp/x/data",
            "SLOP_SHOWCASE_SETTLE": "250",
        ]))
        #expect(request.scene == "hero")
        #expect(request.size == CGSize(width: 1280, height: 800))
        #expect(request.readyFile?.path == "/tmp/x/ready.json")
        #expect(request.dataDirectory?.path == "/tmp/x/data")
        #expect(request.settle == .milliseconds(250))
    }

    @Test func defaultsWhenOnlyTheSceneIsSet() throws {
        let request = try #require(ShowcaseRequest.parse(["SLOP_SHOWCASE": "rules"]))
        #expect(request.size == nil)
        #expect(request.readyFile == nil)
        #expect(request.dataDirectory == nil)
        #expect(request.settle == ShowcaseRequest.defaultSettle)
    }

    @Test func negativeSettleIsZero() throws {
        let request = try #require(ShowcaseRequest.parse(["SLOP_SHOWCASE": "a", "SLOP_SHOWCASE_SETTLE": "-5"]))
        #expect(request.settle == .zero)
    }

    @Test(arguments: [
        ("1280x800", CGSize(width: 1280, height: 800)),
        ("1280×800", CGSize(width: 1280, height: 800)),
        ("640, 400", CGSize(width: 640, height: 400)),
        ("900.5X600", CGSize(width: 900.5, height: 600)),
    ])
    func parsesSizes(text: String, size: CGSize) {
        #expect(ShowcaseRequest.parseSize(text) == size)
    }

    @Test(arguments: ["", "1280", "1280x", "x800", "0x800", "axb", "1x2x3", "20000x10"])
    func rejectsBadSizes(text: String) {
        #expect(ShowcaseRequest.parseSize(text) == nil)
    }
}

@Suite struct ShowcaseLayoutTests {
    let visible = CGRect(x: 0, y: 96, width: 3008, height: 1566)

    @Test func centresOnWholePoints() {
        let frame = ShowcaseLayout.centered(CGSize(width: 1281, height: 801), in: visible)
        #expect(frame.size == CGSize(width: 1281, height: 801))
        #expect(abs(frame.midX - visible.midX) <= 0.5)
        #expect(abs(frame.midY - visible.midY) <= 0.5)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.minY == frame.minY.rounded())
    }

    @Test func shrinksToFitSmallScreens() {
        let small = CGRect(x: 0, y: 0, width: 1024, height: 640)
        let frame = ShowcaseLayout.centered(CGSize(width: 1400, height: 900), in: small, margin: 20)
        #expect(frame == CGRect(x: 20, y: 20, width: 984, height: 600))
    }

    @Test func movesOutFromUnderThePointer() {
        let frame = ShowcaseLayout.centered(CGSize(width: 1160, height: 720), in: visible)
        let moved = ShowcaseLayout.avoiding(CGPoint(x: frame.midX, y: frame.midY), frame, in: visible)
        #expect(!moved.insetBy(dx: -24, dy: -24).contains(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(moved.size == frame.size)
        #expect(moved.minY == frame.minY)
        #expect(visible.contains(moved))
        // A pointer elsewhere changes nothing.
        #expect(ShowcaseLayout.avoiding(CGPoint(x: 5, y: 5), frame, in: visible) == frame)
    }

    @Test func goesBelowWhenTooWideToMoveSideways() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 2000)
        let frame = CGRect(x: 20, y: 800, width: 1160, height: 400)
        let moved = ShowcaseLayout.avoiding(CGPoint(x: 600, y: 1000), frame, in: screen)
        #expect(moved.maxY <= 1000 - 24)
        #expect(moved.minX == 20)
    }

    @Test func windowFrameKeepsTheTitleBar() {
        let size = ShowcaseLayout.frameSize(
            forContent: CGSize(width: 1000, height: 600),
            frame: CGRect(x: 0, y: 0, width: 800, height: 552),
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 500)
        )
        #expect(size == CGSize(width: 1000, height: 652))
    }
}

@Suite struct ShowcaseReadyTests {
    @Test func roundTripsThroughJSON() throws {
        let ready = ShowcaseReady(
            scene: "hero", appearance: "dark", scale: 2,
            screen: .init(CGRect(x: 0, y: 0, width: 1440, height: 900)),
            windows: [
                .init(id: 42, kind: .window, title: "Editor", frame: .init(CGRect(x: 80, y: 50, width: 1280, height: 800))),
                .init(id: 7, kind: .statusItem, title: "", frame: .init(CGRect(x: 1200, y: 0, width: 36, height: 24))),
            ]
        )
        let data = try ready.encoded()
        let decoded = try JSONDecoder().decode(ShowcaseReady.self, from: data)
        #expect(decoded == ready)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"statusItem\""))
        #expect(text.contains("\"width\" : 1280"))
        #expect(!text.contains("\"error\""))
    }

    @Test func failuresCarryTheMessage() throws {
        let ready = ShowcaseReady(scene: "x", appearance: "light", scale: 2, screen: .init(.zero), windows: [], error: "no window")
        let decoded = try JSONDecoder().decode(ShowcaseReady.self, from: ready.encoded())
        #expect(decoded.error == "no window")
        #expect(decoded.windows.isEmpty)
    }
}
