import AppKit
import SlopKit
import SnapperCore
import SwiftUI

enum RecordingPhase: Equatable {
    case idle
    /// Area picked; waiting for Record Video / Record GIF.
    case ready
    case countdown
    case recording
    case paused
    /// Writing the file (and the GIF).
    case finishing
}

/// The screen recording flow: pick an area or window → choose video or GIF → record with a
/// small control bar (stop, pause, time, discard) → the recording shows up as a thumbnail.
@MainActor
final class RecordingController {
    private unowned let model: AppModel
    private let recorder: ScreenRecording
    private var frame: RegionFrame?
    private var bar: FloatingPanel?
    private var region: PickedRegion?
    private var asGIF = false
    private var url: URL?
    private let clock = RecordingClock()

    init(model: AppModel, recorder: ScreenRecording) {
        self.model = model
        self.recorder = recorder
    }

    private var phase: RecordingPhase {
        get { model.recordingPhase }
        set { model.recordingPhase = newValue; clock.phase = newValue }
    }

    // MARK: Flow

    func begin(started: TimeInterval) async {
        guard phase == .idle else { return }
        guard let region = await PickedRegion.pick(.area, capturer: model.capturer, options: model.overlayOptions,
                                                   started: started, report: model.report) else { return }
        ready(region)
    }

    /// Skips the overlay (scripted tests pick the test scene's area).
    func ready(_ region: PickedRegion) {
        guard phase == .idle else { return }
        self.region = region
        phase = .ready
        frame = RegionFrame(rect: region.global, dimOutside: false)
        showBar(ready: true)
        Diagnostics.record("recording ready points=\(Int(region.local.width))x\(Int(region.local.height))")
    }

    /// Starts recording what was picked. `gif`: convert to an animated GIF when done.
    func record(gif: Bool) {
        guard phase == .ready, let region else { return }
        asGIF = gif
        Task { await startRecording(region) }
    }

    private func startRecording(_ region: PickedRegion) async {
        let testScene = TestScene.recordingTarget
        if TestScene.isActive, testScene == nil {
            // Fail closed: test mode must never fall back to recording the display.
            HUD.show(RecordingError.refusedInTestMode.localizedDescription, systemImage: "exclamationmark.triangle")
            tearDown()
            return
        }
        let quartzDisplay = ScreenCoordinates.flip(region.screen.frame, primaryHeight: NSScreen.primaryHeight)
        guard let plan = RecordingPlan.make(selection: region.quartz, display: (region.displayID, quartzDisplay), testScene: testScene) else {
            HUD.show(TestScene.isActive ? "In test mode, record inside the test scene." : "That area is too small to record.",
                     systemImage: "exclamationmark.triangle")
            tearDown()
            return
        }
        if TestScene.isActive, case .display = plan.source {
            tearDown()
            return
        }
        hideBar()
        if model.recordCountdown {
            phase = .countdown
            guard await Countdown.run(3, centeredIn: region.global, label: "Recording") else {
                tearDown()
                return
            }
        }
        // The frame (and the dimming) around the area while recording.
        frame?.close()
        let shown = ScreenCoordinates.flip(plan.screenRect, primaryHeight: NSScreen.primaryHeight)
        frame = RegionFrame(rect: shown, dimOutside: model.recordDimScreen, color: .systemRed)
        let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(FileNaming.baseName(template: model.fileNameTemplate, type: "Recording", date: Date())).mp4")
        self.url = url
        do {
            try await recorder.start(plan: plan, options: model.recordingOptions, keepWindows: model.pins.windowNumbers, to: url)
        } catch {
            Diagnostics.record("recording failed to start error=\(error)")
            HUD.show("Couldn't start recording. \(error.localizedDescription)", systemImage: "exclamationmark.triangle", duration: .seconds(3))
            tearDown()
            return
        }
        phase = .recording
        clock.start()
        showBar(ready: false)
        Diagnostics.record("recording started source=\(plan.source) rect=\(Int(plan.sourceRect.width))x\(Int(plan.sourceRect.height)) gif=\(asGIF)")
    }

    func togglePause() {
        switch phase {
        case .recording:
            recorder.setPaused(true)
            clock.pause()
            phase = .paused
        case .paused:
            recorder.setPaused(false)
            clock.resume()
            phase = .recording
        default:
            break
        }
    }

    func stop() {
        switch phase {
        case .ready, .countdown:
            Countdown.cancel()
            tearDown()
        case .recording, .paused:
            Task { await finish() }
        default:
            break
        }
    }

    /// Stops and throws the recording away.
    func discard() {
        switch phase {
        case .recording, .paused:
            phase = .finishing
            Task {
                await recorder.cancel()
                Diagnostics.record("recording discarded")
                tearDown()
            }
        default:
            stop()
        }
    }

