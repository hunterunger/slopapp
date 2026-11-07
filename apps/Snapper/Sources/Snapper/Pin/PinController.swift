import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// Pinned captures: floating, always-on-top image windows you can move, resize, fade and
/// close with Esc.
@MainActor
final class PinController {
    private unowned let model: AppModel
    private var panels: [PinPanel] = []

    init(model: AppModel) {
        self.model = model
    }

    var isEmpty: Bool { panels.isEmpty }
    var count: Int { panels.count }

    /// Pins are part of what's on screen, so captures keep them.
    var windowNumbers: Set<CGWindowID> {
        Set(panels.filter(\.isVisible).map { CGWindowID($0.windowNumber) })
    }

    func contains(_ item: CaptureItem) -> Bool { panels.contains { $0.item === item } }
    var items: [CaptureItem] { panels.map(\.item) }

    func pin(_ item: CaptureItem) {
        let screen = NSScreen.screens.first { $0.displayID == item.displayID } ?? NSScreen.underPointer ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = PinGeometry.initialSize(imagePoints: item.size, visible: visible.size)
        // Cascade new pins so they don't land exactly on top of each other.
        let offset = CGFloat(panels.count % 8) * 24
        let center = CGPoint(x: visible.midX + offset, y: visible.midY - offset)
        let panel = PinPanel(item: item, frame: PinGeometry.frame(size: size, centeredAt: center), controller: self)
        panels.append(panel)
        model.openPins = panels.count
        panel.applyStyle(rounded: model.pinRoundedCorners, shadow: model.pinShadow, border: model.pinBorder)
        panel.orderFrontRegardless()
        panel.makeKey()
        Diagnostics.record("pinned pixels=\(item.pixelSizeDescription) pins=\(panels.count)")
    }

    /// Applies the pin settings (corners, shadow, border) to every pin.
    func restyle() {
        for panel in panels {
            panel.applyStyle(rounded: model.pinRoundedCorners, shadow: model.pinShadow, border: model.pinBorder)
        }
    }

    func close(_ panel: PinPanel) {
        panels.removeAll { $0 === panel }
        model.openPins = panels.count
        panel.orderOut(nil)
        panel.close()
        model.remember(panel.item)
    }

    func closeAll() {
        for panel in panels { close(panel) }
    }

    func copy(_ panel: PinPanel) { model.copy(panel.item, closeCard: false) }
    func save(_ panel: PinPanel) { model.save(panel.item, closeCard: false) }

    func annotate(_ panel: PinPanel) {
        let item = panel.item
        panels.removeAll { $0 === panel }
        model.openPins = panels.count
        panel.orderOut(nil)
        panel.close()
        EditorWindowController.open(item, model: model)
    }
}

/// One pinned capture.
@MainActor
final class PinPanel: NSPanel {
    let item: CaptureItem
    private unowned let controller: PinController
    private let imageView: PinImageView

