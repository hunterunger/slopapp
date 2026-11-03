import CoreGraphics
import Foundation
import zlib

/// Straight-alpha RGBA8 pixels plus the color space they're in.
struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]
    let colorSpace: CGColorSpace

    /// Draws `image` into RGBA8 in its own RGB color space (sRGB for gray/indexed ones),
    /// then un-premultiplies.
    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        guard width > 0, height > 0 else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        colorSpace = space
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        buffer.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                let a = p[i + 3]
                if a == 0 {
                    p[i] = 0; p[i + 1] = 0; p[i + 2] = 0
                } else if a < 255 {
                    let a32 = UInt32(a)
                    p[i] = UInt8(min(255, (UInt32(p[i]) * 255 + a32 / 2) / a32))
                    p[i + 1] = UInt8(min(255, (UInt32(p[i + 1]) * 255 + a32 / 2) / a32))
                    p[i + 2] = UInt8(min(255, (UInt32(p[i + 2]) * 255 + a32 / 2) / a32))
                }
                i += 4
            }
        }
        pixels = buffer
    }
}

/// Reduces an image to a palette of at most `maxColors` colors (median cut, refined with
/// a couple of k-means passes, Floyd–Steinberg dithering). Images that already have few
/// enough colors keep them exactly.
enum PaletteQuantizer {
    struct Result {
        /// RGBA entries, ones with transparency first (so the tRNS chunk stays short).
        var palette: [SIMD4<UInt8>]
        var indices: [UInt8]
    }

    static func quantize(_ image: RGBAImage, maxColors: Int, dither: Bool = true) -> Result {
        let maxColors = min(256, max(2, maxColors))
        let counts = census(image)
        if counts.count <= maxColors, !counts.overflowed {
            return exact(image, colors: Array(counts.colors.keys))
        }
        // Flat colors that cover a lot of pixels (backgrounds, UI fills, text) go into the
        // palette exactly and are never dithered, so flat areas stay clean.
        let threshold = max(64, image.width * image.height / 500)
        let reserved = counts.colors.filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .prefix(maxColors / 4)
            .map(\.key)
        var palette = reserved.map { SIMD4<Float>(unpack($0)) }
        let reservedSet = Set(reserved)
        palette += medianCut(image, maxColors: maxColors - reserved.count, excluding: reservedSet, fixed: palette)
        var lookup: [UInt32: UInt8] = [:]
        for (i, c) in reserved.enumerated() { lookup[c] = UInt8(i) }
        return map(image, palette: palette, exact: lookup, dither: dither)
    }

    static func unpack(_ c: UInt32) -> SIMD4<UInt8> {
        withUnsafeBytes(of: c) { SIMD4($0[0], $0[1], $0[2], $0[3]) }
    }

    // MARK: Census

    private struct Census {
        var colors: [UInt32: Int] = [:]
        var overflowed = false
        var count: Int { colors.count }
    }

    /// Counts exact colors (up to 65,536 distinct; after that only known ones are counted).
    private static func census(_ image: RGBAImage) -> Census {
        var census = Census()
        let cap = 1 << 16
        image.pixels.withUnsafeBufferPointer { p in
            p.withMemoryRebound(to: UInt32.self) { px in
                var i = 0
                while i < px.count {
                    let c = px[i]
                    var run = 1
                    while i + run < px.count, px[i + run] == c { run += 1 }
                    if census.colors[c] != nil {
                        census.colors[c]! += run
                    } else if census.colors.count < cap {
                        census.colors[c] = run
                    } else {
                        census.overflowed = true
                    }
                    i += run
                }
            }
        }
        return census
    }

    private static func exact(_ image: RGBAImage, colors: [UInt32]) -> Result {
        var lookup: [UInt32: UInt8] = [:]
        for (i, c) in colors.enumerated() { lookup[c] = UInt8(i) }
        var indices = [UInt8](repeating: 0, count: image.width * image.height)
        image.pixels.withUnsafeBufferPointer { p in
            p.withMemoryRebound(to: UInt32.self) { px in
                var last: UInt32 = px.isEmpty ? 0 : px[0]
                var lastIndex = lookup[last] ?? 0
                for i in 0..<px.count {
                    if px[i] != last { last = px[i]; lastIndex = lookup[last] ?? 0 }
                    indices[i] = lastIndex
                }
            }
        }
        return reorderTransparentFirst(Result(palette: colors.map(unpack), indices: indices))
    }