    private func finish() async {
        phase = .finishing
        hideBar()
        frame?.close()
        frame = nil
        let started = Diagnostics.now()
        do {
            let duration = try await recorder.stop()
            guard var file = url else { throw RecordingError.noFrames }
            var poster = await VideoFrames.poster(of: file)
            if asGIF {
                HUD.show("Making GIF…", systemImage: "hourglass")
                let gif = try await VideoFrames.makeGIF(from: file, options: model.gifOptions)
                try? FileManager.default.removeItem(at: file)
                file = gif
            }
            if poster == nil { poster = GIFPoster.first(of: file) }
            Diagnostics.record("recording finished seconds=\(String(format: "%.1f", duration)) gif=\(asGIF) ms=\(Diagnostics.milliseconds(since: started))")
            if let poster, let region {
                let scale = CGFloat(poster.width) / max(region.local.width, 1)
                model.deliver(poster, scale: max(1, scale), displayID: region.displayID, started: started, kind: asGIF ? "gif" : "video",
                              media: MediaFile(url: file, duration: duration))
            }
        } catch {
            Diagnostics.record("recording failed error=\(error)")
            HUD.show(error.localizedDescription, systemImage: "exclamationmark.triangle", duration: .seconds(3))
        }
        tearDown()
    }

    private func tearDown() {
        hideBar()
        frame?.close()
        frame = nil
        region = nil
        clock.stop()
        phase = .idle
    }

    // MARK: Control bar

    private func showBar(ready: Bool) {
        hideBar()
        guard let region else { return }
        let panel = FloatingPanel(cornerRadius: ControlBar.panelRadius) {
            RecordingBar(controller: self, clock: clock, ready: ready)
        }
        panel.dismissesOnResignKey = false
        panel.level = .statusBar
        panel.title = ready ? "Record" : "Recording"
        panel.setAccessibilityLabel(ready ? "Record" : "Recording controls")
        panel.onDismiss = { [weak self] in
            // Esc on the bar: before recording it cancels; while recording it does nothing
            // (a stray Esc must not end a take).
            guard let self else { return }
            if self.phase == .ready { self.tearDown() } else if self.phase == .recording || self.phase == .paused { self.showBar(ready: false) }
        }
        panel.keyHandler = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == 36 || event.keyCode == 76 { // Return
                if self.phase == .ready { self.record(gif: event.modifierFlags.contains(.option)) }
                return true
            }
            return false
        }
        let size = panel.contentView?.fittingSize ?? CGSize(width: 320, height: ControlBar.height)
        panel.setFrame(ControlBar.frame(size: size, under: region.global, visible: region.screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
        if ready {
            NSApp.activate()
            panel.makeKey()
        }
        bar = panel
    }

    private func hideBar() {
        bar?.onDismiss = nil
        bar?.orderOut(nil)
        bar?.close()
        bar = nil
    }
}

/// The recording's elapsed time, for the bar.
@MainActor
@Observable
final class RecordingClock {
    var phase: RecordingPhase = .idle
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var banked: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?

    func start() {
        banked = 0
        startedAt = Date()
        elapsed = 0
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        if let startedAt { banked += Date().timeIntervalSince(startedAt) }
        startedAt = nil
        tick()
    }

    func resume() { startedAt = Date() }

    func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
    }

    private func tick() {
        elapsed = banked + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }
}

struct RecordingBar: View {
    let controller: RecordingController
    let clock: RecordingClock
    let ready: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if ready {
                BarTextButton(title: "Record Video", systemImage: "video.fill", prominent: true) { controller.record(gif: false) }
                    .keyboardShortcut(.defaultAction)
                    .help("Record a video (Return)")
                BarTextButton(title: "Record GIF", systemImage: "photo.stack") { controller.record(gif: true) }
                    .help("Record an animated GIF (Option-Return)")
                BarIconButton("Cancel", systemImage: "xmark") { controller.stop() }
                    .help("Cancel (Esc)")
            } else {
                BarIconButton("Stop Recording", systemImage: "stop.fill", tint: .red) { controller.stop() }
                    .help("Stop and keep the recording")
                // A fixed slot: the bar doesn't change width as the minutes tick over.
                FixedWidthText(text: Elapsed.string(clock.elapsed), variants: ["00:00"], alignment: .center)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(clock.phase == .paused ? .secondary : .primary)
                    .padding(.horizontal, Spacing.xs)
                    .accessibilityLabel("Elapsed time, \(Elapsed.string(clock.elapsed))\(clock.phase == .paused ? ", paused" : "")")
                BarIconButton(clock.phase == .paused ? "Resume" : "Pause",
                              systemImage: clock.phase == .paused ? "play.fill" : "pause.fill") { controller.togglePause() }
                BarIconButton("Discard Recording", systemImage: "trash") { controller.discard() }
                    .help("Stop and throw the recording away")
            }
        }
        .padding(ControlBar.inset)
        .frame(height: ControlBar.height)
        .fixedSize()
    }
}

/// The first frame of a GIF, as a poster.
enum GIFPoster {
    static func first(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