    init(item: CaptureItem, frame: CGRect, controller: PinController) {
        self.item = item
        self.controller = controller
        imageView = PinImageView(image: item.image)
        super.init(contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentAspectRatio = item.size
        minSize = CGSize(width: PinGeometry.minimumSide, height: PinGeometry.minimumSide)
        title = "Pinned Capture"
        contentView = imageView
        imageView.panel = self
        setAccessibilityLabel("Pinned capture")
        imageView.menu = makeMenu()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 53 { controller.close(self); return } // Esc
        if let arrow = ArrowKey(keyCode: event.keyCode), flags.subtracting(.shift).isEmpty {
            let delta = SelectionGeometry.nudge(for: arrow, large: flags.contains(.shift))
            setFrameOrigin(CGPoint(x: frame.minX + delta.dx, y: frame.minY + delta.dy))
            return
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.isEmpty, let digit = Int(key), let opacity = PinGeometry.opacity(forDigit: digit) {
            setOpacity(opacity)
            return
        }
        switch (flags, key) {
        case ([.command], "c"): controller.copy(self)
        case ([.command], "s"): controller.save(self)
        case ([.command], "e"): controller.annotate(self)
        case ([.command], "w"): controller.close(self)
        case ([.command], "="), ([.command, .shift], "="), ([.command], "+"): zoom(by: PinGeometry.zoomStep)
        case ([.command], "-"): zoom(by: 1 / PinGeometry.zoomStep)
        case ([.command], "0"): actualSize()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller.close(self)
    }

    func applyStyle(rounded: Bool, shadow: Bool, border: Bool) {
        // A window capture with a transparent shadow margin is already shaped: a border or
        // rounding would draw a frame around its invisible margin.
        let framed = imageView.edgesAreOpaque
        imageView.layer?.cornerRadius = rounded && framed ? PinImageView.cornerRadius : 0
        imageView.showsBorder = border && framed
        hasShadow = shadow
        invalidateShadow()
    }

    // MARK: Actions

    func setOpacity(_ value: Double) {
        alphaValue = PinGeometry.clampedOpacity(value)
    }

    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        let limit = screen?.visibleFrame.size ?? CGSize(width: 4000, height: 4000)
        let size = PinGeometry.zoomed(frame.size, by: factor, limit: limit)
        let center = anchor ?? CGPoint(x: frame.midX, y: frame.midY)
        setFrame(PinGeometry.frame(size: size, centeredAt: center), display: true)
    }

    func actualSize() {
        let limit = screen?.visibleFrame.size ?? item.size
        setFrame(PinGeometry.frame(size: PinGeometry.fit(item.size, into: limit), centeredAt: CGPoint(x: frame.midX, y: frame.midY)), display: true)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Pinned Capture")
        menu.addItem(MenuAction("Copy", key: "c") { [unowned self] in controller.copy(self) })
        menu.addItem(MenuAction("Save", key: "s") { [unowned self] in controller.save(self) })
        menu.addItem(MenuAction("Annotate", key: "e") { [unowned self] in controller.annotate(self) })
        menu.addItem(.separator())
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Opacity")
        for (title, value) in [("100%", 1.0), ("75%", 0.75), ("50%", 0.5), ("25%", 0.25)] {
            sub.addItem(MenuAction(title) { [unowned self] in setOpacity(value) })
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(MenuAction("Zoom In", key: "=") { [unowned self] in zoom(by: PinGeometry.zoomStep) })
        menu.addItem(MenuAction("Zoom Out", key: "-") { [unowned self] in zoom(by: 1 / PinGeometry.zoomStep) })
        menu.addItem(MenuAction("Actual Size", key: "0") { [unowned self] in actualSize() })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Close", key: "w") { [unowned self] in controller.close(self) })
        return menu
    }
}

/// The pin's content: the image with rounded corners and a hairline border, a close button
/// on hover, pinch or ⌘-scroll to zoom.
@MainActor
final class PinImageView: NSView {
    weak var panel: PinPanel?
    private var closeButton: NSView!
    private var tracking: NSTrackingArea?

    /// The capture fills its rectangle (not a window capture with a transparent margin).
    let edgesAreOpaque: Bool

    init(image: CGImage) {
        edgesAreOpaque = ImageEdges.areOpaque(image)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        // The same round material button as on the thumbnails.
        let button = NSHostingView(rootView: CornerButton("Close", systemImage: "xmark") { [weak self] in self?.closePin() }
            .help("Close (Esc)"))
        // SNAPPER_CARD_HOVER also shows the pin's hover button, for screenshots.
        button.alphaValue = Diagnostics.forceCardHover ? 1 : 0
        closeButton = button
        addSubview(closeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Pinned capture")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static let cornerRadius = Radius.m
    /// The close button's square, `Spacing.s` in from the top and leading edges.
    private static let buttonSide: CGFloat = 24

    /// A one-device-pixel border in the separator colour (Settings → Pinned Screenshots).
    var showsBorder = true {
        didSet { updateBorder() }
    }

    private func updateBorder() {
        layer?.borderWidth = showsBorder ? pixelWidth : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        closeButton.frame = CGRect(x: Spacing.s, y: bounds.height - Spacing.s - Self.buttonSide,
                                   width: Self.buttonSide, height: Self.buttonSide)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBorder()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBorder()
    }

    override func viewDidChangeEffectiveAppearance() { updateBorder() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { fadeCloseButton(to: 1) }
    override func mouseExited(with event: NSEvent) { if !Diagnostics.forceCardHover { fadeCloseButton(to: 0) } }

    private func fadeCloseButton(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            closeButton.animator().alphaValue = alpha
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        panel?.makeKey()
        super.mouseDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        panel?.zoom(by: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.scrollWheel(with: event) }
        panel?.zoom(by: event.scrollingDeltaY > 0 ? 1.05 : 1 / 1.05)
    }

    private func closePin() {
        guard let panel else { return }
        panel.cancelOperation(nil)
    }
}

/// An NSMenuItem that runs a closure.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

extension NSView {
    /// One device pixel in points, for layer borders.
    var pixelWidth: CGFloat { 1 / max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1) }
}
