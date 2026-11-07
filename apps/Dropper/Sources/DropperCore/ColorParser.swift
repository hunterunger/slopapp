import Foundation

/// Reads a color someone typed or pasted: hex, CSS `rgb()`/`rgba()`, `hsl()`/`hsla()`
/// (comma or space syntax), or `color(display-p3 r g b)`. Values without their own space
/// (hex, rgb, hsl) are read in `space`; `color(display-p3 …)` is always P3. A trailing
/// alpha is accepted only when it's fully opaque (1 or 100%), since contrast with
/// transparency depends on what's behind.
public enum ColorParser {
    public static func color(_ text: String, in space: OutputSpace) -> ColorValue? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let rgb = HexParser.parse(s) { return ColorValue(rgb, in: space) }
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let name = s[..<open].trimmingCharacters(in: .whitespaces)
        let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
        // Split on commas, spaces and the "/" before alpha.
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        switch name {
        case "rgb", "rgba":
            guard let c = channels(parts, alphaAt: 3) else { return nil }
            let values = c.compactMap { component($0, scale: 255) }
            guard values.count == 3 else { return nil }
            return ColorValue(RGB(red: values[0], green: values[1], blue: values[2]), in: space)
        case "hsl", "hsla":
            guard let c = channels(parts, alphaAt: 3),
                  let h = hue(c[0]), let sat = percent(c[1]), let l = percent(c[2]) else { return nil }
            return ColorValue(hslToRGB(h: h, s: sat, l: l), in: space)
        case "oklch":
            guard let c = channels(parts, alphaAt: 3) else { return nil }
            let lightness: Double?
            if c[0].hasSuffix("%") { lightness = Double(c[0].dropLast()).map { $0 / 100 } } else { lightness = Double(c[0]) }
            guard let l = lightness, (0...1).contains(l), let chroma = Double(c[1]), chroma >= 0, let h = hue(c[2]) else { return nil }
            return ColorValue(sRGB: ColorMath.sRGB(fromOKLCH: LCh(l: l, c: chroma, h: h)))
        case "color":
            guard parts.first == "display-p3", let c = channels(Array(parts.dropFirst()), alphaAt: 3) else { return nil }
            let values = c.compactMap { component($0, scale: 1) }
            guard values.count == 3 else { return nil }
            return ColorValue(displayP3: RGB(red: values[0], green: values[1], blue: values[2]))
        default:
            return nil
        }
    }

    /// The first three parts, after checking that any alpha is opaque.
    private static func channels(_ parts: [String], alphaAt index: Int) -> [String]? {
        guard parts.count == index || parts.count == index + 1 else { return nil }
        if parts.count == index + 1 {
            let a = parts[index]
            let opaque = a.hasSuffix("%") ? Double(a.dropLast()) == 100 : Double(a) == 1
            guard opaque else { return nil }
        }
        return Array(parts.prefix(index))
    }

    /// "51" (of `scale`) or "20%", to 0...1. Out-of-range numbers are rejected.
    private static func component(_ s: String, scale: Double) -> Double? {
        let value: Double
        if s.hasSuffix("%") {
            guard let p = Double(s.dropLast()) else { return nil }
            value = p / 100
        } else {
            guard let n = Double(s) else { return nil }
            value = n / scale
        }
        return (0...1).contains(value) ? value : nil
    }

    private static func percent(_ s: String) -> Double? {
        guard s.hasSuffix("%"), let p = Double(s.dropLast()), (0...100).contains(p) else { return nil }
        return p / 100
    }

    private static func hue(_ s: String) -> Double? {
        let number = s.hasSuffix("deg") ? String(s.dropLast(3)) : s
        guard let h = Double(number), h.isFinite else { return nil }
        let wrapped = h.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    public static func hslToRGB(h: Double, s: Double, l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}
