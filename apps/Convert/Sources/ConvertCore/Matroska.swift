import Foundation

// Matroska (MKV, MKA, WebM) has no reader in macOS. This is a small demuxer for it: it reads
// the track headers and the frames, and `MatroskaBridge` hands them to AVFoundation in an
// MP4 (or MOV), whose decoders read everything we pass on (H.264, HEVC, AV1, VP9, AAC, AC-3,
// E-AC-3, MP3, Opus, FLAC, PCM, text subtitles). Pure byte parsing, behind `ByteSource` so
// tests can feed it bytes.

/// Random-access bytes: a file, or memory in tests.
public protocol ByteSource: AnyObject {
    var length: UInt64 { get }
    /// Up to `count` bytes from `offset` (fewer only at the end).
    func read(at offset: UInt64, count: Int) throws -> Data
}

/// Reads a file through a 1 MB window, so walking it front to back costs one read per MB.
public final class FileByteSource: ByteSource {
    private let handle: FileHandle
    public let length: UInt64
    private var window = Data()
    private var windowStart: UInt64 = 0
    private static let windowSize = 1 << 20

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        length = try handle.seekToEnd()
    }

    deinit { try? handle.close() }

    public func read(at offset: UInt64, count: Int) throws -> Data {
        guard count > 0, offset < length else { return Data() }
        let end = min(length, offset + UInt64(count))
        if offset >= windowStart, end <= windowStart + UInt64(window.count) {
            let lower = window.startIndex + Int(offset - windowStart)
            return window.subdata(in: lower..<(lower + Int(end - offset)))
        }
        if count >= Self.windowSize {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: Int(end - offset)) ?? Data()
        }
        try handle.seek(toOffset: offset)
        window = try handle.read(upToCount: Self.windowSize) ?? Data()
        windowStart = offset
        let available = min(Int(end - offset), window.count)
        return window.prefix(available)
    }
}

/// Bytes in memory (tests).
public final class DataByteSource: ByteSource {
    private let data: Data
    public init(_ data: Data) { self.data = data }
    public var length: UInt64 { UInt64(data.count) }
    public func read(at offset: UInt64, count: Int) throws -> Data {
        guard offset < UInt64(data.count) else { return Data() }
        let lower = data.startIndex + Int(offset)
        return data.subdata(in: lower..<min(data.endIndex, lower + count))
    }
}

public enum MatroskaError: Error, Equatable {
    case notMatroska
    case truncated
    case encrypted
}

/// Element IDs we use (with their marker bits, as written).
enum EBMLID {
    static let ebml: UInt32 = 0x1A45_DFA3
    static let docType: UInt32 = 0x4282
    static let segment: UInt32 = 0x1853_8067
    static let seekHead: UInt32 = 0x114D_9B74
    static let seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB
    static let seekPosition: UInt32 = 0x53AC
    static let info: UInt32 = 0x1549_A966
    static let timestampScale: UInt32 = 0x2AD7B1
    static let duration: UInt32 = 0x4489
    static let title: UInt32 = 0x7BA9
    static let tracks: UInt32 = 0x1654_AE6B
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackType: UInt32 = 0x83
    static let flagEnabled: UInt32 = 0xB9
    static let flagDefault: UInt32 = 0x88
    static let flagForced: UInt32 = 0x55AA
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let language: UInt32 = 0x22B59C
    static let languageBCP47: UInt32 = 0x22B59D
    static let name: UInt32 = 0x536E
    static let defaultDuration: UInt32 = 0x23E383
    static let contentEncodings: UInt32 = 0x6D80
    static let contentEncoding: UInt32 = 0x6240
    static let contentCompression: UInt32 = 0x5034
    static let contentCompAlgo: UInt32 = 0x4254
    static let contentCompSettings: UInt32 = 0x4255
    static let contentEncryption: UInt32 = 0x5035
    static let video: UInt32 = 0xE0
    static let pixelWidth: UInt32 = 0xB0
    static let pixelHeight: UInt32 = 0xBA
    static let displayWidth: UInt32 = 0x54B0
    static let displayHeight: UInt32 = 0x54BA
    static let colour: UInt32 = 0x55B0
    static let matrix: UInt32 = 0x55B1
    static let range: UInt32 = 0x55B9
    static let transfer: UInt32 = 0x55BA
    static let primaries: UInt32 = 0x55BB
    static let audio: UInt32 = 0xE1
    static let samplingFrequency: UInt32 = 0xB5
    static let outputSamplingFrequency: UInt32 = 0x78B5
    static let channels: UInt32 = 0x9F
    static let bitDepth: UInt32 = 0x6264
    static let cluster: UInt32 = 0x1F43_B675
    static let timestamp: UInt32 = 0xE7
    static let simpleBlock: UInt32 = 0xA3
    static let blockGroup: UInt32 = 0xA0
    static let block: UInt32 = 0xA1
    static let blockDuration: UInt32 = 0x9B
    static let referenceBlock: UInt32 = 0xFB
    static let cues: UInt32 = 0x1C53_BB6B
    static let chapters: UInt32 = 0x1043_A770
    static let tags: UInt32 = 0x1254_C367
    static let attachments: UInt32 = 0x1941_A469

