import Foundation

/// What the numbers mean.
public enum MeasureUnit: String, CaseIterable, Sendable, Identifiable {
    /// Points, like design tools and code use (pixels ÷ the display's scale). Half points
    /// show as .5 where an edge really sits on one (Retina).
    case points
    /// The display's backing pixels.
    case pixels

    public var id: String { rawValue }
    public var title: String { self == .points ? "Points" : "Pixels" }
    public var suffix: String { self == .points ? "pt" : "px" }
    /// Spoken form for VoiceOver.
    public var spoken: String { self == .points ? "points" : "pixels" }

    public var toggled: MeasureUnit { self == .points ? .pixels : .points }

    /// The pointer step for an arrow key, in points: 1 (or 10) of this unit.
    public func nudgeStep(scale: Double, large: Bool) -> Double {
        let unit = self == .points ? 1 : 1 / max(scale, 1)
        return large ? unit * 10 : unit
    }
}

/// A divisor for designs shown bigger or smaller than their real size: a mockup exported
/// @2x and viewed at 100%, or a design tool zoomed to 200%, reads true at ÷2.
public enum DesignScale {
    /// The menu's presets: 1 (actual size), @2x, @3x, and a 50% zoom (×2).
    public static let presets: [Double] = [1, 2, 3, 0.5]

    /// Kept within a sane range (5%–1000% zoom).
    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        return min(max(value, 0.1), 20)
    }

    /// "Actual Size", "@2x (÷2)", "50% Zoom (×2)", "÷1.5".
    public static func title(_ value: Double) -> String {
        let v = clamped(value)
        if v == 1 { return "Actual Size" }
        let n = Readout.format(v, locale: Locale(identifier: "en_US_POSIX"), maxFraction: 2)
        if v == v.rounded() { return "@\(n)x (÷\(n))" }
        if v < 1 {
            let percent = Readout.format(v * 100, locale: Locale(identifier: "en_US_POSIX"), maxFraction: 0)
            let times = Readout.format(1 / v, locale: Locale(identifier: "en_US_POSIX"), maxFraction: 2)
            return "\(percent)% Zoom (×\(times))"
        }
        return "÷\(n)"
    }

    /// Short badge text for the overlay: "@2x", "÷1.5", "×2". Nil at actual size.
    public static func badge(_ value: Double) -> String? {
        let v = clamped(value)
        guard v != 1 else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        if v == v.rounded() { return "@\(Readout.format(v, locale: posix, maxFraction: 0))x" }
        if v < 1 { return "×\(Readout.format(1 / v, locale: posix, maxFraction: 2))" }
        return "÷\(Readout.format(v, locale: posix, maxFraction: 2))"
    }
}

/// Turns pixel counts into readable numbers for one display.
public struct Readout: Sendable {
    public var scale: Double
    public var unit: MeasureUnit
    public var locale: Locale
    /// Divides every value (see `DesignScale`).
    public var designScale: Double
    /// Whether labels end in "pt"/"px".
    public var showsUnit: Bool

    public init(scale: Double, unit: MeasureUnit, locale: Locale = .current, designScale: Double = 1, showsUnit: Bool = true) {
        self.scale = scale
        self.unit = unit
        self.locale = locale
        self.designScale = DesignScale.clamped(designScale)
        self.showsUnit = showsUnit
    }

    /// The value in the chosen unit. Points on Retina can be x.5. A design scale makes finer
    /// steps (one Retina pixel is 0.25 pt of an @2x design), so values keep the two decimals
    /// that step needs: 100.5 pt at @2x reads 50.25, not a rounded 50.3.
    public func value(_ pixels: Int) -> Double {
        let base: Double = unit == .pixels ? Double(pixels) : Double(pixels) / max(scale, 0.01)
        let v = base / designScale
        let places: Double = designScale == 1 ? 10 : 100
        return (v * places).rounded() / places
    }

    /// "100.5" (with the locale's decimal separator).
    public func number(_ pixels: Int) -> String {
        Self.format(value(pixels), locale: locale)
    }

    private var unitSuffix: String { showsUnit ? " \(unit.suffix)" : "" }

    /// "100.5 pt" (always with the unit: menus, toasts and VoiceOver).
    public func length(_ pixels: Int) -> String {
        "\(number(pixels)) \(unit.suffix)"
    }

    /// "200 × 120 pt" (always with the unit).
    public func size(width: Int, height: Int) -> String {
        "\(number(width)) × \(number(height)) \(unit.suffix)"
    }

    /// A label on the overlay: the unit only if `showsUnit`.
    public func lengthLabel(_ pixels: Int) -> String {
        number(pixels) + unitSuffix
    }

    /// A size label on the overlay, with an optional aspect ratio: "320 × 180 pt  16:9".
    public func sizeLabel(width: Int, height: Int, ratio: AspectRatioStyle? = nil) -> String {
        let base = "\(number(width)) × \(number(height))" + unitSuffix
        guard let ratio, let text = AspectRatio.text(width: width, height: height, style: ratio) else { return base }
        return base + "  " + text
    }

