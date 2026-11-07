import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The menu bar icon and the panel under it.
///
/// Like the original's default "split" icon: the eyedropper half picks a color, the small
/// arrow opens the panel. "Single icon" (Settings) makes the whole icon open the panel.
/// A right-click, or an Accessibility press (VoiceOver, scripts), always opens the panel.
/// A dot shows the last picked color (Settings › General).
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private var item: NSStatusItem?
    private var panel: StatusPanel?
    private var appliedIconVisibility = true
    private var lastClosed = Date.distantPast
    /// The app that was in front when the panel opened, to hand focus back like a menu does.
    private var previousApp: NSRunningApplication?

    init(controller: AppController) {
        self.controller = controller
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "DropperStatusItem"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Dropper")
        item.button?.toolTip = "Dropper"
        self.item = item
        appliedIconVisibility = MenuBarIcon.isVisible
        item.isVisible = appliedIconVisibility
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, MenuBarIcon.isVisible != self.appliedIconVisibility else { return }
                self.appliedIconVisibility = MenuBarIcon.isVisible
                DispatchQueue.main.async { self.item?.isVisible = self.appliedIconVisibility }
            }
        }
        updateIcon()
    }

    /// Redraws the icon whenever what it shows changes.
    private func updateIcon() {
        let state = withObservationTracking {
            (controller.settings.iconStyle, controller.settings.tintIcon ? controller.model.history.latest?.color : nil,
             controller.model.isPicking)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        item?.button?.image = StatusIcon.image(split: state.0 == .split, color: state.1, picking: state.2)
        item?.button?.setAccessibilityHelp(state.0 == .split ? "Opens the Dropper panel. Click the eyedropper to pick a color." : nil)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isMouse = event?.type == .leftMouseUp || event?.type == .rightMouseUp
        if isMouse, event?.type == .leftMouseUp, controller.settings.iconStyle == .split, let event {
            let point = sender.convert(event.locationInWindow, from: nil)
            if StatusIcon.isPickArea(x: point.x, buttonWidth: sender.bounds.width) {
                closePanel()
                controller.pickAndCopy()
                return
            }
        }
        // A click on the icon while the panel is open first closes it (resign key), then
        // arrives here: don't reopen straight away.
        if Date().timeIntervalSince(lastClosed) < 0.3 { return }
        togglePanel()
    }

    // MARK: Panel

    var isPanelShown: Bool { panel?.isVisible == true }

    func togglePanel() {
        if isPanelShown { closePanel() } else { showPanel() }
    }

    func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        controller.panelState.list = nil
        panel.layoutForContent()
        panel.setFrameTopLeftPoint(anchorPoint(for: panel.frame.size))
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        AppActivation.activate()
        panel.makeKeyAndOrderFront(nil)
        item?.button?.highlight(true)
        Diagnostics.record("panel shown")
    }

    /// Keeps the panel's top edge where it is while its content grows or shrinks.
    func panelSizeChanged() {
        guard let panel, panel.isVisible else { return }
        let top = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        DispatchQueue.main.async {
            panel.layoutForContent()
            panel.setFrameTopLeftPoint(top)
        }
    }

    func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        item?.button?.highlight(false)
        lastClosed = Date()
        // Still in front (Esc, a pick, an action) and no Dropper window open: give focus
        // back. If the person clicked another app, it already has focus.
        let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.level == .normal && $0.styleMask.contains(.titled) }
        if NSApp.isActive, !ownWindowOpen, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func makePanel() -> StatusPanel {
        let panel = StatusPanel(controller: controller)
        panel.delegate = self
        return panel
    }

    /// Under the icon, kept on screen. If the icon is hidden (crowded menu bar), top right
    /// of the screen with the pointer.
    private func anchorPoint(for size: CGSize) -> CGPoint {
        if let button = item?.button, let window = button.window, item?.isVisible == true,
           let screen = window.screen ?? NSScreen.main {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen.visibleFrame
            let x = min(max(frame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            return CGPoint(x: x, y: frame.minY - 6)
        }
        let visible = (NSScreen.underPointer ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - 6)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Menus opened from the panel don't take key; alerts and other windows do.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow,
                  panel.attachedSheet == nil else { return }
            self.closePanel()
        }
    }
}

