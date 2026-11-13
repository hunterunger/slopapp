import Foundation

/// The small codec configuration records MP4 files carry (and Core Audio wants as "magic
/// cookies"), built from what Matroska stores. Pure, so they're tested byte for byte.
enum CodecBoxes {
    // MARK: MPEG-4 descriptors (AAC, MPEG-4 Part 2 video)

    /// An ES_Descriptor (ISO 14496-1) holding a decoder config. Core Audio takes this as the
    /// AAC cookie; with 4 bytes of version/flags in front it's an `esds` atom.
    static func esDescriptor(objectType: UInt8, streamType: UInt8, specificInfo: Data) -> Data {
        var decoderConfig = Data([objectType, streamType << 2 | 1, 0, 0, 0])
        decoderConfig += Data(repeating: 0, count: 8) // max and average bit rate: unknown
        decoderConfig += descriptor(tag: 0x05, specificInfo)
        var es = Data([0, 0, 0]) // ES_ID 0, no flags
        es += descriptor(tag: 0x04, decoderConfig)
        es += descriptor(tag: 0x06, Data([0x02])) // SL config: predefined MP4
        return descriptor(tag: 0x03, es)
    }

    /// A tag, its length in the 4-byte form (`80 80 80 nn`), then the body.
    static func descriptor(tag: UInt8, _ body: Data) -> Data {
        let n = body.count
        return Data([tag, UInt8(0x80 | (n >> 21) & 0x7F), UInt8(0x80 | (n >> 14) & 0x7F),
                     UInt8(0x80 | (n >> 7) & 0x7F), UInt8(n & 0x7F)]) + body
    }

    static let aacSampleRates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

    /// An AudioSpecificConfig for files that name the AAC profile in the codec ID instead
    /// of storing one ("A_AAC/MPEG4/LC").
    static func audioSpecificConfig(objectType: Int, sampleRate: Double, channels: Int) -> Data {
        let index = aacSampleRates.firstIndex(of: sampleRate) ?? 4
        let config = UInt16(objectType & 0x1F) << 11 | UInt16(index & 0x0F) << 7 | UInt16(min(7, channels) & 0x0F) << 3
        return Data([UInt8(config >> 8), UInt8(config & 0xFF)])
    }

    /// (object type, sample rate, channels) from an AudioSpecificConfig.
    static func parseAudioSpecificConfig(_ data: Data) -> (objectType: Int, sampleRate: Double, channels: Int)? {
        let b = [UInt8](data)
        guard b.count >= 2 else { return nil }
        let objectType = Int(b[0] >> 3)
        let index = Int((b[0] & 0x07) << 1 | b[1] >> 7)
        let channels = Int((b[1] >> 3) & 0x0F)
        guard index < aacSampleRates.count else { return nil }
        return (objectType, aacSampleRates[index], channels)
    }

    // MARK: Boxes

