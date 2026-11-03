import AppKit
import TallyCore

/// Styles note parts as they're typed: headers semibold, comments, labels and quoted text
/// secondary. Only the edited lines are restyled.
@MainActor
final class SheetStyler: NSObject, NSTextStorageDelegate {
    var font: NSFont
    var headerFont: NSFont
    var paragraph: NSParagraphStyle

    init(pointSize: CGFloat) {
        font = .monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        headerFont = .monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
        paragraph = Self.paragraph(for: pointSize)
    }

    static func paragraph(for pointSize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (pointSize * 0.35).rounded()
        return style
    }

    func setPointSize(_ size: CGFloat) {
        font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        headerFont = .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        paragraph = Self.paragraph(for: size)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // NSTextStorage edits from an NSTextView always arrive on the main thread.
        nonisolated(unsafe) let storage = textStorage
        MainActor.assumeIsolated {
            style(storage, in: editedRange)
        }
    }

    /// Restyles every line touching `range`.
    func style(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let lines = text.lineRange(for: NSRange(location: min(range.location, text.length), length: min(range.length, text.length - min(range.location, text.length))))
        storage.setAttributes(baseAttributes, range: lines)
        text.enumerateSubstrings(in: lines, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let syntax = LineSyntax.parse(line)
            switch syntax.kind {
            case .blank, .content: break
            case .header:
                storage.addAttribute(.font, value: self.headerFont, range: lineRange)
            case .comment:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            }
            for part in syntax.quotes + [syntax.label, syntax.comment].compactMap({ $0 }) {
                let r = NSRange(location: lineRange.location + part.location, length: part.length)
                if NSMaxRange(r) <= NSMaxRange(lineRange) {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                }
            }
        }
    }

    func styleAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        style(storage, in: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }
}
