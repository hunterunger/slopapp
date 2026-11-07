import AppKit
import SlopKit
import TallyCore

/// A text container that narrows only the lines that have a result, by that result's
/// width, so text wraps just before its own answer and uses the full width otherwise.
final class ResultAwareTextContainer: NSTextContainer {
    /// Reserved width per line (0 = none), and where each line starts (UTF-16).
    var reserved: [CGFloat] = []
    var lineStarts: [Int] = [0]

    override var isSimpleRectangularTextContainer: Bool { false }

    override func lineFragmentRect(forProposedRect proposedRect: NSRect, at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var rect = super.lineFragmentRect(forProposedRect: proposedRect, at: characterIndex,
                                          writingDirection: baseWritingDirection, remaining: remainingRect)
        let line = SheetText.lineIndex(containing: characterIndex, lineStarts: lineStarts)
        if line < reserved.count, reserved[line] > 0 {
            rect.size.width = max(40, min(rect.width, size.width - reserved[line]))
        }
        return rect
    }
}

/// The sheet editor: a plain-text NSTextView (TextKit 1, so line fragments are cheap to
/// query) with the results column as a subview on its right. Text wraps before the column.
final class SheetTextView: NSTextView {
    let resultsView = ResultsColumnView()
    private(set) var lineStarts: [Int] = [0]
    var displays: [ResultDisplay?] = []
    /// Width each line keeps free for its result (0 = none).
    private(set) var reserved: [CGFloat] = []
    /// Text and results sit this far in from each side (the bottom bar's controls line up
    /// with both edges).
    static let margin: CGFloat = Spacing.xl
    /// The least space between a line's text and its result.
    static let gap: CGFloat = Spacing.l
    /// A result takes at most this share of the width; longer ones are shortened.
    static let resultShare: CGFloat = 0.6

    var resultFont: NSFont = .monospacedDigitSystemFont(ofSize: 15, weight: .medium) { didSet { widthCache.removeAll() } }
    var errorFont: NSFont = .systemFont(ofSize: 13) { didSet { widthCache.removeAll() } }
    /// Measured text widths; measuring 1,000 strings per keystroke would cost a few ms.
    private var widthCache: [String: CGFloat] = [:]
    private(set) var theme: Theme = .system
    /// Typing attributes for plain text (the styler's base attributes).
    var baseAttributes: [NSAttributedString.Key: Any] = [:]

    var onResultClick: ((Int) -> Void)?
    /// Variable names of the shown sheet, for suggestions.
    var variableNames: () -> [String] = { [] }
    /// Whether to show the rest of a name greyed after the insertion point.
    var suggestsInline: () -> Bool = { true }
    /// The greyed rest of the word being typed (Tab accepts it).
    private(set) var suggestion: String?

