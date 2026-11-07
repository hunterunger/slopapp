import AppKit
import DictateCore
import SlopKit
import SwiftUI

/// The recording ring: a drop of liquid falls out of the notch (or the top edge of a screen
/// without one), blooms into a circle with the live transcript running around its rim and
/// a waveform in the middle, and is pulled back up when the dictation ends. Purely
/// decorative for VoiceOver (the menu bar status says the same) and never takes clicks.
final class RecordingRing {
    private var panel: HUDPanel?
    private let sim = LiquidHUDSimulation()
    private var hideWorkItem: DispatchWorkItem?

    private static let panelSize = NSSize(width: 440, height: 380)

    func show(audio: AudioCapturing, controller: DictationController) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let screen = Self.activeScreen() else { return }

        let panelFrame = NSRect(
            x: screen.frame.midX - Self.panelSize.width / 2,
            y: screen.frame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )

        if panel == nil {
            let panel = HUDPanel(
                contentRect: panelFrame,
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            // Above the menu bar so the drop can leave the notch cleanly.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let hosting = NSHostingView(
                rootView: LiquidHUDView(sim: sim, audio: audio, controller: controller)
            )
            hosting.sizingOptions = []
            panel.contentView = hosting
            self.panel = panel
        }

        panel?.setFrame(panelFrame, display: false)
        sim.present(
            geometry: HUDGeometry(screen: screen, panelFrame: panelFrame),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        panel?.orderFrontRegardless()
    }

    /// Show the outcome briefly (a check or a warning), then retract.
    func hideSoon(outcome: DictationOutcome = .nothing) {
        hideWorkItem?.cancel()
        sim.finish(outcome)
        let hold: TimeInterval
        switch outcome {
        case .nothing: hold = 0.05
        case .success: hold = 0.4
        case .failure: hold = 1.0
        }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    func hide() {
        hideWorkItem?.cancel()
        guard let panel, panel.isVisible else { return }
        sim.dismiss()
        let work = DispatchWorkItem { [weak self] in
            // A new recording may have re-presented the HUD mid-retract.
            guard let self, self.sim.phase == .closing else { return }
            self.sim.stop()
            self.panel?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LiquidHUDSimulation.dismissDuration, execute: work)
    }
}

extension RecordingRing {
    /// The screen you're working on: the one with the key window's app, else the pointer.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.main ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
    }
}

/// The ring's colours. It sits over whatever's on screen, so it always uses the dark
/// appearance (like SlopKit's `OverlayPalette`), the person's accent colour and system colours.
enum RingPalette {
    /// The hardware notch is black; the liquid matches it so the drop looks like it comes out of it.
    static let notch = Color(nsColor: .black)   // lint:allow matches the hardware notch
    static var ink: Color { Color(nsColor: OverlayPalette.ink) }
    static var text: Color { Color(nsColor: OverlayPalette.paper) }
    static var dictation: NSColor { dark(.controlAccentColor) }
    static var command: NSColor { dark(.systemPurple) }
    static var success: Color { Color(nsColor: dark(.systemGreen)) }
    static var failure: Color { Color(nsColor: dark(.systemYellow)) }

    static func shifted(_ color: NSColor, hue delta: Double) -> Color {
        let c = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let hue = (h + CGFloat(delta)).truncatingRemainder(dividingBy: 1)
        return Color(nsColor: NSColor(hue: hue < 0 ? hue + 1 : hue, saturation: max(s, 0.55), brightness: max(b, 0.85), alpha: 1))
    }

    private static func dark(_ color: NSColor) -> NSColor {
        var result = color
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }
}

/// Borderless panel allowed to sit over the menu bar / notch area.
private final class HUDPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - Geometry

/// Where the notch and the resting circle sit, in the panel's top-left-origin
/// coordinate space.
struct HUDGeometry {
    var notch: CGRect
    var hasNotch: Bool
    var center: CGPoint
    var radius: CGFloat

    static let circleRadius: CGFloat = 54
    static let gap: CGFloat = 16

