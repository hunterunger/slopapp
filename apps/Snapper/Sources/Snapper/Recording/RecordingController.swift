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

/// The screen recording flow: pick an area or window → set up the sound, camera, clicks and
/// keys from the bar and choose video or GIF → record with a small control bar (stop, pause,
/// time, microphone level, discard) → the recording shows up as a thumbnail.
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
    /// The microphone while the bar is up (its level shows in the bar).
    let microphone = MicrophoneFeed()
    let camera = CameraBubbleController()
    private var overlay: InputOverlay?
    private let makeInputEvents: () -> InputEvents

    init(model: AppModel, recorder: ScreenRecording,
         inputEvents: @escaping () -> InputEvents = { TestScene.isActive && !Diagnostics.realInputInTestMode ? NoInputEvents() : SystemInputEvents() }) {
        self.model = model
        self.recorder = recorder
        makeInputEvents = inputEvents
        camera.onChange = { [weak model] width, corner in
            model?.cameraWidth = Double(width)
            model?.cameraCorner = corner
        }
        camera.onShapeChange = { [weak model] shape in model?.cameraShape = shape }
        camera.onHide = { [weak model] in model?.recordCamera = false }
    }

    var isSettingUp: Bool { phase == .ready }

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
        startExtras()
        Diagnostics.record("recording ready points=\(Int(region.local.width))x\(Int(region.local.height))")
    }

    // MARK: Sound, camera, clicks and keys

    /// What's on from last time, if it's still allowed (nothing is asked for here: a prompt
    /// only ever follows the person's own click).
    private func startExtras() {
        if model.recordMicrophone, MediaEnvironment.authorizer.status(.microphone) == .authorized { startMicrophone() }
        if model.recordCamera, MediaEnvironment.authorizer.status(.camera) == .authorized { showCamera() }
    }

    private func stopExtras() {
        microphone.stop()
        camera.hide()
        overlay?.close()
        overlay = nil
    }

    /// The microphone is on in Settings but macOS won't let us use it.
    var microphoneBlocked: Bool { model.recordMicrophone && MediaEnvironment.authorizer.status(.microphone) != .authorized }
    var cameraBlocked: Bool { model.recordCamera && MediaEnvironment.authorizer.status(.camera) != .authorized }
    var keysBlocked: Bool { model.recordShowKeys && !KeyAccess.isGranted }

    var microphones: [MediaDevice] { MediaEnvironment.devices.devices(.microphone) }
    var cameras: [MediaDevice] { MediaEnvironment.devices.devices(.camera) }

    /// The microphone in use (the chosen one if it's there, else the default).
    var currentMicrophoneID: String? { resolved(model.microphoneID, among: microphones, kind: .microphone) }
    var currentCameraID: String? { resolved(model.cameraID, among: cameras, kind: .camera) }

    private func resolved(_ id: String?, among devices: [MediaDevice], kind: MediaKind) -> String? {
        if let id, devices.contains(where: { $0.id == id }) { return id }
        return MediaEnvironment.devices.defaultID(kind) ?? devices.first?.id
    }

    /// Picks a microphone (nil: none) from the bar or Settings.
    func chooseMicrophone(_ id: String?) {
        guard let id else {
            model.recordMicrophone = false
            microphone.stop()
            return
        }
        Task {
            guard await MediaEnvironment.ensureAccess(.microphone) else { return }
            model.microphoneID = id
            model.recordMicrophone = true
            if phase == .ready { startMicrophone() }
        }
    }

    func chooseCamera(_ id: String?) {
        guard let id else {
            model.recordCamera = false
            camera.hide()
            return
        }
        Task {
            guard await MediaEnvironment.ensureAccess(.camera) else { return }
            model.cameraID = id
            model.recordCamera = true
            if phase == .ready { showCamera() }
        }
    }

    /// A blocked microphone or camera: explain how to allow it.
    func fixAccess(_ kind: MediaKind) {
        MediaPermissionWindow.show(.media(kind)) { [weak self] in
            guard let self, self.phase == .ready else { return }
            if kind == .microphone { self.startMicrophone() } else { self.showCamera() }
        }
    }

    func toggleComputerAudio() {
        model.recordComputerAudio.toggle()
    }

    func toggleClicks() {
        model.recordShowClicks.toggle()
    }

    func toggleKeys(on: Bool? = nil) {
        if keysBlocked, on == nil {
            // On, but macOS won't deliver keys: explain how to allow it (Not Now leaves it as is;
            // Settings → Recording turns it off).
            MediaPermissionWindow.show(.accessibility) { [weak self] in self?.model.recordShowKeys = true }
        } else if model.recordShowKeys, on != true {
            model.recordShowKeys = false
        } else if model.recordShowKeys {
            return
        } else if KeyAccess.isGranted {
            model.recordShowKeys = true
        } else {
            MediaPermissionWindow.show(.accessibility) { [weak self] in self?.model.recordShowKeys = true }
        }
    }

    private func startMicrophone() {
        do {
            try microphone.start(deviceID: currentMicrophoneID)
        } catch {
            Diagnostics.record("microphone failed error=\(error)")
            HUD.show(error.localizedDescription, systemImage: "mic.slash")
        }
    }

    private func showCamera() {
        guard let region else { return }
        do {
            try camera.show(deviceID: currentCameraID, shape: model.cameraShape, width: CGFloat(model.cameraWidth),
                            corner: model.cameraCorner, in: region.global)
        } catch {
            Diagnostics.record("camera failed error=\(error)")
            HUD.show(error.localizedDescription, systemImage: "video.slash")
        }
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
        // A blocked microphone records silently rather than not at all.
        if !asGIF, microphoneBlocked { HUD.show("Recording without the microphone", systemImage: "mic.slash", duration: .seconds(2)) }
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
        var options = model.recordingOptions.forRecording(gif: asGIF)
        options.audio.microphone = options.audio.microphone && microphone.isRunning
        if asGIF { microphone.stop() }
        if model.recordShowClicks || (model.recordShowKeys && KeyAccess.isGranted) {
            overlay = InputOverlay(area: shown, clicks: model.recordShowClicks,
                                   keys: model.recordShowKeys && KeyAccess.isGranted ? model.keystrokeMode : nil, events: makeInputEvents())
        }
        var keep = model.pins.windowNumbers
        if camera.isShown, let id = camera.windowNumber { keep.insert(id) }
        if let id = overlay?.windowNumber { keep.insert(id) }
        do {
            try await recorder.start(plan: plan, options: options, keepWindows: keep, microphone: microphone.tap, to: url)
            overlay?.start()
        } catch {
            Diagnostics.record("recording failed to start error=\(error)")
            HUD.show("Couldn't start recording. \(error.localizedDescription)", systemImage: "exclamationmark.triangle", duration: .seconds(3))
            tearDown()
            return
        }
        phase = .recording
        clock.start()
        showBar(ready: false)
        Diagnostics.record("recording started source=\(plan.source) rect=\(Int(plan.sourceRect.width))x\(Int(plan.sourceRect.height)) gif=\(asGIF) computerAudio=\(options.audio.computer) microphone=\(options.audio.microphone) camera=\(camera.isShown) clicks=\(model.recordShowClicks) keys=\(overlay.map { _ in model.recordShowKeys && KeyAccess.isGranted } ?? false)")
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
        overlay?.close()
        overlay = nil
        let started = Diagnostics.now()
        do {
            let duration = try await recorder.stop()
            stopExtras()
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
        stopExtras()
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
            RecordingBar(controller: self, model: model, clock: clock, microphone: microphone, ready: ready)
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
    @Bindable var model: AppModel
    let clock: RecordingClock
    let microphone: MicrophoneFeed
    let ready: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if ready {
                extras
                Divider()
                    .frame(height: ControlBar.controlHeight - Spacing.s)
                    .padding(.horizontal, Spacing.xs / 2)
                BarTextButton(title: "Record Video", systemImage: "video.fill", prominent: true) { controller.record(gif: false) }
                    .keyboardShortcut(.defaultAction)
                    .help("Record a video (Return)")
                BarTextButton(title: "Record GIF", systemImage: "photo.stack") { controller.record(gif: true) }
                    .help("Record an animated GIF, without sound (Option-Return)")
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
                if microphone.isRunning {
                    MicrophoneGlyph(level: clock.phase == .paused ? 0 : microphone.level, isOn: true)
                        .frame(width: ControlBar.controlHeight, height: ControlBar.controlHeight)
                        .help("Microphone level")
                        .accessibilityElement()
                        .accessibilityLabel("Microphone")
                        .accessibilityValue(clock.phase == .paused ? "Paused" : "Recording")
                }
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

    /// Microphone and camera (menus: none or a device), computer sound, clicks and keys.
    @ViewBuilder private var extras: some View {
        let micOn = model.recordMicrophone && !controller.microphoneBlocked
        BarMenuButton(title: "Microphone", value: micOn ? deviceName(controller.currentMicrophoneID, in: controller.microphones) : "Off",
                      isOn: micOn, warning: controller.microphoneBlocked) {
            MicrophoneGlyph(level: microphone.level, isOn: micOn, warning: controller.microphoneBlocked)
        } menu: {
            deviceMenu(kind: .microphone, devices: controller.microphones, current: micOn ? controller.currentMicrophoneID : nil,
                       blocked: controller.microphoneBlocked, choose: controller.chooseMicrophone)
        }
        BarToggleButton(title: "Computer Sound", systemImage: model.recordComputerAudio ? "speaker.wave.2.fill" : "speaker.slash",
                        isOn: model.recordComputerAudio) { controller.toggleComputerAudio() }
            .help(model.recordComputerAudio ? "Recording the Mac's sound" : "Record the Mac's sound")
        let cameraOn = model.recordCamera && !controller.cameraBlocked
        BarMenuButton(title: "Camera", value: cameraOn ? deviceName(controller.currentCameraID, in: controller.cameras) : "Off",
                      isOn: cameraOn, warning: controller.cameraBlocked) {
            Image(systemName: cameraOn ? "video.fill" : "video.slash")
                .foregroundStyle(cameraOn ? AnyShapeStyle(Color.accentColor) : controller.cameraBlocked ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
        } menu: {
            deviceMenu(kind: .camera, devices: controller.cameras, current: cameraOn ? controller.currentCameraID : nil,
                       blocked: controller.cameraBlocked, choose: controller.chooseCamera)
            if cameraOn {
                Divider()
                Picker("Shape", selection: Binding(get: { model.cameraShape }, set: { controller.camera.setShape($0); model.cameraShape = $0 })) {
                    ForEach(BubbleShape.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        BarToggleButton(title: "Show Clicks", systemImage: "cursorarrow.click.2", isOn: model.recordShowClicks) { controller.toggleClicks() }
            .help(model.recordShowClicks ? "Clicks show as a ring" : "Show clicks as a ring")
        BarToggleButton(title: "Show Keystrokes", systemImage: "keyboard", isOn: model.recordShowKeys && !controller.keysBlocked,
                        warning: controller.keysBlocked) { controller.toggleKeys() }
            .help(controller.keysBlocked ? "Showing keys needs Accessibility" : model.recordShowKeys ? "Pressed keys show in the recording" : "Show the keys you press")
    }

    private func deviceName(_ id: String?, in devices: [MediaDevice]) -> String {
        devices.first { $0.id == id }?.name ?? "On"
    }

    @ViewBuilder
    private func deviceMenu(kind: MediaKind, devices: [MediaDevice], current: String?, blocked: Bool,
                            choose: @escaping (String?) -> Void) -> some View {
        if blocked {
            Button("Allow \(kind.title)…") { controller.fixAccess(kind) }
            Divider()
        }
        Toggle(kind == .camera ? "No Camera" : "No Microphone", isOn: Binding(get: { current == nil }, set: { if $0 { choose(nil) } }))
        if devices.isEmpty {
            Text(kind == .camera ? "No cameras found" : "No microphones found")
        }
        ForEach(devices) { device in
            Toggle(device.name, isOn: Binding(get: { current == device.id }, set: { if $0 { choose(device.id) } }))
        }
    }
}

/// The microphone symbol, filling with the voice level from the bottom while it's on.
struct MicrophoneGlyph: View {
    let level: Double
    let isOn: Bool
    var warning = false

    var body: some View {
        if isOn {
            ZStack {
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.accentColor)
                    .mask(alignment: .bottom) {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(height: proxy.size.height * max(0.18, level))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .font(.body.weight(.semibold))
        } else {
            Image(systemName: "mic.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(warning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
        }
    }
}

/// A round bar button that's on (accent) or off (secondary), for the recording extras.
struct BarToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var warning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(warning ? AnyShapeStyle(Color.orange) : isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: ControlBar.controlHeight, height: ControlBar.controlHeight)
                .background {
                    if isOn { Circle().fill(Color.accentColor.opacity(0.14)) }
                }
        }
        .buttonStyle(TileButtonStyle(radius: ControlBar.controlHeight / 2))
        .accessibilityLabel(title)
        .accessibilityValue(warning ? "Needs permission" : isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A round bar button that opens a menu (microphone, camera).
struct BarMenuButton<Label: View, Content: View>: View {
    let title: String
    let value: String
    var isOn = false
    var warning = false
    @ViewBuilder let label: Label
    @ViewBuilder let menu: Content

    var body: some View {
        Menu {
            menu
        } label: {
            label
                .frame(width: ControlBar.controlHeight, height: ControlBar.controlHeight)
                .background {
                    if isOn { Circle().fill(Color.accentColor.opacity(0.14)) }
                }
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(TileButtonStyle(radius: ControlBar.controlHeight / 2))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(warning ? "\(title): needs permission" : "\(title): \(value)")
        .accessibilityLabel(title)
        .accessibilityValue(warning ? "Needs permission" : value)
    }
}

/// The first frame of a GIF, as a poster.
enum GIFPoster {
    static func first(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