    /// Children of a Segment: an unknown-size cluster ends where one of these starts.
    static let topLevel: Set<UInt32> = [seekHead, info, tracks, cluster, cues, chapters, tags, attachments]
}

/// One element's header.
struct EBMLElement {
    var id: UInt32
    /// Where its data starts.
    var dataStart: UInt64
    /// nil: unknown size (live streams and some recorders write clusters this way).
    var size: UInt64?
    var end: UInt64? { size.map { dataStart + $0 } }
}

/// EBML primitives over a `ByteSource`.
struct EBMLReader {
    let source: ByteSource

    /// The element header at `offset`, or nil at the end of the data.
    func element(at offset: UInt64) throws -> EBMLElement? {
        let head = try source.read(at: offset, count: 12)
        guard !head.isEmpty else { return nil }
        let bytes = [UInt8](head)
        guard let (id, idLength) = Self.vint(bytes, at: 0, keepMarker: true), idLength <= 4,
              let (size, sizeLength) = Self.vint(bytes, at: idLength, keepMarker: false)
        else { throw MatroskaError.truncated }
        let unknown = size == (UInt64(1) << (7 * UInt64(sizeLength))) - 1
        return EBMLElement(id: UInt32(id), dataStart: offset + UInt64(idLength + sizeLength), size: unknown ? nil : size)
    }

    /// A variable-length integer: (value, length in bytes).
    static func vint(_ bytes: [UInt8], at index: Int, keepMarker: Bool) -> (UInt64, Int)? {
        guard index < bytes.count, bytes[index] != 0 else { return nil }
        let first = bytes[index]
        let length = first.leadingZeroBitCount + 1
        guard index + length <= bytes.count else { return nil }
        var value = UInt64(keepMarker ? first : first & (0xFF >> UInt8(length)))
        for i in 1..<length { value = value << 8 | UInt64(bytes[index + i]) }
        return (value, length)
    }

    func data(_ element: EBMLElement) throws -> Data {
        guard let size = element.size, size < 1 << 30 else { throw MatroskaError.truncated }
        let data = try source.read(at: element.dataStart, count: Int(size))
        guard data.count == Int(size) else { throw MatroskaError.truncated }
        return data
    }

    func uint(_ element: EBMLElement) throws -> UInt64 {
        try data(element).reduce(0) { $0 << 8 | UInt64($1) }
    }

    func float(_ element: EBMLElement) throws -> Double {
        let d = try data(element)
        let bits = d.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        switch d.count {
        case 4: return Double(Float(bitPattern: UInt32(bits)))
        case 8: return Double(bitPattern: bits)
        default: return 0
        }
    }

    func string(_ element: EBMLElement) throws -> String {
        let d = try data(element)
        let trimmed = d.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }

    /// Calls `body` for each child of `parent` (which must have a known size).
    func children(of parent: EBMLElement, _ body: (EBMLElement) throws -> Void) throws {
        guard let end = parent.end else { return }
        var offset = parent.dataStart
        while offset < end, let child = try element(at: offset) {
            try body(child)
            guard let next = child.end else { return }
            offset = next
        }
    }
}