    init(screen: NSScreen, panelFrame: NSRect) {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let x = left.maxX - panelFrame.minX
            notch = CGRect(x: x, y: 0, width: right.minX - left.maxX, height: inset)
            hasNotch = true
        } else {
            // No notch: the drop is drawn out of the top edge of the screen.
            notch = CGRect(x: panelFrame.width / 2 - 40, y: 0, width: 80, height: 0)
            hasNotch = false
        }
        radius = Self.circleRadius
        center = CGPoint(x: notch.midX, y: notch.maxY + Self.gap + radius)
    }

    init() {
        notch = CGRect(x: 170, y: 0, width: 100, height: 32)
        hasNotch = true
        radius = Self.circleRadius
        center = CGPoint(x: 220, y: 32 + Self.gap + radius)
    }
}

// MARK: - Simulation

/// A damped spring (unit mass), integrated with small fixed substeps.
private struct Spring {
    var value: Double
    var velocity: Double = 0
    var target: Double
    var stiffness: Double
    var damping: Double

    init(_ value: Double, stiffness: Double, damping: Double) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(_ dt: Double) {
        var remaining = dt
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240.0)
            let force = -stiffness * (value - target) - damping * velocity
            velocity += force * h
            value += velocity * h
            remaining -= h
        }
    }
}

/// One character placed on the ring.
struct RingGlyph {
    var character: String
    var angle: Double
    var opacity: Double
}

/// Everything the renderer needs for one frame.
struct LiquidFrame {
    var notch: CGRect = .zero
    var blobs: [CGRect] = []
    var body: CGRect?
    var center: CGPoint = .zero
    var visibility: Double = 0
    var glowRadius: CGFloat = 0
    var glowOpacity: Double = 0
    /// Where the glow's mid stop sits: low = tight core, high = soft wash.
    var glowSoftness: Double = 0.42
    var accent: Color = .accentColor
    var ringRadius: CGFloat = 0
    var glyphs: [RingGlyph] = []
    var bars: [CGFloat] = []
    var barOpacity: Double = 0
    var outcome: DictationOutcome = .nothing
    var iconScale: Double = 0
    /// The liquid: true black under a notch, so it reads as part of the hardware; the dark
    /// appearance's window colour elsewhere.
    var liquid: Color = RingPalette.ink
}

/// Time-stepped physics for the liquid HUD. Owned by the controller and stepped
/// once per display frame by `LiquidHUDView`.
final class LiquidHUDSimulation: ObservableObject {
    enum Phase { case hidden, dropping, open, closing }

    static let dismissDuration: TimeInterval = 0.45

    /// How strongly the voice puppets the HUD. 0 disables each effect.
    private enum Puppet {
        /// Pitch → glow hue shift (1 = full amber ↔ magenta range).
        static let hue: Double = 1
        /// Syllable onset → squash velocity kick.
        static let onsetSquash: Double = 3.2
        /// Syllable onset → glow flash.
        static let onsetGlow: Double = 5
        /// Sibilance → how much the glow tightens.
        static let brightnessTighten: Double = 0.2
    }
    nonisolated static let fontSize: CGFloat = 10.5

    /// Drives whether the view's timeline is running.
    @Published private(set) var isRunning = false
    private(set) var phase: Phase = .hidden

    private var geometry = HUDGeometry()
    private var reduceMotion = false
    private var phaseStart: TimeInterval = 0
    private var lastTick: TimeInterval?
    private var outcome: DictationOutcome = .nothing

    private let dropRadius: Double = 9
    private let fallDuration: Double = 0.2
    private let tailRetract: Double = 0.26

    private var radius = Spring(0, stiffness: 520, damping: 22)
    private var squash = Spring(0, stiffness: 380, damping: 11)
    private var centerY = Spring(0, stiffness: 200, damping: 28)
    private var glow = Spring(0, stiffness: 420, damping: 26)
    private var lip = Spring(0, stiffness: 400, damping: 40)
    private var textAlpha = Spring(0, stiffness: 300, damping: 35)
    private var iconScale = Spring(0, stiffness: 520, damping: 24)
    private var bars = Array(repeating: Spring(0, stiffness: 700, damping: 30), count: 7)
    private var pitch = Spring(0, stiffness: 60, damping: 14)
    private var brightness = Spring(0, stiffness: 260, damping: 30)
    private var lastFeatureIndex = 0