    static func make() -> SheetTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = ResultAwareTextContainer(containerSize: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = SheetTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), textContainer: container)
        view.configure()
        return view
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        allowsDocumentBackgroundColorChange = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        textContainerInset = NSSize(width: Self.margin, height: Spacing.l)
        setAccessibilityLabel("Sheet")
        setAccessibilityHelp("Type one calculation per line. Results appear in the results column.")

        resultsView.textView = self
        addSubview(resultsView)
    }

    // MARK: Sheets and themes

    /// Shows `document`: its shared text storage, selection and answers.
    func show(_ document: SheetDocument) {
        guard let layout = layoutManager else { return }
        if layout.textStorage !== document.storage {
            breakUndoCoalescing()
            layout.replaceTextStorage(document.storage)
        }
        suggestion = nil
        let length = document.storage.length
        var selection = document.selection
        if selection.location == NSNotFound || NSMaxRange(selection) > length {
            selection = NSRange(location: length, length: 0)
        }
        setSelectedRange(selection)
        typingAttributes = baseAttributes
        apply(displays: document.displays)
        scrollRangeToVisible(selection)
        needsDisplay = true
    }

    func applyTheme(_ theme: Theme, pointSize size: CGFloat) {
        self.theme = theme
        backgroundColor = theme.background
        insertionPointColor = theme.caret
        enclosingScrollView?.backgroundColor = theme.background
        if let name = theme.appearance { appearance = NSAppearance(named: name) } else { appearance = nil }
        enclosingScrollView?.appearance = appearance
        font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        typingAttributes = baseAttributes
        defaultParagraphStyle = SheetStyler.paragraph(for: size)
        resultFont = .monospacedDigitSystemFont(ofSize: size, weight: .medium)
        errorFont = .systemFont(ofSize: (size * 0.87).rounded())
        layoutColumns()
        resultsView.needsDisplay = true
        needsDisplay = true
    }

    // MARK: Suggestions

    /// Recomputes the inline suggestion after typing.
    func updateSuggestion() {
        let old = suggestion
        defer { if old != suggestion { needsDisplay = true } }
        guard suggestsInline(), selectedRange().length == 0, window?.firstResponder === self || window == nil else {
            suggestion = nil
            return
        }
        let cursor = selectedRange().location
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(cursor, ns.length), length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        suggestion = Completions.inline(line: line, cursor: cursor - lineRange.location, variables: variableNames())
    }

    func clearSuggestion() {
        guard suggestion != nil else { return }
        suggestion = nil
        needsDisplay = true
    }

    /// Tab accepts the greyed suggestion, else offers completions for the word, else is a tab.
    override func insertTab(_ sender: Any?) {
        if let suggestion {
            self.suggestion = nil
            insertText(suggestion, replacementRange: selectedRange())
            return
        }
        let range = rangeForUserCompletion
        if window != nil, range.location != NSNotFound, range.length > 0,
           !Completions.candidates(for: (string as NSString).substring(with: range), variables: variableNames()).isEmpty {
            complete(sender)
            return
        }
        super.insertTab(sender)
    }

    /// Esc hides the suggestion first; otherwise it opens the completion list as usual.
    override func cancelOperation(_ sender: Any?) {
        if suggestion != nil {
            clearSuggestion()
            return
        }
        super.cancelOperation(sender)
    }

    override func complete(_ sender: Any?) {
        clearSuggestion()
        super.complete(sender)
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let partial = (string as NSString).substring(with: charRange)
        let list = Completions.candidates(for: partial, variables: variableNames())
        return list.isEmpty ? nil : list
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Moving the insertion point away hides the suggestion (typing recomputes it).
        if suggestion != nil, !isApplyingEdit { clearSuggestion() }
    }

    private var isApplyingEdit = false

    override func insertText(_ string: Any, replacementRange: NSRange) {
        isApplyingEdit = true
        super.insertText(string, replacementRange: replacementRange)
        isApplyingEdit = false
        updateSuggestion()
    }

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        clearSuggestion()
    }

    /// Where the suggestion is drawn: just after the insertion point.
    func suggestionOrigin() -> NSPoint? {
        guard let layout = layoutManager, let container = textContainer else { return nil }
        let cursor = selectedRange().location
        guard cursor > 0 else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: cursor - 1)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return NSPoint(x: glyphRect.maxX + textContainerOrigin.x, y: fragment.minY + textContainerOrigin.y)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        layoutColumns()
        if old != newSize { scheduleRedisplay() }
    }

    private var redisplayScheduled = false

    /// With non-contiguous layout the text view resizes itself while lines are laid out, which
    /// can happen in the middle of a display pass; invalidations made then can be dropped
    /// (seen as a blank sheet, or a last line without its answer, at narrow widths). One
    /// redisplay on the next turn of the run loop catches up.
    private func scheduleRedisplay() {
        guard !redisplayScheduled else { return }
        redisplayScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            redisplayScheduled = false
            needsDisplay = true
            resultsView.needsDisplay = true
        }
    }

    /// Text container = width minus margins. Results float over the right side.
    func layoutColumns() {
        guard let container = textContainer else { return }
        let textWidth = max(80, bounds.width - 2 * Self.margin)
        if abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
            recomputeReserved(invalidateAll: true)
        }
        resultsView.frame = NSRect(x: Self.margin, y: 0, width: textWidth, height: bounds.height)
        resultsView.needsDisplay = true
    }

    /// Updates results after an evaluation and re-wraps lines whose result width changed.
    func apply(displays: [ResultDisplay?]) {
        self.displays = displays
        lineStarts = SheetText.lineStarts(of: string as NSString)
        recomputeReserved(invalidateAll: false)
        resultsView.resultsChanged()
    }

    /// The widest a result is drawn; wider ones are shortened. Leaves `gap` between it and
    /// its line's text, which wraps at `resultShare` of the width.
    var maxResultWidth: CGFloat {
        max(0, (textContainer?.containerSize.width ?? bounds.width) * Self.resultShare - Self.gap)
    }

    /// The width a result needs, including the stale-rates clock.
    func resultWidth(_ d: ResultDisplay) -> CGFloat {
        textWidth(d) + (d.isStale ? resultFont.pointSize * 1.3 : 0)
    }

    func textWidth(_ d: ResultDisplay) -> CGFloat {
        let key = d.kind == .value ? d.text : "\u{1}" + d.text
        if let w = widthCache[key] { return w }
        let font = d.kind == .value ? resultFont : errorFont
        let w = ceil((d.text as NSString).size(withAttributes: [.font: font]).width)
        if widthCache.count > 5_000 { widthCache.removeAll() }
        widthCache[key] = w
        return w
    }

    private func recomputeReserved(invalidateAll: Bool) {
        guard let container = textContainer as? ResultAwareTextContainer, let layout = layoutManager else { return }
        let maxReserve = container.containerSize.width * Self.resultShare
        var next = [CGFloat](repeating: 0, count: displays.count)
        for (i, d) in displays.enumerated() {
            guard let d else { continue }
            // Round up to 8 pt so a growing number doesn't re-wrap on every digit.
            next[i] = min(maxReserve, ceil((resultWidth(d) + Self.gap) / 8) * 8)
        }
        let old = reserved
        reserved = next
        container.reserved = next
        container.lineStarts = lineStarts
        if invalidateAll {
            layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
            return
        }
        var start: Int?
        var end = 0
        for i in 0..<max(old.count, next.count) where (old[safe: i] ?? 0) != (next[safe: i] ?? 0) {
            if start == nil { start = i }
            end = i
        }
        guard let first = start else { return }
        let length = (string as NSString).length
        let from = characterRange(ofLine: first).location
        let to = min(length, NSMaxRange(characterRange(ofLine: min(end, lineStarts.count - 1))) + 1)
        layout.invalidateLayout(forCharacterRange: NSRange(location: from, length: max(0, to - from)), actualCharacterRange: nil)
    }

    // MARK: Lines

    /// The line holding the insertion point.
    var currentLine: Int {
        SheetText.lineIndex(containing: selectedRange().location, lineStarts: lineStarts)
    }

    func characterRange(ofLine line: Int) -> NSRange {
        let length = (string as NSString).length
        guard lineStarts.indices.contains(line) else { return NSRange(location: length, length: 0) }
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : length
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The first line fragment of `line`, in view coordinates.
    func lineRect(_ line: Int) -> NSRect? {
        guard let layout = layoutManager, let container = textContainer, lineStarts.indices.contains(line) else { return nil }
        let length = (string as NSString).length
        let start = lineStarts[line]
        var rect: NSRect
        if start >= length {
            rect = layout.extraLineFragmentRect
            if rect.height == 0 { return nil }
        } else {
            let glyph = layout.glyphIndexForCharacter(at: start)
            rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: false)
        }
        _ = container
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    /// The baseline of `line`'s first line fragment, in view coordinates (results sit on it).
    func baseline(ofLine line: Int) -> CGFloat? {
        guard let layout = layoutManager, let rect = lineRect(line) else { return nil }
        let length = (string as NSString).length
        let start = lineStarts[line]
        // The empty last line has no glyphs (and never a result).
        guard start < length else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: start)
        return rect.minY + layout.location(forGlyphAt: glyph).y
    }

    /// How far below the top of a one-line box `font`'s baseline is drawn (the same rule the
    /// text column's typesetter uses, so a result drawn at `baseline - offset` shares it).
    func baselineOffset(for font: NSFont) -> CGFloat {
        layoutManager?.defaultBaselineOffset(for: font) ?? font.ascender
    }

    /// Lines intersecting `rect` (view coordinates).
    func lines(in rect: NSRect) -> ClosedRange<Int> {
        guard let layout = layoutManager, let container = textContainer, !lineStarts.isEmpty else { return 0...0 }
        var r = rect
        r.origin.x = 0
        r.size.width = container.containerSize.width
        r.origin.y -= textContainerOrigin.y
        let glyphs = layout.glyphRange(forBoundingRect: r, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = SheetText.lineIndex(containing: chars.location, lineStarts: lineStarts)
        var last = SheetText.lineIndex(containing: max(chars.location, NSMaxRange(chars)), lineStarts: lineStarts)
        // The empty last line has no glyphs; include it when the rect reaches it.
        if last == lineStarts.count - 2, let extra = lineRect(lineStarts.count - 1), extra.intersects(rect) {
            last += 1
        }
        return first...max(first, last)
    }

    // MARK: Editing helpers

    /// Replaces everything as one undoable step.
    func replaceAll(with text: String, actionName: String) {
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        undoManager?.setActionName(actionName)
        setSelectedRange(NSRange(location: 0, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Accessibility

    /// NSTextView doesn't expose subviews; add the results column so VoiceOver can reach it.
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + [resultsView]
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let suggestion, let origin = suggestionOrigin() {
            // Opaque (blended with the background), since overlapping redraws of a
            // translucent colour would darken it.
            let grey = theme.background.blended(withFraction: 0.45, of: theme.text) ?? theme.comment
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 15), .foregroundColor: grey]
            (suggestion as NSString).draw(at: origin, withAttributes: attrs)
        }
        if string.isEmpty {
            let base = font ?? NSFont.systemFont(ofSize: 15)
            let attrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: theme.comment]
            ("Type a calculation, like 120 + 15%" as NSString).draw(at: textContainerOrigin, withAttributes: attrs)
            let small = NSFont.systemFont(ofSize: (base.pointSize * 0.8).rounded())
            let hint: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: theme.comment]
            let y = textContainerOrigin.y + (layoutManager?.defaultLineHeight(for: base) ?? base.pointSize * 1.2) * 1.5
            ("Help ▸ Tally Syntax Guide lists everything Tally understands." as NSString)
                .draw(at: NSPoint(x: textContainerOrigin.x, y: y), withAttributes: hint)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        if string.isEmpty || (string as NSString).length < 2 { needsDisplay = true }
    }
}
