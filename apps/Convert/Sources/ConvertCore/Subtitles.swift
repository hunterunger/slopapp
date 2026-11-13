import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import Foundation

/// One subtitle track of a video.
public struct SubtitleTrackInfo: Equatable, Sendable {
    /// Position among the file's subtitle tracks (0-based).
    public var index: Int
    /// "tx3g" (MP4 text), "wvtt" (WebVTT), "c608" (closed captions)…
    public var format: String
    /// "English", when the track says.
    public var language: String?
    public var name: String?
    public var isForced = false

    public init(index: Int, format: String, language: String? = nil, name: String? = nil, isForced: Bool = false) {
        self.index = index
        self.format = format
        self.language = language
        self.name = name
        self.isForced = isForced
    }

    /// Text we can read and draw into the picture.
    public var canBurn: Bool { format == "tx3g" || format == "wvtt" }

    /// "English", "English (Forced)", "Commentary · English", "Subtitles 2".
    public var title: String {
        var parts: [String] = []
        if let name, !name.isEmpty, name != language { parts.append(name) }
        if let language { parts.append(language) }
        var title = parts.isEmpty ? "Subtitles \(index + 1)" : parts.joined(separator: " · ")
        if format == "c608" { title += " (Closed Captions)" }
        if isForced { title += " (Forced)" }
        return title
    }
}

