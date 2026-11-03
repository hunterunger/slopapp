import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import IconsmithCore

/// A fresh folder under /tmp/iconsmith-test (the only place tests touch).
func makeTestFolder(_ name: String = #function) throws -> URL {
    let safe = name.filter { $0.isLetter || $0.isNumber }
    let url = URL(fileURLWithPath: "/tmp/iconsmith-test/unit/\(safe)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A solid or transparent-edged test picture.
func makeImage(width: Int, height: Int, transparentEdges: Bool = false, color: CGColor = CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1)) -> CGImage {
    let context = Bitmap.context(width: width, height: height)!
    if transparentEdges {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
    } else {
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: width / 3, y: height / 3, width: width / 3, height: height / 3))
    }
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try Bitmap.pngData(image)!.write(to: url)
}

func rasterSource(width: Int = 512, height: Int = 512, transparentEdges: Bool = false) -> IconSource {
    IconSource(content: .raster(makeImage(width: width, height: height, transparentEdges: transparentEdges)),
               name: "test", url: nil, size: CGSize(width: width, height: height))
}

/// RGBA of one pixel (x from the left, y from the top), un-premultiplied.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
    let context = Bitmap.context(width: image.width, height: image.height)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let p = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * image.height)
    let i = y * context.bytesPerRow + x * 4
    let a = Double(p[i + 3]) / 255
    guard a > 0 else { return (0, 0, 0, 0) }
    return (Double(p[i]) / 255 / a, Double(p[i + 1]) / 255 / a, Double(p[i + 2]) / 255 / a, a)
}

func imageSize(_ data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}

func hasAlphaChannel(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return true }
    return props[kCGImagePropertyHasAlpha] as? Bool ?? false
}

struct FakeIconProvider: FileIconProvider {
    func icon(forFile url: URL) -> NSImage? {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        let rep = NSBitmapImageRep(cgImage: makeImage(width: 64, height: 64))
        image.addRepresentation(rep)
        return image
    }
}

/// In-memory custom icons with switchable failures.
@MainActor
final class FakeFileIcons: FileIconSystem {
    var icons: [String: NSImage] = [:]
    var infos: [String: TargetInfo] = [:]
    var refuseSet: Set<String> = []
    var setCalls = 0

    func info(_ url: URL) -> TargetInfo { infos[url.path] ?? TargetInfo() }
    func hasCustomIcon(_ url: URL) -> Bool { icons[url.path] != nil }
    func customIcon(_ url: URL) -> NSImage? { icons[url.path] }
    func setIcon(_ image: NSImage?, for url: URL) -> Bool {
        setCalls += 1
        guard !refuseSet.contains(url.path) else { return false }
        icons[url.path] = image
        return true
    }
}
