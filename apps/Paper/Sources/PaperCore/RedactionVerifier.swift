import Foundation
import PDFKit

/// Independent checks that redacted content is really gone (research P5).
public enum RedactionVerifier {
    /// The characters of `page` whose glyph centers fall inside any of `rects`, in reading
    /// order, with a space between runs that aren't adjacent. Whitespace is dropped.
    ///
    /// Uses selections, not `characterBounds(at:)`: on macOS 27 that API's indexes drift from
    /// `page.string` by the number of line breaks before the character.
    public static func characters(on page: PDFPage, in rects: [CGRect]) -> String {
        guard !rects.isEmpty, let text = page.string, !text.isEmpty else { return "" }
        let ns = text as NSString
        var candidates = IndexSet()
        for rect in rects {
            guard let selection = page.selection(for: rect.insetBy(dx: -3, dy: -3)) else { continue }
            for index in 0..<selection.numberOfTextRanges(on: page) {
                let range = selection.range(at: index, on: page)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                let lower = max(0, range.location - 1)
                let upper = min(ns.length, range.location + range.length + 1)
                candidates.insert(integersIn: lower..<upper)
            }
        }
        var out = ""
        var lastIndex = -2
        for index in candidates {
            let character = ns.substring(with: NSRange(location: index, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let bounds = page.selection(for: NSRange(location: index, length: 1))?.bounds(for: page),
                  bounds.width > 0 || bounds.height > 0 else { continue }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            guard rects.contains(where: { $0.insetBy(dx: -0.25, dy: -0.25).contains(center) }) else { continue }
            if index != lastIndex + 1, !out.isEmpty { out += " " }
            out += character
            lastIndex = index
        }
        return out
    }

    /// Words (2+ characters) a check should find fewer of after redaction.
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { $0.count >= 2 }
    }

    /// Whether the visible content of every region is gone. Compares each region before and
    /// after removal (annotations hidden, inset so neighbouring glyph edges don't count):
    /// a pixel that had content (not page white) and still looks the same is content that
    /// survived. Removed text turns white and removed image pixels turn black, so both count
    /// as changed; leftover text, vector art or image pixels don't. A region where more than
    /// 1% of the pixels survive fails.
    public static func regionsAreBlank(original: PDFPage, redacted: PDFPage, rects: [CGRect]) -> Bool {
        let media = redacted.bounds(for: .mediaBox)
        for rect in rects {
            let clipped = rect.intersection(media)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            let inset = min(2, clipped.width / 4, clipped.height / 4)
            let region = clipped.insetBy(dx: inset, dy: inset)
            guard region.width >= 0.5, region.height >= 0.5,
                  let before = PageRenderer.render(original, region: region, scale: 2, annotations: false),
                  let after = PageRenderer.render(redacted, region: region, scale: 2, annotations: false)
            else { continue }
            if PageRenderer.survivingFraction(before: before, after: after) > 0.01 { return false }
        }
        return true
    }

    public struct PageCheck: Sendable, Equatable {
        /// Characters still found inside the marked areas.
        public var leftover: String
        /// Words that should have disappeared but are still on the page as often as before.
        public var survivingWords: [String]
        public var passed: Bool { leftover.isEmpty && survivingWords.isEmpty }
    }

    /// Compares one page before and after: nothing inside the areas, and each removed word
    /// occurs on the page fewer times than before by at least the number of areas it was in.
    public static func check(original: PDFPage, redacted: PDFPage, rects: [CGRect]) -> PageCheck {
        let leftover = characters(on: redacted, in: rects)
        let originalText = original.string ?? ""
        let redactedText = redacted.string ?? ""
        var needed: [String: Int] = [:]
        for rect in rects {
            for word in tokens(characters(on: original, in: [rect])) { needed[word, default: 0] += 1 }
        }
        var surviving: [String] = []
        for (word, count) in needed.sorted(by: { $0.key < $1.key }) {
            let before = TextMatcher.count(of: word, in: originalText)
            let after = TextMatcher.count(of: word, in: redactedText)
            if after > max(0, before - count) { surviving.append(word) }
        }
        return PageCheck(leftover: leftover, survivingWords: surviving)
    }
}