    /// "200 by 120 points", for VoiceOver.
    public func spokenSize(width: Int, height: Int) -> String {
        "\(number(width)) by \(number(height)) \(unit.spoken)"
    }

    public func text(_ reading: Reading) -> String {
        switch reading {
        case .size(let w, let h): size(width: w, height: h)
        case .length(let l, _): length(l)
        }
    }

    public func spoken(_ reading: Reading) -> String {
        switch reading {
        case .size(let w, let h): spokenSize(width: w, height: h)
        case .length(let l, let axis): "\(axis == .horizontal ? "width" : "height") \(number(l)) \(unit.spoken)"
        }
    }

    static func format(_ value: Double, locale: Locale, maxFraction: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)).grouping(.never).locale(locale))
    }
}

/// What Return / ⌘C put on the clipboard.
public enum CopyFormat: String, CaseIterable, Sendable, Identifiable {
    case plain
    case css
    case sass
    case tailwind
    case swiftUI

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: "Plain (200 × 120)"
        case .css: "CSS (width: 200px;)"
        case .sass: "Sass ($width: 200px;)"
        case .tailwind: "Tailwind (w-[200px])"
        case .swiftUI: "SwiftUI (.frame)"
        }
    }

    /// Short name for menus.
    public var shortTitle: String {
        switch self {
        case .plain: "Plain"
        case .css: "CSS"
        case .sass: "Sass"
        case .tailwind: "Tailwind"
        case .swiftUI: "SwiftUI"
        }
    }

    /// The clipboard text for a width and height. Code formats always use "." decimals.
    public func text(width: Int, height: Int, readout: Readout) -> String {
        let code = Locale(identifier: "en_US_POSIX")
        let w = Readout.format(readout.value(width), locale: code)
        let h = Readout.format(readout.value(height), locale: code)
        switch self {
        case .plain: return "\(readout.number(width)) × \(readout.number(height))"
        case .css: return "width: \(w)px;\nheight: \(h)px;"
        case .sass: return "$width: \(w)px;\n$height: \(h)px;"
        case .tailwind: return "w-[\(w)px] h-[\(h)px]"
        case .swiftUI: return ".frame(width: \(w), height: \(h))"
        }
    }

    /// The clipboard text for any reading. A single distance copies just its own property.
    public func text(_ reading: Reading, readout: Readout) -> String {
        switch reading {
        case .size(let w, let h):
            return text(width: w, height: h, readout: readout)
        case .length(let l, let axis):
            let v = Readout.format(readout.value(l), locale: Locale(identifier: "en_US_POSIX"))
            let name = axis == .horizontal ? "width" : "height"
            switch self {
            case .plain: return readout.number(l)
            case .css: return "\(name): \(v)px;"
            case .sass: return "$\(name): \(v)px;"
            case .tailwind: return "\(axis == .horizontal ? "w" : "h")-[\(v)px]"
            case .swiftUI: return ".frame(\(name): \(v))"
            }
        }
    }
}

/// How an aspect ratio is written.
public enum AspectRatioStyle: String, CaseIterable, Sendable, Identifiable {
    /// A common ratio (16:9) when it's within 1%, else decimal.
    case automatic
    /// The exact reduced fraction (16:9, 7:5), decimal when the terms get large.
    case fraction
    /// "1.78:1".
    case decimal
    /// Only common ratios; nothing otherwise.
    case commonOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .fraction: "Fraction (16:9)"
        case .decimal: "Decimal (1.78:1)"
        case .commonOnly: "Common Ratios Only"
        }
    }
}

public enum AspectRatio {
    /// Ratios people name, landscape first (portrait versions are matched too).
    public static let common: [(Int, Int)] = [(1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (21, 9)]

    public static func text(width: Int, height: Int, style: AspectRatioStyle) -> String? {
        guard width > 0, height > 0 else { return nil }
        let ratio = Double(width) / Double(height)
        let named = commonMatch(ratio)
        switch style {
        case .automatic:
            return named ?? decimal(ratio)
        case .commonOnly:
            return named
        case .decimal:
            return decimal(ratio)
        case .fraction:
            let g = gcd(width, height)
            let a = width / g, b = height / g
            return a <= 50 && b <= 50 ? "\(a):\(b)" : decimal(ratio)
        }
    }

    static func commonMatch(_ ratio: Double) -> String? {
        for (a, b) in common {
            if abs(ratio / (Double(a) / Double(b)) - 1) <= 0.01 { return "\(a):\(b)" }
            if a != b, abs(ratio / (Double(b) / Double(a)) - 1) <= 0.01 { return "\(b):\(a)" }
        }
        return nil
    }

    static func decimal(_ ratio: Double) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        return ratio >= 1
            ? "\(Readout.format(ratio, locale: posix)):1"
            : "1:\(Readout.format(1 / ratio, locale: posix))"
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }
}
