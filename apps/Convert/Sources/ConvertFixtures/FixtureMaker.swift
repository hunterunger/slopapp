import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

/// Makes synthetic media for tests and blind testers: a moving test pattern with a tone,
/// tones in every audio format macOS writes, and photo-like images. No personal content.
public enum FixtureMaker {
    public struct VideoSpec: Sendable {
        public var width = 640
        public var height = 360
        public var seconds = 2.0
        public var fps = 30.0
        public var codec: AVVideoCodecType = .h264
        public var fileType: AVFileType = .mov
        /// Number of tone tracks (0 = silent video).
        public var audioTracks = 1
        /// Stored landscape, shown portrait (like phone videos).
        public var portrait = false
        /// Tagged HLG HDR (HEVC Main10).
        public var hdr = false
        public var quality = 0.8
        /// Adds phone-style metadata: a title, creation date and location.
        public var metadata = false

        public init() {}
    }

    public enum FixtureError: Error { case failed(String) }

    // MARK: Video

    public static func video(_ url: URL, _ spec: VideoSpec = VideoSpec()) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: spec.fileType)
        var compression: [String: Any] = [:]
        if spec.codec != .proRes422 { compression[AVVideoQualityKey] = spec.quality }
        if spec.hdr { compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String }
        var settings: [String: Any] = [
            AVVideoCodecKey: spec.codec, AVVideoWidthKey: spec.width, AVVideoHeightKey: spec.height,
        ]
        if !compression.isEmpty { settings[AVVideoCompressionPropertiesKey] = compression }
        if spec.hdr {
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ]
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = false
        if spec.portrait { video.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let pixelFormat = spec.hdr ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: spec.width,
            kCVPixelBufferHeightKey as String: spec.height,
        ])
        writer.add(video)
        if spec.metadata {
            func item(_ key: AVMetadataKey, _ space: AVMetadataKeySpace, _ value: String) -> AVMetadataItem {
                let item = AVMutableMetadataItem()
                item.key = key as NSString
                item.keySpace = space
                item.value = value as NSString
                return item
            }
            writer.metadata = [
                item(.quickTimeMetadataKeyTitle, .quickTimeMetadata, "Fixture Title"),
                item(.quickTimeMetadataKeyCreationDate, .quickTimeMetadata, "2024-05-01T12:00:00-0600"),
                item(.quickTimeMetadataKeyLocationISO6709, .quickTimeMetadata, "+51.0447-114.0719/"),
            ]
        }

        let sampleRate = 44_100.0
        var audios: [AVAssetWriterInput] = []
        for _ in 0..<spec.audioTracks {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
            ])
            audio.expectsMediaDataInRealTime = false
            writer.add(audio)
            audios.append(audio)
        }
        guard writer.startWriting() else { throw FixtureError.failed("start: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(spec.seconds * spec.fps)
        let chunk = 4410
        let audioChunks = Int(spec.seconds * sampleRate) / chunk
        var frame = 0
        var chunks = Array(repeating: 0, count: audios.count)
        // Give up after 20 s without progress rather than spin forever (an encoder that
        // never becomes ready, e.g. on a virtual Mac without one).
        var lastProgress = Date()
        // Feed whichever track is behind; if it isn't ready, feed the others (the writer
        // may want more of them first to interleave).
        while frame < frames || chunks.contains(where: { $0 < audioChunks }) {
            var progressed = false
            let videoTime = frame < frames ? Double(frame) / spec.fps : .infinity
            let audioTimes = chunks.map { $0 < audioChunks ? Double($0 * chunk) / sampleRate : .infinity }
            let earliest = min(videoTime, audioTimes.min() ?? .infinity)
            let videoFirst = videoTime <= earliest
            if frame < frames, video.isReadyForMoreMediaData, videoFirst || !audios.indices.contains(where: {
                audioTimes[$0] <= earliest && audios[$0].isReadyForMoreMediaData
            }) {
                guard let pool = adaptor.pixelBufferPool else { throw FixtureError.failed("no pool") }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw FixtureError.failed("no buffer") }
                draw(frame: frame, of: frames, into: buffer, hdr: spec.hdr)
                if spec.hdr {
                    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
                    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, .shouldPropagate)
                    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(spec.fps))) else {
                    throw FixtureError.failed("video append: \(String(describing: writer.error))")
                }
                frame += 1
                if frame == frames { video.markAsFinished() }
                progressed = true
            } else {
                for (index, audio) in audios.enumerated() where chunks[index] < audioChunks && audio.isReadyForMoreMediaData {
                    let tone = 440.0 * Double(index + 1)
                    let sample = try toneSample(start: chunks[index] * chunk, count: chunk, rate: sampleRate, channels: 2, frequency: tone)
                    guard audio.append(sample) else { throw FixtureError.failed("audio append: \(String(describing: writer.error))") }
                    chunks[index] += 1
                    if chunks[index] == audioChunks { audio.markAsFinished() }
                    progressed = true
                    break
                }
            }
            if progressed {
                lastProgress = Date()
            } else {
                if writer.status == .failed { throw FixtureError.failed("writer: \(String(describing: writer.error))") }
                if Date().timeIntervalSince(lastProgress) > 20 { throw FixtureError.failed("writer stalled") }
                usleep(500)
            }
        }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) let w = writer
        w.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw FixtureError.failed("finish: \(String(describing: writer.error))") }
    }

    /// A gradient background, a bar that sweeps across over the clip, and a frame-number
    /// strip, so moving pictures and timing are easy to check by eye.
    static func draw(frame: Int, of frames: Int, into buffer: CVPixelBuffer, hdr: Bool) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let space = hdr ? CGColorSpace(name: CGColorSpace.itur_2100_HLG)! : CGColorSpace(name: CGColorSpace.sRGB)!
        let info = hdr
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                  bitsPerComponent: hdr ? 16 : 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: space, bitmapInfo: info) else { return }
        let colors = [CGColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1), CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)] // lint:allow synthetic test-pattern pixels (fixture data, not UI)
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        let t = Double(frame) / Double(max(1, frames - 1))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)) // lint:allow synthetic test-pattern pixels (fixture data, not UI)
        let barWidth = Double(width) / 8
        ctx.fill(CGRect(x: t * (Double(width) - barWidth), y: Double(height) * 0.25, width: barWidth, height: Double(height) * 0.5))
        // Frame counter: 10 bits as black/white squares along the bottom.
        let cell = Double(width) / 12
        for bit in 0..<10 {
            let on = (frame >> bit) & 1 == 1
            ctx.setFillColor(on ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0, green: 0, blue: 0, alpha: 1)) // lint:allow synthetic test-pattern pixels (fixture data, not UI)
            ctx.fill(CGRect(x: cell * Double(bit + 1), y: 4, width: cell * 0.8, height: cell * 0.5))
        }
    }

    /// Interleaved 16-bit PCM sine wave as a sample buffer.
    static func toneSample(start: Int, count: Int, rate: Double, channels: Int, frequency: Double) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var samples = [Int16](repeating: 0, count: count * channels)
        for i in 0..<count {
            let value = Int16(sin(2 * .pi * frequency * Double(start + i) / rate) * 8000)
            for c in 0..<channels { samples[i * channels + c] = value }
        }
        let bytes = samples.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard let block, let format else { throw FixtureError.failed("audio buffer") }
        _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw FixtureError.failed("audio sample") }
        return sample
    }

    // MARK: Audio

    /// A tone in the format the extension implies (wav, aiff, caf, m4a = AAC, flac).
    public static func audio(_ url: URL, seconds: Double = 2, channels: Int = 2, sampleRate: Double = 44_100, bits: Int = 16) throws {
        try? FileManager.default.removeItem(at: url)
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        // Surround needs its layout: 5.1 and 7.1 in WAV order (L R C LFE Ls Rs …).
        let tag: AudioChannelLayoutTag? = switch channels {
        case 6: kAudioChannelLayoutTag_MPEG_5_1_A
        case 8: kAudioChannelLayoutTag_MPEG_7_1_C
        default: nil
        }
        if let tag {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = tag
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        switch url.pathExtension.lowercased() {
        case "m4a":
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = channels == 1 ? 96_000 : 192_000
        case "flac":
            settings[AVFormatIDKey] = kAudioFormatFLAC
        default:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = bits
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = ["aif", "aiff"].contains(url.pathExtension.lowercased())
        }
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw FixtureError.failed("audio buffer")
        }
        buffer.frameLength = frames
        for c in 0..<channels {
            let data = buffer.floatChannelData![c]
            for i in 0..<Int(frames) {
                data[i] = Float(sin(2 * .pi * 440 * Double(c + 1) * Double(i) / sampleRate) * 0.3)
            }
        }
        try file.write(from: buffer)
    }

    // MARK: Images

    /// A photo-like image (gradient + noise), optionally with transparency or a sideways
    /// EXIF orientation (6 = shown rotated 90°).
    public static func image(_ url: URL, type: UTType, width: Int = 800, height: Int = 600,
                             alpha: Bool = false, orientation: Int = 1, frames: Int = 1) throws {
        try? FileManager.default.removeItem(at: url)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil) else {
            throw FixtureError.failed("can't write \(type.identifier)")
        }
        for f in 0..<frames {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
            let colors = [CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1), CGColor(red: 0.9, green: 0.8, blue: 0.3, alpha: 1)] // lint:allow synthetic test-pattern pixels (fixture data, not UI)
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
            if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width, height: height)) }
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width / 3, height: height)) }
            // An arrow-ish marker in the top-left so orientation is visible.
            ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)) // lint:allow synthetic test-pattern pixels (fixture data, not UI)
            ctx.fill(CGRect(x: width / 20 + f * 10, y: height - height / 4, width: width / 5, height: height / 6))
            var options: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                            kCGImageDestinationLossyCompressionQuality: 0.95]
            options[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "Convert fixture"]
            options[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 51.05, kCGImagePropertyGPSLatitudeRef: "N",
                                                      kCGImagePropertyGPSLongitude: 114.07, kCGImagePropertyGPSLongitudeRef: "W"]
            if frames > 1 { options[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: 0.2] }
            CGImageDestinationAddImage(dest, ctx.makeImage()!, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw FixtureError.failed("finalize \(url.lastPathComponent)") }
    }

    // MARK: The blind-test set

    /// Everything a tester needs in one folder: videos, audio, images, and files Convert
    /// should refuse with a clear reason.
    public static func standardSet(in folder: URL, includeLong: Bool = true) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var made: [URL] = []
        func add(_ name: String, _ make: (URL) throws -> Void) rethrows {
            let url = folder.appendingPathComponent(name)
            try make(url)
            made.append(url)
        }
        try add("Screen Recording.mov") { url in
            var s = VideoSpec(); s.width = 1280; s.height = 720; s.seconds = 6; s.codec = .hevc
            try video(url, s)
        }
        try add("Clip H264.mov") { url in
            var s = VideoSpec(); s.width = 1280; s.height = 720; s.seconds = 4
            try video(url, s)
        }
        try add("Phone Video.mov") { url in
            var s = VideoSpec(); s.width = 1280; s.height = 720; s.seconds = 3; s.portrait = true; s.codec = .hevc
            try video(url, s)
        }
        try add("Silent Clip.mp4") { url in
            var s = VideoSpec(); s.seconds = 2; s.audioTracks = 0; s.fileType = .mp4
            try video(url, s)
        }
        try add("Two Sound Tracks.mov") { url in
            var s = VideoSpec(); s.seconds = 2; s.audioTracks = 2
            try video(url, s)
        }
        try add("Already.mp4") { url in
            var s = VideoSpec(); s.seconds = 2; s.fileType = .mp4
            try video(url, s)
        }
        if includeLong {
            try add("Long Clip.mov") { url in
                var s = VideoSpec(); s.width = 640; s.height = 360; s.seconds = 35; s.fps = 24
                try video(url, s)
            }
        }
        try add("Interview.wav") { try audio($0, seconds: 5) }
        try add("Voice Memo.m4a") { try audio($0, seconds: 4, channels: 1) }
        try add("Loop.aiff") { try audio($0, seconds: 3, bits: 24) }
        try add("Photo.heic") { try image($0, type: .heic, width: 1600, height: 1200) }
        try add("Sideways Photo.jpg") { try image($0, type: .jpeg, width: 1200, height: 900, orientation: 6) }
        try add("Logo.png") { try image($0, type: .png, width: 512, height: 512, alpha: true) }
        try add("Animated.gif") { try image($0, type: .gif, width: 200, height: 150, frames: 4) }
        try add("Surround.wav") { try audio($0, seconds: 4, channels: 6, sampleRate: 48_000) }
        try add("Not Really.mkv") { try Data("not really a matroska file".utf8).write(to: $0) }
        try add("Broken.mp4") { try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: $0) }
        try add("Notes.txt") { try Data("Convert should say it can't convert this.".utf8).write(to: $0) }
        return made
    }

    /// The Matroska part of the set (needs the clips above): a real MKV with subtitles, made
    /// from "Clip H264.mov".
    public static func matroskaSet(in folder: URL) async throws -> [URL] {
        let source = folder.appendingPathComponent("Clip H264.mov")
        let movie = folder.appendingPathComponent("Movie with Subtitles.mkv")
        var spec = MatroskaFixture.Spec()
        spec.subtitles = [(0.3, 1.6, "This line is a subtitle"), (1.8, 3.6, "<i>And this is the second one</i>")]
        try await MatroskaFixture.make(movie, from: source, spec: spec)
        return [movie]
    }
}
