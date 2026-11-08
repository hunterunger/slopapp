import AppKit
import GaugeCore
import SlopKit

/// The one status item. Its content is drawn into a single template image: symbols and text
/// in fixed slots, so the item never changes width and macOS tints it for any menu bar
/// (light, dark, tinted glass). A redraw costs a few milliseconds of AppKit work on macOS 27
/// whatever we draw, so `RedrawPolicy` decides how often this is called; drawing the image
/// itself is cheap.
@MainActor
final class StatusItemController: NSObject {
    let item: NSStatusItem
    /// The item's button was pressed: a click on macOS 14–26, or VoiceOver / Accessibility
    /// pressing it on any version.
    var onPress: (() -> Void)?
    /// macOS 27 began the item's expanded session (a click, or keyboard navigation of the
    /// menu bar).
    var onSessionBegin: (() -> Void)?
    /// macOS 27 ended the expanded session (a click elsewhere, Esc in the menu bar).
    var onSessionEnd: (() -> Void)?
    /// The person ⌘-dragged the item out of the menu bar.
    var onRemoved: (() -> Void)?

    private var layout: MenuBarLayout?
    /// `GAUGE_LOG_RENDERS=1`: every redraw goes to stderr (for measuring the redraw rate).
    private static let logsRenders = ProcessInfo.processInfo.environment["GAUGE_LOG_RENDERS"] != nil
    private var visibilityObservation: NSKeyValueObservation?
    private(set) var lastContent: MenuBarContent?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "GaugeStatusItem"
        item.behavior = .removalAllowed
        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "Gauge"
        button.setAccessibilityLabel("Gauge")
        // The action stays on macOS 27 too: an Accessibility press (VoiceOver, scripts) reaches
        // the button, not the expanded session.
        adoptExpandedInterface()
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated { self?.onRemoved?() }
        }
    }

    /// On macOS 27 the menu bar owns open and close: the item highlights, keyboard navigation
    /// works, and a second click closes instead of reopening.
    private func adoptExpandedInterface() {
        #if compiler(>=6.4)
        if #available(macOS 27, *) { item.expandedInterfaceDelegate = self }
        #endif
    }

    /// Ends the macOS 27 session when the panel closes itself (Esc, an action).
    func endSession() {
        #if compiler(>=6.4)
        if #available(macOS 27, *) { item.expandedInterfaceSession?.cancel() }
        #endif
    }

    var hasSession: Bool {
        #if compiler(>=6.4)
        if #available(macOS 27, *) { return item.expandedInterfaceSession != nil }
        #endif
        return false
    }

    @objc private func clicked() {
        onPress?()
    }

    // MARK: Drawing

    func render(_ content: MenuBarContent) {
        lastContent = content
        if Self.logsRenders {
            FileHandle.standardError.write(Data("render \(Date().timeIntervalSince1970) \(content.drawnText)\n".utf8))
        }
        // Hidden (Settings, or ⌘-dragged out): nothing to draw until it's back.
        guard let button = item.button, item.isVisible else { return }
        if layout?.key != content.layoutKey {
            layout = MenuBarLayout(content: content)
        }
        guard let layout else { return }
        button.image = layout.image(for: content)
        button.setAccessibilityLabel(content.accessibilityLabel)
    }

    /// Where the panel should hang from: the item's frame on screen, if it's showing.
    var anchorFrame: NSRect? {
        guard item.isVisible, let window = item.button?.window, window.isVisible else { return nil }
        let frame = window.frame
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }
        return frame
    }

    var isVisible: Bool {
        get { item.isVisible }
        set {
            guard item.isVisible != newValue else { return }
            item.isVisible = newValue
            if newValue, let lastContent { render(lastContent) }
        }
    }
}

#if compiler(>=6.4)
@available(macOS 27, *)
extension StatusItemController: NSStatusItemExpandedInterfaceDelegate {
    nonisolated func statusItem(_ statusItem: NSStatusItem,
                                didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated { onSessionBegin?() }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        MainActor.assumeIsolated { onSessionEnd?() }
    }
}
#endif