    static func box(_ type: String, _ body: Data) -> Data {
        let size = UInt32(8 + body.count)
        return Data([UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
            + Data(type.utf8) + body
    }

    // MARK: AC-3 / E-AC-3

    struct AC3Header: Equatable {
        var sampleRate: Double
        var channels: Int
        /// The `dac3` / `dec3` box, which Core Audio takes as the cookie.
        var cookie: Data
        var samplesPerFrame: Int
    }

    /// Reads the first AC-3 sync frame.
    static func ac3(_ frame: Data) -> AC3Header? {
        let b = [UInt8](frame.prefix(8))
        guard b.count >= 7, b[0] == 0x0B, b[1] == 0x77 else { return nil }
        let fscod = Int(b[4] >> 6)
        let frmsizecod = Int(b[4] & 0x3F)
        let bsid = Int(b[5] >> 3)
        let bsmod = Int(b[5] & 0x07)
        guard fscod < 3, bsid <= 10 else { return nil }
        var bits = BitReader(Array(b[6...]))
        let acmod = bits.read(3)
        if acmod & 1 != 0 && acmod != 1 { _ = bits.read(2) }
        if acmod & 4 != 0 { _ = bits.read(2) }
        if acmod == 2 { _ = bits.read(2) }
        let lfe = bits.read(1)
        let payload = UInt32(fscod) << 22 | UInt32(bsid) << 17 | UInt32(bsmod) << 14 | UInt32(acmod) << 11
            | UInt32(lfe) << 10 | UInt32(frmsizecod >> 1) << 5
        let rate = [48000.0, 44100, 32000][fscod]
        return AC3Header(sampleRate: rate, channels: acmodChannels[acmod] + lfe,
                         cookie: box("dac3", Data([UInt8(payload >> 16), UInt8(payload >> 8 & 0xFF), UInt8(payload & 0xFF)])),
                         samplesPerFrame: 1536)
    }

    /// Reads the first E-AC-3 frame (one independent substream).
    static func eac3(_ frame: Data) -> AC3Header? {
        let b = [UInt8](frame.prefix(8))
        guard b.count >= 6, b[0] == 0x0B, b[1] == 0x77 else { return nil }
        var bits = BitReader(Array(b[2...]))
        _ = bits.read(2) // stream type
        _ = bits.read(3) // substream id
        let frameSize = (bits.read(11) + 1) * 2
        let fscod = bits.read(2)
        var blocks = 6
        var rate: Double
        if fscod == 3 {
            rate = [24000.0, 22050, 16000, 0][bits.read(2)]
        } else {
            blocks = [1, 2, 3, 6][bits.read(2)]
            rate = [48000.0, 44100, 32000][fscod]
        }
        let acmod = bits.read(3)
        let lfe = bits.read(1)
        let bsid = bits.read(5)
        guard rate > 0, bsid > 10 else { return nil }
        let samples = blocks * 256
        let dataRate = Int(Double(frameSize * 8) * rate / Double(samples) / 1000)
        // data_rate(13) num_ind_sub(3) | fscod(2) bsid(5) reserved(1) | asvc(1) bsmod(3) acmod(3) lfeon(1) | reserved(3) num_dep_sub(4) reserved(1)
        var body = Data([UInt8((dataRate >> 5) & 0xFF), UInt8((dataRate & 0x1F) << 3)])
        body.append(UInt8((fscod == 3 ? 3 : fscod) << 6 | bsid << 1))
        body.append(UInt8(acmod << 1 | lfe))
        body.append(0)
        return AC3Header(sampleRate: rate, channels: acmodChannels[acmod] + lfe, cookie: box("dec3", body),
                         samplesPerFrame: samples)
    }

    static let acmodChannels = [2, 1, 2, 3, 3, 4, 4, 5]

    // MARK: FLAC

    struct FLACInfo: Equatable {
        var sampleRate: Double
        var channels: Int
        var bitsPerSample: Int
        var maxBlockSize: Int
        /// The `dfLa` box (Core Audio's cookie for FLAC in MP4).
        var cookie: Data
    }

    /// From Matroska's FLAC codec private data ("fLaC" then metadata blocks). Only the
    /// stream info block is kept.
    static func flac(_ codecPrivate: Data) -> FLACInfo? {
        var b = [UInt8](codecPrivate)
        if b.count >= 4, b[0...3] == [0x66, 0x4C, 0x61, 0x43] { b.removeFirst(4) }
        guard b.count >= 38, b[0] & 0x7F == 0 else { return nil }
        let length = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length == 34 else { return nil }
        let info = Array(b[4..<38])
        let maxBlock = Int(info[2]) << 8 | Int(info[3])
        let rate = Int(info[10]) << 12 | Int(info[11]) << 4 | Int(info[12]) >> 4
        let channels = Int((info[12] >> 1) & 0x07) + 1
        let bits = Int((info[12] & 0x01) << 4 | info[13] >> 4) + 1
        let block = Data([0x80, 0, 0, 34] + info) // last-metadata-block flag set
        return FLACInfo(sampleRate: Double(rate), channels: channels, bitsPerSample: bits, maxBlockSize: maxBlock,
                        cookie: box("dfLa", Data([0, 0, 0, 0]) + block))
    }

    // MARK: Opus

    /// Channels and pre-skip from an "OpusHead" packet.
    static func opusHead(_ data: Data) -> (channels: Int, preSkip: Int)? {
        let b = [UInt8](data)
        guard b.count >= 19, String(decoding: b[0..<8], as: UTF8.self) == "OpusHead" else { return nil }
        return (Int(b[9]), Int(b[10]) | Int(b[11]) << 8)
    }

    // MARK: VP9

    /// A `vpcC` (VP codec configuration, version 1) for a VP9 stream, from its first frame
    /// and the track's colour tags.
    static func vpcC(firstFrame: Data, primaries: Int?, transfer: Int?, matrix: Int?, fullRange: Bool) -> Data {
        let first = firstFrame.first ?? 0x80
        // frame_marker(2) profile_low_bit profile_high_bit …
        let profile = Int((first >> 5) & 1) | Int((first >> 4) & 1) << 1
        let bitDepth = profile >= 2 ? 10 : 8
        let chroma = profile == 1 || profile == 3 ? 3 : 1 // 4:4:4, else 4:2:0
        let packed = UInt8(bitDepth << 4 | chroma << 1 | (fullRange ? 1 : 0))
        let body = Data([1, 0, 0, 0, UInt8(profile), 0, packed,
                         UInt8(primaries ?? 2), UInt8(transfer ?? 2), UInt8(matrix ?? 2), 0, 0])
        return body
    }
}

/// Reads bits most significant first.
struct BitReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func read(_ count: Int) -> Int {
        var value = 0
        for _ in 0..<count {
            let byte = position / 8 < bytes.count ? bytes[position / 8] : 0
            value = value << 1 | Int((byte >> (7 - UInt8(position % 8))) & 1)
            position += 1
        }
        return value
    }
}
