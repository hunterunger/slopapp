import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bounds how much memory files being compressed at the same time may use, on top of the
/// queue's file count limit. A JPEG costs a few MB to re-encode; Apple's AVIF encoder needs
/// ~50 bytes per pixel (≈400 MB for an 8 MP photo), so AVIFs and big PDFs run one at a time
/// while JPEGs still run eight at once. One file always runs, however big.
public actor MemoryBudget {
    public static let shared = MemoryBudget(limit: 256 << 20)

    public let limit: Int
    private var used = 0
    private var waiting: [(cost: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init(limit: Int) {
        self.limit = limit
    }

    public var inUse: Int { used }

    /// Waits until `cost` bytes fit (first come, first served). Costs above the limit
    /// count as the whole budget, so such a file runs alone.
    public func acquire(_ cost: Int) async {
        let cost = min(max(cost, 0), limit)
        if waiting.isEmpty, used == 0 || used + cost <= limit {
            used += cost
            return
        }
        await withCheckedContinuation { waiting.append((cost, $0)) }
    }

    public func release(_ cost: Int) {
        used -= min(max(cost, 0), limit)
        // Big encoders (AVIF, PDFs) leave hundreds of MB of freed pages behind; hand them
        // back to the system so the footprint drops between files, not just at the end.
        if cost >= 64 << 20 { malloc_zone_pressure_relief(nil, 0) }
        while let next = waiting.first, used == 0 || used + next.cost <= limit {
            waiting.removeFirst()
            used += next.cost
            next.continuation.resume()
        }
    }

    /// Estimated peak bytes to compress one file, from its header (cheap; no decoding).
    public static func estimate(for url: URL, kind: InputKind, settings: SquishSettings, fileBytes: Int64) -> Int {
        switch kind {
        case .pdf:
            // The Quartz filter decodes every image in the document.
            return max(64 << 20, Int(fileBytes) * 8)
        case .image(let inputType):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int
            else { return 16 << 20 }
            var pixels = Double(width) * Double(height)
            if let maxDimension = settings.maxDimension, max(width, height) > maxDimension {
                let scale = Double(maxDimension) / Double(max(width, height))
                pixels *= scale * scale
            }
            let output = settings.format.type ?? inputType
            let perPixel: Double
            if output.identifier == "public.avif" {
                perPixel = 50
            } else if output.conforms(to: .png) {
                if case .palette = settings.pngMode { perPixel = 13 } else { perPixel = 8 }
            } else if output.conforms(to: .heic) || output.conforms(to: .heif) {
                perPixel = 4
            } else if output.conforms(to: .jpeg) {
                perPixel = 1
            } else {
                perPixel = 8
            }
            return Int(pixels * perPixel) + (4 << 20)
        }
    }
}