    // MARK: Median cut

    private struct Bin {
        var color: SIMD4<Float>
        var count: Float
    }

    /// 5 bits each for RGB, 4 for alpha.
    private static func histogramKey(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Int {
        (Int(r >> 3) << 14) | (Int(g >> 3) << 9) | (Int(b >> 3) << 4) | Int(a >> 4)
    }

    /// Median cut over pixels not in `excluding`; returns `maxColors` new entries. The k-means
    /// refinement treats `fixed` entries as already taken.
    private static func medianCut(_ image: RGBAImage, maxColors: Int, excluding: Set<UInt32>,
                                  fixed: [SIMD4<Float>]) -> [SIMD4<Float>] {
        let size = 1 << 19
        var counts = [UInt32](repeating: 0, count: size)
        var sums = [SIMD4<Float>](repeating: .zero, count: size)
        image.pixels.withUnsafeBufferPointer { p in
            counts.withUnsafeMutableBufferPointer { counts in
                sums.withUnsafeMutableBufferPointer { sums in
                    var i = 0
                    var lastValue: UInt32 = 0, lastExcluded = false, hasLast = false
                    let raw = UnsafeRawPointer(p.baseAddress!)
                    while i < p.count {
                        if !excluding.isEmpty {
                            let value = raw.loadUnaligned(fromByteOffset: i, as: UInt32.self)
                            if !hasLast || value != lastValue {
                                lastValue = value; lastExcluded = excluding.contains(value); hasLast = true
                            }
                            if lastExcluded { i += 4; continue }
                        }
                        let key = histogramKey(p[i], p[i + 1], p[i + 2], p[i + 3])
                        counts[key] &+= 1
                        sums[key] += SIMD4(Float(p[i]), Float(p[i + 1]), Float(p[i + 2]), Float(p[i + 3]))
                        i += 4
                    }
                }
            }
        }
        var bins: [Bin] = []
        bins.reserveCapacity(8192)
        for key in 0..<size where counts[key] > 0 {
            let n = Float(counts[key])
            bins.append(Bin(color: sums[key] / n, count: n))
        }

        // Boxes are ranges of `bins`; split the one with the widest spread × population.
        struct Box { var range: Range<Int>; var score: Float; var axis: Int }
        func makeBox(_ range: Range<Int>) -> Box {
            var lo = SIMD4<Float>(repeating: 255), hi = SIMD4<Float>(repeating: 0), total: Float = 0
            for i in range {
                lo = pointwiseMin(lo, bins[i].color)
                hi = pointwiseMax(hi, bins[i].color)
                total += bins[i].count
            }
            let spread = (hi - lo) * weights
            var axis = 0
            for c in 1..<4 where spread[c] > spread[axis] { axis = c }
            let score = range.count > 1 ? spread[axis] * spread[axis] * total.squareRoot() : -1
            return Box(range: range, score: score, axis: axis)
        }
        var boxes = [makeBox(0..<bins.count)]
        while boxes.count < maxColors {
            guard let pick = boxes.indices.max(by: { boxes[$0].score < boxes[$1].score }),
                  boxes[pick].score > 0 else { break }
            let box = boxes[pick]
            let axis = box.axis
            bins[box.range].sort { $0.color[axis] < $1.color[axis] }
            let half = box.range.reduce(Float(0)) { $0 + bins[$1].count } / 2
            var running: Float = 0
            var cut = box.range.lowerBound + 1
            for i in box.range {
                running += bins[i].count
                if running >= half { cut = min(max(i + 1, box.range.lowerBound + 1), box.range.upperBound - 1); break }
            }
            boxes[pick] = makeBox(box.range.lowerBound..<cut)
            boxes.append(makeBox(cut..<box.range.upperBound))
        }
        var palette = boxes.map { box -> SIMD4<Float> in
            var sum = SIMD4<Float>.zero, total: Float = 0
            for i in box.range { sum += bins[i].color * bins[i].count; total += bins[i].count }
            return sum / max(total, 1)
        }

        // Two k-means passes over the histogram pull entries toward where pixels really are.
        for _ in 0..<2 {
            let all = fixed + palette
            var sum = [SIMD4<Float>](repeating: .zero, count: all.count)
            var total = [Float](repeating: 0, count: all.count)
            for bin in bins {
                let j = nearest(bin.color, in: all)
                sum[j] += bin.color * bin.count
                total[j] += bin.count
            }
            for j in palette.indices where total[fixed.count + j] > 0 {
                palette[j] = sum[fixed.count + j] / total[fixed.count + j]
            }
        }
        return palette
    }

    /// Perceptual-ish channel weights (green matters most; alpha edges matter).
    private static let weights = SIMD4<Float>(0.75, 1.0, 0.6, 0.9)

    private static func nearest(_ color: SIMD4<Float>, in palette: [SIMD4<Float>]) -> Int {
        var best = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (j, entry) in palette.enumerated() {
            let d = (entry - color) * weights
            let distance = (d * d).sum()
            if distance < bestDistance { bestDistance = distance; best = j }
        }
        return best
    }

    // MARK: Mapping

    private static func map(_ image: RGBAImage, palette floatPalette: [SIMD4<Float>],
                            exact: [UInt32: UInt8], dither: Bool) -> Result {
        let palette = floatPalette.map { c in
            SIMD4<UInt8>(clamping: SIMD4<Int32>((c).rounded(.toNearestOrAwayFromZero)))
        }
        let paletteF = palette.map { SIMD4<Float>($0) }
        let width = image.width, height = image.height
        var indices = [UInt8](repeating: 0, count: width * height)
        // Nearest-entry cache: 6 bits per RGB channel, 4 for alpha.
        var cache = [Int16](repeating: -1, count: 1 << 22)
        var errorThis = [SIMD4<Float>](repeating: .zero, count: width + 2)
        var errorNext = [SIMD4<Float>](repeating: .zero, count: width + 2)
        let strength: Float = dither ? 0.82 : 0

        image.pixels.withUnsafeBufferPointer { p in
            indices.withUnsafeMutableBufferPointer { out in
                cache.withUnsafeMutableBufferPointer { cache in
                    for y in 0..<height {
                        swap(&errorThis, &errorNext)
                        for x in 0..<(width + 2) { errorNext[x] = .zero }
                        let leftToRight = y % 2 == 0
                        var x = leftToRight ? 0 : width - 1
                        var lastValue: UInt32 = 0, lastExact: Int = -1, hasLast = false
                        let raw = UnsafeRawPointer(p.baseAddress!)
                        for _ in 0..<width {
                            let i = (y * width + x) * 4
                            if !exact.isEmpty {
                                let value = raw.loadUnaligned(fromByteOffset: i, as: UInt32.self)
                                if !hasLast || value != lastValue {
                                    lastValue = value; hasLast = true
                                    lastExact = exact[value].map(Int.init) ?? -1
                                }
                                if lastExact >= 0 {
                                    // Exact flat color: no dithering, and don't pass error on.
                                    out[y * width + x] = UInt8(lastExact)
                                    x += leftToRight ? 1 : -1
                                    continue
                                }
                            }
                            let original = SIMD4<Float>(Float(p[i]), Float(p[i + 1]), Float(p[i + 2]), Float(p[i + 3]))
                            var wanted = original
                            if strength > 0, original[3] > 0 {
                                wanted += errorThis[x + 1]
                                wanted = pointwiseMin(pointwiseMax(wanted, .zero), SIMD4(repeating: 255))
                                wanted[3] = original[3]
                            }
                            let r = Int(wanted[0]) >> 2, g = Int(wanted[1]) >> 2, b = Int(wanted[2]) >> 2, a = Int(wanted[3]) >> 4
                            let key = (r << 16) | (g << 10) | (b << 4) | a
                            var j = Int(cache[key])
                            if j < 0 {
                                j = nearest(wanted, in: paletteF)
                                cache[key] = Int16(j)
                            }
                            out[y * width + x] = UInt8(j)
                            if strength > 0, original[3] > 0 {
                                var err = (wanted - paletteF[j]) * strength
                                err[3] = 0
                                let dir = leftToRight ? 1 : -1
                                errorThis[x + 1 + dir] += err * (7.0 / 16)
                                errorNext[x + 1 - dir] += err * (3.0 / 16)
                                errorNext[x + 1] += err * (5.0 / 16)
                                errorNext[x + 1 + dir] += err * (1.0 / 16)
                            }
                            x += leftToRight ? 1 : -1
                        }
                    }
                }
            }
        }
        return reorderTransparentFirst(Result(palette: palette, indices: indices))
    }

    /// Drops unused entries and puts the transparent ones first.
    private static func reorderTransparentFirst(_ result: Result) -> Result {
        var used = [Bool](repeating: false, count: result.palette.count)
        for i in result.indices { used[Int(i)] = true }
        let order = result.palette.indices
            .filter { used[$0] }
            .sorted { (result.palette[$0][3] < 255 ? 0 : 1, $0) < (result.palette[$1][3] < 255 ? 0 : 1, $1) }
        var remap = [UInt8](repeating: 0, count: result.palette.count)
        for (new, old) in order.enumerated() { remap[old] = UInt8(new) }
        return Result(palette: order.map { result.palette[$0] }, indices: result.indices.map { remap[Int($0)] })
    }
}

/// Writes an indexed-color PNG (color type 3) with zlib at maximum compression.
enum PalettePNGWriter {
    static func encode(_ result: PaletteQuantizer.Result, width: Int, height: Int, colorSpace: CGColorSpace) -> Data? {
        let count = result.palette.count
        let depth = count <= 2 ? 1 : count <= 4 ? 2 : count <= 16 ? 4 : 8
        let rowBytes = (width * depth + 7) / 8
        var raw = [UInt8](repeating: 0, count: (rowBytes + 1) * height)
        result.indices.withUnsafeBufferPointer { idx in
            raw.withUnsafeMutableBufferPointer { raw in
                let perByte = 8 / depth
                for y in 0..<height {
                    let row = y * (rowBytes + 1)
                    raw[row] = 0 // filter: none (best for palettes)
                    if depth == 8 {
                        for x in 0..<width { raw[row + 1 + x] = idx[y * width + x] }
                    } else {
                        for x in 0..<width {
                            let shift = (perByte - 1 - x % perByte) * depth
                            raw[row + 1 + x / perByte] |= idx[y * width + x] << UInt8(shift)
                        }
                    }
                }
            }
        }
        guard let compressed = zlibCompress(raw) else { return nil }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header.append(contentsOf: [UInt8(depth), 3, 0, 0, 0])
        png.appendChunk("IHDR", header)
        if colorSpace.name == CGColorSpace.sRGB {
            png.appendChunk("sRGB", Data([0]))
        } else if let icc = colorSpace.copyICCData() as Data?, let packed = zlibCompress([UInt8](icc)) {
            png.appendChunk("iCCP", Data("ICC Profile".utf8) + Data([0, 0]) + packed)
        }
        png.appendChunk("PLTE", Data(result.palette.flatMap { [$0[0], $0[1], $0[2]] }))
        let alphas = result.palette.prefix { $0[3] < 255 }.map { $0[3] }
        if !alphas.isEmpty { png.appendChunk("tRNS", Data(alphas)) }
        png.appendChunk("IDAT", compressed)
        png.appendChunk("IEND", Data())
        return png
    }

    static func zlibCompress(_ bytes: [UInt8]) -> Data? {
        var length = compressBound(uLong(bytes.count))
        var out = [UInt8](repeating: 0, count: Int(length))
        let status = compress2(&out, &length, bytes, uLong(bytes.count), Z_BEST_COMPRESSION)
        guard status == Z_OK else { return nil }
        return Data(out.prefix(Int(length)))
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendChunk(_ type: String, _ body: Data) {
        appendBigEndian(UInt32(body.count))
        let typeBytes = Data(type.utf8)
        append(typeBytes)
        append(body)
        let crcInput = [UInt8](typeBytes + body)
        appendBigEndian(UInt32(crc32(0, crcInput, uInt(crcInput.count))))
    }
}
