import AppKit
import TallyCore

/// Draws each line's result right-aligned beside it, handles clicks (copy), and exposes
/// results to VoiceOver as one element per line.
final class ResultsColumnView: NSView {
    weak var textView: SheetTextView?
    private var hoveredLine: Int?
    private var flashLine: Int?
    private var tracking: NSTrackingArea?
    private var elements: [Int: ResultElement] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = []
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Results")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func resultsChanged() {
        elements.removeAll()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    // MARK: Geometry

    /// Where `line`'s result is drawn, in this view's coordinates.
    func resultRect(_ line: Int) -> NSRect? {
        guard let tv = textView, tv.displays.indices.contains(line), let display = tv.displays[line],
              let lineRect = tv.lineRect(line) else { return nil }
        let font = display.kind == .value ? tv.resultFont : tv.errorFont
        let textHeight = ceil(lineHeight(font))
        let width = min(bounds.width * 0.6, tv.resultWidth(display))
        let height = ceil(lineHeight(tv.resultFont))
        let y = lineRect.minY + max(0, (min(lineRect.height, height) - textHeight) / 2)
        return NSRect(x: bounds.width - width, y: y, width: width, height: textHeight)
    }

    private func lineHeight(_ font: NSFont) -> CGFloat {
        textView?.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.2
    }

    private func line(at point: NSPoint) -> Int? {
        guard let tv = textView else { return nil }
        let probe = NSRect(x: 0, y: point.y - 1, width: 1, height: 2)
        for line in tv.lines(in: probe) {
            if let r = resultRect(line), r.insetBy(dx: -6, dy: -3).contains(point) { return line }
        }
        return nil
    }

    /// Only results take clicks; everything else goes to the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return line(at: local) != nil ? self : nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView else { return }
        for line in tv.lines(in: dirtyRect) {
            guard tv.displays.indices.contains(line), let display = tv.displays[line], let rect = resultRect(line) else { continue }
            let clickable = display.kind == .value || display.opensCurrencySettings
            if clickable, line == hoveredLine || line == flashLine {
                let bg = rect.insetBy(dx: -5, dy: -2)
                NSColor.quaternaryLabelColor.withAlphaComponent(line == flashLine ? 0.6 : 0.35).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
            }
            var textRect = rect
            if display.isStale, let icon = NSImage(systemSymbolName: "clock", accessibilityDescription: "Old exchange rates") {
                let side = tv.resultFont.pointSize * 0.9
                let iconRect = NSRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
                let config = NSImage.SymbolConfiguration(pointSize: side, weight: .regular)
                    .applying(.init(hierarchicalColor: .secondaryLabelColor))
                icon.withSymbolConfiguration(config)?.draw(in: iconRect)
                textRect.origin.x += tv.resultFont.pointSize * 1.3
                textRect.size.width -= tv.resultFont.pointSize * 1.3
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            style.lineBreakMode = .byTruncatingHead
            let attrs: [NSAttributedString.Key: Any] = display.kind == .value
                ? [.font: tv.resultFont, .foregroundColor: NSColor.controlAccentColor, .paragraphStyle: style]
                : [.font: tv.errorFont, .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: style]
            (display.text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(line(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(nil)
    }

    private func setHovered(_ line: Int?) {
        guard line != hoveredLine else { return }
        let old = hoveredLine
        hoveredLine = line
        for l in [old, line].compactMap({ $0 }) {
            if let r = resultRect(l) { setNeedsDisplay(r.insetBy(dx: -8, dy: -4)) }
        }
        toolTip = line.flatMap { textView?.displays[safe: $0]??.help }
    }

    override func resetCursorRects() {
        guard let tv = textView else { return }
        for line in tv.lines(in: visibleRect) {
            guard let d = tv.displays[safe: line] ?? nil, d.kind == .value || d.opensCurrencySettings,
                  let r = resultRect(line) else { continue }
            addCursorRect(r.insetBy(dx: -6, dy: -3), cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let line = line(at: convert(event.locationInWindow, from: nil)) else {
            textView?.mouseDown(with: event)
            return
        }
        activate(line)
    }

    func activate(_ line: Int) {
        flashLine = line
        if let r = resultRect(line) { setNeedsDisplay(r.insetBy(dx: -8, dy: -4)) }
        textView?.onResultClick?(line)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, flashLine == line else { return }
            flashLine = nil
            if let r = resultRect(line) { setNeedsDisplay(r.insetBy(dx: -8, dy: -4)) }
        }
    }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        guard let tv = textView else { return [] }
        var children: [ResultElement] = []
        for (line, display) in tv.displays.enumerated() {
            guard let display else { continue }
            let element = elements[line] ?? ResultElement(column: self, line: line, display: display, lineText: lineText(line))
            elements[line] = element
            children.append(element)
        }
        return children
    }

    private func lineText(_ line: Int) -> String {
        guard let tv = textView else { return "" }
        return (tv.string as NSString).substring(with: tv.characterRange(ofLine: line)).trimmingCharacters(in: .whitespaces)
    }
}

/// One result, for VoiceOver: "Line 3, dinner + tip, result $219.95". Pressing it copies.
// Immutable after init and only touched on the main thread (AppKit accessibility).
final class ResultElement: NSAccessibilityElement, @unchecked Sendable {
    weak var column: ResultsColumnView?
    let line: Int
    let display: ResultDisplay

    init(column: ResultsColumnView, line: Int, display: ResultDisplay, lineText: String) {
        self.column = column
        self.line = line
        self.display = display
        super.init()
        let clickable = display.kind == .value || display.opensCurrencySettings
        setAccessibilityRole(clickable ? .button : .staticText)
        setAccessibilityParent(column)
        setAccessibilityEnabled(true)
        let kind = display.kind == .value ? "result" : "no result"
        let stale = display.isStale ? ", using old exchange rates" : ""
        setAccessibilityLabel("Line \(line + 1), \(lineText), \(kind) \(display.text)\(stale)")
        if display.kind == .value { setAccessibilityHelp(display.isStale ? display.help : "Copies the result") }
        if display.opensCurrencySettings { setAccessibilityHelp("Opens Currency settings") }
    }

    // Accessibility calls arrive on the main thread.
    override func accessibilityFrame() -> NSRect {
        let column = column
        let line = line
        return MainActor.assumeIsolated {
            guard let column, let rect = column.resultRect(line), let window = column.window else { return .zero }
            return window.convertToScreen(column.convert(rect, to: nil))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        let column = column
        let line = line
        guard display.kind == .value || display.opensCurrencySettings else { return false }
        return MainActor.assumeIsolated {
            guard let column else { return false }
            column.activate(line)
            return true
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
