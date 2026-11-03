// Generates an Slopapp app icon: a forest-green macOS tile with a cream Lucide glyph.
//
//   swift scripts/icongen.swift <Icon.svg> <out.icns> [--png <out-1024.png>] [--full-art]
//
// The glyph is any Lucide SVG (24x24 viewBox, stroke="currentColor"). We recolor it,
// let NSImage render the SVG natively, and draw every iconset size directly at its
// pixel size so small icons stay sharp. No dependencies beyond macOS.
//
// --full-art: the SVG is a finished, square icon (its own tile and colors, like
// brand/logo.svg). It's drawn as-is on Apple's icon grid with the standard shadow,
// instead of as a glyph on the forest tile. bundle.sh uses this for AppIcon.svg.
import AppKit

let forestTop = NSColor(srgbRed: 0x16 / 255, green: 0x52 / 255, blue: 0x3D / 255, alpha: 1)
let forest = NSColor(srgbRed: 0x0F / 255, green: 0x3D / 255, blue: 0x2E / 255, alpha: 1)
let cream = "#FAF6EC"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("icongen: \(message)\n".utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var pngOut: String?
var fullArt = false
if let i = args.firstIndex(of: "--full-art") {
    fullArt = true
    args.remove(at: i)
}
if let i = args.firstIndex(of: "--png"), i + 1 < args.count {
    pngOut = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
guard args.count == 2 else { fail("usage: icongen.swift <Icon.svg> <out.icns> [--png <out.png>] [--full-art]") }
let svgPath = args[0], icnsPath = args[1]
guard let source = try? String(contentsOfFile: svgPath, encoding: .utf8) else { fail("can't read \(svgPath)") }

/// The glyph SVG recolored, with a heavier stroke for tiny sizes.
func glyph(strokeWidth: Double) -> NSImage {
    var svg = source.replacingOccurrences(of: "currentColor", with: cream)
    svg = svg.replacingOccurrences(of: #"stroke-width="2""#, with: #"stroke-width="\#(strokeWidth)""#)
    guard let image = NSImage(data: Data(svg.utf8)) else { fail("NSImage can't render \(svgPath)") }
    return image
}

/// Apple-style continuous-corner tile (a superellipse, close to the macOS icon shape).
func tilePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fail("can't allocate \(pixels)px bitmap") }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let unit = Double(pixels) / 1024 // Apple's grid is 1024pt; the tile is 824 with a 100 margin.

    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    if fullArt {
        // Finished artwork: draw it on the grid with the same soft shadow (it follows the art's alpha).
        guard let art = NSImage(data: Data(source.utf8)) else { fail("NSImage can't render \(svgPath)") }
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        art.draw(in: tile)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    let path = tilePath(in: tile)

    // Soft drop shadow, as on Apple's own icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(forest.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Gentle top-to-bottom gradient.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [forestTop.cgColor, forest.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // Glyph, about half the tile. Thicker strokes at tiny sizes so lines don't vanish.
    let strokeWidth = pixels <= 32 ? 2.5 : (pixels <= 64 ? 2.25 : 2)
    let side = 440 * unit
    let glyphRect = NSRect(x: (Double(pixels) - side) / 2, y: (Double(pixels) - side) / 2, width: side, height: side)
    glyph(strokeWidth: strokeWidth).draw(in: glyphRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG encode failed") }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("can't write \(path): \(error)") }
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "slopapp-\(UUID().uuidString).iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(atPath: iconset) }

for points in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: points), to: "\(iconset)/icon_\(points)x\(points).png")
    writePNG(render(pixels: points * 2), to: "\(iconset)/icon_\(points)x\(points)@2x.png")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", icnsPath]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }

if let pngOut { writePNG(render(pixels: 1024), to: pngOut) }
print("icongen: wrote \(icnsPath)\(pngOut.map { " and \($0)" } ?? "")")
