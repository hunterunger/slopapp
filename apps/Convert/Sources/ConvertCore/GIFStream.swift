import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes an animated GIF one frame at a time, so memory stays flat however long the clip.
///
/// ImageIO's own animated-GIF writer keeps every frame until it finalizes (a minute of
/// 640×360 video peaked at over 1 GB). Instead, each frame is encoded on its own by
/// ImageIO (palette + LZW, the hard part) and its image block is copied into our file
/// with its own colour table and timing.
final class GIFStreamWriter {
    enum Failure: Error { case encode, parse, write }

    private let handle: FileHandle
    private var buffer = Data()
    private let width: Int
    private let height: Int
    /// The previous frame's pixels (RGBA), to only store what changed.
    private var previous: [UInt8]?

    init(url: URL, width: Int, height: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = FileHandle(forWritingAtPath: url.path)
        else { throw Failure.write }
        self.handle = handle
        self.width = width
        self.height = height
        buffer.append(contentsOf: Array("GIF89a".utf8))
        buffer.append(le16(width))
        buffer.append(le16(height))
        buffer.append(contentsOf: [0x00, 0x00, 0x00]) // no global colour table
        // Loop forever (NETSCAPE2.0 application extension, loop count 0).
        buffer.append(contentsOf: [0x21, 0xFF, 0x0B])
        buffer.append(contentsOf: Array("NETSCAPE2.0".utf8))
        buffer.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
    }

    /// Adds a frame shown for `delay` seconds (rounded to 1/100 s, GIF's unit). Only the
    /// rectangle that changed since the last frame is stored, so mostly-still clips (screen
    /// recordings) stay small.
    func add(_ image: CGImage, delay: Double) throws {
        var region = CGRect(x: 0, y: 0, width: width, height: height)
        var part = image
        if image.width == width, image.height == height, let pixels = Self.pixels(of: image) {
            if var shown = previous {
                // Compare with what's on screen (not the last source frame), so slow fades
                // still get drawn once they add up. Inside the changed rectangle, pixels
                // that didn't change are transparent: long runs of them cost almost nothing.
                region = Self.changedRegion(shown, pixels, width: width, height: height)
                    ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                part = Self.delta(region, from: pixels, over: &shown, width: width) ?? image.cropping(to: region) ?? image
                previous = shown
            } else {
                previous = pixels
            }
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil)
        else { throw Failure.encode }
        CGImageDestinationAddImage(destination, part, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encode }
        let frame = try Self.parse(data as Data)

        // Graphics control extension: timing, and transparency if the frame has any.
        let centiseconds = max(2, Int((delay * 100).rounded()))
        let packed: UInt8 = (1 << 2) | (frame.transparentIndex == nil ? 0 : 1)
        buffer.append(contentsOf: [0x21, 0xF9, 0x04, packed])
        buffer.append(le16(centiseconds))
        buffer.append(contentsOf: [frame.transparentIndex ?? 0, 0x00])
        // Image descriptor with the frame's own (local) colour table.
        buffer.append(0x2C)
        buffer.append(le16(Int(region.minX)))
        buffer.append(le16(Int(region.minY)))
        buffer.append(frame.descriptor.suffix(4))
        buffer.append(0x80 | frame.colorTableSizeBits | (frame.interlaced ? 0x40 : 0))
        buffer.append(frame.colorTable)
        buffer.append(frame.imageData)
        try flushIfNeeded()
    }

    func finish() throws {
        buffer.append(0x3B)
        try flushIfNeeded(force: true)
        try handle.close()
    }

    func abandon() {
        try? handle.close()
    }

    private func flushIfNeeded(force: Bool = false) throws {
        guard force || buffer.count > 1 << 20 else { return }
        do {
            try handle.write(contentsOf: buffer)
        } catch {
            throw Failure.write
        }
        buffer.removeAll(keepingCapacity: true)
    }

