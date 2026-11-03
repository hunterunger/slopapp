// Test pictures and target folders for Iconsmith walkthroughs and blind tests.
//
//   swift apps/Iconsmith/Tools/make-fixtures.swift [/tmp/iconsmith-test]
//
// Writes only inside the given folder (default /tmp/iconsmith-test).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/iconsmith-test")
let fm = FileManager.default
let pictures = root.appending(path: "pictures")
let targets = root.appending(path: "targets")
for dir in [pictures, targets, root.appending(path: "exports")] {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
}

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String, type: String = "public.png") {
    let url = pictures.appending(path: name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// A photo-like opaque landscape (sky, sun, hills), 1600x1000 JPEG.
save(bitmap(1600, 1000) { c in
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        CGColor(srgbRed: 0.35, green: 0.6, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.95, green: 0.75, blue: 0.5, alpha: 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 1000), end: CGPoint(x: 0, y: 0), options: [])
    c.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1))
    c.fillEllipse(in: CGRect(x: 1050, y: 560, width: 260, height: 260))
    c.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.25, alpha: 1))
    c.fillEllipse(in: CGRect(x: -300, y: -500, width: 1400, height: 900))
    c.setFillColor(CGColor(srgbRed: 0.15, green: 0.4, blue: 0.2, alpha: 1))
    c.fillEllipse(in: CGRect(x: 600, y: -600, width: 1400, height: 950))
}, "landscape.jpg", type: "public.jpeg")

// A transparent logo: a bold ring and dot, 1024 PNG.
save(bitmap(1024, 1024) { c in
    c.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.2, blue: 0.35, alpha: 1))
    c.setLineWidth(110)
    c.strokeEllipse(in: CGRect(x: 200, y: 200, width: 624, height: 624))
    c.setFillColor(CGColor(srgbRed: 0.2, green: 0.25, blue: 0.7, alpha: 1))
    c.fillEllipse(in: CGRect(x: 412, y: 412, width: 200, height: 200))
}, "logo.png")

// A tiny 96 px badge (should warn about soft large sizes).
save(bitmap(96, 96) { c in
    c.setFillColor(CGColor(srgbRed: 0.1, green: 0.55, blue: 0.5, alpha: 1))
    c.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
    c.setFillColor(CGColor(gray: 1, alpha: 1))
    c.fill(CGRect(x: 30, y: 30, width: 36, height: 36))
}, "tiny.png")

// An SVG mark (vector, transparent).
try """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <rect x="10" y="10" width="80" height="80" rx="18" fill="#2a6df4"/>
  <path d="M30 65 L50 30 L70 65 Z" fill="#ffffff"/>
</svg>
""".write(to: pictures.appending(path: "mark.svg"), atomically: true, encoding: .utf8)

// Not a picture.
try Data("this is not an image".utf8).write(to: pictures.appending(path: "broken.png"))

// Targets: folders and a document to put icons on.
for name in ["Project Alpha", "Project Beta", "Photos 2026"] {
    try fm.createDirectory(at: targets.appending(path: name), withIntermediateDirectories: true)
}
try "Some notes.".write(to: targets.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
print("Fixtures in \(root.path): pictures/ (landscape.jpg, logo.png, tiny.png, mark.svg, broken.png), targets/ (3 folders, notes.txt), exports/")
