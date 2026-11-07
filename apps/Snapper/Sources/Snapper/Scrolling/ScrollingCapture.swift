import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// Scrolling capture: pick the scrolling part of a window, press Start, scroll down at your
/// own pace, press Done. Snapper keeps taking the same area (same filtered, test-mode-masked
/// snapshots as every other capture) and stitches what scrolled into view into one tall
/// image. A live preview grows next to the area.
@MainActor
final class ScrollingCapture {
    private(set) static weak var current: ScrollingCapture?

    private unowned let model: AppModel
    let region: PickedRegion
    private let state = ScrollingState()
    private var frame: RegionFrame?
    private var bar: FloatingPanel?
    private var preview: NSPanel?
    private var previewLayer = CALayer()
    private var previewCard: CALayer?
    private var stitcher: ScrollStitcher?
    private var loop: Task<Void, Never>?
    private var continuation: CheckedContinuation<CGImage?, Never>?

    init(model: AppModel, region: PickedRegion) {
        self.model = model
        self.region = region
    }

    /// Runs the session; the stitched image, or nil if cancelled.
    func run() async -> CGImage? {
        Self.current = self
        frame = RegionFrame(rect: region.global, dimOutside: false)
        showBar()
        Diagnostics.record("scrolling ready points=\(Int(region.local.width))x\(Int(region.local.height))")
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func start() {
        guard !state.started else { return }
        state.started = true
        showPreview()
        // The bar grows (height readout, Done): re-centre it once SwiftUI has laid it out.
        DispatchQueue.main.async { [weak self] in self?.placeBar() }
        loop = Task { [weak self] in await self?.captureLoop() }
        Diagnostics.record("scrolling started")
    }

    func finish() {
        guard state.started else { cancel(); return }
        loop?.cancel()
        Task {
            // Let the last capture land first.
            await loop?.value
            let image = stitcher?.image()
            Diagnostics.record("scrolling done frames=\(stitcher?.frameCount ?? 0) height=\(stitcher?.height ?? 0)")
            end(image)
        }
    }

    func cancel() {
        loop?.cancel()
        Diagnostics.record("scrolling cancelled")
        end(nil)
    }

    private func end(_ image: CGImage?) {
        bar?.onDismiss = nil
        bar?.orderOut(nil)
        bar?.close()
        bar = nil
        preview?.orderOut(nil)
        preview?.close()
        preview = nil
        frame?.close()
        frame = nil
        if Self.current === self { Self.current = nil }
        continuation?.resume(returning: image)
        continuation = nil
    }

    // MARK: Capturing

    private func grab() async -> CGImage? {
        guard let images = try? await model.capturer.snapshot(displays: [region.displayID], excluding: model.exclusions),
              let full = images[region.displayID] else { return nil }
        let scale = CGFloat(full.width) / region.screen.frame.width
        return full.cropping(to: ScreenCoordinates.pixelRect(local: region.local, screenSize: region.screen.frame.size, scale: scale))
    }

    private func captureLoop() async {
        guard let first = await grab(), let initial = ScrollStitcher(first: first) else {
            HUD.show("Couldn't capture that area", systemImage: "exclamationmark.triangle")
            cancel()
            return
        }
        stitcher = initial
        updatePreview()
        var lastPreview = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(120))
            guard let frame = await grab(), var current = stitcher else { break }
            let (next, result) = await Task.detached(priority: .userInitiated) { () -> (ScrollStitcher, ScrollStitcher.AddResult) in
                let result = current.add(frame)
                return (current, result)
            }.value
            stitcher = next
            switch result {
            case .appended(let rows):
                state.height = next.height
                state.lostTrack = false
                Diagnostics.record("scrolling appended rows=\(rows) height=\(next.height)")
            case .noMatch:
                state.lostTrack = true
            case .full:
                state.height = next.height
                Diagnostics.record("scrolling full height=\(next.height)")
                finish()
                return
            case .unchanged:
                break
            }
            if Date().timeIntervalSince(lastPreview) > 0.4 {
                updatePreview()
                lastPreview = Date()
            }
            if Task.isCancelled { break }
        }
    }

    // MARK: Chrome

    private func showBar() {
        let panel = FloatingPanel(cornerRadius: ControlBar.panelRadius) { ScrollingBar(session: self, state: state) }
        panel.dismissesOnResignKey = false
        panel.level = .statusBar
        panel.title = "Scrolling Capture"
        panel.setAccessibilityLabel("Scrolling capture controls")
        panel.onDismiss = { [weak self] in self?.cancel() }
        panel.keyHandler = { [weak self] event in
            guard let self, event.keyCode == 36 || event.keyCode == 76 else { return false }
            if self.state.started { self.finish() } else { self.start() }
            return true
        }
        bar = panel
        placeBar()
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()
    }

    /// Sizes the bar to its content, centred under the area (inside it when there's no room).
    private func placeBar() {
        guard let bar else { return }
        let size = bar.contentView?.fittingSize ?? CGSize(width: 300, height: ControlBar.height)
        let area = region.global, visible = region.screen.visibleFrame
        var frame = ControlBar.frame(size: size, under: area, visible: visible)
        if frame.maxY > area.minY, frame.minY < area.maxY, area.minY - size.height - Spacing.m < visible.minY {
            // No room below or above: inside the area's bottom edge.
            frame.origin.y = area.minY + Spacing.l
        }
        bar.setFrame(frame, display: true)
        Diagnostics.record("scrolling bar width=\(Int(frame.width)) offCentre=\(Int(frame.midX - area.midX))")
    }

    private func showPreview() {
        let area = region.global, visible = region.screen.visibleFrame
        let width: CGFloat = 120
        let gap = Spacing.l
        let x = area.minX - width - gap >= visible.minX ? area.minX - width - gap : min(area.maxX + gap, visible.maxX - width)
        let rect = CGRect(x: x, y: area.minY, width: width, height: area.height)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = PreviewView(frame: CGRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        // A rounded card with a one-pixel edge; the stitched image inside it starts at the
        // top and, once it's taller than the card, shows its newest (bottom) part.
        let card = CALayer()
        card.frame = view.bounds
        card.masksToBounds = true
        card.cornerRadius = Radius.m
        card.cornerCurve = .continuous
        card.borderWidth = 1 / max(region.screen.backingScaleFactor, 1)
        view.card = card
        previewLayer.contentsGravity = .resize
        previewLayer.frame = CGRect(x: 0, y: card.bounds.height, width: card.bounds.width, height: 0)
        card.addSublayer(previewLayer)
        previewCard = card
        view.layer?.addSublayer(card)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Scrolling capture preview")
        panel.contentView = view
        panel.orderFrontRegardless()
        preview = panel
    }

    private func updatePreview() {
        guard let stitcher, let image = stitcher.image() else { return }
        guard let card = previewCard else { return }
        // Scale to the card's width. Shorter than the card: from the top. Taller: its newest
        // (bottom) part.
        let bounds = card.bounds
        let scale = bounds.width / CGFloat(image.width)
        let shownRows = min(CGFloat(image.height), bounds.height / scale)
        let crop = CGRect(x: 0, y: CGFloat(image.height) - shownRows, width: CGFloat(image.width), height: shownRows)
        let height = (shownRows * scale).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.contents = image.cropping(to: crop)
        previewLayer.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        CATransaction.commit()
    }
}

