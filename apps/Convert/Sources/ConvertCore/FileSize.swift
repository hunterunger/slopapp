import Foundation

/// "Under 25 MB": a size each file should fit in. Megabytes are Finder's (1,000,000 bytes),
/// which is also under the same number of mebibytes, so it fits either way a site counts.
public struct FileSizeLimit: Codable, Equatable, Hashable, Sendable {
    public var megabytes: Double

    public init(megabytes: Double) {
        self.megabytes = max(0.1, megabytes)
    }

    public var bytes: Int64 { Int64(megabytes * 1_000_000) }

    /// "Under 25 MB", "Under 2.5 MB".
    public var title: String { "Under \(Self.number(megabytes)) MB" }

    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The sizes the menus offer: chat apps, email, then bigger uploads.
    public static let choices: [FileSizeLimit] = [10, 25, 50, 100, 250].map { FileSizeLimit(megabytes: $0) }

    /// Who each size is for, for the menu's second line.
    public var detail: String? {
        switch megabytes {
        case 10: "Free chat app uploads"
        case 25: "Email attachments"
        case 50: "Larger chat uploads"
        default: nil
        }
    }
}

/// Bit rates that make a file fit in a size. Pure, so tested.
public enum SizeBudget {
    /// Aim a little under: containers add a few percent and encoders overshoot a little.
    static let margin = 0.94

    public struct Video: Equatable, Sendable {
        /// Picture bit rate, bits per second.
        public var videoBitRate: Int
        /// AAC bit rate, or nil when there's no sound.
        public var audioBitRate: Int?
        /// A smaller frame, when the size leaves too few bits for the full one to look right.
        public var box: (long: Int, short: Int)?
        /// Even the smallest frame will look rough at this size.
        public var isTight: Bool

        public static func == (a: Video, b: Video) -> Bool {
            a.videoBitRate == b.videoBitRate && a.audioBitRate == b.audioBitRate && a.isTight == b.isTight
                && a.box?.long == b.box?.long && a.box?.short == b.box?.short
        }
    }

    /// Fewer bits per pixel than this and H.264/HEVC start to smear.
    static let minimumBitsPerPixel = 0.04
    /// Frames to step down to, largest first.
    static let boxes: [(long: Int, short: Int)] = [(3840, 2160), (2560, 1440), (1920, 1080), (1280, 720), (854, 480), (640, 360)]

    public static func video(_ limit: FileSizeLimit, duration: Double, width: Int, height: Int, frameRate: Double,
                             audioChannels: Int?, quality: Quality, sourceVideoBitRate: Double = 0,
                             codecEfficiency: Double = 1) -> Video {
        let seconds = max(0.5, duration)
        let total = Double(limit.bytes) * 8 * margin / seconds
        var audio: Int?
        if let channels = audioChannels {
            let wanted = Double(QualityTable.aacBitRate(quality, channels: channels))
            let floor = Double(minimumAAC(channels: channels))
            // Sound gets up to an eighth of the budget, never less than it needs to be clear.
            audio = snapAAC(max(floor, min(wanted, total * 0.125)))
        }
        var videoRate = max(50_000, total - Double(audio ?? 0))
        if sourceVideoBitRate > 0 { videoRate = min(videoRate, sourceVideoBitRate) }
        let fps = frameRate > 0 ? min(frameRate, 60) : 30
        let needed = minimumBitsPerPixel / codecEfficiency
        func bpp(_ w: Int, _ h: Int) -> Double { videoRate / (Double(w * h) * fps) }
        var box: (long: Int, short: Int)?
        var tight = false
        if width > 0, height > 0, bpp(width, height) < needed {
            let long = max(width, height), short = min(width, height)
            let candidates = boxes.filter { $0.long < long || $0.short < short }
            box = candidates.first { candidate in
                let (w, h) = Planner.fit(width, height, in: candidate)
                return bpp(w, h) >= needed
            } ?? candidates.last
            let (w, h) = box.map { Planner.fit(width, height, in: $0) } ?? (width, height)
            tight = bpp(w, h) < needed / 2
        }
        return Video(videoBitRate: Int(videoRate.rounded()), audioBitRate: audio, box: box, isTight: tight)
    }

    /// An AAC bit rate that fits sound of this length in the size, never above Best's.
    public static func audio(_ limit: FileSizeLimit, duration: Double, channels: Int) -> Int {
        let total = Double(limit.bytes) * 8 * margin / max(0.5, duration)
        let best = Double(QualityTable.aacBitRate(.best, channels: channels))
        return snapAAC(max(Double(minimumAAC(channels: channels)), min(best, total)))
    }

    /// AAC encoders take a fixed set of bit rates: the largest standard one at or under `rate`.
    static func snapAAC(_ rate: Double) -> Int {
        let steps = [32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 192, 224, 256, 288, 320, 384, 448, 512, 576, 640]
        let kbps = steps.last { Double($0 * 1000) <= rate + 1 } ?? steps[0]
        return kbps * 1000
    }

    /// The lowest AAC rate that still sounds acceptable (and that the encoder takes).
    static func minimumAAC(channels: Int) -> Int {
        switch channels {
        case ...1: 32_000
        case 2: 64_000
        default: 160_000
        }
    }

    /// Whether the sound alone (at its floor) already needs more than the size allows.
    public static func soundAloneTooBig(_ limit: FileSizeLimit, duration: Double, channels: Int) -> Bool {
        Double(minimumAAC(channels: channels)) * duration / 8 > Double(limit.bytes)
    }

    /// The next bit rate to try after a file came out `actual` bytes for a `limit`.
    static func retryRate(_ rate: Int, actual: Int64, limit: FileSizeLimit) -> Int {
        Int(Double(rate) * Double(limit.bytes) * margin / Double(max(1, actual)))
    }

    /// "25 MB is very little for 1:02:03, so it will look rough."
    static func tightNote(_ limit: FileSizeLimit, duration: Double) -> String {
        "\(FileSizeLimit.number(limit.megabytes)) MB is very little for \(Durations.string(duration)), so it will look rough. Trim it, or choose a bigger size."
    }
}

extension TranscodePlan {
    /// The same plan at a lower bit rate, after a first try came out `actual` bytes.
    func lowered(actual: Int64, limit: FileSizeLimit) -> TranscodePlan? {
        var plan = self
        if case .encode(var e)? = video, let rate = e.bitRate {
            e.bitRate = max(40_000, SizeBudget.retryRate(rate, actual: actual, limit: limit))
            plan.video = .encode(e)
            return plan
        }
        if video == nil, case .encode(var a) = audio, case .aac(let rate) = a.format {
            let lower = SizeBudget.snapAAC(Double(SizeBudget.retryRate(rate, actual: actual, limit: limit)))
            guard lower < rate else { return nil }
            a.format = .aac(bitRate: max(SizeBudget.minimumAAC(channels: a.channels), lower))
            plan.audio = .encode(a)
            return plan
        }
        return nil
    }
}
