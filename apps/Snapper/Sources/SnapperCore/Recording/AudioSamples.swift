import AVFoundation
import CoreMedia

/// Audio sample buffers: reading their samples (for the level meter) and making them (the
/// test microphone, the test scene's tone, test files).
public enum AudioSamples {
    /// The samples of a linear PCM buffer as Float32, all channels in a row. Nil for compressed
    /// or unsupported formats.
    public static func floats(in sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return nil }
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
                                                                bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                flags: 0, blockBufferOut: nil)
        guard sizeNeeded > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        guard status == noErr else { return nil }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        var result: [Float] = []
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData else { continue }
            let bytes = Int(buffer.mDataByteSize)
            if isFloat, asbd.mBitsPerChannel == 32 {
                result.append(contentsOf: UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: bytes / 4))
            } else if !isFloat, asbd.mBitsPerChannel == 16 {
                let ints = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self), count: bytes / 2)
                result.append(contentsOf: ints.map { Float($0) / Float(Int16.max) })
            } else if !isFloat, asbd.mBitsPerChannel == 32 {
                let ints = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int32.self), count: bytes / 4)
                result.append(contentsOf: ints.map { Float($0) / Float(Int32.max) })
            } else {
                return nil
            }
        }
        return result
    }

    /// A Float32 interleaved PCM sample buffer stamped `time`.
    public static func makeBuffer(_ samples: [Float], channels: Int = 1, sampleRate: Double = 48_000, time: CMTime) -> CMSampleBuffer? {
        let frames = samples.count / max(1, channels)
        guard frames > 0 else { return nil }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let byteCount = frames * channels * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copied == noErr else { return nil }
        var buffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: frames, presentationTimeStamp: time,
                                                                   packetDescriptions: nil, sampleBufferOut: &buffer) == noErr else { return nil }
        return buffer
    }

    /// The same samples at a new time (recordings move samples back by the paused time).
    public static func retimed(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(1, count))
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: timing.count, arrayToFill: &timing, entriesNeededOut: &count)
        let shift = CMTimeSubtract(time, CMSampleBufferGetPresentationTimeStamp(buffer))
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeAdd(timing[index].presentationTimeStamp, shift)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(timing[index].decodeTimeStamp, shift)
            }
        }
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer, sampleTimingEntryCount: timing.count,
                                                    sampleTimingArray: &timing, sampleBufferOut: &output) == noErr else { return nil }
        return output
    }
}

/// How loud a block of samples is, for the microphone meter.
public enum AudioLevel {
    /// Root mean square of the samples (0 = silence, ~0.707 = a full-scale sine).
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// 0…1 for a meter: decibels from `floor` (silent) to 0 dBFS (full), linear in between.
    public static func meter(rms: Float, floor: Float = -50) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return Double(min(1, max(0, (decibels - floor) / -floor)))
    }
}

/// A meter value that jumps up at once and falls back smoothly, like a VU meter.
public struct LevelMeter: Equatable, Sendable {
    public private(set) var value: Double = 0
    /// How much of the level falls away per second.
    public var decayPerSecond: Double = 1.6

    public init() {}

    public mutating func feed(_ level: Double, elapsed: TimeInterval) {
        let fallen = max(0, value - decayPerSecond * max(0, elapsed))
        value = min(1, max(level, fallen))
    }

    public mutating func reset() { value = 0 }
}

/// A sine tone, block by block (the test microphone and the test scene's sound).
public struct ToneGenerator: Sendable {
    public var frequency: Double
    public var amplitude: Float
    public var sampleRate: Double
    private var phase: Double = 0

    public init(frequency: Double, amplitude: Float = 0.25, sampleRate: Double = 48_000) {
        self.frequency = frequency
        self.amplitude = amplitude
        self.sampleRate = sampleRate
    }

    /// The next `count` samples, mono.
    public mutating func next(_ count: Int) -> [Float] {
        let step = 2 * Double.pi * frequency / sampleRate
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = amplitude * Float(sin(phase))
            phase += step
            if phase > 2 * .pi { phase -= 2 * .pi }
        }
        return samples
    }

    /// How strongly `frequency` is present in `samples` (Goertzel), 0…~1 relative to the
    /// block's own energy. Tests use it to tell the computer's tone from the microphone's.
    public static func presence(of frequency: Double, in samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 16 else { return 0 }
        let k = (Double(samples.count) * frequency / sampleRate).rounded()
        let omega = 2 * Double.pi * k / Double(samples.count)
        let coefficient = 2 * cos(omega)
        var s1 = 0.0, s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
        let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        guard energy > 0 else { return 0 }
        return power / (energy * Double(samples.count) / 2)
    }
}
