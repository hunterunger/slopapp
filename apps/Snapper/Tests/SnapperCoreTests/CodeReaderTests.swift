import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SnapperCore
import Testing

@Suite struct ScannedCodeTests {
    @Test func webLinksCanBeOpened() {
        #expect(ScannedCode(payload: "https://example.com/menu?table=4").link?.host == "example.com")
        #expect(ScannedCode(payload: "HTTP://EXAMPLE.COM").link != nil)
        #expect(ScannedCode(payload: "  https://example.com/\n").link != nil)
    }

    @Test func otherContentIsOnlyText() {
        for payload in [
            "WIFI:T:WPA;S:Cafe;P:secret;;",
            "tel:+15550100",
            "mailto:someone@example.com",
            "file:///etc/hosts",
            "javascript:alert(1)",
            "x-apple.systempreferences:com.apple.preference.security",
            "example.com",
            "https://",
            "https://example.com and more",
            "Just some words",
        ] {
            #expect(ScannedCode(payload: payload).link == nil, "\(payload)")
        }
    }

    @Test func linksShowTheSiteFirst() {
        #expect(ScannedCode(payload: "https://example.com/menu?table=4").displayText == "example.com/menu?table=4")
        #expect(ScannedCode(payload: "http://example.com/").displayText == "example.com")
        #expect(ScannedCode(payload: "https://example.com/a/").displayText == "example.com/a/")
        #expect(ScannedCode(payload: "tel:+15550100").displayText == "tel:+15550100")
    }

    @Test func multilineContentShowsOnOneLine() {
        #expect(ScannedCode(payload: "BEGIN:VCARD\nFN:Ada\n  END:VCARD").displayText == "BEGIN:VCARD FN:Ada END:VCARD")
    }

    @Test func duplicatesAndBlanksAreDroppedAndTheListIsCapped() {
        let codes = ScannedCodes.unique(["a", " a ", "", "  ", "b", "c", "d"])
        #expect(codes.map(\.payload) == ["a", "b", "c"])
        #expect(ScannedCodes.unique([]).isEmpty)
    }
}

@Suite struct VisionCodeReaderTests {
    /// A white canvas with QR codes drawn at the given points (top-left origin, in pixels).
    private func canvas(width: Int, height: Int, codes: [(String, CGPoint)]) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ci = CIContext()
        for (text, origin) in codes {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = "M"
            let output = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 6, y: 6))
            let code = try #require(ci.createCGImage(output, from: output.extent))
            context.interpolationQuality = .none
            context.draw(code, in: CGRect(x: origin.x, y: CGFloat(height) - origin.y - CGFloat(code.height),
                                          width: CGFloat(code.width), height: CGFloat(code.height)))
        }
        return try #require(context.makeImage())
    }

    @Test func readsCodesTopToBottom() async throws {
        let image = try canvas(width: 900, height: 900, codes: [
            ("second line", CGPoint(x: 80, y: 500)),
            ("https://example.com/slopapp-test", CGPoint(x: 500, y: 60)),
        ])
        let codes = try await VisionCodeReader().codes(in: image)
        #expect(codes.map(\.payload) == ["https://example.com/slopapp-test", "second line"])
    }

    @Test func aCaptureWithoutCodesFindsNothing() async throws {
        let image = try canvas(width: 400, height: 300, codes: [])
        #expect(try await VisionCodeReader().codes(in: image).isEmpty)
    }
}
