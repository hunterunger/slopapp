import AppKit
@preconcurrency import AVFoundation
import Observation
import QuartzCore
import SnapperCore

// Camera and microphone for recordings, each behind a protocol: the system's devices, or
// (test mode, `SNAPPER_FAKE_MEDIA`) a generated test camera and a test microphone that plays
// a tone, so tests never open a real device or ask for permission.
//
// `MediaPermission` and `MediaPermissionPrompt` are written so they could move to SlopKit next
// to `Permission` (which has no camera or microphone).

enum MediaKind: String, Sendable {
    case camera, microphone

    var title: String { self == .camera ? "Camera" : "Microphone" }
    var avType: AVMediaType { self == .camera ? .video : .audio }
    var systemImage: String { self == .camera ? "video" : "mic" }
    /// The exact Privacy pane in System Settings.
    var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(self == .camera ? "Privacy_Camera" : "Privacy_Microphone")")!
    }
}

enum MediaAuthorization: Sendable {
    case authorized, denied, notDetermined
}

@MainActor
protocol MediaAuthorizing {
    func status(_ kind: MediaKind) -> MediaAuthorization
    /// Asks (macOS shows its prompt the first time). True when allowed.
    func request(_ kind: MediaKind) async -> Bool
}

struct SystemMediaAuthorizer: MediaAuthorizing {
    func status(_ kind: MediaKind) -> MediaAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: kind.avType) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func request(_ kind: MediaKind) async -> Bool {
        await AVCaptureDevice.requestAccess(for: kind.avType)
    }
}

/// `SNAPPER_FAKE_MEDIA`: granted, denied, or undetermined (which grants when asked).
@MainActor
final class FakeMediaAuthorizer: MediaAuthorizing {
    private var state: MediaAuthorization

    init(_ value: String) {
        state = switch value {
        case "denied": .denied
        case "undetermined", "notDetermined": .notDetermined
        default: .authorized
        }
    }

    func status(_ kind: MediaKind) -> MediaAuthorization { state }

    func request(_ kind: MediaKind) async -> Bool {
        if state == .notDetermined { state = .authorized }
        return state == .authorized
    }
}

/// A camera or microphone the user can pick.
struct MediaDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
protocol MediaDeviceListing {
    func devices(_ kind: MediaKind) -> [MediaDevice]
    /// The system's default device's id.
    func defaultID(_ kind: MediaKind) -> String?
}

struct SystemMediaDevices: MediaDeviceListing {
    func devices(_ kind: MediaKind) -> [MediaDevice] {
        let types: [AVCaptureDevice.DeviceType] = kind == .camera
            ? [.builtInWideAngleCamera, .external, .continuityCamera]
            : [.microphone, .external]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: kind.avType, position: .unspecified)
            .devices.map { MediaDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func defaultID(_ kind: MediaKind) -> String? {
        AVCaptureDevice.default(for: kind.avType)?.uniqueID
    }
}

struct FakeMediaDevices: MediaDeviceListing {
    static let microphone = MediaDevice(id: "test-microphone", name: "Test Microphone")
    static let camera = MediaDevice(id: "test-camera", name: "Test Camera")

    func devices(_ kind: MediaKind) -> [MediaDevice] { [kind == .camera ? Self.camera : Self.microphone] }
    func defaultID(_ kind: MediaKind) -> String? { devices(kind).first?.id }
}

/// The real devices, or the generated ones (test mode / `SNAPPER_FAKE_MEDIA`).
@MainActor
enum MediaEnvironment {
    static var isSynthetic: Bool { Diagnostics.fakeMedia != nil }
    static let authorizer: MediaAuthorizing = Diagnostics.fakeMedia.map { FakeMediaAuthorizer($0) } ?? SystemMediaAuthorizer()
    static let devices: MediaDeviceListing = isSynthetic ? FakeMediaDevices() : SystemMediaDevices()

    static func makeMicrophone() -> MicrophoneSource { isSynthetic ? ToneMicrophone() : CaptureMicrophone() }
    static func makeCamera() -> CameraSource { isSynthetic ? TestCamera() : CaptureCamera() }

