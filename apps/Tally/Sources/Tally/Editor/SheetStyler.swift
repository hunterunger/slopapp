import AppKit
import TallyCore

/// Colours each line as it's typed, from the theme: numbers, operator words, units,
/// variables, labels, comments and headers. Only edited lines are restyled; a full pass
/// runs when the theme, text size or the sheet's variable names change.
@MainActor
final class SheetStyler: NSObject, NSTextStorageDelegate {
    private(set) var font: NSFont
    private(set) var headerFont: NSFont
    private(set) var paragraph: NSParagraphStyle
    private(set) var theme: Theme
    private(set) var pointSize: CGFloat
    /// Bumped on every theme or size change, so sheets styled earlier get restyled when shown.
    private(set) var generation = 0
    /// The lower-cased variable names of the sheet a storage belongs to.
    var variables: (NSTextStorage) -> Set<String> = { _ in [] }

    init(pointSize: CGFloat, theme: Theme) {
        self.pointSize = pointSize
        self.theme = theme
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
        pointSize = size
        font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        headerFont = .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        paragraph = Self.paragraph(for: size)
        generation += 1
    }

    func setTheme(_ theme: Theme) {
        self.theme = theme
        generation += 1
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: theme.text, .paragraphStyle: paragraph]
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
        let location = min(range.location, text.length)
        let lines = text.lineRange(for: NSRange(location: location, length: min(range.length, text.length - location)))
        storage.setAttributes(baseAttributes, range: lines)
        let names = variables(storage)
        text.enumerateSubstrings(in: lines, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            for span in Highlighter.spans(line, variables: names) {
                let r = NSRange(location: lineRange.location + span.range.location, length: span.range.length)
                guard NSMaxRange(r) <= NSMaxRange(lineRange) else { continue }
                storage.addAttribute(.foregroundColor, value: self.theme.color(for: span.kind), range: r)
                if span.kind == .header { storage.addAttribute(.font, value: self.headerFont, range: r) }
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
