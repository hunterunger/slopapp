import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import DictateCore
import Foundation

/// Captures the microphone as 16 kHz mono Float32, and the voice features the ring draws.
///
/// Two rules keep the app from freezing here:
/// - Input only, through an audio queue. AVAudioEngine's input node joins the microphone and
///   the speakers into an aggregate device on every new engine, and on macOS 27 that setup
///   can fail and then spin forever inside Core Audio.
/// - The main thread never waits on Core Audio. Opening and closing the microphone run on
///   their own queue, and an open that takes longer than `openTimeout` fails the dictation
///   ("The microphone didn't respond") instead of hanging the app.
final class AudioRecorder: AudioCapturing {
    private(set) var features = AudioFeatures()
    /// Called when the input device goes away mid-recording and no other microphone takes over.
    var onInterruption: () -> Void = {}

    private let microphoneUID: () -> String
    private var sink: AudioSink?
    private var capture: MicrophoneCapture?
    private var meterTimer: Timer?
    /// Bumped by every start and stop, so a late open or device change from an earlier
    /// recording is dropped.
    private var session = 0

    /// Opening a microphone takes well under a second; Bluetooth headsets can take a few.
    private static let openTimeout: Double = 6
    /// Restarts after the microphone changes, at most this many times per recording.
    private static let maxRestarts = 3
    private var restarts = 0

    init(microphoneUID: @escaping () -> String) {
        self.microphoneUID = microphoneUID
    }

    func start() async throws {
        guard sink == nil else { return }
        session += 1
        let session = self.session
        restarts = 0
        let sink = AudioSink()
        self.sink = sink
        do {
            capture = try await open(sink: sink, session: session)
        } catch {
            if session == self.session { self.sink = nil }
            throw error
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sink = self.sink else { return }
                self.features = sink.nextFeatures()
            }
        }
    }

    /// Opens the chosen microphone (or the default one) off the main thread.
    private func open(sink: AudioSink, session: Int) async throws -> MicrophoneCapture {
        let capture = try await MicrophoneCapture.open(
            preferredUID: microphoneUID(), sink: sink, timeout: Self.openTimeout
        ) { [weak self] in
            Task { @MainActor in self?.microphoneChanged(session: session) }
        }
        guard session == self.session, self.sink === sink else {
            // Stopped or cancelled while the microphone was opening.
            capture.close()
            throw CancellationError()
        }
        return capture
    }

    /// The microphone being recorded went away, or the one that should be recorded changed
    /// (a new default input, the chosen microphone plugged back in). Keep recording on the
    /// right one, with what was said so far; only when there's none does the recording end.
    private func microphoneChanged(session: Int) {
        guard session == self.session, let sink, let old = capture else { return }
        capture = nil
        old.close()
        restarts += 1
        guard restarts <= Self.maxRestarts else {
            Diagnostics.record("microphone changed: gave up after \(Self.maxRestarts) restarts")
            onInterruption()
            return
        }
        let attempt = restarts
        Task {
            do {
                capture = try await open(sink: sink, session: session)
                Diagnostics.record("microphone changed: recording continues (restart \(attempt))")
            } catch is CancellationError {
            } catch {
                guard session == self.session else { return }
                Diagnostics.record("microphone changed: no microphone (\(error.localizedDescription))")
                onInterruption()
            }
        }
    }

    func recentSamples(seconds: Double) -> [Float] {
        sink?.recent(Int(seconds * AudioDecoder.sampleRate)) ?? []
    }

    /// Returns at once: the microphone closes in the background.
    @discardableResult
    func stop() -> [Float] {
        session += 1
        guard let sink else { return [] }
        capture?.close()
        capture = nil
        meterTimer?.invalidate()
        meterTimer = nil
        features = AudioFeatures()
        self.sink = nil
        return sink.close()
    }

    enum RecorderError: LocalizedError {
        case noInput
        case notResponding
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone is available. Connect one, or choose another in Settings."
            case .notResponding:
                "The microphone didn't respond. Try again, or choose another microphone in Settings."
            case .failed(let status): "The microphone couldn't start (error \(status))."
            }
        }
    }
}