    // Transcript ring.
    private var chars: [String] = []
    private var offsets: [CGFloat] = [0]
    private var widths: [CGFloat] = []
    private var lastPreview = ""
    private var shown: Double = 0
    private var spin: Double = 0
    private var spinVelocity: Double = 0
    /// Position along the text (in points) that sits at 12 o'clock: the middle
    /// of the word being spoken, eased so the ring glides between words.
    private var anchor = Spring(0, stiffness: 170, damping: 26)
    private var widthCache: [String: CGFloat] = [:]
    private let font = NSFont.systemFont(ofSize: LiquidHUDSimulation.fontSize, weight: .medium)

    // MARK: Lifecycle

    func present(geometry: HUDGeometry, reduceMotion: Bool) {
        self.geometry = geometry
        self.reduceMotion = reduceMotion
        outcome = .nothing
        iconScale = Spring(0, stiffness: 520, damping: 24)
        resetText()

        if phase == .open || phase == .closing {
            // Re-triggered while still on screen: just re-inflate.
            phase = .open
            phaseStart = now
            radius.target = geometry.radius
            centerY.target = geometry.center.y
        } else {
            phase = reduceMotion ? .open : .dropping
            phaseStart = now
            radius = Spring(reduceMotion ? geometry.radius * 0.8 : 0, stiffness: 520, damping: reduceMotion ? 46 : 22)
            radius.target = reduceMotion ? geometry.radius : 0
            squash = Spring(0, stiffness: 380, damping: 11)
            centerY = Spring(geometry.center.y, stiffness: 200, damping: 28)
            glow = Spring(0, stiffness: 420, damping: 26)
            lip = Spring(0, stiffness: 400, damping: 40)
            textAlpha = Spring(0, stiffness: 300, damping: 35)
            for i in bars.indices { bars[i] = Spring(0, stiffness: 700, damping: 30) }
            pitch = Spring(0, stiffness: 60, damping: 14)
            brightness = Spring(0, stiffness: 260, damping: 30)
        }
        lastTick = nil
        isRunning = true
    }

    func finish(_ outcome: DictationOutcome) {
        guard phase != .hidden else { return }
        self.outcome = outcome
        iconScale.target = outcome == .nothing ? 0 : 1
    }

    func dismiss() {
        guard phase != .hidden, phase != .closing else { return }
        phase = .closing
        phaseStart = now
        radius.stiffness = 600
        radius.damping = 48
        radius.target = dropRadius * 0.9
    }

    func stop() {
        phase = .hidden
        isRunning = false
    }

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    private func resetText() {
        chars = []
        offsets = [0]
        widths = []
        lastPreview = ""
        shown = 0
        spin = 0
        spinVelocity = 0
        anchor = Spring(0, stiffness: 170, damping: 26)
    }

    private func width(of character: String) -> CGFloat {
        if let w = widthCache[character] { return w }
        let w = (character as NSString).size(withAttributes: [.font: font]).width + 0.25
        widthCache[character] = w
        return w
    }

    private func ingest(_ preview: String) {
        // Ignore the clear that happens once transcription finishes, so the
        // ring keeps its words while it spins away.
        guard !preview.isEmpty, preview != lastPreview else { return }
        lastPreview = preview
        chars = preview.map(String.init)
        widths = chars.map(width(of:))
        offsets = [0]
        offsets.reserveCapacity(widths.count + 1)
        for w in widths { offsets.append(offsets[offsets.count - 1] + w) }
        shown = min(shown, Double(chars.count))
    }

    // MARK: Step

