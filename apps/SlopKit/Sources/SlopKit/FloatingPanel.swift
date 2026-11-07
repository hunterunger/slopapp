import AppKit
import SwiftUI

/// A non-activating floating panel hosting SwiftUI: the app you were in keeps focus, but the
/// panel still gets key events. Use for pickers, quick-access thumbnails and search panels.
///
///     let panel = FloatingPanel { PickerView(...) }
///     panel.keyHandler = { event in            // optional: return true if handled
///         if let n = event.digit { choose(n); return true }
///         return false
///     }
///     panel.show(at: .nearMouse)
///
/// Esc and clicking elsewhere dismiss it (`dismissesOnResignKey`).
///
/// Corners: the panel's radius (default `Radius.xl`) reaches the content as
/// `@Environment(\.floatingPanelCornerRadius)`, and the content's container shape is the
/// panel's own, so inner shapes stay concentric:
///
///     .padding(Spacing.s)                                  // around the rows
///     RoundedRectangle(cornerRadius: Radius.nested(in: panelRadius, padding: Spacing.s))
///     // or, on macOS 26+, ConcentricRectangle() / windowConcentric(fill:inset:)
@MainActor
public final class FloatingPanel: NSPanel {
    /// Called for every key press before SwiftUI sees it. Return true to swallow it.
    public var keyHandler: ((NSEvent) -> Bool)?
    /// Called after the panel hides, however it was dismissed.
    public var onDismiss: (() -> Void)?
    /// Hide when the user clicks outside or switches apps. Default true.
    public var dismissesOnResignKey = true

    /// The panel's corner radius. Content gets it as `floatingPanelCornerRadius`.
    public let cornerRadius: CGFloat
    private let hostingView: NSHostingView<AnyView>

    public init<Content: View>(cornerRadius: CGFloat = Radius.xl, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        hostingView = NSHostingView(rootView: Self.root(content(), cornerRadius: cornerRadius))
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        contentView = Self.materialView(wrapping: hostingView, cornerRadius: cornerRadius)
        // Liquid Glass draws its own rounded shadow; the window's would be square.
        hasShadow = !Self.usesGlass
    }

    /// Replaces the panel's SwiftUI content.
    public func setContent<Content: View>(@ViewBuilder _ content: () -> Content) {
        hostingView.rootView = Self.root(content(), cornerRadius: cornerRadius)
    }

    /// The content with the panel's radius in its environment and as its container shape.
    private static func root(_ content: some View, cornerRadius: CGFloat) -> AnyView {
        AnyView(
            content
                .environment(\.floatingPanelCornerRadius, cornerRadius)
                .containerShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    /// Sizes the panel to its content, places it, and shows it without activating the app.
    public func show(at placement: PanelPlacement) {
        let size = hostingView.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        setFrame(placement.frame(size: size, mouse: mouse, visibleFrame: visible), display: true)
        orderFrontRegardless()
        makeKey()
        invalidateShadow()
    }

    public func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        onDismiss?()
    }

    override public func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Esc
                dismiss()
                return
            }
            if keyHandler?(event) == true { return }
        }
        super.sendEvent(event)
    }

    override public func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override public func resignKey() {
        super.resignKey()
        if dismissesOnResignKey { dismiss() }
    }

    static var usesGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Liquid Glass on macOS 26+, the popover material before that.
    static func materialView(wrapping content: NSView, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Regular (never `.clear`): the text-bearing style, which follows the person's
            // clear-to-tinted setting in System Settings › Appearance and Reduce Transparency
            // and keeps text legible over anything. No tint: that would fake the setting.
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return pinned(glass)
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return pinned(effect)
    }

    /// Wraps a material view in a clear, layer-backed container so the borderless window
    /// shows only the rounded shape (and its shadow), not a square frame.
    private static func pinned(_ view: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}

extension EnvironmentValues {
    /// The corner radius of the `FloatingPanel` (or `HUD`) this view is in; `Radius.xl`
    /// outside one. Use it for concentric inner shapes: `Radius.nested(in: radius, padding: p)`.
    @Entry public var floatingPanelCornerRadius: CGFloat = Radius.xl
}

extension NSEvent {
    /// 1–9 if this key press is a bare digit (number row or keypad), for "press 1 to pick".
    public var digit: Int? {
        guard modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = charactersIgnoringModifiers, chars.count == 1,
              let value = Int(chars), (1...9).contains(value) else { return nil }
        return value
    }
}