/// One open microphone: an input-only audio queue that hands 16 kHz mono Float32 to a sink.
/// Every Core Audio call it makes runs on its own serial queue, never on the main thread.
private nonisolated final class MicrophoneCapture: @unchecked Sendable {
    private static let sampleFormat = AudioStreamBasicDescription(
        mSampleRate: AudioDecoder.sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
        mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    /// 32 ms buffers keep the ring's reaction to the voice tight.
    private static let bufferFrames: UInt32 = 512
    private static let bufferCount = 3

    private let worker: DispatchQueue
    private let preferredUID: String
    private let deviceID: AudioDeviceID
    private var queue: AudioQueueRef?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private init(worker: DispatchQueue, preferredUID: String, deviceID: AudioDeviceID) {
        self.worker = worker
        self.preferredUID = preferredUID
        self.deviceID = deviceID
    }

    /// Opens and starts the microphone on a queue of its own. Gives up after `timeout`
    /// seconds; a microphone that opens after that is closed again.
    static func open(preferredUID: String, sink: AudioSink, timeout: Double,
                     onChange: @escaping @Sendable () -> Void) async throws -> MicrophoneCapture {
        let worker = DispatchQueue(label: "app.slopapp.dictate.microphone", qos: .userInitiated)
        let outcome = OneShot()
        return try await withCheckedThrowingContinuation { continuation in
            worker.async {
                let result = Result { try start(preferredUID: preferredUID, sink: sink, worker: worker, onChange: onChange) }
                if outcome.claim() {
                    continuation.resume(with: result)
                } else if case .success(let late) = result {
                    Diagnostics.record("microphone opened after the timeout; closing it")
                    late.close()
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                guard outcome.claim() else { return }
                Diagnostics.record("microphone didn't open within \(timeout) s")
                continuation.resume(throwing: AudioRecorder.RecorderError.notResponding)
            }
        }
    }

    /// Runs on `worker`.
    private static func start(preferredUID: String, sink: AudioSink, worker: DispatchQueue,
                              onChange: @escaping @Sendable () -> Void) throws -> MicrophoneCapture {
        // The chosen microphone when it's connected, else the default input.
        let preferred = preferredUID.isEmpty ? nil : AudioDevices.deviceID(forUID: preferredUID)
        guard let device = preferred ?? AudioDevices.defaultInputDevice(),
              let uid = AudioDevices.uid(of: device) else { throw AudioRecorder.RecorderError.noInput }

        let capture = MicrophoneCapture(worker: worker, preferredUID: preferredUID, deviceID: device)
        var format = sampleFormat
        var queue: AudioQueueRef?
        let buffers = DispatchQueue(label: "app.slopapp.dictate.microphone.buffers", qos: .userInteractive)
        var status = AudioQueueNewInputWithDispatchQueue(&queue, &format, 0, buffers, callback(into: sink))
        guard status == noErr, let queue else { throw AudioRecorder.RecorderError.failed(status) }
        capture.queue = queue
        do {
            var deviceUID = uid as CFString
            status = withUnsafeMutablePointer(to: &deviceUID) {
                AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, $0, UInt32(MemoryLayout<CFString>.size))
            }
            guard status == noErr else { throw AudioRecorder.RecorderError.failed(status) }
            for _ in 0..<bufferCount {
                var buffer: AudioQueueBufferRef?
                status = AudioQueueAllocateBuffer(queue, bufferFrames * sampleFormat.mBytesPerFrame, &buffer)
                guard status == noErr, let buffer else { throw AudioRecorder.RecorderError.failed(status) }
                AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            }
            status = AudioQueueStart(queue, nil)
            guard status == noErr else { throw AudioRecorder.RecorderError.failed(status) }
        } catch {
            capture.shutDown()
            throw error
        }
        capture.watchDevices(onChange: onChange)
        return capture
    }

    /// The buffer callback. Built in a nonisolated function so it can't inherit main-actor
    /// isolation (it runs on the buffers queue).
    private static func callback(into sink: AudioSink) -> AudioQueueInputCallbackBlock {
        { queue, buffer, _, _, _ in
            let bytes = Int(buffer.pointee.mAudioDataByteSize)
            if bytes > 0 {
                sink.append(buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self),
                            count: bytes / MemoryLayout<Float>.size)
            }
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
    }

    /// Calls `onChange` when the device list or the default input changes in a way that means
    /// a different microphone should be recording.
    private func watchDevices(onChange: @escaping @Sendable () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.queue != nil, self.shouldSwitch() else { return }
                onChange()
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, worker, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    /// Runs on `worker`.
    private func shouldSwitch() -> Bool {
        guard AudioDevices.isAlive(deviceID) else { return true }
        let preferred = preferredUID.isEmpty ? nil : AudioDevices.deviceID(forUID: preferredUID)
        let wanted = preferred ?? AudioDevices.defaultInputDevice()
        return wanted != nil && wanted != deviceID
    }

    /// Stops and disposes of the queue in the background.
    func close() {
        worker.async { self.shutDown() }
    }

    /// Runs on `worker`.
    private func shutDown() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, worker, block)
        }
        listeners = []
        guard let queue else { return }
        self.queue = nil
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
    }
}