    func step(at time: TimeInterval, features: AudioFeatures,
              phase state: DictationPhase, mode: DictationMode, preview: String) -> LiquidFrame {
        let dt = min(1.0 / 30.0, max(0, time - (lastTick ?? time)))
        lastTick = time
        let t = time - phaseStart
        let g = geometry
        let R = Double(g.radius)
        let notchBottom = Double(g.notch.maxY)

        let listening = state == .recording && outcome == .nothing && phase != .closing
        let busy: Bool
        switch state {
        case .transcribing, .polishing, .editing, .inserting: busy = outcome == .nothing
        default: busy = false
        }
        let voice = listening ? Double(features.level) : 0

        // One-shot events are applied once per analysed window, not per frame.
        let isNewWindow = features.index != lastFeatureIndex
        lastFeatureIndex = features.index
        let onset = listening && isNewWindow ? Double(features.onset) : 0

        pitch.target = listening ? Double(features.pitch) : 0
        pitch.step(dt)
        brightness.target = listening ? Double(features.brightness) : 0
        brightness.step(dt)

        var frame = LiquidFrame()
        frame.liquid = g.hasNotch ? RingPalette.notch : RingPalette.ink
        frame.accent = Self.accent(mode: mode, pitch: pitch.value * Puppet.hue)

        // Without a notch, a short lip of liquid gathers at the top edge while
        // the drop is leaving or returning, so it has something to pull from.
        lip.target = (!g.hasNotch && (phase == .dropping || phase == .closing || (phase == .open && t < tailRetract))) ? 10 : 0
        lip.step(dt)
        var notch = g.notch
        if !g.hasNotch { notch.size.height = max(0, lip.value) }
        // Extend upward so the blur never eats the top edge.
        frame.notch = CGRect(x: notch.minX + 1, y: -40, width: max(0, notch.width - 2), height: notch.maxY + 40)

        switch phase {
        case .hidden:
            return frame

        case .dropping:
            let p = min(1, t / fallDuration)
            let startY = notchBottom - dropRadius * 0.6
            let y = startY + (g.center.y - startY) * p * p
            let stretch = 0.55 * p
            let w = dropRadius * 2 * (1 - 0.22 * stretch)
            let h = dropRadius * 2 * (1 + stretch)
            frame.blobs.append(CGRect(x: g.center.x - w / 2, y: y - h / 2, width: w, height: h))
            appendTail(to: &frame, from: notchBottom, to: y - h / 2, thinning: 0)
            if p >= 1 {
                // Impact: the drop flattens, then springs open into the ring.
                phase = .open
                phaseStart = time
                radius.value = dropRadius
                radius.velocity = 90
                radius.target = R
                squash.value = -0.2
                squash.velocity = 7
            }

        case .open, .closing:
            break
        }

        if phase == .open {
            radius.target = listening ? R + voice * 4 : (busy ? R * 0.95 : R)
            centerY.target = g.center.y
        } else if phase == .closing {
            if t > 0.04 { centerY.target = notchBottom - 14 }
            centerY.stiffness = 190
            centerY.damping = 26
        }

        if phase == .open, onset > 0 {
            squash.velocity += onset * Puppet.onsetSquash
            glow.velocity += onset * Puppet.onsetGlow
        }
        radius.step(dt)
        squash.step(dt)
        centerY.step(dt)

        if phase == .open || phase == .closing {
            let r = max(0, radius.value)
            // While rising into the notch the body stretches with its speed.
            let speedStretch = phase == .closing ? min(0.35, abs(centerY.velocity) / 1100) : 0
            let sq = max(-0.4, min(0.4, squash.value)) - speedStretch
            let w = 2 * r * (1 + sq), h = 2 * r * (1 - sq)
            let body = CGRect(x: g.center.x - w / 2, y: centerY.value - h / 2, width: w, height: h)
            frame.blobs.append(body)
            if phase == .open {
                frame.body = body
                if t < tailRetract {
                    appendTail(to: &frame, from: notchBottom, to: body.minY, thinning: t / tailRetract)
                }
            }
        }

        frame.center = CGPoint(x: g.center.x, y: centerY.value)
        let visibility = phase == .dropping ? 0 : min(1, max(0, radius.value / R))
        frame.visibility = visibility

        // Glow follows the voice; a slow breath while working.
        glow.target = listening ? voice : 0
        glow.step(dt)
        let breathe = busy ? 0.16 + 0.1 * sin(time * 5.5) : 0
        let outcomeGlow = outcome == .nothing ? 0 : 0.15 * iconScale.value
        let tighten = 1 - brightness.value * Puppet.brightnessTighten
        frame.glowRadius = CGFloat((radius.value + 18 + max(0, glow.value) * 100) * tighten)
        frame.glowSoftness = 0.5 - 0.22 * brightness.value
        frame.glowOpacity = visibility * min(0.95, 0.08 + 0.87 * glow.value + breathe + outcomeGlow)
        if outcome == .success { frame.accent = RingPalette.success }
        if outcome == .failure { frame.accent = RingPalette.failure }

        stepText(&frame, dt: dt, preview: preview, listening: listening, busy: busy, visibility: visibility)
        stepBars(&frame, time: time, dt: dt, bands: features.bands, listening: listening, busy: busy, visibility: visibility)

        iconScale.step(dt)
        frame.outcome = outcome
        frame.iconScale = max(0, iconScale.value) * visibility
        return frame
    }