/// What a Matroska file holds, from its headers.
public struct MatroskaInfo: Equatable, Sendable {
    public enum TrackKind: Int, Sendable { case video = 1, audio = 2, subtitle = 17, other = 0 }

    public struct Track: Equatable, Sendable {
        public var number: UInt64 = 0
        public var kind: TrackKind = .other
        public var codecID = ""
        public var codecPrivate: Data?
        public var isEnabled = true
        public var isDefault = true
        public var isForced = false
        /// ISO 639-2 ("eng") or BCP 47 ("en-US"); nil when undetermined.
        public var language: String?
        public var name: String?
        /// Nanoseconds per frame, when constant.
        public var defaultDuration: UInt64?
        // Video
        public var pixelWidth = 0
        public var pixelHeight = 0
        public var displayWidth = 0
        public var displayHeight = 0
        public var primaries: Int?
        public var transfer: Int?
        public var matrix: Int?
        public var fullRange = false
        // Audio
        public var sampleRate: Double = 0
        public var channels = 1
        public var bitDepth = 0
        /// Header-stripping compression: these bytes start every frame.
        public var strippedHeader: Data?
        /// zlib-compressed frames.
        public var zlib = false

        public init() {}
    }

    public var docType = "matroska"
    /// Nanoseconds per timestamp tick.
    public var timestampScale: UInt64 = 1_000_000
    public var duration: Double = 0
    public var title: String?
    public var tracks: [Track] = []
    /// Where the frames start.
    var firstCluster: UInt64 = 0
    var segmentEnd: UInt64?

    public init() {}

    public var isWebM: Bool { docType == "webm" }
}

/// One frame of one track, as stored.
struct MatroskaFrame {
    var track: UInt64
    /// Presentation time in nanoseconds.
    var time: Int64
    /// Nanoseconds, when the file says (block groups, or laced frames).
    var duration: Int64?
    var isKey: Bool
    var data: Data
}

/// Reads headers and frames from a Matroska file.
final class MatroskaReader {
    let reader: EBMLReader
    private(set) var info = MatroskaInfo()
    private var tracksByNumber: [UInt64: MatroskaInfo.Track] = [:]

    init(source: ByteSource) throws {
        reader = EBMLReader(source: source)
        try readHeaders()
    }

    convenience init(url: URL) throws {
        try self.init(source: try FileByteSource(url: url))
    }

    // MARK: Headers

    private func readHeaders() throws {
        guard let header = try reader.element(at: 0), header.id == EBMLID.ebml else { throw MatroskaError.notMatroska }
        try reader.children(of: header) { child in
            if child.id == EBMLID.docType { info.docType = try reader.string(child) }
        }
        guard info.docType == "matroska" || info.docType == "webm", let headerEnd = header.end,
              let segment = try reader.element(at: headerEnd), segment.id == EBMLID.segment
        else { throw MatroskaError.notMatroska }
        info.segmentEnd = segment.end
        let segmentStart = segment.dataStart
        var offset = segmentStart
        var tracksAt: UInt64?
        var infoAt: UInt64?
        var sawTracks = false
        // Walk the Segment's children up to the first cluster.
        while let element = try reader.element(at: offset) {
            switch element.id {
            case EBMLID.info:
                try readInfo(element)
                infoAt = nil
            case EBMLID.tracks:
                try readTracks(element)
                sawTracks = true
            case EBMLID.seekHead:
                try reader.children(of: element) { seek in
                    guard seek.id == EBMLID.seek else { return }
                    var id: UInt64 = 0, position: UInt64 = 0
                    try reader.children(of: seek) { field in
                        if field.id == EBMLID.seekID { id = try reader.uint(field) }
                        if field.id == EBMLID.seekPosition { position = try reader.uint(field) }
                    }
                    if id == UInt64(EBMLID.tracks) { tracksAt = segmentStart + position }
                    if id == UInt64(EBMLID.info), info.duration == 0 { infoAt = segmentStart + position }
                }
            case EBMLID.cluster:
                info.firstCluster = offset
            default:
                break
            }
            if element.id == EBMLID.cluster { break }
            guard let next = element.end, next > offset else { break }
            offset = next
        }
        // Tracks (or Info) written after the frames: follow the seek head.
        if !sawTracks, let tracksAt, let element = try reader.element(at: tracksAt), element.id == EBMLID.tracks {
            try readTracks(element)
            sawTracks = true
        }
        if let infoAt, let element = try reader.element(at: infoAt), element.id == EBMLID.info {
            try readInfo(element)
        }
        guard sawTracks, info.firstCluster > 0 || !info.tracks.isEmpty else { throw MatroskaError.notMatroska }
        if info.firstCluster == 0 { info.firstCluster = offset }
    }