/// A line of subtitle text and when it shows, in seconds.
public struct SubtitleCue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Subtitle text without styling: Convert draws and stores plain lines.
enum SubtitleText {
    static func plain(_ raw: String, format: MatroskaCodec.Text) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        switch format {
        case .ass:
            // Matroska's ASS lines: ReadOrder, Layer, Style, Name, MarginL, MarginR, MarginV, Effect, Text.
            let fields = text.split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
            if fields.count == 9 { text = String(fields[8]) }
            text = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
        case .srt, .webvtt:
            text = text.replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// MP4 text subtitles ("3GPP timed text"): what QuickTime, iPhone and Apple TV show.
enum Tx3g {
    static func formatDescription() -> CMFormatDescription {
        let white: [CFString: Any] = [kCMTextFormatDescriptionColor_Red: 255, kCMTextFormatDescriptionColor_Green: 255,
                                      kCMTextFormatDescriptionColor_Blue: 255, kCMTextFormatDescriptionColor_Alpha: 255]
        let clear: [CFString: Any] = [kCMTextFormatDescriptionColor_Red: 0, kCMTextFormatDescriptionColor_Green: 0,
                                      kCMTextFormatDescriptionColor_Blue: 0, kCMTextFormatDescriptionColor_Alpha: 0]
        let box: [CFString: Any] = [kCMTextFormatDescriptionRect_Top: 0, kCMTextFormatDescriptionRect_Left: 0,
                                    kCMTextFormatDescriptionRect_Bottom: 0, kCMTextFormatDescriptionRect_Right: 0]
        let style: [CFString: Any] = [
            kCMTextFormatDescriptionStyle_StartChar: 0, kCMTextFormatDescriptionStyle_EndChar: 0,
            kCMTextFormatDescriptionStyle_Font: 1, kCMTextFormatDescriptionStyle_FontFace: 0,
            kCMTextFormatDescriptionStyle_ForegroundColor: white, kCMTextFormatDescriptionStyle_FontSize: 18,
        ]
        let extensions: [CFString: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags: 0,
            kCMTextFormatDescriptionExtension_BackgroundColor: clear,
            kCMTextFormatDescriptionExtension_DefaultTextBox: box,
            kCMTextFormatDescriptionExtension_DefaultStyle: style,
            kCMTextFormatDescriptionExtension_FontTable: ["1": "Sans-Serif"],
            kCMTextFormatDescriptionExtension_HorizontalJustification: 1,
            kCMTextFormatDescriptionExtension_VerticalJustification: -1,
        ]
        var format: CMFormatDescription?
        CMFormatDescriptionCreate(allocator: nil, mediaType: kCMMediaType_Subtitle, mediaSubType: kCMTextFormatType_3GText,
                                  extensions: extensions as CFDictionary, formatDescriptionOut: &format)
        return format!
    }

    /// A sample showing `text` (empty for a gap) between two times in nanoseconds.
    static func sample(_ text: String, start: Int64, end: Int64, format: CMFormatDescription?) -> CMSampleBuffer? {
        let utf8 = Array(text.utf8.prefix(65_000))
        let payload = Data([UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8)
        let ns: Int32 = 1_000_000_000
        let timing = CMSampleTimingInfo(duration: CMTime(value: max(1, end - start), timescale: ns),
                                        presentationTimeStamp: CMTime(value: start, timescale: ns), decodeTimeStamp: .invalid)
        return SampleBuffers.make(payload, format: format, timing: timing, isKey: true)
    }

    /// The text of a tx3g sample (UTF-8, or UTF-16 with a byte-order mark).
    static func text(_ data: Data) -> String {
        let b = [UInt8](data)
        guard b.count >= 2 else { return "" }
        let length = min(Int(b[0]) << 8 | Int(b[1]), b.count - 2)
        let body = Data(b[2..<(2 + length)])
        if body.starts(with: [0xFE, 0xFF]) { return String(data: body, encoding: .utf16BigEndian).map { String($0.dropFirst()) } ?? "" }
        if body.starts(with: [0xFF, 0xFE]) { return String(data: body, encoding: .utf16LittleEndian).map { String($0.dropFirst()) } ?? "" }
        return String(decoding: body, as: UTF8.self)
    }
}

/// WebVTT in MP4 ("wvtt"): each sample holds boxes; a cue's text is in vttc ▸ payl.
enum WebVTTSample {
    static func text(_ data: Data) -> String {
        var lines: [String] = []
        walk([UInt8](data)) { type, body in
            if type == "vttc" {
                walk(body) { inner, payload in
                    if inner == "payl" { lines.append(SubtitleText.plain(String(decoding: payload, as: UTF8.self), format: .webvtt)) }
                }
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func walk(_ bytes: [UInt8], _ body: (String, [UInt8]) -> Void) {
        var index = 0
        while index + 8 <= bytes.count {
            let size = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard size >= 8, index + size <= bytes.count else { return }
            body(String(decoding: bytes[(index + 4)..<(index + 8)], as: UTF8.self), Array(bytes[(index + 8)..<(index + size)]))
            index += size
        }
    }
}

/// Reads the cues of one subtitle track, for drawing them into the picture.
enum SubtitleReader {
    static func cues(_ asset: AVAsset, trackIndex: Int) async throws -> [SubtitleCue] {
        let tracks = try await subtitleTracks(asset)
        guard tracks.indices.contains(trackIndex) else { return [] }
        let track = tracks[trackIndex]
        let format = try await track.load(.formatDescriptions).first.map { Codecs.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var cues: [SubtitleCue] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                              dataPointerOut: &pointer) == noErr, let pointer else { continue }
            let data = Data(bytes: pointer, count: length)
            let text = format == "wvtt" ? WebVTTSample.text(data) : Tx3g.text(data)
            let start = CMSampleBufferGetPresentationTimeStamp(sample)
            let duration = CMSampleBufferGetDuration(sample)
            guard !text.isEmpty, start.isNumeric else { continue }
            let end = duration.isNumeric ? start + duration : start + CMTime(seconds: 3, preferredTimescale: 600)
            cues.append(SubtitleCue(start: start.seconds, end: end.seconds, text: text))
        }
        return cues
    }

    /// The tracks counted as subtitles, in file order: text subtitles and closed captions.
    static func subtitleTracks(_ asset: AVAsset) async throws -> [AVAssetTrack] {
        try await asset.load(.tracks).filter { $0.mediaType == .subtitle || $0.mediaType == .closedCaption }
    }
}

/// Draws a subtitle line the way TVs do: white, outlined, centred near the bottom, sized to
/// the picture. Cached per cue, so each line is drawn once.
final class SubtitleOverlay: @unchecked Sendable {
    let cues: [SubtitleCue]
    private let lock = NSLock()
    private var cache: [Int: (image: CGImage, origin: CGPoint)] = [:]

    init(cues: [SubtitleCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    /// The cue showing at `time`, by index.
    func cueIndex(at time: Double) -> Int? {
        // Binary search for the last cue starting at or before `time`.
        var low = 0, high = cues.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard let found else { return nil }
        // Overlapping cues: the latest one that is still on.
        var index = found
        while index >= 0 {
            if cues[index].end > time { return index }
            if found - index > 8 { break }
            index -= 1
        }
        return nil
    }

    /// The picture of the cue at `time` and where its bottom-left corner goes (y up), for a
    /// frame this size.
    func image(at time: Double, width: Int, height: Int) -> (image: CGImage, origin: CGPoint)? {
        guard let index = cueIndex(at: time) else { return nil }
        let key = index &* 31 &+ width &* 7 &+ height
        if let cached = lock.withLock({ cache[key] }) { return cached }
        guard let drawn = Self.draw(cues[index].text, width: width, height: height) else { return nil }
        lock.withLock {
            if cache.count > 64 { cache.removeAll() }
            cache[key] = drawn
        }
        return drawn
    }

    static func draw(_ text: String, width: Int, height: Int) -> (image: CGImage, origin: CGPoint)? {
        let short = Double(min(width, height))
        let size = max(12, (short * 0.055).rounded())
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) ?? font
        let paragraph: CTParagraphStyle = {
            var alignment = CTTextAlignment.center
            return withUnsafePointer(to: &alignment) { pointer in
                var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
                return CTParagraphStyleCreate(&setting, 1)
            }
        }()
        let white = CGColor(gray: 1, alpha: 1)
        let ink = CGColor(gray: 0, alpha: 0.9)
        func attributed(stroke: Bool) -> CFAttributedString {
            var attributes: [CFString: Any] = [kCTFontAttributeName: bold, kCTParagraphStyleAttributeName: paragraph,
                                               kCTForegroundColorAttributeName: stroke ? ink : white]
            if stroke {
                attributes[kCTStrokeWidthAttributeName] = 18.0 // percent of the font size: a thick outline
                attributes[kCTStrokeColorAttributeName] = ink
            }
            return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        }
        let maxWidth = Double(width) * 0.9
        let setter = CTFramesetterCreateWithAttributedString(attributed(stroke: false))
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let pad = size * 0.25
        let boxWidth = Int(ceil(maxWidth + 2 * pad))
        let boxHeight = Int(ceil(fit.height + 2 * pad))
        guard boxWidth > 0, boxHeight > 0, boxHeight < height,
              let context = CGContext(data: nil, width: boxWidth, height: boxHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let path = CGPath(rect: CGRect(x: pad, y: pad, width: maxWidth, height: fit.height + 1), transform: nil)
        for stroke in [true, false] {
            let s = CTFramesetterCreateWithAttributedString(attributed(stroke: stroke))
            if stroke { context.setShadow(offset: .zero, blur: size * 0.15, color: ink) } else { context.setShadow(offset: .zero, blur: 0) }
            CTFrameDraw(CTFramesetterCreateFrame(s, CFRange(location: 0, length: 0), path, nil), context)
        }
        guard let image = context.makeImage() else { return nil }
        // Inside the TV-safe area: 8% up from the bottom.
        let origin = CGPoint(x: (Double(width) - Double(boxWidth)) / 2, y: Double(height) * 0.08 - pad)
        return (image, origin)
    }
}
