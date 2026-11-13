import CoreGraphics
import Foundation

/// A turn and/or mirror applied to a picture, as the user sees it. Stored as "mirror left to
/// right first (if `mirrored`), then turn clockwise by `quarterTurns` × 90°", which covers all
/// eight combinations of turns and flips exactly once.
public struct PictureTransform: Codable, Equatable, Hashable, Sendable {
    /// Clockwise quarter turns, 0...3.
    public var quarterTurns: Int
    public var mirrored: Bool

    public init(quarterTurns: Int = 0, mirrored: Bool = false) {
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.mirrored = mirrored
    }

    public static let identity = PictureTransform()
    public var isIdentity: Bool { quarterTurns == 0 && !mirrored }
    /// Width and height trade places.
    public var swapsSides: Bool { quarterTurns % 2 == 1 }

    public func rotatedRight() -> Self { Self(quarterTurns: quarterTurns + 1, mirrored: mirrored) }
    public func rotatedLeft() -> Self { Self(quarterTurns: quarterTurns + 3, mirrored: mirrored) }
    /// Mirror left to right after this transform: H·R(r)·Hᵐ = R(−r)·Hᵐ⁺¹.
    public func flippedHorizontally() -> Self { Self(quarterTurns: -quarterTurns, mirrored: !mirrored) }
    /// Upside down after this transform: V = R(180)·H, so V·R(r)·Hᵐ = R(180−r)·Hᵐ⁺¹.
    public func flippedVertically() -> Self { Self(quarterTurns: 2 - quarterTurns, mirrored: !mirrored) }

    /// `self` applied after `other`.
    public func after(_ other: PictureTransform) -> PictureTransform {
        mirrored
            ? Self(quarterTurns: quarterTurns - other.quarterTurns, mirrored: !other.mirrored)
            : Self(quarterTurns: quarterTurns + other.quarterTurns, mirrored: other.mirrored)
    }

    /// EXIF / CGImagePropertyOrientation (1...8) as a transform of the stored pixels.
    public init(exifOrientation: Int) {
        switch exifOrientation {
        case 2: self.init(quarterTurns: 0, mirrored: true)
        case 3: self.init(quarterTurns: 2)
        case 4: self.init(quarterTurns: 2, mirrored: true)
        case 5: self.init(quarterTurns: 3, mirrored: true)
        case 6: self.init(quarterTurns: 1)
        case 7: self.init(quarterTurns: 1, mirrored: true)
        case 8: self.init(quarterTurns: 3)
        default: self.init()
        }
    }

    public var exifOrientation: Int {
        switch (quarterTurns, mirrored) {
        case (0, false): 1
        case (0, true): 2
        case (2, false): 3
        case (2, true): 4
        case (3, true): 5
        case (1, false): 6
        case (1, true): 7
        default: 8
        }
    }

    /// The affine transform that maps a `width`×`height` picture (y down, as in video
    /// compositions and track matrices) to its transformed self, placed at the origin.
    public func affine(width: Double, height: Double) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        if mirrored { t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)) }
        let turn: CGAffineTransform = switch quarterTurns {
        case 1: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        case 2: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 3: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        default: .identity
        }
        return t.concatenating(turn)
    }

    /// "Turned right", "Mirrored", "Turned around and mirrored".
    public var title: String {
        let turn: String? = switch quarterTurns {
        case 1: "Turned right"
        case 2: "Turned upside down"
        case 3: "Turned left"
        default: nil
        }
        switch (turn, mirrored) {
        case (nil, false): return "Not turned"
        case (nil, true): return "Mirrored"
        case (let turn?, false): return turn
        case (let turn?, true): return turn + " and mirrored"
        }
    }
}

/// The part of a video or sound file to keep, in seconds from its start.
public struct TrimRange: Codable, Equatable, Hashable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = max(0, start)
        self.end = max(self.start, end)
    }

    public var duration: Double { end - start }

    /// Whether it keeps (almost) the whole of a file this long: then it's no trim at all.
    public func isWhole(of duration: Double) -> Bool {
        start < 0.01 && end > duration - 0.01
    }

    /// "0:12.5 – 1:03.0".
    public var title: String { "\(Durations.precise(start)) – \(Durations.precise(end))" }
}