    private func readInfo(_ element: EBMLElement) throws {
        var rawDuration = 0.0
        try reader.children(of: element) { child in
            switch child.id {
            case EBMLID.timestampScale: info.timestampScale = max(1, try reader.uint(child))
            case EBMLID.duration: rawDuration = try reader.float(child)
            case EBMLID.title: info.title = try reader.string(child)
            default: break
            }
        }
        if rawDuration > 0 { info.duration = rawDuration * Double(info.timestampScale) / 1e9 }
    }

    private func readTracks(_ element: EBMLElement) throws {
        try reader.children(of: element) { entry in
            guard entry.id == EBMLID.trackEntry else { return }
            var track = MatroskaInfo.Track()
            var bcp47: String?
            try reader.children(of: entry) { field in
                switch field.id {
                case EBMLID.trackNumber: track.number = try reader.uint(field)
                case EBMLID.trackType:
                    track.kind = MatroskaInfo.TrackKind(rawValue: Int(try reader.uint(field))) ?? .other
                case EBMLID.flagEnabled: track.isEnabled = try reader.uint(field) != 0
                case EBMLID.flagDefault: track.isDefault = try reader.uint(field) != 0
                case EBMLID.flagForced: track.isForced = try reader.uint(field) != 0
                case EBMLID.codecID: track.codecID = try reader.string(field)
                case EBMLID.codecPrivate: track.codecPrivate = try reader.data(field)
                case EBMLID.language: track.language = try reader.string(field)
                case EBMLID.languageBCP47: bcp47 = try reader.string(field)
                case EBMLID.name: track.name = try reader.string(field)
                case EBMLID.defaultDuration: track.defaultDuration = try reader.uint(field)
                case EBMLID.video: try readVideo(field, into: &track)
                case EBMLID.audio: try readAudio(field, into: &track)
                case EBMLID.contentEncodings: try readEncodings(field, into: &track)
                default: break
                }
            }
            // The default language is English; "und" means not set.
            if let bcp47, !bcp47.isEmpty { track.language = bcp47 }
            if track.language == nil { track.language = "eng" }
            if track.language == "und" { track.language = nil }
            if track.displayWidth == 0 { track.displayWidth = track.pixelWidth }
            if track.displayHeight == 0 { track.displayHeight = track.pixelHeight }
            info.tracks.append(track)
            tracksByNumber[track.number] = track
        }
    }

    private func readVideo(_ element: EBMLElement, into track: inout MatroskaInfo.Track) throws {
        try reader.children(of: element) { field in
            switch field.id {
            case EBMLID.pixelWidth: track.pixelWidth = Int(try reader.uint(field))
            case EBMLID.pixelHeight: track.pixelHeight = Int(try reader.uint(field))
            case EBMLID.displayWidth: track.displayWidth = Int(try reader.uint(field))
            case EBMLID.displayHeight: track.displayHeight = Int(try reader.uint(field))
            case EBMLID.colour:
                try reader.children(of: field) { c in
                    switch c.id {
                    case EBMLID.primaries: track.primaries = Int(try reader.uint(c))
                    case EBMLID.transfer: track.transfer = Int(try reader.uint(c))
                    case EBMLID.matrix: track.matrix = Int(try reader.uint(c))
                    case EBMLID.range: track.fullRange = try reader.uint(c) == 2
                    default: break
                    }
                }
            default: break
            }
        }
    }