    /// Glow colour: the person's accent colour for dictation, purple for Command Mode, its hue
    /// nudged by the voice's pitch (down warmer, up cooler).
    private static func accent(mode: DictationMode, pitch: Double) -> Color {
        let base = mode == .command ? RingPalette.command : RingPalette.dictation
        return RingPalette.shifted(base, hue: max(-1, min(1, pitch)) * 0.07)
    }

    /// A chain of shrinking blobs between the notch and the drop. Through the
    /// metaball filter it reads as a strand of liquid that thins and snaps.
    private func appendTail(to frame: inout LiquidFrame, from top: Double, to bottom: Double, thinning: Double) {
        let ease = 1 - pow(1 - min(1, thinning), 3)
        let x = Double(geometry.center.x)
        for (fraction, r) in [(0.2, 7.0), (0.45, 5.8), (0.7, 4.8)] {
            let span = max(0, bottom - top) * (1 - ease)
            let y = top + span * fraction
            let rr = r * (1 - 0.55 * ease)
            frame.blobs.append(CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }
    }

    private func stepText(_ frame: inout LiquidFrame, dt: Double, preview: String,
                          listening: Bool, busy: Bool, visibility: Double) {
        ingest(preview)

        let target = Double(chars.count)
        if shown < target {
            // Catch up quickly when a big chunk arrives, otherwise type steadily.
            let rate = max(30, (target - shown) * 5)
            shown = min(target, shown + rate * dt)
        }

        if busy || phase == .closing || outcome != .nothing {
            spinVelocity += 18 * dt
            spin += spinVelocity * dt
            textAlpha.target = 0
        } else {
            textAlpha.target = (listening && visibility > 0.85) ? 1 : 0
        }
        textAlpha.step(dt)

        let alpha = max(0, min(1, textAlpha.value))
        let rt = Double(max(1, radius.value - 11))
        frame.ringRadius = CGFloat(rt)
        guard alpha > 0.005, !chars.isEmpty else { return }

        let n = min(chars.count, Int(shown))
        let head = Double(offsets[n]) + (n < widths.count ? (shown - Double(n)) * Double(widths[n]) : 0)

        // Centre the current word (not just the last letter) at the top.
        var wordStart = n
        while wordStart > 0, chars[wordStart - 1] != " " { wordStart -= 1 }
        if wordStart == n, n > 0 {
            // Just typed a space: keep the previous word centred until the next begins.
            var s = n - 1
            while s > 0, chars[s - 1] != " " { s -= 1 }
            wordStart = s
        }
        let wordEnd = wordStart == n ? head : min(head, Double(offsets[n]))
        anchor.target = (Double(offsets[wordStart]) + wordEnd) / 2
        if anchor.value == 0 { anchor.value = anchor.target }
        anchor.step(dt)

        // Older text trails counter-clockwise until it nearly meets the front
        // of the current word, fading out over the last stretch.
        let circumference = 2 * Double.pi * rt
        let ahead = max(0, head - anchor.value)
        let maxBehind = max(40, circumference - ahead - 16)
        let tailFade = 34.0
        let top = -Double.pi / 2 + spin

        var glyphs: [RingGlyph] = []
        glyphs.reserveCapacity(n)
        for i in 0..<n {
            let behind = anchor.value - Double(offsets[i] + widths[i] / 2)
            if behind > maxBehind { continue }
            let tail = 1 - min(1, max(0, (behind - (maxBehind - tailFade)) / tailFade))
            let age = min(1, (shown - Double(i)) / 1.2)
            glyphs.append(RingGlyph(character: chars[i], angle: top - behind / rt,
                                    opacity: alpha * tail * age))
        }
        frame.glyphs = glyphs
    }

    private func stepBars(_ frame: inout LiquidFrame, time: TimeInterval, dt: Double, bands: SIMD8<Float>,
                          listening: Bool, busy: Bool, visibility: Double) {
        let shape: [Double] = [0.45, 0.7, 0.9, 1, 0.9, 0.7, 0.45]
        for i in bars.indices {
            if listening {
                // Lowest band in the centre, higher bands alternating outward.
                let band = [5, 3, 1, 0, 2, 4, 6][i]
                bars[i].target = (0.12 + 0.88 * Double(bands[band])) * (0.6 + 0.4 * shape[i])
            } else if busy {
                bars[i].target = 0.22 + 0.5 * max(0, sin(time * 9 - Double(i) * 0.8))
            } else {
                bars[i].target = shape[i] * 0.16
            }
            bars[i].step(dt)
        }
        frame.bars = bars.map { CGFloat(max(0, $0.value)) }
        frame.barOpacity = min(1, max(0, (visibility - 0.5) / 0.4)) * max(0, 1 - iconScale.value)
    }
}

// MARK: - View

private struct LiquidHUDView: View {
    @ObservedObject var sim: LiquidHUDSimulation
    // Read each frame rather than observed; the timeline already redraws.
    let audio: AudioCapturing
    let controller: DictationController

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !sim.isRunning)) { timeline in
            let frame = sim.step(
                at: timeline.date.timeIntervalSinceReferenceDate,
                features: audio.features,
                phase: controller.phase,
                mode: controller.mode,
                preview: controller.livePreview
            )
            Canvas { ctx, _ in
                LiquidRenderer.draw(frame, in: &ctx)
            }
            .environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }
}