@MainActor
@Observable
final class ScrollingState {
    var started = false
    var height = 0
    var lostTrack = false
}

struct ScrollingBar: View {
    let session: ScrollingCapture
    let state: ScrollingState

    static let readyHint = "Press Start, then scroll down"
    static let scrollHint = "Scroll down, then press Done"
    static let lostHint = "Scroll back up a little"

    private var status: String {
        !state.started ? Self.readyHint : state.lostTrack ? Self.lostHint : Self.scrollHint
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Fixed slots: the hint and the height change without resizing the bar.
            FixedWidthText(text: status, variants: state.started ? [Self.scrollHint, Self.lostHint] : [Self.readyHint])
                .foregroundStyle(state.lostTrack ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.secondary))
                .padding(.leading, Spacing.s)
                .padding(.trailing, Spacing.xs)
            if state.started {
                FixedWidthText(text: "\(state.height.formatted()) px", variants: ["40,000 px"], alignment: .trailing)
                    .font(.body.monospacedDigit())
                    .padding(.trailing, Spacing.xs)
                    .accessibilityLabel("Height, \(state.height) pixels")
            }
            if state.started {
                BarTextButton(title: "Done", systemImage: "checkmark", prominent: true) { session.finish() }
                    .keyboardShortcut(.defaultAction)
                    .help("Finish (Return)")
            } else {
                BarTextButton(title: "Start", systemImage: "arrow.down", prominent: true) { session.start() }
                    .keyboardShortcut(.defaultAction)
                    .help("Start, then scroll (Return)")
            }
            BarIconButton("Cancel", systemImage: "xmark") { session.cancel() }
                .help("Cancel (Esc)")
        }
        .padding(ControlBar.inset)
        .frame(height: ControlBar.height)
        .fixedSize()
    }
}

/// The scrolling preview's container: re-resolves the card's layer colours whenever the
/// appearance changes (layer colours don't follow it by themselves).
private final class PreviewView: NSView {
    var card: CALayer? { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let card else { return }
        card.borderColor = NSColor.separatorColor.cgColor
        card.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