    private func readAudio(_ element: EBMLElement, into track: inout MatroskaInfo.Track) throws {
        var output: Double = 0
        try reader.children(of: element) { field in
            switch field.id {
            case EBMLID.samplingFrequency: track.sampleRate = try reader.float(field)
            case EBMLID.outputSamplingFrequency: output = try reader.float(field)
            case EBMLID.channels: track.channels = max(1, Int(try reader.uint(field)))
            case EBMLID.bitDepth: track.bitDepth = Int(try reader.uint(field))
            default: break
            }
        }
        // HE-AAC: the stored rate is the core's, the output twice that.
        if output > 0 { track.sampleRate = output }
        if track.sampleRate == 0 { track.sampleRate = 8000 }
    }

    private func readEncodings(_ element: EBMLElement, into track: inout MatroskaInfo.Track) throws {
        try reader.children(of: element) { encoding in
            guard encoding.id == EBMLID.contentEncoding else { return }
            try reader.children(of: encoding) { part in
                if part.id == EBMLID.contentEncryption { throw MatroskaError.encrypted }
                guard part.id == EBMLID.contentCompression else { return }
                var algorithm: UInt64 = 0
                var settings: Data?
                try reader.children(of: part) { field in
                    if field.id == EBMLID.contentCompAlgo { algorithm = try reader.uint(field) }
                    if field.id == EBMLID.contentCompSettings { settings = try reader.data(field) }
                }
                switch algorithm {
                case 3: track.strippedHeader = settings
                case 0: track.zlib = true
                default: throw MatroskaError.encrypted // bzlib / lzo1x: no one writes these any more
                }
            }
        }
    }

    // MARK: Frames

    /// Walks every frame in file order. `body` returns false to stop. Frames from tracks not
    /// in `tracks` are skipped without being read.
    func forEachFrame(tracks wanted: Set<UInt64>, _ body: (MatroskaFrame) throws -> Bool) throws {
        var offset = info.firstCluster
        let end = info.segmentEnd ?? reader.source.length
        while offset < end, let element = try reader.element(at: offset) {
            if element.id == EBMLID.cluster {
                let (next, keepGoing) = try readCluster(element, wanted: wanted, body)
                guard keepGoing else { return }
                offset = next
            } else {
                guard let next = element.end, next > offset else { return }
                offset = next
            }
        }
    }

    /// Returns where the next element starts and whether to go on.
    private func readCluster(_ cluster: EBMLElement, wanted: Set<UInt64>,
                             _ body: (MatroskaFrame) throws -> Bool) throws -> (UInt64, Bool) {
        let limit = cluster.end ?? reader.source.length
        var offset = cluster.dataStart
        var clusterTime: Int64 = 0
        while offset < limit, let child = try reader.element(at: offset) {
            // An unknown-size cluster ends where the next top-level element starts.
            if cluster.size == nil, EBMLID.topLevel.contains(child.id) { return (offset, true) }
            guard let childEnd = child.end else { return (limit, false) }
            switch child.id {
            case EBMLID.timestamp:
                clusterTime = Int64(try reader.uint(child))
            case EBMLID.simpleBlock:
                for frame in try block(child, clusterTime: clusterTime, wanted: wanted, isSimple: true, duration: nil, reference: false) {
                    guard try body(frame) else { return (childEnd, false) }
                }
            case EBMLID.blockGroup:
                var blockElement: EBMLElement?
                var duration: UInt64?
                var hasReference = false
                try reader.children(of: child) { field in
                    switch field.id {
                    case EBMLID.block: blockElement = field
                    case EBMLID.blockDuration: duration = try reader.uint(field)
                    case EBMLID.referenceBlock: hasReference = true
                    default: break
                    }
                }
                if let blockElement {
                    for frame in try block(blockElement, clusterTime: clusterTime, wanted: wanted, isSimple: false,
                                           duration: duration, reference: hasReference) {
                        guard try body(frame) else { return (childEnd, false) }
                    }
                }
            default:
                break
            }
            offset = childEnd
        }
        return (limit, true)
    }

