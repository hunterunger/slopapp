import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SquishCore

/// A fresh folder under /tmp/squish-test/unit for one test.
func makeTempFolder() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/squish-test/unit/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A noisy, photo-like test image (noise makes encoders work, like a real photo).
func makeImage(width: Int, height: Int, alpha: Bool = false, flat: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var seed: UInt32 = 12345
    for y in 0..<height {
        for x in 0..<width {
            let i = y * ctx.bytesPerRow + x * 4
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = flat ? 0 : Int(seed >> 27)
            let a = alpha ? UInt8(x < width / 2 ? 255 : 128) : 255
            let r = UInt8(min(255, (x * 255 / max(1, width - 1) + noise)))
            let g = UInt8(min(255, (y * 255 / max(1, height - 1) + noise)))
            let b = UInt8(flat ? 90 : min(255, ((x + y) * 127 / max(1, width + height - 2) + noise)))
            // premultiplied
            data[i] = UInt8(Int(r) * Int(a) / 255)
            data[i + 1] = UInt8(Int(g) * Int(a) / 255)
            data[i + 2] = UInt8(Int(b) * Int(a) / 255)
            data[i + 3] = a
        }
    }
    return ctx.makeImage()!
}

/// An image with exactly these colors in vertical stripes.
func makeStripes(_ colors: [(UInt8, UInt8, UInt8, UInt8)], width: Int = 40, height: Int = 10) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let c = colors[x * colors.count / width]
            let i = y * width * 4 + x * 4
            data[i] = UInt8(Int(c.0) * Int(c.3) / 255)
            data[i + 1] = UInt8(Int(c.1) * Int(c.3) / 255)
            data[i + 2] = UInt8(Int(c.2) * Int(c.3) / 255)
            data[i + 3] = c.3
        }
    }
    return ctx.makeImage()!
}

@discardableResult
func writeImage(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.98,
                properties: [CFString: Any] = [:]) -> URL {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var props = properties
    props[kCGImageDestinationLossyCompressionQuality] = quality
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))
    return url
}

func imageProperties(_ data: Data) -> [CFString: Any] {
    let src = CGImageSourceCreateWithData(data as CFData, nil)!
    return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
}

func decode(_ data: Data) -> CGImage? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

func fileSize(_ url: URL) -> Int64 {
    // Not URL.resourceValues: those are cached per URL object, and a file rewritten in
    // place would keep reporting its old size.
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
}

/// Writes go to memory; reads of real input files pass through to disk.
final class FakeFileStore: FileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [String: Data] = [:]
    private var _trashed: [URL] = []
    var failTrash = false
    var folders: Set<String> = []

    var written: [String: Data] { lock.withLock { _written } }
    var trashed: [URL] { lock.withLock { _trashed } }

    func seed(_ url: URL, _ data: Data = Data([1])) {
        lock.withLock { _written[url.path] = data }
    }

    func size(of url: URL) throws -> Int64 {
        if let data = lock.withLock({ _written[url.path] }) { return Int64(data.count) }
        return try SystemFileStore().size(of: url)
    }

    func fileExists(_ url: URL) -> Bool {
        lock.withLock { _written[url.path] != nil } || (FileManager.default.fileExists(atPath: url.path) && !trashed.contains(url))
    }

    func isDirectory(_ url: URL) -> Bool {
        lock.withLock { folders.contains(url.path) } || SystemFileStore().isDirectory(url)
    }

    func createFolder(_ url: URL) throws {
        lock.withLock { _ = folders.insert(url.path) }
    }

    func create(_ data: Data, at url: URL) throws {
        try lock.withLock {
            if _written[url.path] != nil || (FileManager.default.fileExists(atPath: url.path) && !_trashed.contains(url)) {
                throw OutputError.exists
            }
            _written[url.path] = data
        }
    }

    func overwrite(_ data: Data, at url: URL) throws {
        lock.withLock { _written[url.path] = data }
    }

    func move(_ source: URL, to target: URL) throws {
        try lock.withLock {
            if _written[target.path] != nil || (FileManager.default.fileExists(atPath: target.path) && !_trashed.contains(target)) {
                throw OutputError.exists
            }
            _written[target.path] = _written.removeValue(forKey: source.path)
        }
    }

    func remove(_ url: URL) {
        lock.withLock { _ = _written.removeValue(forKey: url.path) }
    }

    func trash(_ url: URL) throws -> URL {
        if failTrash { throw OutputError.cantTrash(url.lastPathComponent) }
        lock.withLock {
            _trashed.append(url)
            if let data = _written.removeValue(forKey: url.path) { _written["/Trash/" + url.lastPathComponent] = data }
        }
        return URL(fileURLWithPath: "/Trash/" + url.lastPathComponent)
    }

    private var _datesCopied: [URL] = []
    var datesCopied: [URL] { lock.withLock { _datesCopied } }
    func copyDates(from source: URL, to target: URL) {
        lock.withLock { _datesCopied.append(target) }
    }

    func sha256(of url: URL) throws -> String {
        if let data = lock.withLock({ _written[url.path] }) {
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return try SystemFileStore().sha256(of: url)
    }

    func markAsOutput(_ url: URL) {}
    func isMarkedAsOutput(_ url: URL) -> Bool { false }
}

func md5(_ url: URL) throws -> String {
    Insecure.MD5.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

struct Missing: Error {}

func decodeRGBA(_ data: Data?) throws -> RGBAImage {
    guard let data, let image = decode(data), let rgba = RGBAImage(image) else { throw Missing() }
    return rgba
}

func decoded(_ data: Data) throws -> CGImage {
    guard let image = decode(data) else { throw Missing() }
    return image
}
