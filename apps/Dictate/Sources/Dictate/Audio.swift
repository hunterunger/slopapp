@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import DictateCore
import Foundation

/// Captures the microphone as 16 kHz mono Float32, and the voice features the ring draws.
final class AudioRecorder: AudioCapturing {
    private(set) var features = AudioFeatures()
    /// Called when the input device goes away mid-recording (unplugged, switched).
    var onInterruption: () -> Void = {}

    private let microphoneUID: () -> String
    private var engine: AVAudioEngine?
    private var sink: AudioSink?
    private var meterTimer: Timer?
    private var configObserver: NSObjectProtocol?

    init(microphoneUID: @escaping () -> String) {
        self.microphoneUID = microphoneUID
    }

    func start() throws {
        guard sink == nil else { return }
        // A fresh engine each time picks up the current default device and format.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        Self.applyPreferredDevice(microphoneUID(), to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.noInput
        }
        let sink = AudioSink(inputFormat: format)
        // Small buffers keep the ring's reaction to the voice tight.
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            sink.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        self.sink = sink
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let next = sink.nextFeatures()
            MainActor.assumeIsolated { self?.features = next }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onInterruption() }
        }
    }

    func recentSamples(seconds: Double) -> [Float] {
        sink?.recent(Int(seconds * AudioDecoder.sampleRate)) ?? []
    }

    @discardableResult
    func stop() -> [Float] {
        guard let sink, let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        features = AudioFeatures()
        self.sink = nil
        self.engine = nil
        return sink.drain()
    }

    /// Points the input node at the chosen microphone. No-op for "System Default" or a device
    /// that isn't connected (the default input is used then).
    private static func applyPreferredDevice(_ uid: String, to input: AVAudioInputNode) {
        guard !uid.isEmpty, var deviceID = AudioDevices.deviceID(forUID: uid), let unit = input.audioUnit else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    enum RecorderError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone is available. Connect one, or choose another in Settings." }
    }
}

/// Collects and resamples audio off the main thread (the tap runs on a realtime thread).
private nonisolated final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let extractor = FeatureExtractor()
    private var pending: [AudioFeatures] = []
    private var current = AudioFeatures()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioDecoder.sampleRate,
                                             channels: 1, interleaved: false)!
    private let converter: AVAudioConverter?

    init(inputFormat: AVAudioFormat) {
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        samples.reserveCapacity(Int(AudioDecoder.sampleRate) * 60)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        append(channel, count: Int(out.frameLength))
    }

    func append(_ pointer: UnsafePointer<Float>, count: Int) {
        lock.lock()
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

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
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

    func start() throws {
        guard !file.isEmpty else { throw AudioRecorder.RecorderError.noInput }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioDecoder.sampleRate,
                                   channels: 1, interleaved: false)!
        let sink = AudioSink(inputFormat: format)
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