    private func block(_ element: EBMLElement, clusterTime: Int64, wanted: Set<UInt64>, isSimple: Bool,
                       duration: UInt64?, reference: Bool) throws -> [MatroskaFrame] {
        // Peek at the track number before reading the whole block.
        let head = [UInt8](try reader.source.read(at: element.dataStart, count: 12))
        guard let (number, numberLength) = EBMLReader.vint(head, at: 0, keepMarker: false) else { throw MatroskaError.truncated }
        guard wanted.contains(number), let track = tracksByNumber[number] else { return [] }
        let bytes = [UInt8](try reader.data(element))
        guard bytes.count >= numberLength + 3 else { throw MatroskaError.truncated }
        let relative = Int16(bitPattern: UInt16(bytes[numberLength]) << 8 | UInt16(bytes[numberLength + 1]))
        let flags = bytes[numberLength + 2]
        let scale = Int64(info.timestampScale)
        let time = (clusterTime + Int64(relative)) * scale
        let isKey = isSimple ? flags & 0x80 != 0 : !reference
        let payloads = try Self.unlace(bytes, from: numberLength + 3, lacing: (flags >> 1) & 0x03)
        let blockDuration = duration.map { Int64($0) * scale }
        let each: Int64? = track.defaultDuration.map(Int64.init) ?? blockDuration.map { $0 / Int64(max(1, payloads.count)) }
        return try payloads.enumerated().map { index, payload in
            MatroskaFrame(track: number, time: time + Int64(index) * (each ?? 0),
                          duration: payloads.count > 1 ? each : (blockDuration ?? track.defaultDuration.map(Int64.init)),
                          isKey: isKey, data: try decode(payload, track: track))
        }
    }

    /// Splits a block into its frames (Xiph, EBML or fixed-size lacing).
    static func unlace(_ bytes: [UInt8], from start: Int, lacing: UInt8) throws -> [Data] {
        guard lacing != 0 else { return [Data(bytes[start...])] }
        guard start < bytes.count else { throw MatroskaError.truncated }
        let count = Int(bytes[start]) + 1
        var index = start + 1
        var sizes: [Int] = []
        switch lacing {
        case 1: // Xiph
            for _ in 0..<(count - 1) {
                var size = 0
                while true {
                    guard index < bytes.count else { throw MatroskaError.truncated }
                    let b = Int(bytes[index]); index += 1
                    size += b
                    if b != 255 { break }
                }
                sizes.append(size)
            }
        case 3: // EBML: the first size, then signed differences
            guard let (first, length) = EBMLReader.vint(bytes, at: index, keepMarker: false) else { throw MatroskaError.truncated }
            index += length
            sizes.append(Int(first))
            for _ in 1..<max(1, count - 1) where count > 2 {
                guard let (raw, length) = EBMLReader.vint(bytes, at: index, keepMarker: false) else { throw MatroskaError.truncated }
                index += length
                let bias = (Int64(1) << (7 * Int64(length) - 1)) - 1
                sizes.append(sizes[sizes.count - 1] + Int(Int64(raw) - bias))
            }
        default: // fixed
            let total = bytes.count - index
            guard total % count == 0 else { throw MatroskaError.truncated }
            sizes = Array(repeating: total / count, count: count - 1)
        }
        let used = sizes.reduce(0, +)
        guard used <= bytes.count - index, sizes.allSatisfy({ $0 >= 0 }) else { throw MatroskaError.truncated }
        sizes.append(bytes.count - index - used)
        var frames: [Data] = []
        for size in sizes {
            frames.append(Data(bytes[index..<(index + size)]))
            index += size
        }
        return frames
    }

    private func decode(_ payload: Data, track: MatroskaInfo.Track) throws -> Data {
        var data = payload
        if track.zlib { data = try Inflate.zlib(data) }
        if let header = track.strippedHeader { data = header + data }
        return data
    }
}

/// zlib streams (a few files compress their subtitle or header data).
enum Inflate {
    static func zlib(_ data: Data) throws -> Data {
        // A zlib stream is a 2-byte header, raw DEFLATE (what Foundation calls "zlib"), then
        // a checksum, which the decoder ignores.
        guard data.count > 6, let output = try? (Data(data.dropFirst(2)) as NSData).decompressed(using: .zlib)
        else { throw MatroskaError.truncated }
        return output as Data
    }
}