/// The first of several racing callers wins.
private nonisolated final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Collects 16 kHz mono samples and the voice features off the main thread (audio arrives
/// on the microphone's buffers queue).
private nonisolated final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var closed = false
    private let extractor = FeatureExtractor()
    private var pending: [AudioFeatures] = []
    private var current = AudioFeatures()

    init() {
        samples.reserveCapacity(Int(AudioDecoder.sampleRate) * 60)
    }

    func append(_ pointer: UnsafePointer<Float>, count: Int) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
        lock.unlock()
        extractor.consume(pointer, count: count) { features in
            lock.lock()
            pending.append(features)
            if pending.count > 6 { pending.removeFirst(pending.count - 6) }
            lock.unlock()
        }
    }

    /// The next analysed window, with a fast-attack, smoothed-release level.
    func nextFeatures() -> AudioFeatures {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return current }
        var next = pending.removeFirst()
        if next.level < current.level { next.level = current.level * 0.55 + next.level * 0.45 }
        current = next
        return current
    }

    func recent(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return Array(samples.suffix(count))
    }

    /// Everything recorded so far, for a sink that's still recording (file audio).
    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Everything recorded; later audio is ignored.
    func close() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        closed = true
        return samples
    }
}

/// Test stand-in for the microphone: "records" an audio file in real time, so a scripted
/// walkthrough exercises the whole pipeline (ring, preview, transcription, insertion)
/// without ever hearing the room. `DICTATE_FAKE_AUDIO=/path/file`.
final class FileAudioSource: AudioCapturing {
    private(set) var features = AudioFeatures()
    private var file: [Float] = []
    private var position = 0
    private var sink: AudioSink?
    private var timer: Timer?

    init(url: URL) {
        Task {
            do {
                file = try await AudioDecoder.decode(url: url)
                Diagnostics.record("fake-audio loaded samples=\(file.count)")
            } catch {
                Diagnostics.record("fake-audio failed \(error.localizedDescription)")
            }
        }
    }

    func start() async throws {
        guard !file.isEmpty else { throw AudioRecorder.RecorderError.noInput }
        let sink = AudioSink()
        self.sink = sink
        position = 0
        let chunk = Int(AudioDecoder.sampleRate / 30)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sink = self.sink else { return }
                // After the file ends, keep "recording" silence like a quiet room.
                let end = min(self.file.count, self.position + chunk)
                var piece = self.position < end ? Array(self.file[self.position..<end]) : []
                if piece.count < chunk { piece += Array(repeating: 0, count: chunk - piece.count) }
                self.position += chunk
                piece.withUnsafeBufferPointer { sink.append($0.baseAddress!, count: $0.count) }
                self.features = sink.nextFeatures()
            }
        }
    }

    func recentSamples(seconds: Double) -> [Float] {
        sink?.recent(Int(seconds * AudioDecoder.sampleRate)) ?? []
    }

    @discardableResult
    func stop() -> [Float] {
        timer?.invalidate()
        timer = nil
        features = AudioFeatures()
        defer { sink = nil }
        return sink?.drain() ?? []
    }
}

/// Microphone permission.
final class SystemMicrophone: MicrophoneAuthorizing {
    var status: MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Fake audio needs no permission.
final class NoMicrophoneNeeded: MicrophoneAuthorizing {
    var status: MicrophoneStatus { .granted }
    func request() async -> Bool { true }
}

/// A microphone people can pick.
struct MicrophoneDevice: Identifiable, Hashable {
    /// Core Audio's stable UID (survives replugging; the numeric id doesn't).
    let uid: String
    let name: String
    var id: String { uid }
}

/// Core Audio input devices.
nonisolated enum AudioDevices {
    static func inputDevices() -> [MicrophoneDevice] {
        allDeviceIDs().compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return MicrophoneDevice(uid: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { hasInput($0) && string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        let id = uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
        return id.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    static func uid(of id: AudioDeviceID) -> String? {
        string(id, kAudioDevicePropertyDeviceUID)
    }

    /// Connected and still an input.
    static func isAlive(_ id: AudioDeviceID) -> Bool {
        uint32(id, kAudioDevicePropertyDeviceIsAlive) == 1 && hasInput(id)
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty,
              AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
            .contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
