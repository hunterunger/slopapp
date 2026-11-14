import CoreGraphics
import CoreText
import Foundation
import Vision

/// Reads text out of an image (on-device, Vision). Behind a protocol so the app can be
/// tested with a fake.
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage, keepLineBreaks: Bool) async throws -> String
}

/// One recognized line and where it sits (Vision's normalized, bottom-left coordinates).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var box: CGRect
    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum TextLayout {
    /// Lines top to bottom, joined with line breaks or spaces. Pieces Vision reads apart on
    /// the same visual line ("a   ·   b" with wide gaps) stay on one line, left to right,
    /// separated by a space. Hyphenated line ends are kept as they are.
    public static func join(_ lines: [RecognizedLine], keepLineBreaks: Bool) -> String {
        let pieces = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        var rows: [[RecognizedLine]] = []
        for piece in pieces {
            // Same visual line if its vertical center is within half a line height of the row's.
            if let row = rows.last, let first = row.first,
               abs(first.box.midY - piece.box.midY) <= min(first.box.height, piece.box.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        let texts = rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
        return texts.joined(separator: keepLineBreaks ? "\n" : " ")
    }

    /// A one-line preview of recognized text for a confirmation: whitespace collapsed, at
    /// most `limit` characters, cut at a word boundary (never mid-word) with an ellipsis.
    public static func preview(_ text: String, limit: Int = 40) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let flat = words.joined(separator: " ")
        guard flat.count > limit else { return flat }
        var kept: [Substring] = []
        var length = 0
        for word in words {
            let next = length + (kept.isEmpty ? 0 : 1) + word.count
            if next > limit { break }
            kept.append(word)
            length = next
        }
        // Don't end on a lone separator ("·", "-", "|").
        while let last = kept.last, !last.contains(where: { $0.isLetter || $0.isNumber }) { kept.removeLast() }
        var result = kept.joined(separator: " ")
        // A single word longer than the limit: cut it (nothing better to do).
        if result.isEmpty { result = String(flat.prefix(limit)) }
        return result + "…"
    }
}

/// Vision's accurate text recognizer, with automatic language detection.
///
/// The first recognition after macOS drops its compiled copy of the recognizer takes 30 s or
/// more: the Neural Engine compiles the networks again, and the compiled copy is kept per
/// executable. `warmUp()` pays that cost ahead of time (see `TextWarmUp` in the app).
public struct VisionTextRecognizer: TextRecognizing {
    /// `fast` trades accuracy for speed (tests use it; the app reads accurately).
    public var fast = false

    public init(fast: Bool = false) {
        self.fast = fast
    }

    public func recognize(_ image: CGImage, keepLineBreaks: Bool) async throws -> String {
        let fast = self.fast
        return try await Task.detached(priority: .userInitiated) {
            let lines = try Self.lines(in: image, fast: fast)
            return TextLayout.join(lines, keepLineBreaks: keepLineBreaks)
        }.value
    }

    /// Reads a small built-in sample with the same settings as `recognize`, so the networks
    /// are compiled and loaded. Blocks; returns what it read (empty if it failed).
    @discardableResult
    public static func warmUp() -> String {
        guard let image = sampleImage(), let lines = try? lines(in: image, fast: false) else { return "" }
        return TextLayout.join(lines, keepLineBreaks: false)
    }

    private static func lines(in image: CGImage, fast: Bool) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        request.automaticallyDetectsLanguage = !fast
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let best = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: best.string, box: observation.boundingBox)
        }
    }

    /// Dark text on white. It has to hold real text: an empty image never reaches the
    /// recognition networks.
    public static let sampleText = "Snapper reads text"

    public static func sampleImage() -> CGImage? {
        let width = 360, height = 64
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateUIFontForLanguage(.system, 28, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let text = NSAttributedString(string: sampleText, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        context.setFillColor(gray: 0, alpha: 1)
        context.textPosition = CGPoint(x: 16, y: 20)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        return context.makeImage()
    }
}
