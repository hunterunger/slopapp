import CoreGraphics
import Foundation
import Vision

/// A QR code found in a capture: its text, and the web link it holds, if any.
public struct ScannedCode: Equatable, Sendable, Identifiable {
    public var payload: String
    public var id: String { payload }

    public init(payload: String) {
        self.payload = payload
    }

    /// The code's web address, when it's exactly one http(s) link. Other schemes (`tel:`,
    /// `x-apple…:`, custom app links) are never offered for opening: a code on screen is
    /// untrusted, and those can launch apps or act without a browser in between.
    public var link: URL? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The text for the card: whitespace collapsed (a vCard or Wi-Fi code is several lines),
    /// and a link without its `https://` (and a bare trailing slash), so the site comes first
    /// and survives truncation.
    public var displayText: String {
        if link != nil, let range = payload.range(of: "://") {
            var rest = payload[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasSuffix("/"), rest.dropLast().firstIndex(of: "/") == nil { rest.removeLast() }
            return rest
        }
        return payload.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum ScannedCodes {
    /// At most this many show under a card.
    public static let limit = 3

    /// Codes in reading order with duplicates and empty ones dropped, at most `limit`.
    public static func unique(_ payloads: [String], limit: Int = limit) -> [ScannedCode] {
        var seen = Set<String>()
        var codes: [ScannedCode] = []
        for payload in payloads {
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            codes.append(ScannedCode(payload: trimmed))
            if codes.count == limit { break }
        }
        return codes
    }

    /// Captures bigger than this aren't scanned (a very long scrolling capture), so a scan
    /// never holds a lot of memory or time for a card.
    public static let maxPixels = 60_000_000
}

/// Finds QR codes in an image (on-device, Vision). Behind a protocol so the app can be
/// tested with a fake.
public protocol CodeReading: Sendable {
    func codes(in image: CGImage) async throws -> [ScannedCode]
}

public struct VisionCodeReader: CodeReading {
    public init() {}

    public func codes(in image: CGImage) async throws -> [ScannedCode] {
        guard image.width * image.height <= ScannedCodes.maxPixels else { return [] }
        return try await Task.detached(priority: .utility) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr, .microQR]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            // Top to bottom, then left to right (Vision's boxes are bottom-left based).
            let found = (request.results ?? []).sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.05 { return a.boundingBox.midY > b.boundingBox.midY }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            return ScannedCodes.unique(found.compactMap(\.payloadStringValue))
        }.value
    }
}
