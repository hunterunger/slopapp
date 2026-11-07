import Foundation

/// OKLab / OKLCH (Björn Ottosson) and CIE Lab / LCH (D50, as CSS Color 4 defines them).
/// Inputs are gamma-encoded extended sRGB; outputs follow the CSS conventions:
/// OKLab L 0...1, CIE L 0...100, hue in degrees 0..<360.
public struct OKLab: Equatable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double
}

public struct LCh: Equatable, Sendable {
    /// Lightness: 0...1 for OKLCH, 0...100 for CIE LCH.
    public var l: Double
    public var c: Double
    /// Degrees, 0..<360. 0 for grays.
    public var h: Double
}

public struct CIELab: Equatable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double
}

extension ColorMath {
    // MARK: OKLab

    public static func oklab(fromSRGB c: RGB) -> OKLab {
        let r = linear(c.red), g = linear(c.green), b = linear(c.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return OKLab(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    public static func sRGB(fromOKLab lab: OKLab) -> RGB {
        let l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return RGB(
            red: gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }

    public static func oklch(fromSRGB c: RGB) -> LCh {
        let lab = oklab(fromSRGB: c)
        return polar(l: lab.l, a: lab.a, b: lab.b, grayBelow: 0.0004)
    }

    public static func sRGB(fromOKLCH lch: LCh) -> RGB {
        let rad = lch.h * .pi / 180
        return sRGB(fromOKLab: OKLab(l: lch.l, a: lch.c * cos(rad), b: lch.c * sin(rad)))
    }

    // MARK: CIE Lab (D50)

    static let sRGBToXYZD65: [[Double]] = [
        [0.41239079926595934, 0.357584339383878, 0.1804807884018343],
        [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
        [0.01933081871559182, 0.11919477979462598, 0.9505321522496607],
    ]
    static let xyzD65ToSRGB: [[Double]] = [
        [3.2409699419045226, -1.537383177570094, -0.4986107602930034],
        [-0.9692436362808796, 1.8759675015077202, 0.04155505740717559],
        [0.05563007969699366, -0.20397695888897652, 1.0569715142428786],
    ]
    static let d65ToD50: [[Double]] = [
        [1.0479298208405488, 0.022946793341019088, -0.05019222954313557],
        [0.029627815688159344, 0.990434484573249, -0.01707382502938514],
        [-0.009243058152591178, 0.015055144896577895, 0.7518742899580008],
    ]
    static let d50ToD65: [[Double]] = [
        [0.9554734527042182, -0.023098536874261423, 0.0632593086610217],
        [-0.028369706963208136, 1.0099954580058226, 0.021041398966943008],
        [0.012314001688319899, -0.020507696433477912, 1.3303659366080753],
    ]
    static let whiteD50 = [0.3457 / 0.3585, 1.0, (1.0 - 0.3457 - 0.3585) / 0.3585]
    private static let epsilon = 216.0 / 24389
    private static let kappa = 24389.0 / 27

    public static func lab(fromSRGB c: RGB) -> CIELab {
        let xyz = multiply(d65ToD50, multiply(sRGBToXYZD65, decode(c)))
        let f = (0..<3).map { i -> Double in
            let v = xyz[i] / whiteD50[i]
            return v > epsilon ? cbrt(v) : (kappa * v + 16) / 116
        }
        return CIELab(l: 116 * f[1] - 16, a: 500 * (f[0] - f[1]), b: 200 * (f[1] - f[2]))
    }

    public static func sRGB(fromLab lab: CIELab) -> RGB {
        let f1 = (lab.l + 16) / 116
        let f0 = lab.a / 500 + f1
        let f2 = f1 - lab.b / 200
        let x = pow(f0, 3) > epsilon ? pow(f0, 3) : (116 * f0 - 16) / kappa
        let y = lab.l > kappa * epsilon ? pow(f1, 3) : lab.l / kappa
        let z = pow(f2, 3) > epsilon ? pow(f2, 3) : (116 * f2 - 16) / kappa
        let xyz = [x * whiteD50[0], y * whiteD50[1], z * whiteD50[2]]
        return encode(multiply(xyzD65ToSRGB, multiply(d50ToD65, xyz)))
    }

    public static func lch(fromSRGB c: RGB) -> LCh {
        let lab = lab(fromSRGB: c)
        return polar(l: lab.l, a: lab.a, b: lab.b, grayBelow: 0.02)
    }

    static func polar(l: Double, a: Double, b: Double, grayBelow: Double) -> LCh {
        let c = (a * a + b * b).squareRoot()
        guard c >= grayBelow else { return LCh(l: l, c: 0, h: 0) }
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        if h >= 360 { h -= 360 }
        return LCh(l: l, c: c, h: h)
    }
}

extension RGB {
    /// Hue 0..<1, saturation and brightness 0...1, unrounded (for code that takes HSB).
    public var hsbUnits: (hue: Double, saturation: Double, brightness: Double) {
        let c = clamped
        let maxV = Swift.max(c.red, c.green, c.blue)
        let minV = Swift.min(c.red, c.green, c.blue)
        return (hueDegrees / 360, maxV == 0 ? 0 : (maxV - minV) / maxV, maxV)
    }

    /// The color for hue (0..<1), saturation and brightness (0...1).
    public static func fromHSB(hue: Double, saturation s: Double, brightness v: Double) -> RGB {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(red: v, green: t, blue: p)
        case 1: return RGB(red: q, green: v, blue: p)
        case 2: return RGB(red: p, green: v, blue: t)
        case 3: return RGB(red: p, green: q, blue: v)
        case 4: return RGB(red: t, green: p, blue: v)
        default: return RGB(red: v, green: p, blue: q)
        }
    }

    /// HSL with unrounded parts: hue 0..<360, saturation and lightness 0...1.
    public var hslUnits: (hue: Double, saturation: Double, lightness: Double) {
        let c = clamped
        let maxV = Swift.max(c.red, c.green, c.blue)
        let minV = Swift.min(c.red, c.green, c.blue)
        let d = maxV - minV
        let l = (maxV + minV) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return (hueDegrees, s, l)
    }

    /// Naive (device) CMYK, 0...1 each.
    public var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let c = clamped
        let k = 1 - Swift.max(c.red, c.green, c.blue)
        guard k < 1 else { return (0, 0, 0, 1) }
        return ((1 - c.red - k) / (1 - k), (1 - c.green - k) / (1 - k), (1 - c.blue - k) / (1 - k), k)
    }
}
