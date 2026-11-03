import AppKit
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
    static let margin: CGFloat = 20
    static let gap: CGFloat = 16

    var resultFont: NSFont = .monospacedDigitSystemFont(ofSize: 15, weight: .medium) { didSet { widthCache.removeAll() } }
    var errorFont: NSFont = .systemFont(ofSize: 13) { didSet { widthCache.removeAll() } }
    /// Measured text widths; measuring 1,000 strings per keystroke would cost a few ms.
    private var widthCache: [String: CGFloat] = [:]

    var onResultClick: ((Int) -> Void)?

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
        smartInsertDeleteEnabled = false
        allowsDocumentBackgroundColorChange = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        textContainerInset = NSSize(width: Self.margin, height: 14)
        setAccessibilityLabel("Sheet")
        setAccessibilityHelp("Type one calculation per line. Results appear in the results column.")

        resultsView.textView = self
        addSubview(resultsView)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutColumns()
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
        let maxReserve = container.containerSize.width * 0.6
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
        if string.isEmpty {
            let base = font ?? NSFont.systemFont(ofSize: 15)
            let attrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: NSColor.placeholderTextColor]
            ("Type a calculation, like 120 + 15%" as NSString).draw(at: textContainerOrigin, withAttributes: attrs)
            let small = NSFont.systemFont(ofSize: (base.pointSize * 0.8).rounded())
            let hint: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: NSColor.tertiaryLabelColor]
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
