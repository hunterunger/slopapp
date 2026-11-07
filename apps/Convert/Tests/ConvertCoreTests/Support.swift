import AVFoundation
import ConvertFixtures
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ConvertCore

import Testing

/// GitHub's macOS runners are virtual Macs with no media engine: video (and HEIC) encodes
/// fall back to software or aren't there at all, and the suite crawled past CI's 45-minute
/// limit. With `CI` set, tests that really encode video or HEIC are skipped; everything
/// else (planning, options, presets, audio, PNG/JPEG images) still runs. Locally they all run.
enum TestEnvironment {
    static var isCI: Bool {
        guard let value = ProcessInfo.processInfo.environment["CI"]?.lowercased() else { return false }
        return !["", "0", "false", "no"].contains(value)
    }
}

extension Trait where Self == ConditionTrait {
    /// For tests that encode video or HEIC for real (see `TestEnvironment`).
    static var needsMediaEngine: Self {
        .enabled(if: !TestEnvironment.isCI, "Encodes video/HEIC: skipped on CI runners, which have no hardware encoder")
    }
}

/// A fresh folder under /tmp/convert-test/unit for one test.
func makeTempFolder() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/convert-test/unit/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Makes a fixture in a fresh folder and returns its URL.
func fixture(_ name: String, _ make: (URL) throws -> Void) throws -> URL {
    let url = try makeTempFolder().appendingPathComponent(name)
    try make(url)
    return url
}

func videoFixture(_ name: String = "clip.mov", configure: (inout FixtureMaker.VideoSpec) -> Void = { _ in }) throws -> URL {
    var spec = FixtureMaker.VideoSpec()
    configure(&spec)
    return try fixture(name) { try FixtureMaker.video($0, spec) }
}

func sha(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

/// Everything in a folder except hidden files.
func visibleFiles(_ folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
}

func converter(_ configure: (inout ConvertSettings) -> Void = { _ in }) -> Converter {
    var settings = ConvertSettings()
    configure(&settings)
    return Converter(settings: settings)
}

func report(_ conversion: Conversion) throws -> ConversionReport {
    guard case .converted(let report) = conversion else {
        throw TestFailure("expected a converted file, got \(conversion)")
    }
    return report
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// What an output file really contains, read back with AVFoundation.
struct PlayedBack {
    var duration: Double
    var videoCodec: String?
    var audioCodec: String?
    var displaySize: CGSize?
    var audioTracks: Int
    var bitsPerSample: Int
    var playable: Bool
}

func playBack(_ url: URL) async throws -> PlayedBack {
    let asset = AVURLAsset(url: url)
    let (tracks, duration, playable) = try await asset.load(.tracks, .duration, .isPlayable)
    var result = PlayedBack(duration: duration.seconds, audioTracks: 0, bitsPerSample: 0, playable: playable)
    for track in tracks {
        let formats = try await track.load(.formatDescriptions)
        guard let format = formats.first else { continue }
        let code = Codecs.fourCC(CMFormatDescriptionGetMediaSubType(format))
        if track.mediaType == .video {
            result.videoCodec = code
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let shown = size.applying(transform)
            result.displaySize = CGSize(width: abs(shown.width), height: abs(shown.height))
        } else if track.mediaType == .audio {
            result.audioTracks += 1
            result.audioCodec = code
            result.bitsPerSample = Int(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mBitsPerChannel ?? 0)
        }
    }
    return result
}

/// The average color of a video frame at `time`, upright. Used to check that a converted
/// picture looks like the original (not black, not shifted, not washed out).
func averageColor(ofVideo url: URL, at time: Double) async throws -> (r: Double, g: Double, b: Double) {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
    return averageColor(image)
}

func averageColor(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
    let w = 32, h = 32
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var r = 0.0, g = 0.0, b = 0.0
    for i in 0..<(w * h) {
        r += Double(data[i * 4]); g += Double(data[i * 4 + 1]); b += Double(data[i * 4 + 2])
    }
    let n = Double(w * h) * 255
    return (r / n, g / n, b / n)
}

func colorDistance(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
    max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
}

func imageProperties(_ url: URL) -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
}

func imageFrameCount(_ url: URL) -> Int {
    CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 0
}

func firstImage(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

func sampleInfo(_ kind: MediaKind = .video, configure: (inout MediaInfo) -> Void) -> MediaInfo {
    var info = MediaInfo(kind: kind)
    configure(&info)
    return info
}

/// A file store that delegates to the real one but can refuse to write.
struct FailingFileStore: FileStore {
    var real = SystemFileStore()
    var writable = true
    var failMove = false

    func size(of url: URL) -> Int64? { real.size(of: url) }
    func fileExists(_ url: URL) -> Bool { real.fileExists(url) }
    func isDirectory(_ url: URL) -> Bool { real.isDirectory(url) }
    func isWritableDirectory(_ url: URL) -> Bool { writable && real.isWritableDirectory(url) }
    func scratch(for fileName: String, near folder: URL) throws -> (url: URL, cleanup: @Sendable () -> Void) {
        try real.scratch(for: fileName, near: folder)
    }
    func moveExclusive(_ source: URL, to target: URL) throws {
        if failMove { throw ConvertError.diskFull(name: target.lastPathComponent) }
        try real.moveExclusive(source, to: target)
    }
    func replace(_ target: URL, with source: URL) throws { try real.replace(target, with: source) }
    func copyDates(from source: URL, to target: URL) { real.copyDates(from: source, to: target) }
}

/// The average color of part of an image, given in top-down fractions of its size.
func averageColor(_ image: CGImage, x: Double, y: Double, width: Double, height: Double) -> (r: Double, g: Double, b: Double) {
    let rect = CGRect(x: Double(image.width) * x, y: Double(image.height) * y,
                      width: Double(image.width) * width, height: Double(image.height) * height).integral
    return averageColor(image.cropping(to: rect)!)
}

/// A video frame, upright.
func videoFrame(_ url: URL, at time: Double) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
}

/// Moves nothing: records what it was asked to trash.
final class FakeTrasher: Trasher, @unchecked Sendable {
    private let lock = NSLock()
    private var _trashed: [URL] = []
    var trashed: [URL] { lock.withLock { _trashed } }
    func trash(_ url: URL) throws -> URL? {
        lock.withLock { _trashed.append(url) }
        return nil
    }
}
