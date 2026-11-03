// Generates Squish test fixtures. Only ever writes under the given directory.
//
//   swift apps/Squish/Tools/make-fixtures.swift [/tmp/squish-test] [--batch 200]
//
// Sources are macOS's own wallpapers (no personal content). WebP needs `cwebp` (optional).
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let args = CommandLine.arguments.dropFirst()
let root = URL(fileURLWithPath: args.first(where: { $0.hasPrefix("/") }) ?? "/tmp/squish-test")
guard root.path.hasPrefix("/tmp/") || root.path.hasPrefix("/private/tmp/") else {
    fatalError("fixtures must live under /tmp")
}
let batchCount: Int = {
    if let i = args.firstIndex(of: "--batch"), let n = Int(args[args.index(after: i)]) { return n }
    return 200
}()
let fm = FileManager.default
let samples = root.appendingPathComponent("samples")
let batch = root.appendingPathComponent("batch")
try? fm.removeItem(at: samples)
try? fm.removeItem(at: batch)
try fm.createDirectory(at: samples, withIntermediateDirectories: true)
try fm.createDirectory(at: batch, withIntermediateDirectories: true)

func load(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func scaled(_ image: CGImage, width: Int) -> CGImage {
    let height = Int(Double(image.height) * Double(width) / Double(image.width))
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}
func write(_ image: CGImage, to url: URL, type: UTType, props: [CFString: Any] = [:]) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
}
let exifGPS: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Fixture Lens 50mm", kCGImagePropertyExifUserComment: "squish fixture"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.05, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 114.07, kCGImagePropertyGPSLongitudeRef: "W"],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Fixture Camera"],
]

let aerial = load("/System/Library/Wallpapers/.default/DefaultAerial.jpg")        // 3840x2160
let sonoma = load("/System/Library/Desktop Pictures/Sonoma.heic")

// Photos: a near-lossless JPEG (big, like a camera file) with EXIF + GPS.
write(aerial, to: samples.appendingPathComponent("Aerial photo.jpg"), type: .jpeg,
      props: exifGPS.merging([kCGImageDestinationLossyCompressionQuality: 0.97]) { $1 })
// A JPEG that's already heavily compressed (Squish should keep the original).
write(scaled(aerial, width: 800), to: samples.appendingPathComponent("Tiny already compressed.jpg"), type: .jpeg,
      props: [kCGImageDestinationLossyCompressionQuality: 0.2])
write(scaled(sonoma, width: 3000), to: samples.appendingPathComponent("Sonoma.heic"), type: .heic,
      props: [kCGImageDestinationLossyCompressionQuality: 0.95])
write(scaled(aerial, width: 2400), to: samples.appendingPathComponent("Photo as PNG.png"), type: .png)

// A screenshot-like PNG: flat UI colors and text, with alpha (rounded window).
func screenshot(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = ns
    let window = NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: width - 40, height: height - 40), xRadius: 24, yRadius: 24)
    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1).setFill(); window.fill()
    NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 20, y: height - 120, width: width - 40, height: 80)).fill()
    for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill(); NSBezierPath(ovalIn: NSRect(x: 50 + i * 40, y: height - 92, width: 24, height: 24)).fill()
    }
    NSColor(srgbRed: 0.2, green: 0.45, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 80, width: 300, height: 64), xRadius: 12, yRadius: 12).fill()
    let gradient = NSGradient(starting: .systemTeal, ending: .systemPurple)!
    gradient.draw(in: NSRect(x: width - 700, y: 200, width: 600, height: 400), angle: 30)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
    for line in 0..<24 {
        ("Line \(line + 1): The quick brown fox jumps over the lazy dog. 0123456789" as NSString)
            .draw(at: NSPoint(x: 60, y: height - 180 - line * 44), withAttributes: attrs)
    }
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}
write(screenshot(width: 2880, height: 1800), to: samples.appendingPathComponent("Screenshot.png"), type: .png)

// Animated GIF (kept as is).
do {
    let url = samples.appendingPathComponent("Animated.gif")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 4, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<4 {
        let frame = scaled(aerial, width: 320 + i * 4)
        CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(dest))
}

// WebP (needs cwebp; ImageIO reads WebP but can't write it).
if let cwebp = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first(where: fm.isExecutableFile(atPath:)) {
    let png = root.appendingPathComponent("webp-source.png")
    write(scaled(aerial, width: 1600), to: png, type: .png)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cwebp)
    p.arguments = ["-quiet", "-q", "95", png.path, "-o", samples.appendingPathComponent("Photo.webp").path]
    try p.run(); p.waitUntilExit()
    try? fm.removeItem(at: png)
}

// Broken inputs.
try Data("this is not an image".utf8).write(to: samples.appendingPathComponent("Broken.jpg"))
fm.createFile(atPath: samples.appendingPathComponent("Empty.png").path, contents: Data())

// PDFs.
func makePDF(_ url: URL, pages: Int, draw: (CGContext, Int, CGRect) -> Void) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle: url.deletingPathExtension().lastPathComponent] as CFDictionary)!
    for page in 0..<pages {
        ctx.beginPDFPage(nil)
        draw(ctx, page, box)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}
func text(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat = 12) {
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (string as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size)])
    NSGraphicsContext.current = nil
}
// A "scanned" document: full-page photos at high resolution, plus a line of real text.
makePDF(samples.appendingPathComponent("Scanned report.pdf"), pages: 6) { ctx, page, box in
    ctx.interpolationQuality = .none
    ctx.draw(page % 2 == 0 ? aerial : sonoma, in: box.insetBy(dx: 36, dy: 120))
    text(ctx, "Page \(page + 1): searchable text survives compression.", at: CGPoint(x: 36, y: 60), size: 14)
}
// Text only: nothing to squeeze (Squish should keep the original).
makePDF(samples.appendingPathComponent("Text only.pdf"), pages: 3) { ctx, page, _ in
    for line in 0..<40 {
        text(ctx, "Page \(page + 1), line \(line + 1). Plain vector text compresses well already.", at: CGPoint(x: 48, y: 740 - line * 17))
    }
}
// Password-protected PDF.
do {
    let doc = PDFDocument(url: samples.appendingPathComponent("Text only.pdf"))!
    doc.write(to: samples.appendingPathComponent("Locked.pdf"),
              withOptions: [.userPasswordOption: "squish", .ownerPasswordOption: "squish-owner"])
}

// Batch: N mid-size JPEGs (2400 px, q 0.95) for the performance benchmark.
let batchSource = scaled(aerial, width: 2400)
let batchData: Data = {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, batchSource, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return data as Data
}()
for i in 1...batchCount {
    try batchData.write(to: batch.appendingPathComponent(String(format: "IMG_%04d.jpg", i)))
}
print("Fixtures in \(root.path):")
for name in try fm.contentsOfDirectory(atPath: samples.path).sorted() {
    let size = (try fm.attributesOfItem(atPath: samples.appendingPathComponent(name).path)[.size] as? Int) ?? 0
    print(String(format: "  %-28@ %10d bytes", name as NSString, size))
}
print("  batch/ \(batchCount) JPEGs, \(batchData.count) bytes each")