private enum LiquidRenderer {
    static func draw(_ f: LiquidFrame, in ctx: inout GraphicsContext) {
        guard !f.blobs.isEmpty else { return }

        // Glow behind the liquid.
        if f.glowOpacity > 0.002 {
            let r = f.glowRadius
            let rect = CGRect(x: f.center.x - r, y: f.center.y - r, width: r * 2, height: r * 2)
            let gradient = Gradient(stops: [
                .init(color: f.accent.opacity(f.glowOpacity), location: 0),
                .init(color: f.accent.opacity(f.glowOpacity * 0.5), location: f.glowSoftness),
                .init(color: f.accent.opacity(0), location: 1),
            ])
            ctx.fill(Path(ellipseIn: rect),
                     with: .radialGradient(gradient, center: f.center, startRadius: 0, endRadius: r))
        }

        // Metaballs: blur everything together, then threshold the alpha back to
        // a hard edge so touching shapes merge like liquid.
        ctx.drawLayer { layer in
            layer.addFilter(.alphaThreshold(min: 0.5, color: f.liquid))
            layer.addFilter(.blur(radius: 7))
            layer.drawLayer { shapes in
                shapes.fill(Path(roundedRect: f.notch, cornerRadius: Radius.m, style: .continuous), with: .color(f.liquid))
                for blob in f.blobs {
                    shapes.fill(Path(ellipseIn: blob), with: .color(f.liquid))
                }
            }
        }

        guard let body = f.body else { return }

        // Crisp, anti-aliased body over the thresholded one.
        ctx.fill(Path(ellipseIn: body), with: .color(f.liquid))

        // Transcript around the inside of the rim.
        let font = Font.system(size: LiquidHUDSimulation.fontSize, weight: .medium)
        for glyph in f.glyphs where glyph.opacity > 0.01 {
            var c = ctx
            c.opacity = glyph.opacity
            c.translateBy(x: f.center.x, y: f.center.y)
            c.rotate(by: .radians(glyph.angle + .pi / 2))
            c.translateBy(x: 0, y: -f.ringRadius)
            c.draw(c.resolve(Text(glyph.character).font(font).foregroundStyle(RingPalette.text)),
                   at: .zero, anchor: .center)
        }

        // Centre waveform.
        if f.barOpacity > 0.01 {
            let scale = CGFloat(f.visibility)
            for (i, value) in f.bars.enumerated() {
                let h = (3 + 22 * value) * scale
                let w: CGFloat = 3
                let x = f.center.x + CGFloat(i - 3) * 6 - w / 2
                let rect = CGRect(x: x, y: f.center.y - h / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2),
                         with: .color(RingPalette.text.opacity(f.barOpacity)))
            }
        }

        // Outcome glyph.
        if f.iconScale > 0.01, f.outcome != .nothing {
            let symbol = f.outcome == .success ? "checkmark" : "exclamationmark"
            let color = f.outcome == .success ? RingPalette.success : RingPalette.failure
            var c = ctx
            c.translateBy(x: f.center.x, y: f.center.y)
            c.scaleBy(x: f.iconScale, y: f.iconScale)
            c.draw(c.resolve(Text(Image(systemName: symbol))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(color)),
                   at: .zero, anchor: .center)
        }
    }
}
