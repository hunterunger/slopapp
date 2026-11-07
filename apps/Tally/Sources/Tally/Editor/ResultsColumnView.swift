import AppKit
import SlopKit
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

    /// Where `line`'s result is drawn, in this view's coordinates: right-aligned, on the
    /// line's own baseline (errors use a smaller font, so centring would sit them high).
    func resultRect(_ line: Int) -> NSRect? {
        guard let tv = textView, tv.displays.indices.contains(line), let display = tv.displays[line],
              let baseline = tv.baseline(ofLine: line) else { return nil }
        let font = display.kind == .value ? tv.resultFont : tv.errorFont
        let width = min(tv.maxResultWidth, tv.resultWidth(display))
        let height = ceil(font.ascender - font.descender)
        return NSRect(x: bounds.width - width, y: baseline - tv.baselineOffset(for: font), width: width, height: height)
    }

    /// The result doesn't fit its column and is drawn shortened.
    func isTruncated(_ line: Int) -> Bool {
        guard let tv = textView, let display = tv.displays[safe: line] ?? nil else { return false }
        return tv.resultWidth(display) > tv.maxResultWidth
    }

    /// The hover tip: the whole result when it's shortened, then what a click does.
    func toolTip(for line: Int) -> String? {
        guard let display = textView?.displays[safe: line] ?? nil else { return nil }
        guard isTruncated(line) else { return display.help }
        return [display.text, display.help].compactMap { $0 }.joined(separator: "\n")
    }

    /// The filled shape behind a hovered or clicked result.
    static let pillInset = NSSize(width: Spacing.xs, height: 2)

    private func pillRect(_ rect: NSRect) -> NSRect {
        rect.insetBy(dx: -Self.pillInset.width, dy: -Self.pillInset.height)
    }

    private func line(at point: NSPoint) -> Int? {
        guard let tv = textView else { return nil }
        let probe = NSRect(x: 0, y: point.y - 1, width: 1, height: 2)
        for line in tv.lines(in: probe) {
            if let r = resultRect(line), pillRect(r).contains(point) { return line }
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
                tv.theme.result.withAlphaComponent(line == flashLine ? 0.28 : 0.14).setFill()
                NSBezierPath(roundedRect: pillRect(rect), xRadius: Radius.s, yRadius: Radius.s).fill()
            }
            var textRect = rect
            if display.isStale, let icon = NSImage(systemSymbolName: "clock", accessibilityDescription: "Old exchange rates") {
                let side = tv.resultFont.pointSize * 0.9
                let iconRect = NSRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
                let config = NSImage.SymbolConfiguration(pointSize: side, weight: .regular)
                    .applying(.init(hierarchicalColor: tv.theme.comment))
                icon.withSymbolConfiguration(config)?.draw(in: iconRect)
                textRect.origin.x += tv.resultFont.pointSize * 1.3
                textRect.size.width -= tv.resultFont.pointSize * 1.3
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            // A shortened answer keeps its start and its unit ("Tue, Nov 3, 20…2:46:26 PM");
            // an error keeps its first words. The tooltip has the whole answer.
            style.lineBreakMode = display.kind == .value ? .byTruncatingMiddle : .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = display.kind == .value
                ? [.font: tv.resultFont, .foregroundColor: tv.theme.result, .paragraphStyle: style]
                : [.font: tv.errorFont, .foregroundColor: tv.theme.error, .paragraphStyle: style]
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
            if let r = resultRect(l) { setNeedsDisplay(pillRect(r).insetBy(dx: -1, dy: -1)) }
        }
        toolTip = line.flatMap { toolTip(for: $0) }
    }

    override func resetCursorRects() {
        guard let tv = textView else { return }
        for line in tv.lines(in: visibleRect) {
            guard let d = tv.displays[safe: line] ?? nil, d.kind == .value || d.opensCurrencySettings,
                  let r = resultRect(line) else { continue }
            addCursorRect(pillRect(r), cursor: .pointingHand)
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
        if let r = resultRect(line) { setNeedsDisplay(pillRect(r).insetBy(dx: -1, dy: -1)) }
        textView?.onResultClick?(line)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, flashLine == line else { return }
            flashLine = nil
            if let r = resultRect(line) { setNeedsDisplay(pillRect(r).insetBy(dx: -1, dy: -1)) }
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
