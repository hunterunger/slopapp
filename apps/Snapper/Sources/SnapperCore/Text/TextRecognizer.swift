import CoreGraphics
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
    /// Lines top to bottom (left to right on the same line), joined with line breaks or
    /// spaces. Hyphenated line ends are kept as they are.
    public static func join(_ lines: [RecognizedLine], keepLineBreaks: Bool) -> String {
        let sorted = lines.sorted { a, b in
            // Same visual line if their vertical centers are within half a line height.
            let tolerance = min(a.box.height, b.box.height) / 2
            if abs(a.box.midY - b.box.midY) > tolerance { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
        let texts = sorted.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
public struct VisionTextRecognizer: TextRecognizing {
    /// `fast` trades accuracy for speed (tests use it; the app reads accurately).
    public var fast = false

    public init(fast: Bool = false) {
        self.fast = fast
    }

    public func recognize(_ image: CGImage, keepLineBreaks: Bool) async throws -> String {
        let fast = self.fast
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.usesLanguageCorrection = !fast
            request.automaticallyDetectsLanguage = !fast
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let best = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(text: best.string, box: observation.boundingBox)
            }
            return TextLayout.join(lines, keepLineBreaks: keepLineBreaks)
        }.value
    }
}