    /// Makes sure `kind` may be used, asking if macOS hasn't yet. When it's off, explains how
    /// to turn it on and returns false.
    static func ensureAccess(_ kind: MediaKind) async -> Bool {
        switch authorizer.status(kind) {
        case .authorized:
            return true
        case .notDetermined:
            if await authorizer.request(kind) { return true }
        case .denied:
            break
        }
        Diagnostics.record("media access denied kind=\(kind.rawValue)")
        MediaPermissionWindow.show(.media(kind))
        return false
    }
}

// MARK: Microphone

/// Delivers microphone samples stamped on the host clock (like the screen's frames).
@MainActor
protocol MicrophoneSource: AnyObject {
    func start(deviceID: String?, deliver: @escaping @Sendable (CMSampleBuffer) -> Void) throws
    func stop()
}

enum MediaCaptureError: LocalizedError {
    case noDevice(MediaKind)
    case cantUse(MediaKind)

    var errorDescription: String? {
        switch self {
        case .noDevice(let kind): "There's no \(kind.title.lowercased()) to use."
        case .cantUse(let kind): "The \(kind.title.lowercased()) can't be used right now."
        }
    }
}

/// The microphone while a recording is set up and made: its level for the bar, its samples
/// for the file. The sound is never kept anywhere but the recording.
@MainActor
@Observable
final class MicrophoneFeed {
    /// 0…1, for the meter.
    private(set) var level: Double = 0
    private(set) var isRunning = false
    private(set) var deviceID: String?
    @ObservationIgnored private var source: MicrophoneSource?
    @ObservationIgnored let tap = SampleTap()

    func start(deviceID: String?) throws {
        if isRunning, deviceID == self.deviceID { return }
        stop()
        let source = MediaEnvironment.makeMicrophone()
        tap.onLevel = { [weak self] value in
            Task { @MainActor in if self?.isRunning == true { self?.level = value } }
        }
        let tap = self.tap
        try source.start(deviceID: deviceID) { buffer in tap.deliver(buffer) }
        self.source = source
        self.deviceID = deviceID
        isRunning = true
        Diagnostics.record("microphone started synthetic=\(MediaEnvironment.isSynthetic)")
    }

    func stop() {
        guard let source else { return }
        source.stop()
        self.source = nil
        tap.setConsumer(nil)
        isRunning = false
        level = 0
        Diagnostics.record("microphone stopped")
    }
}

/// Hands each microphone buffer to the recording (when one is listening) and works out the
/// level, on the microphone's own queue.
final class SampleTap: @unchecked Sendable {
    private let lock = NSLock()
    private var consumer: (@Sendable (CMSampleBuffer) -> Void)?
    private var meter = LevelMeter()
    private var lastTime: TimeInterval = 0
    private var lastPublished: TimeInterval = 0
    var onLevel: (@Sendable (Double) -> Void)?

    func setConsumer(_ consumer: (@Sendable (CMSampleBuffer) -> Void)?) {
        lock.withLock { self.consumer = consumer }
    }

    func deliver(_ buffer: CMSampleBuffer) {
        let consumer = lock.withLock { self.consumer }
        consumer?(buffer)
        guard let samples = AudioSamples.floats(in: buffer) else { return }
        let now = CACurrentMediaTime()
        let level = lock.withLock { () -> Double? in
            meter.feed(AudioLevel.meter(rms: AudioLevel.rms(samples)), elapsed: lastTime == 0 ? 0 : now - lastTime)
            lastTime = now
            // About 20 updates a second is plenty for a meter.
            guard now - lastPublished >= 0.05 else { return nil }
            lastPublished = now
            return meter.value
        }
        if let level { onLevel?(level) }
    }
}

/// The real microphone (AVCaptureSession). Samples are converted to 48 kHz mono Float32 and
/// restamped from the session's clock onto the host clock.
@MainActor
final class CaptureMicrophone: NSObject, MicrophoneSource {
    private var session: AVCaptureSession?
    private var receiver: Receiver?

    func start(deviceID: String?, deliver: @escaping @Sendable (CMSampleBuffer) -> Void) throws {
        let device = deviceID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw MediaCaptureError.noDevice(.microphone) }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        guard session.canAddInput(input), session.canAddOutput(output) else { throw MediaCaptureError.cantUse(.microphone) }
        session.addInput(input)
        session.addOutput(output)
        let receiver = Receiver(session: session, deliver: deliver)
        output.setSampleBufferDelegate(receiver, queue: receiver.queue)
        self.session = session
        self.receiver = receiver
        receiver.queue.async { session.startRunning() }
    }

    func stop() {
        guard let session, let receiver else { return }
        self.session = nil
        self.receiver = nil
        receiver.queue.async { session.stopRunning() }
    }

    private final class Receiver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
        let queue = DispatchQueue(label: "app.slopapp.snapper.microphone")
        private let session: AVCaptureSession
        private let deliver: @Sendable (CMSampleBuffer) -> Void

