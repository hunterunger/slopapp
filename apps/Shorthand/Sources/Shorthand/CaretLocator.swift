import AppKit
import ApplicationServices
import ShorthandCore
import SlopKit

/// SlopKit candidate: where the text caret is in another app, through Accessibility. The
/// caret's own rect where the app reports it (most Cocoa apps, Safari, Chromium), else the
/// focused field's frame, else nil (place the panel in the screen's centre). Never waits
/// long on a busy app. Returns AppKit screen coordinates.
@MainActor
enum CaretLocator {
    struct Anchor {
        var rect: CGRect
        /// The caret itself (align with it) rather than a whole field (centre on it).
        var isCaret: Bool
    }

    static func anchor(pid: pid_t?) -> Anchor? {
        let root = pid.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.1)
        guard let focused = copy(root, kAXFocusedUIElementAttribute) , CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        let height = NSScreen.screens.first?.frame.height ?? 0
        if let caret = caretRect(element) {
            return Anchor(rect: CaretPlacement.appKitRect(fromAccessibility: caret, mainScreenHeight: height), isCaret: true)
        }
        if let frame = frame(element) {
            return Anchor(rect: CaretPlacement.appKitRect(fromAccessibility: frame, mainScreenHeight: height), isCaret: false)
        }
        return nil
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func caretRect(_ element: AXUIElement) -> CGRect? {
        guard let rangeValue = copy(element, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        func bounds(_ r: CFRange) -> CGRect? {
            var r = r
            guard let value = AXValueCreate(.cfRange, &r) else { return nil }
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &result) == .success,
                  let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.height > 0, rect.origin != .zero || rect.width > 0 else { return nil }
            return rect
        }
        if let rect = bounds(range) { return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: rect.height) }
        // An empty range often has no bounds: use the character before the caret.
        if range.location > 0, let rect = bounds(CFRange(location: range.location - 1, length: 1)) {
            return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
        }
        return nil
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = copy(element, kAXPositionAttribute), let size = copy(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }
}

extension FloatingPanel {
    /// Shows the panel next to `anchor` (AppKit coordinates), or centred when there's none.
    func show(near anchor: CaretLocator.Anchor?) {
        guard let anchor else {
            show(at: .center)
            return
        }
        let size = contentView?.fittingSize ?? CGSize(width: 420, height: 240)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor.rect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        setFrame(CaretPlacement.frame(size: size, anchor: anchor.rect, visibleFrame: visible, leading: anchor.isCaret), display: true)
        orderFrontRegardless()
        makeKey()
        invalidateShadow()
    }
}