    private func le16(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    // MARK: Changed regions

    static func pixels(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// The changed rectangle as an image where unchanged pixels are transparent, updating
    /// `shown` to what the viewer sees after this frame.
    static func delta(_ region: CGRect, from source: [UInt8], over shown: inout [UInt8], width: Int,
                      tolerance: Int = changeTolerance) -> CGImage? {
        let rx = Int(region.minX), ry = Int(region.minY), rw = Int(region.width), rh = Int(region.height)
        var out = [UInt8](repeating: 0, count: rw * rh * 4)
        for y in 0..<rh {
            for x in 0..<rw {
                let i = ((ry + y) * width + rx + x) * 4
                let o = (y * rw + x) * 4
                let changed = abs(Int(source[i]) - Int(shown[i])) > tolerance
                    || abs(Int(source[i + 1]) - Int(shown[i + 1])) > tolerance
                    || abs(Int(source[i + 2]) - Int(shown[i + 2])) > tolerance
                    || source[i + 3] != shown[i + 3]
                guard changed else { continue }
                for c in 0..<4 {
                    out[o + c] = source[i + c]
                    shown[i + c] = source[i + c]
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: rw, height: rh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rw * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Differences smaller than this (out of 255 per channel) are video noise, not change.
    static let changeTolerance = 8

    /// The smallest rectangle (top-left origin) holding every pixel that differs by more
    /// than a hair (video noise), or nil when nothing changed.
    static func changedRegion(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, tolerance: Int = changeTolerance) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for y in 0..<height {
                    let row = y * width * 4
                    var x = 0
                    while x < width {
                        let i = row + x * 4
                        if abs(Int(pa[i]) - Int(pb[i])) > tolerance || abs(Int(pa[i + 1]) - Int(pb[i + 1])) > tolerance
                            || abs(Int(pa[i + 2]) - Int(pb[i + 2])) > tolerance || pa[i + 3] != pb[i + 3] {
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                        x += 1
                    }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Parsing a one-frame GIF

    struct Frame {
        /// left, top, width, height (8 bytes, little-endian) from the image descriptor.
        var descriptor: Data
        var colorTable: Data
        /// log2(entries) - 1, as GIF stores it.
        var colorTableSizeBits: UInt8
        var interlaced: Bool
        var transparentIndex: UInt8?
        /// LZW minimum code size byte plus the data sub-blocks and their terminator.
        var imageData: Data
    }

    static func parse(_ data: Data) throws -> Frame {
        let bytes = [UInt8](data)
        guard bytes.count > 13, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 else { throw Failure.parse }
        var i = 6
        let screenPacked = bytes[i + 4]
        i += 7
        var globalTable = Data()
        var globalBits: UInt8 = 0
        if screenPacked & 0x80 != 0 {
            globalBits = screenPacked & 0x07
            let size = 3 * (1 << (Int(globalBits) + 1))
            guard i + size <= bytes.count else { throw Failure.parse }
            globalTable = Data(bytes[i..<(i + size)])
            i += size
        }
        var transparent: UInt8?
        func skipSubBlocks() throws {
            while i < bytes.count {
                let length = Int(bytes[i])
                i += 1
                if length == 0 { return }
                i += length
            }
            throw Failure.parse
        }
        while i < bytes.count {
            switch bytes[i] {
            case 0x21:
                guard i + 2 < bytes.count else { throw Failure.parse }
                if bytes[i + 1] == 0xF9, i + 7 < bytes.count, bytes[i + 3] & 0x01 != 0 {
                    transparent = bytes[i + 6]
                }
                i += 2
                try skipSubBlocks()
            case 0x2C:
                guard i + 10 <= bytes.count else { throw Failure.parse }
                let descriptor = Data(bytes[(i + 1)..<(i + 9)])
                let packed = bytes[i + 9]
                i += 10
                var table = globalTable
                var bits = globalBits
                if packed & 0x80 != 0 {
                    bits = packed & 0x07
                    let size = 3 * (1 << (Int(bits) + 1))
                    guard i + size <= bytes.count else { throw Failure.parse }
                    table = Data(bytes[i..<(i + size)])
                    i += size
                }
                guard !table.isEmpty, i < bytes.count else { throw Failure.parse }
                let start = i
                i += 1 // LZW minimum code size
                try skipSubBlocks()
                return Frame(descriptor: descriptor, colorTable: table, colorTableSizeBits: bits,
                             interlaced: packed & 0x40 != 0, transparentIndex: transparent,
                             imageData: Data(bytes[start..<i]))
            default:
                throw Failure.parse
            }
        }
        throw Failure.parse
    }
}