        init(session: AVCaptureSession, deliver: @escaping @Sendable (CMSampleBuffer) -> Void) {
            self.session = session
            self.deliver = deliver
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let host = CMClockGetHostTimeClock()
            if let clock = session.synchronizationClock, !CFEqual(clock, host) {
                let converted = CMSyncConvertTime(time, from: clock, to: host)
                if let moved = AudioSamples.retimed(sampleBuffer, to: converted) { deliver(moved) }
            } else {
                deliver(sampleBuffer)
            }
        }
    }
}

/// The test microphone: a 1 kHz tone whose loudness swells and fades once a second, stamped
/// on the host clock, so the meter moves and tests can find it in the file.
@MainActor
final class ToneMicrophone: MicrophoneSource {
    nonisolated static let frequency: Double = 1000
    private var timer: DispatchSourceTimer?

    func start(deviceID: String?, deliver: @escaping @Sendable (CMSampleBuffer) -> Void) throws {
        timer = Self.makeTimer(deliver)
    }

    /// Nonisolated, so the timer's handler isn't tied to the main actor (it runs on its own queue).
    nonisolated private static func makeTimer(_ deliver: @escaping @Sendable (CMSampleBuffer) -> Void) -> DispatchSourceTimer {
        let queue = DispatchQueue(label: "app.slopapp.snapper.test-microphone")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let state = ToneState(start: CMClockGetTime(CMClockGetHostTimeClock()))
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { state.tick(deliver) }
        timer.resume()
        return timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Lives on the timer's queue.
    private final class ToneState: @unchecked Sendable {
        let start: CMTime
        var tone = ToneGenerator(frequency: ToneMicrophone.frequency, amplitude: 0.3)
        var produced: Int64 = 0

        init(start: CMTime) { self.start = start }

        func tick(_ deliver: @Sendable (CMSampleBuffer) -> Void) {
            // Catch up to now in 10 ms blocks.
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let due = Int64(CMTimeSubtract(now, start).seconds * 48_000)
            while produced + 480 <= due {
                let swell = Float(0.2 + 0.8 * abs(sin(Double(produced) / 48_000 * .pi)))
                let samples = tone.next(480).map { $0 * swell }
                let time = CMTimeAdd(start, CMTime(value: produced, timescale: 48_000))
                if let buffer = AudioSamples.makeBuffer(samples, time: time) { deliver(buffer) }
                produced += 480
            }
        }
    }
}

// MARK: Camera

/// A live picture for the camera bubble.
@MainActor
protocol CameraSource: AnyObject {
    /// Starts the camera and returns the layer that shows it (mirrored, filling its bounds).
    func start(deviceID: String?) throws -> CALayer
    func stop()
}

/// The real camera: a capture session shown by a preview layer. The bubble is our own window
/// on screen, so the recording picks it up like anything else; no frames are kept.
@MainActor
final class CaptureCamera: CameraSource {
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "app.slopapp.snapper.camera")

    func start(deviceID: String?) throws -> CALayer {
        let device = deviceID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw MediaCaptureError.noDevice(.camera) }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw MediaCaptureError.cantUse(.camera) }
        session.addInput(input)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        self.session = session
        nonisolated(unsafe) let running = session
        queue.async { running.startRunning() }
        return layer
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        nonisolated(unsafe) let running = session
        queue.async { running.stopRunning() }
    }
}

/// The test camera: a slowly turning gradient with a moving bar, so a test recording shows
/// the bubble is live. No real camera is opened.
@MainActor
final class TestCamera: CameraSource {
    func start(deviceID: String?) throws -> CALayer {
        let root = CALayer()
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor.systemTeal.cgColor, NSColor.systemIndigo.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.addSublayer(gradient)
        let spin = CABasicAnimation(keyPath: "colors")
        spin.fromValue = gradient.colors
        spin.toValue = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        spin.duration = 2
        spin.autoreverses = true
        spin.repeatCount = .infinity
        gradient.add(spin, forKey: "colors")
        let bar = CALayer()
        bar.backgroundColor = NSColor.systemYellow.cgColor
        bar.frame = CGRect(x: 0, y: 0, width: 12, height: 400)
        root.addSublayer(bar)
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = 0
        sweep.toValue = 480
        sweep.duration = 1.5
        sweep.repeatCount = .infinity
        bar.add(sweep, forKey: "sweep")
        return root
    }

    func stop() {}
}
