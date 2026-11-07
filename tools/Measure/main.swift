// measure: pixel-level checks on window screenshots (from `scripts/drive shot`).
// Coordinates and results are in points (screenshot pixels / scale; default scale 2).
//
//   measure corners <png>                    window corner radius, and for each corner whether
//                                            the first inset shape inside it is concentric
//   measure line <png> <x> <y> <dx> <dy> [len] colour changes along a line (measure spacing)
//   measure color <png> <x> <y>              the colour at a point
//   measure contrast <png> <x1> <y1> <x2> <y2>  WCAG contrast ratio between two points
//   options: --scale N (pixels per point, default 2), --threshold T (colour step, default 0.08)

import AppKit

struct RGBA: CustomStringConvertible {
    var r, g, b, a: Double
    func distance(_ o: RGBA) -> Double {
        let d = [(r - o.r), (g - o.g), (b - o.b), (a - o.a)].map { $0 * $0 }.reduce(0, +)
        return d.squareRoot()
    }
    var hex: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }
    var description: String { a < 0.99 ? "\(hex)@\(Int(a * 100))%" : hex }
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

final class Image {
    let rep: NSBitmapImageRep
    let width: Int, height: Int
    init(path: String) {
        guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else {
            fail("can't read \(path)")
        }
        self.rep = rep; width = rep.pixelsWide; height = rep.pixelsHigh
    }
    func at(_ x: Int, _ y: Int) -> RGBA? {
        guard x >= 0, y >= 0, x < width, y < height,
              let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("measure: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, _ fallback: Double) -> Double {
    guard let i = args.firstIndex(of: name), i + 1 < args.count, let v = Double(args[i + 1]) else { return fallback }
    args.removeSubrange(i...(i + 1)); return v
}
let scale = option("--scale", 2)
let threshold = option("--threshold", 0.08)
guard args.count >= 2 else {
    print("""
    usage: measure corners <png> | line <png> x y dx dy [len] | color <png> x y | contrast <png> x1 y1 x2 y2
           [--scale 2] [--threshold 0.08]   (points; see tools/Measure/main.swift)
    """)
    exit(args.isEmpty ? 0 : 1)
}
let command = args[0]
let image = Image(path: args[1])
func num(_ i: Int) -> Double { guard i < args.count, let v = Double(args[i]) else { fail("missing number #\(i - 1)") }; return v }
func pt(_ px: Double) -> String { String(format: "%.1f", px / scale) }

/// Walks from (x,y) by (dx,dy) pixels; returns the index where the window starts (alpha) and
/// the first lasting colour change after that.
func edges(fromX x: Int, y: Int, dx: Int, dy: Int, limit: Int) -> (outer: Int, inner: Int?, frame: RGBA?) {
    var outer = -1
    for i in 0..<limit {
        guard let c = image.at(x + dx * i, y + dy * i) else { break }
        if c.a > 0.5 { outer = i; break }
    }
    guard outer >= 0, let frame = image.at(x + dx * (outer + 3), y + dy * (outer + 3)) else { return (outer, nil, nil) }
    var i = outer + 3
    while i < limit {
        guard let c = image.at(x + dx * i, y + dy * i), let next = image.at(x + dx * (i + 2), y + dy * (i + 2)) else { break }
        if c.distance(frame) > threshold, next.distance(frame) > threshold { return (outer, i, frame) }
        i += 1
    }
    return (outer, nil, frame)
}

switch command {
case "corners":
    let w = image.width, h = image.height
    let probe = Int(40 * scale)   // straight-edge samples, 40 pt in from the corner
    let limit = Int(80 * scale)
    print("window \(pt(Double(w))) x \(pt(Double(h))) pt")
    for (name, cx, cy, sx, sy) in [("top-left", 0, 0, 1, 1), ("top-right", w - 1, 0, -1, 1),
                                   ("bottom-left", 0, h - 1, 1, -1), ("bottom-right", w - 1, h - 1, -1, -1)] {
        let diag = edges(fromX: cx, y: cy, dx: sx, dy: sy, limit: limit)
        let horizontal = edges(fromX: cx + sx * probe, y: cy, dx: 0, dy: sy, limit: limit)   // across the top/bottom edge
        let vertical = edges(fromX: cx, y: cy + sy * probe, dx: sx, dy: 0, limit: limit)      // across the side edge
        // A circle of radius r crosses the diagonal r(1 - 1/√2) from the corner.
        let radius = Double(diag.outer) / (1 - 1 / 2.0.squareRoot())
        var line = "\(name): window radius ≈ \(pt(radius)) pt"
        if let di = diag.inner, let hi = horizontal.inner, let vi = vertical.inner {
            let gapH = Double(hi - horizontal.outer), gapV = Double(vi - vertical.outer)
            let radial = Double(di - diag.outer) * 2.0.squareRoot()
            let straight = (gapH + gapV) / 2
            let verdict: String
            if abs(gapH - gapV) > scale * 1.5 {
                verdict = "uneven inset (top/bottom \(pt(gapH)) vs side \(pt(gapV)) pt)"
            } else if radial > straight + scale * 1.5 {
                verdict = "NOT concentric: inner corner too tight (gap at the curve \(pt(radial)) pt > \(pt(straight)) pt); use Radius.nested / windowConcentric"
            } else if radial < straight - scale * 1.5 {
                verdict = "NOT concentric: inner corner too round (gap at the curve \(pt(radial)) pt < \(pt(straight)) pt)"
            } else {
                verdict = "concentric (gap \(pt(straight)) pt along the edges, \(pt(radial)) pt at the curve)"
            }
            line += "; inset shape: \(verdict)"
        } else {
            line += "; no inset shape found (content runs to the edge)"
        }
        print(line)
    }

case "line":
    let x0 = num(2), y0 = num(3), dx = num(4), dy = num(5)
    let len = args.count > 6 ? num(6) : 200
    let steps = Int(len * scale)
    let norm = max((dx * dx + dy * dy).squareRoot(), 0.0001)
    func sample(_ i: Int) -> RGBA? {
        image.at(Int((x0 * scale + dx / norm * Double(i)).rounded()), Int((y0 * scale + dy / norm * Double(i)).rounded()))
    }
    guard var current = sample(0) else { fail("start point is outside the image") }
    var start = 0
    print("from (\(x0), \(y0)) pt, direction (\(dx), \(dy)), \(len) pt:")
    var i = 1
    while i <= steps, let c = sample(i) {
        if c.distance(current) > threshold, let n = sample(i + 1), n.distance(current) > threshold {
            print("  \(pt(Double(start)))–\(pt(Double(i))) pt  (\(pt(Double(i - start))) pt)  \(current)")
            current = n; start = i; i += 2; continue
        }
        i += 1
    }
    print("  \(pt(Double(start)))– pt  \(current)")

case "color":
    guard let c = image.at(Int(num(2) * scale), Int(num(3) * scale)) else { fail("outside the image") }
    print(c)

case "contrast":
    guard let a = image.at(Int(num(2) * scale), Int(num(3) * scale)),
          let b = image.at(Int(num(4) * scale), Int(num(5) * scale)) else { fail("outside the image") }
    let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
    let ratio = (hi + 0.05) / (lo + 0.05)
    print(String(format: "%@ vs %@: %.2f:1 (body text needs 4.5, large text and UI 3.0)", a.description, b.description, ratio))

default:
    fail("unknown command \(command)")
}