/// The status item's image: an eyedropper, a dot of the last color, and (split style) an
/// arrow. Drawn at display time so the glyph follows the menu bar's appearance.
@MainActor
enum StatusIcon {
    static let glyphWidth: CGFloat = 18
    static let arrowWidth: CGFloat = 9

    static func isPickArea(x: CGFloat, buttonWidth: CGFloat) -> Bool {
        x < buttonWidth - arrowWidth - 4
    }

    static func image(split: Bool, color: ColorValue?, picking: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: picking ? "eyedropper.full" : "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        let width = glyphWidth + (split ? arrowWidth + 3 : 0)
        let size = NSSize(width: width, height: 18)
        guard color != nil else {
            // Plain template image: macOS tints it for the menu bar.
            let image = NSImage(size: size, flipped: false) { _ in
                symbol?.draw(at: CGPoint(x: 1, y: (18 - (symbol?.size.height ?? 14)) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                if split, let arrow {
                    arrow.draw(at: CGPoint(x: glyphWidth + 3, y: (18 - arrow.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                }
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = "Dropper"
            return image
        }
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = NSColor.labelColor
            func drawTinted(_ glyph: NSImage?, at point: CGPoint) {
                guard let glyph else { return }
                let tinted = NSImage(size: glyph.size, flipped: false) { rect in
                    glyph.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(at: point, from: .zero, operation: .sourceOver, fraction: 1)
            }
            drawTinted(symbol, at: CGPoint(x: 1, y: (18 - (symbol?.size.height ?? 14)) / 2 + 1))
            if split { drawTinted(arrow, at: CGPoint(x: glyphWidth + 3, y: (18 - (arrow?.size.height ?? 6)) / 2)) }
            if let color {
                let dot = NSBezierPath(ovalIn: CGRect(x: glyphWidth - 8, y: 0.5, width: 8, height: 8))
                color.nsColor.setFill()
                dot.fill()
                ink.withAlphaComponent(0.55).setStroke()
                dot.lineWidth = 1
                dot.stroke()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Dropper"
        return image
    }
}

/// The panel under the menu bar icon: borderless, rounded, material; Esc closes.
@MainActor
final class StatusPanel: NSPanel {
    private let hosting: NSHostingView<AnyView>
    private unowned let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        hosting = NSHostingView(rootView: AnyView(
            PanelView(controller: controller, model: controller.model, settings: controller.settings)
        ))
        super.init(contentRect: CGRect(x: 0, y: 0, width: PanelView.width, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .utilityWindow
        title = "Dropper"
        setAccessibilityLabel("Dropper")
        contentView = Material.view(wrapping: hosting, cornerRadius: PanelView.cornerRadius)
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Sizes the panel to its SwiftUI content.
    func layoutForContent() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        setContentSize(CGSize(width: PanelView.width, height: max(size.height, 200)))
    }

    override func cancelOperation(_ sender: Any?) {
        if controller.panelState.list != nil {
            controller.panelState.list = nil
        } else {
            controller.statusItem.closePanel()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            controller.statusItem.closePanel()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "," {
            controller.showSettings()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Liquid Glass on macOS 26+, the popover material before that, clipped to a rounded rect.
/// (SlopKit's `FloatingPanel` has the same helper internally; candidate to make public.)
@MainActor
enum Material {
    static func view(wrapping content: NSView, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Regular, never `.clear`: the text-bearing style, which follows the clear-to-
            // tinted setting and Reduce Transparency and keeps text legible. No tint.
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
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
        return effect
    }
}
