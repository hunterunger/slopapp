import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// Clicks and key presses, from wherever they come from.
@MainActor
protocol InputEvents: AnyObject {
    /// `click`: a mouse-down at a point (AppKit global points); `secondary` for right clicks.
    /// `key`: a key press (only called when keys are watched).
    func start(clicks: ((CGPoint, Bool) -> Void)?, keys: ((KeyStroke) -> Void)?)
    func stop()
}

/// NSEvent monitors: clicks need no permission; keys in other apps need Accessibility (without
/// it macOS just doesn't deliver them). Nothing is logged or kept.
@MainActor
final class SystemInputEvents: InputEvents {
    private var monitors: [Any] = []

    func start(clicks: ((CGPoint, Bool) -> Void)?, keys: ((KeyStroke) -> Void)?) {
        stop()
        if let clicks {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            let handle: (NSEvent) -> Void = { event in clicks(NSEvent.mouseLocation, event.type != .leftMouseDown) }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handle(event) }
            }) { monitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handle(event) }
                return event
            }) { monitors.append(local) }
        }
        if let keys {
            let handle: (NSEvent) -> Void = { event in
                guard let stroke = Self.stroke(from: event) else { return }
                keys(stroke)
            }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
                MainActor.assumeIsolated { handle(event) }
            }) { monitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
                MainActor.assumeIsolated { handle(event) }
                return event
            }) { monitors.append(local) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The key press, unless it's the record shortcut (stopping shouldn't end on its own keys).
    static func stroke(from event: NSEvent) -> KeyStroke? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let stop = KeyboardShortcuts.getShortcut(for: .recordScreen), stop.carbonKeyCode == Int(event.keyCode),
           flags.intersection([.command, .option, .shift, .control]) == stop.modifiers.intersection([.command, .option, .shift, .control]) {
            return nil
        }
        var modifiers: KeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return KeyStroke(keyCode: event.keyCode, key: event.characters(byApplyingModifiers: []) ?? "",
                         typed: event.characters ?? "", modifiers: modifiers, isRepeat: event.isARepeat)
    }
}

/// Test mode: no real input reaches a test recording; the `recordClick` / `recordKey*` hooks
/// feed the overlay instead.
@MainActor
final class NoInputEvents: InputEvents {
    func start(clicks: ((CGPoint, Bool) -> Void)?, keys: ((KeyStroke) -> Void)?) {}
    func stop() {}
}

/// A transparent, click-through window over the recorded area that draws a ring where you
/// click and a caption of the keys you press. It's our own window, kept in the recording.
@MainActor
final class InputOverlay {
    static private(set) weak var current: InputOverlay?

    private let panel: NSPanel
    private let root: NSView
    private let events: InputEvents
    private let showsClicks: Bool
    private let keyMode: KeystrokeMode?
    private var caption: KeystrokeCaption
    private var captionView: NSView?
    private var captionHost: NSHostingView<CaptionView>?
    private var expiry: Timer?
    private let area: CGRect

    var windowNumber: CGWindowID { CGWindowID(panel.windowNumber) }

    /// `area`: the recorded rect (AppKit global points).
    init(area: CGRect, clicks: Bool, keys: KeystrokeMode?, events: InputEvents) {
        self.area = area
        self.events = events
        showsClicks = clicks
        keyMode = keys
        caption = KeystrokeCaption(mode: keys ?? .shortcuts)
        panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(area, display: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.title = "Clicks and Keys"
        panel.setAccessibilityElement(false)
        root = NSView(frame: CGRect(origin: .zero, size: area.size))
        root.wantsLayer = true
        panel.contentView = root
        if keys != nil { makeCaption() }
        panel.orderFrontRegardless()
        Self.current = self
    }

    func start() {
        events.start(clicks: showsClicks ? { [weak self] point, secondary in self?.showClick(at: point, secondary: secondary) } : nil,
                     keys: keyMode != nil ? { [weak self] stroke in self?.show(stroke) } : nil)
        Diagnostics.record("input overlay started clicks=\(showsClicks) keys=\(keyMode?.rawValue ?? "off")")
    }

    func close() {
        events.stop()
        expiry?.invalidate()
        expiry = nil
        panel.orderOut(nil)
        panel.close()
        if Self.current === self { Self.current = nil }
    }

    // MARK: Clicks

    /// A ring that grows and fades where the click was (`point`: AppKit global points).
    func showClick(at point: CGPoint, secondary: Bool = false) {
        guard showsClicks, area.contains(point), let layer = root.layer else { return }
        Diagnostics.record("click ring shown")
        let local = CGPoint(x: point.x - area.minX, y: point.y - area.minY)
        let radius: CGFloat = 22
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: local.x - radius, y: local.y - radius, width: 2 * radius, height: 2 * radius)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius).insetBy(dx: 2, dy: 2), transform: nil)
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = secondary ? NSColor.systemOrange : NSColor.controlAccentColor
            ring.strokeColor = color.cgColor
            ring.fillColor = color.withAlphaComponent(0.22).cgColor
        }
        ring.lineWidth = 3
        layer.addSublayer(ring)
        let duration = 0.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        var animations: [CAAnimation] = [fade]
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.5
            grow.toValue = 1.2
            animations.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(group, forKey: "click")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { ring.removeFromSuperlayer() }
    }

    // MARK: Keys

    func show(_ stroke: KeyStroke) {
        guard keyMode != nil else { return }
        guard caption.feed(stroke, at: Diagnostics.now()) else { return }
        // Never the key itself: only that the caption changed.
        Diagnostics.record("key caption changed")
        update()
        if expiry == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.expire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            expiry = timer
        }
    }

    private func expire() {
        if caption.expire(at: Diagnostics.now()) { update() }
        if caption.text == nil {
            expiry?.invalidate()
            expiry = nil
        }
    }

    private func update() {
        guard let captionView else { return }
        // Set synchronously (not through observation) so the size below is the new text's.
        if let text = caption.text { captionHost?.rootView = CaptionView(text: text) }
        let visible = caption.text != nil
        if visible { layoutCaption() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.08 : 0.25
            captionView.animator().alphaValue = visible ? 1 : 0
        }
    }

    private func makeCaption() {
        let hosting = NSHostingView(rootView: CaptionView(text: " "))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        captionHost = hosting
        let height = CaptionView.height
        let container = KeyCaptionMaterial.view(wrapping: hosting, cornerRadius: height / 2)
        container.alphaValue = 0
        root.addSubview(container)
        captionView = container
    }

    /// Bottom center of the area, as wide as the text.
    private func layoutCaption() {
        guard let captionView, let captionHost else { return }
        captionHost.layoutSubtreeIfNeeded()
        let fitting = captionHost.fittingSize
        let width = min(max(fitting.width, CaptionView.height), area.width - 2 * Spacing.l)
        let bottom = min(Spacing.xxl * 2, area.height / 6)
        captionView.frame = CGRect(x: ((area.width - width) / 2).rounded(), y: bottom.rounded(), width: width.rounded(), height: CaptionView.height)
        captionHost.frame = captionView.bounds
    }
}

/// The keys, large and legible over anything.
struct CaptionView: View {
    static let height: CGFloat = 56
    let text: String

    var body: some View {
        Text(text)
            .font(.title.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.horizontal, Spacing.xl)
            .frame(height: Self.height)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// Liquid Glass on macOS 26+, the HUD material before that (SlopKit's panel material isn't
/// public; this mirrors it for a view inside another window).
@MainActor
enum KeyCaptionMaterial {
    static func view(wrapping content: NSView, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}
