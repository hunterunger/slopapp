import Foundation

/// Plain descriptive names ("Dark Blue", "Pale Pink", "Gray") worked out from OKLCH, so
/// they follow how colors look rather than their RGB numbers. Used as the default name of
/// a saved color, in VoiceOver labels and in Android XML resource names. Deliberately
/// small and boring: no poetic name list.
public enum ColorNamer {
    public static func name(for color: ColorValue) -> String {
        let lch = ColorMath.oklch(fromSRGB: color.sRGB.clamped)
        let l = lch.l, c = lch.c, h = lch.h

        if c < 0.025 {
            switch l {
            case ..<0.2: return "Black"
            case ..<0.38: return "Very Dark Gray"
            case ..<0.55: return "Dark Gray"
            case ..<0.72: return "Gray"
            case ..<0.88: return "Light Gray"
            case ..<0.97: return "Very Light Gray"
            default: return "White"
            }
        }

        var hue = hueName(h)
        // Dark oranges and yellows read as brown and olive; light reds and magentas as pink.
        if hue == "Orange" || hue == "Amber" {
            if l < 0.6 { hue = "Brown" }
        } else if hue == "Yellow" || hue == "Lime" {
            if l < 0.6 { hue = "Olive" }
        } else if hue == "Red" || hue == "Magenta" || hue == "Rose" {
            if l > 0.78 { hue = "Pink" }
        }

        // Light colors carry less chroma, so they read as muted sooner.
        let muted = c < (l > 0.8 ? 0.035 : 0.06)
        if muted {
            if l < 0.3 { return "Very Dark \(grayish(hue))" }
            if l > 0.85 { return "Pale \(grayish(hue))" }
            return grayish(hue)
        }
        switch l {
        case ..<0.3: return "Very Dark \(hue)"
        case ..<0.48: return "Dark \(hue)"
        case ..<0.72: return c > 0.2 ? "Vivid \(hue)" : hue
        case ..<0.86: return "Light \(hue)"
        default: return "Pale \(hue)"
        }
    }

    /// OKLCH hue → a basic color word. Bucket edges sit between the sRGB primaries'
    /// OKLCH hues (red 29°, yellow 110°, green 142°, cyan 195°, blue 264°, magenta 328°).
    static func hueName(_ h: Double) -> String {
        switch h {
        case ..<14: return "Rose"
        case ..<45: return "Red"
        case ..<70: return "Orange"
        case ..<95: return "Amber"
        case ..<118: return "Yellow"
        case ..<132: return "Lime"
        case ..<165: return "Green"
        case ..<188: return "Teal"
        case ..<215: return "Cyan"
        case ..<245: return "Azure"
        case ..<275: return "Blue"
        case ..<300: return "Violet"
        case ..<320: return "Purple"
        case ..<345: return "Magenta"
        default: return "Rose"
        }
    }

    private static func grayish(_ hue: String) -> String {
        switch hue {
        case "Brown", "Olive": "Grayish \(hue)"
        default: "\(hue) Gray"
        }
    }
}

/// Finds a nearby color that passes a contrast target, changing only lightness (in OKLCH,
/// so hue and chroma stay as close as the sRGB gamut allows). Powers the "Fix" buttons.
public enum ContrastFixer {
    /// The next level worth reaching: AA (4.5) when failing, AAA (7) when only AA passes,
    /// nil when AAA already passes.
    public static func target(for ratio: Double) -> Double? {
        if ratio < 4.5 { return 4.5 }
        if ratio < 7 { return 7 }
        return nil
    }

    /// `color` adjusted to reach `target` against `other`, as an 8-bit sRGB color, or nil
    /// if no lightness gets there (e.g. AAA against a mid gray).
    public static func fix(_ color: ColorValue, against other: ColorValue, target: Double) -> ColorValue? {
        if Contrast.ratio(color, other) >= target { return color }
        let start = ColorMath.oklch(fromSRGB: color.sRGB.clamped)
        let candidates = [search(start, against: other, target: target, towards: 1),
                          search(start, against: other, target: target, towards: 0)].compactMap { $0 }
        return candidates.min { abs(lightness($0) - start.l) < abs(lightness($1) - start.l) }
    }

    private static func lightness(_ color: ColorValue) -> Double {
        ColorMath.oklab(fromSRGB: color.sRGB).l
    }

    /// Binary search between the start lightness and `towards` (0 or 1) for the passing
    /// color closest to the start.
    private static func search(_ start: LCh, against other: ColorValue, target: Double, towards end: Double) -> ColorValue? {
        let extreme = make(LCh(l: end, c: start.c, h: start.h))
        guard Contrast.ratio(extreme, other) >= target else { return nil }
        var passing = end, failing = start.l
        for _ in 0..<40 {
            let mid = (passing + failing) / 2
            if Contrast.ratio(make(LCh(l: mid, c: start.c, h: start.h)), other) >= target {
                passing = mid
            } else {
                failing = mid
            }
        }
        let result = make(LCh(l: passing, c: start.c, h: start.h))
        // 8-bit rounding can land a hair under the target: step one byte further if so.
        if Contrast.ratio(result, other) >= target { return result }
        return extreme
    }

    /// An in-gamut, 8-bit sRGB color for an OKLCH value, reducing chroma until it fits.
    static func make(_ lch: LCh) -> ColorValue {
        var c = lch.c
        var rgb = ColorMath.sRGB(fromOKLCH: LCh(l: lch.l, c: c, h: lch.h))
        var low = 0.0
        if !inGamut(rgb) {
            var high = c
            for _ in 0..<24 {
                c = (low + high) / 2
                rgb = ColorMath.sRGB(fromOKLCH: LCh(l: lch.l, c: c, h: lch.h))
                if inGamut(rgb) { low = c } else { high = c }
            }
            rgb = ColorMath.sRGB(fromOKLCH: LCh(l: lch.l, c: low, h: lch.h))
        }
        return ColorValue(sRGB: rgb.clamped.quantized)
    }

    private static func inGamut(_ c: RGB) -> Bool {
        c.components.allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 }
    }
}

/// How swatches look to people with color-vision deficiencies (Machado, Oliveira and
/// Fernandes 2009, full severity; achromatopsia as luminance). Only changes how swatches
/// are drawn; copied values never change.
public enum ColorVision: String, CaseIterable, Codable, Sendable, Identifiable {
    case normal
    case protanopia
    case deuteranopia
    case tritanopia
    case achromatopsia

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: "Normal Vision"
        case .protanopia: "Protanopia (no red)"
        case .deuteranopia: "Deuteranopia (no green)"
        case .tritanopia: "Tritanopia (no blue)"
        case .achromatopsia: "Achromatopsia (no color)"
        }
    }

    private var matrix: [[Double]]? {
        switch self {
        case .normal, .achromatopsia: nil
        case .protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
        case .deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
        case .tritanopia: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
        }
    }

    public func simulate(_ color: ColorValue) -> ColorValue {
        switch self {
        case .normal:
            return color
        case .achromatopsia:
            let y = ColorMath.gamma(Contrast.luminance(color))
            return ColorValue(red: y, green: y, blue: y)
        default:
            guard let matrix else { return color }
            let linear = ColorMath.decode(color.sRGB.clamped)
            let out = ColorMath.multiply(matrix, linear).map { min(max($0, 0), 1) }
            return ColorValue(sRGB: ColorMath.encode(out))
        }
    }
}