/// The part of a picture to keep, as fractions of the picture as the file shows it (after
/// its own rotation, before any turn chosen in Convert), from the top left. Stored as
/// fractions so it means the same thing at any size.
public struct CropRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        let x = min(max(0, x), 1), y = min(max(0, y), 1)
        self.x = x
        self.y = y
        self.width = min(max(0.001, width), 1 - x)
        self.height = min(max(0.001, height), 1 - y)
    }

    public static let whole = CropRect(x: 0, y: 0, width: 1, height: 1)

    /// Keeps (almost) everything: then it's no crop at all.
    public var isWhole: Bool { x < 0.0005 && y < 0.0005 && width > 0.999 && height > 0.999 }

    /// The rectangle in pixels of a `width`×`height` picture. With `even`, edges land on even
    /// pixels (video encoders want even sizes) and the size is at least 2×2.
    public func pixels(width: Int, height: Int, even: Bool = false) -> CGRect {
        func snap(_ value: Double) -> Double { even ? 2 * (value / 2).rounded(.down) : value.rounded() }
        let left = snap(x * Double(width)), top = snap(y * Double(height))
        let right = min(Double(width), snap((x + self.width) * Double(width) + (even ? 1 : 0)))
        let bottom = min(Double(height), snap((y + self.height) * Double(height) + (even ? 1 : 0)))
        let minimum: Double = even ? 2 : 1
        return CGRect(x: left, y: top, width: max(minimum, right - left), height: max(minimum, bottom - top))
    }

    /// Where this rectangle is once the picture is turned.
    public func turned(by turn: PictureTransform) -> CropRect {
        let rect = CGRect(x: x, y: y, width: width, height: height).applying(turn.affine(width: 1, height: 1)).standardized
        return CropRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// The inverse of `turned(by:)`: a rectangle drawn on the turned picture, in the picture
    /// as the file shows it.
    public func unturned(by turn: PictureTransform) -> CropRect {
        let rect = CGRect(x: x, y: y, width: width, height: height)
            .applying(turn.affine(width: 1, height: 1).inverted()).standardized
        return CropRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// The largest rectangle of this shape (width ÷ height, in pixels) centred in a picture.
    public static func centered(aspect: Double, width: Int, height: Int) -> CropRect {
        guard aspect > 0, width > 0, height > 0 else { return .whole }
        let pictureAspect = Double(width) / Double(height)
        if aspect > pictureAspect {
            let h = pictureAspect / aspect
            return CropRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
        let w = aspect / pictureAspect
        return CropRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
    }
}

/// What a video's subtitles do.
public enum SubtitleChoice: Codable, Equatable, Hashable, Sendable {
    /// Carry every subtitle track over, as tracks viewers can turn on (the default; where the
    /// format can hold them: MP4 and MOV).
    case keep
    /// Draw this track (0-based among the file's subtitle tracks) into the picture.
    case burn(Int)
    /// Leave them out.
    case none
}

/// Which sound a video keeps.
public enum SoundChoice: Codable, Equatable, Hashable, Sendable {
    /// Every enabled track, mixed into one (the default).
    case all
    /// Just this audio track (0-based among the file's audio tracks).
    case track(Int)
    /// No sound at all.
    case none
}

/// What one file gets on top of the window's settings: its own format, a trim, a turn or
/// flip, and its sound track. Kept per file by the app; empty means "use the defaults".
public struct FileOptions: Codable, Equatable, Hashable, Sendable {
    public var video: VideoTarget?
    public var audio: AudioTarget?
    public var image: ImageTarget?
    public var trim: TrimRange?
    public var transform: PictureTransform = .identity
    public var sound: SoundChoice = .all
    /// Keep only part of the picture.
    public var crop: CropRect?
    public var subtitles: SubtitleChoice = .keep
    /// Mix surround sound down to stereo (it's kept as 5.1 or 7.1 otherwise).
    public var stereo = false

    public init(video: VideoTarget? = nil, audio: AudioTarget? = nil, image: ImageTarget? = nil,
                trim: TrimRange? = nil, transform: PictureTransform = .identity, sound: SoundChoice = .all,
                crop: CropRect? = nil, subtitles: SubtitleChoice = .keep, stereo: Bool = false) {
        self.video = video
        self.audio = audio
        self.image = image
        self.trim = trim
        self.transform = transform
        self.sound = sound
        self.crop = crop
        self.subtitles = subtitles
        self.stereo = stereo
    }

    public var isEmpty: Bool { self == FileOptions() }

    /// Whether this file has its own format for files of `kind`.
    public func hasOwnFormat(for kind: MediaKind) -> Bool {
        switch kind {
        case .video: video != nil
        case .audio: audio != nil
        case .image: image != nil
        }
    }

    /// Everything but the format, which `ConvertSettings.applying` handles.
    var editSignature: String {
        var parts: [String] = []
        if let trim { parts.append("trim:\(trim.start)-\(trim.end)") }
        if !transform.isIdentity { parts.append("turn:\(transform.quarterTurns)\(transform.mirrored ? "m" : "")") }
        switch sound {
        case .all: break
        case .track(let i): parts.append("sound:\(i)")
        case .none: parts.append("sound:none")
        }
        if let crop { parts.append("crop:\(crop.x),\(crop.y),\(crop.width),\(crop.height)") }
        switch subtitles {
        case .keep: break
        case .burn(let i): parts.append("subtitles:burn\(i)")
        case .none: parts.append("subtitles:none")
        }
        if stereo { parts.append("stereo") }
        return parts.joined(separator: ",")
    }
}

extension ConvertSettings {
    /// These settings with a file's own formats in place of the defaults.
    public func applying(_ options: FileOptions) -> ConvertSettings {
        var s = self
        if let video = options.video { s.video = video }
        if let audio = options.audio { s.audio = audio }
        if let image = options.image { s.image = image }
        return s
    }

    /// The signature (see `signature(for:)`) of a file with its own options.
    public func signature(for kind: MediaKind, options: FileOptions) -> String {
        let base = applying(options).signature(for: kind)
        let edits = options.editSignature
        return edits.isEmpty ? base : base + "|" + edits
    }
}

extension Durations {
    /// "0:12.5", "1:03:07.0": tenths, for trim points.
    public static func precise(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        let whole = tenths / 10, fraction = tenths % 10
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        return h > 0 ? String(format: "%d:%02d:%02d.%d", h, m, s, fraction) : String(format: "%d:%02d.%d", m, s, fraction)
    }
}