/// Fixed slot widths for one readout configuration, measured once with the menu bar font.
@MainActor
struct MenuBarLayout {
    let key: String
    let font: NSFont
    /// Per segment: the symbol's size (if any) and each field's slot width.
    let segments: [(symbol: NSSize?, fields: [CGFloat])]
    let size: NSSize
    /// Configured symbols, looked up once per layout (the battery's changes with its level).
    let symbols: [String: NSImage]

    static let symbolGap: CGFloat = 3
    static let fieldGap: CGFloat = 6
    static let segmentGap: CGFloat = 8
    static let emptySymbol = "gauge.with.dots.needle.33percent"

    init(content: MenuBarContent) {
        key = content.layoutKey
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var segments: [(NSSize?, [CGFloat])] = []
        var symbols: [String: NSImage] = [:]
        var width: CGFloat = 0
        for (index, segment) in content.segments.enumerated() {
            if index > 0 { width += Self.segmentGap }
            var symbolSize: NSSize?
            if let name = segment.symbol, let image = Self.symbol(name, font: font) {
                symbols[name] = image
                symbolSize = image.size
                width += image.size.width + Self.symbolGap
            }
            var fields: [CGFloat] = []
            for (fieldIndex, field) in segment.fields.enumerated() {
                if fieldIndex > 0 { width += Self.fieldGap }
                let slot = ceil(field.candidates.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
                fields.append(slot)
                width += slot
            }
            segments.append((symbolSize, fields))
        }
        if content.segments.isEmpty, let image = Self.symbol(Self.emptySymbol, font: font) {
            symbols[Self.emptySymbol] = image
            width = image.size.width
        }
        self.segments = segments
        self.symbols = symbols
        let height = ceil(font.ascender - font.descender + font.leading)
        self.size = NSSize(width: ceil(width), height: max(height, 16))
    }

    static func symbol(_ name: String, font: NSFont) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular))
    }

    /// The whole item as one template image, rendered once into bitmaps (one per screen
    /// scale). macOS draws the item once per menu bar it appears in (every Space and display),
    /// so a bitmap that's only copied is much cheaper than drawing text and symbols each time.
    func image(for content: MenuBarContent) -> NSImage {
        let image = NSImage(size: size)
        let scales = Set(NSScreen.screens.map(\.backingScaleFactor) + [2]).sorted()
        for scale in scales {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                             pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(content)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        image.accessibilityDescription = content.accessibilityLabel
        return image
    }

    private func draw(_ content: MenuBarContent) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textY = (size.height - (font.ascender - font.descender)) / 2
        if content.segments.isEmpty, let symbol = symbols[Self.emptySymbol] {
            symbol.draw(in: NSRect(x: 0, y: (size.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            return
        }
        var x: CGFloat = 0
        for (index, segment) in content.segments.enumerated() where index < segments.count {
            if index > 0 { x += Self.segmentGap }
            let metrics = segments[index]
            if let name = segment.symbol, let symbolSize = metrics.symbol {
                let symbol = symbols[name] ?? Self.symbol(name, font: font)
                symbol?.draw(in: NSRect(x: x, y: (size.height - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height))
                x += symbolSize.width + Self.symbolGap
            }
            for (fieldIndex, field) in segment.fields.enumerated() where fieldIndex < metrics.fields.count {
                if fieldIndex > 0 { x += Self.fieldGap }
                // Values sit at the right of their slot, so the % sign and units stay put as
                // the digits change.
                let text = field.text as NSString
                let width = text.size(withAttributes: attributes).width
                text.draw(at: NSPoint(x: x + max(0, metrics.fields[fieldIndex] - width), y: textY), withAttributes: attributes)
                x += metrics.fields[fieldIndex]
            }
        }
    }
}
