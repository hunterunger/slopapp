import AVFoundation
import CoreMedia
import Foundation

/// Writes Matroska test files from FixtureMaker's own clips: the H.264 picture and AAC sound
/// of a MOV, repackaged as MKV (or WebM-labelled), with text subtitles. Synthetic only.
public enum MatroskaFixture {
    public struct Spec: Sendable {
        /// Several sound frames per block (EBML lacing), as some muxers write.
        public var lacedAudio = false
        /// Clusters of unknown size, as recorders and live streams write.
        public var unknownSizeClusters = false
        /// Subtitle lines: start and end in seconds, text (SRT markup allowed).
        public var subtitles: [(Double, Double, String)] = [(0.2, 0.9, "First <i>line</i>"), (1.1, 1.8, "Second line")]
        public var subtitleLanguage = "eng"
        public var docType = "matroska"

        public init() {}
    }

    public static func make(_ url: URL, from mov: URL, spec: Spec = Spec()) async throws {
        let asset = AVURLAsset(url: mov)
        let reader = try AVAssetReader(asset: asset)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        var outputs: [(AVAssetReaderTrackOutput, Int)] = []
        var avcC = Data()
        var size = CGSize.zero
        var fps: Float = 30
        var rate = 44_100.0, channels = 2
        if let videoTrack {
            let (formats, natural, frameRate) = try await videoTrack.load(.formatDescriptions, .naturalSize, .nominalFrameRate)
            let atoms = (formats.first.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) }) as? [String: Any]
            avcC = atoms?["avcC"] as? Data ?? Data()
            size = natural
            fps = frameRate
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            reader.add(output)
            outputs.append((output, 1))
        }
        if let audioTrack {
            let formats = try await audioTrack.load(.formatDescriptions)
            if let asbd = formats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) {
                rate = asbd.mSampleRate
                channels = Int(asbd.mChannelsPerFrame)
            }
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(output)
            outputs.append((output, 2))
        }
        guard reader.startReading() else { throw FixtureMaker.FixtureError.failed("read \(mov.lastPathComponent)") }

        // Every frame: track, decode order key, presentation time (ms), key frame, bytes.
        struct Frame { var track: Int; var order: Double; var pts: Int; var key: Bool; var data: Data; var duration: Int? }
        var frames: [Frame] = []
        for (output, track) in outputs {
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample), CMSampleBufferGetNumSamples(sample) > 0 else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
                guard let pointer else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let dts = CMSampleBufferGetDecodeTimeStamp(sample)
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
                let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
                // Sound buffers may hold several packets: split them at their packet sizes.
                if track == 2, CMSampleBufferGetNumSamples(sample) > 1 {
                    var offset = 0
                    for index in 0..<CMSampleBufferGetNumSamples(sample) {
                        let bytes = CMSampleBufferGetSampleSize(sample, at: index)
                        let t = pts + Double(index) * 1024 / rate
                        frames.append(Frame(track: 2, order: t, pts: Int((t * 1000).rounded()), key: true,
                                            data: Data(bytes: pointer + offset, count: bytes)))
                        offset += bytes
                    }
                    continue
                }
                frames.append(Frame(track: track, order: dts.isNumeric ? dts.seconds : pts, pts: Int((pts * 1000).rounded()),
                                    key: track != 1 || !notSync, data: Data(bytes: pointer, count: length)))
            }
        }
        for (start, end, text) in spec.subtitles {
            frames.append(Frame(track: 3, order: start, pts: Int(start * 1000), key: true, data: Data(text.utf8),
                                duration: Int((end - start) * 1000)))
        }
        frames.sort { $0.order < $1.order }
        let duration = (frames.map { Double($0.pts) + Double($0.duration ?? 0) }.max() ?? 0)

        var out = Data()
        out += element(0x1A45_DFA3, [
            element(0x4286, uint(1)), element(0x42F7, uint(1)), element(0x42F2, uint(4)), element(0x42F3, uint(8)),
            element(0x4282, Data(spec.docType.utf8)), element(0x4287, uint(4)), element(0x4285, uint(2)),
        ].reduce(Data(), +))
        var segment = Data()
        segment += element(0x1549_A966, [
            element(0x2AD7B1, uint(1_000_000)), element(0x4489, float(duration)),
            element(0x4D80, Data("Convert fixtures".utf8)), element(0x5741, Data("Convert fixtures".utf8)),
        ].reduce(Data(), +))
        var tracks = Data()
        if videoTrack != nil {
            tracks += element(0xAE, [
                element(0xD7, uint(1)), element(0x73C5, uint(1)), element(0x83, uint(1)),
                element(0x86, Data("V_MPEG4/ISO/AVC".utf8)), element(0x63A2, avcC),
                element(0x23E383, uint(UInt64(1e9 / Double(max(1, fps))))),
                element(0xE0, element(0xB0, uint(UInt64(size.width))) + element(0xBA, uint(UInt64(size.height)))),
            ].reduce(Data(), +))
        }
        if audioTrack != nil {
            let index = [96000.0, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000].firstIndex(of: rate) ?? 4
            let config = UInt16(2) << 11 | UInt16(index) << 7 | UInt16(channels) << 3
            tracks += element(0xAE, [
                element(0xD7, uint(2)), element(0x73C5, uint(2)), element(0x83, uint(2)),
                element(0x86, Data("A_AAC".utf8)), element(0x63A2, Data([UInt8(config >> 8), UInt8(config & 0xFF)])),
                element(0x23E383, uint(UInt64(1024 / rate * 1e9))),
                element(0xE1, element(0xB5, float(rate)) + element(0x9F, uint(UInt64(channels)))),
            ].reduce(Data(), +))
        }
        if !spec.subtitles.isEmpty {
            tracks += element(0xAE, [
                element(0xD7, uint(3)), element(0x73C5, uint(3)), element(0x83, uint(17)),
                element(0x86, Data("S_TEXT/UTF8".utf8)), element(0x22B59C, Data(spec.subtitleLanguage.utf8)),
                element(0x88, uint(0)),
            ].reduce(Data(), +))
        }
        segment += element(0x1654_AE6B, tracks)

        // Clusters of about a second, in decode order.
        var index = 0
        while index < frames.count {
            let clusterTime = max(0, frames[index].pts - 200)
            var body = element(0xE7, uint(UInt64(clusterTime)))
            let limit = clusterTime + 1000
            while index < frames.count, frames[index].pts < limit {
                let frame = frames[index]
                if frame.track == 2, spec.lacedAudio {
                    // Up to four sound frames in one block.
                    var group = [frame]
                    while group.count < 4, index + group.count < frames.count, frames[index + group.count].track == 2,
                          frames[index + group.count].pts < limit {
                        group.append(frames[index + group.count])
                    }
                    if group.count > 1 {
                        body += element(0xA3, lacedBlock(group.map(\.data), track: 2, time: frame.pts - clusterTime))
                        index += group.count
                        continue
                    }
                }
                let block = simpleBlockHeader(track: frame.track, time: frame.pts - clusterTime,
                                              flags: frame.key ? 0x80 : 0) + frame.data
                if let duration = frame.duration {
                    var plain = block
                    plain[plain.startIndex + 3] = 0 // a Block has no key-frame flag
                    body += element(0xA0, element(0xA1, plain) + element(0x9B, uint(UInt64(duration))))
                } else {
                    body += element(0xA3, block)
                }
                index += 1
            }
            segment += spec.unknownSizeClusters ? unknownSize(0x1F43_B675, body) : element(0x1F43_B675, body)
        }
        out += unknownSize(0x1853_8067, segment)
        try? FileManager.default.removeItem(at: url)
        try out.write(to: url)
    }

    // MARK: EBML

    static func id(_ value: UInt32) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Data($0) }
        while bytes.first == 0 { bytes.removeFirst() }
        return bytes
    }

    /// Sizes as 8-byte variable-length integers (always valid, simple to write).
    static func size(_ value: Int) -> Data {
        Data([0x01] + (0..<7).reversed().map { UInt8((UInt64(value) >> (8 * UInt64($0))) & 0xFF) })
    }

    static func element(_ value: UInt32, _ body: Data) -> Data { id(value) + size(body.count) + body }

    static func unknownSize(_ value: UInt32, _ body: Data) -> Data {
        id(value) + Data([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]) + body
    }

    static func uint(_ value: UInt64) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Data($0) }
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        return bytes
    }

    static func float(_ value: Double) -> Data { withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) } }

    static func simpleBlockHeader(track: Int, time: Int, flags: UInt8) -> Data {
        let t = UInt16(bitPattern: Int16(clamping: time))
        return Data([0x80 | UInt8(track), UInt8(t >> 8), UInt8(t & 0xFF), flags])
    }

    /// EBML lacing: count − 1, the first size, then signed differences.
    static func lacedBlock(_ frames: [Data], track: Int, time: Int) -> Data {
        var data = simpleBlockHeader(track: track, time: time, flags: 0x80 | 0x06)
        data.append(UInt8(frames.count - 1))
        data += vint(UInt64(frames[0].count), length: 2)
        for i in 1..<(frames.count - 1) {
            let difference = frames[i].count - frames[i - 1].count
            data += vint(UInt64(difference + 8191), length: 2) // 2-byte signed: bias 2^13 − 1
        }
        for frame in frames { data += frame }
        return data
    }

    static func vint(_ value: UInt64, length: Int) -> Data {
        let marked = value | (UInt64(1) << (7 * UInt64(length)))
        return Data((0..<length).reversed().map { UInt8((marked >> (8 * UInt64($0))) & 0xFF) })
    }
}
