import Foundation

/// WCAG 2.x contrast. Colors are compared in sRGB (clamped, 8-bit), as the standard defines.
public enum Contrast {
    /// Relative luminance, 0 (black) ... 1 (white).
    public static func luminance(_ color: ColorValue) -> Double {
        let c = color.sRGB.quantized
        return 0.2126 * ColorMath.linear(c.red) + 0.7152 * ColorMath.linear(c.green) + 0.0722 * ColorMath.linear(c.blue)
    }

    /// 1 ... 21, order doesn't matter.
    public static func ratio(_ a: ColorValue, _ b: ColorValue) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// "4.62:1". Truncated, never rounded up, so a failing 4.499 can't show as 4.50.
    public static func formatted(_ ratio: Double) -> String {
        // The epsilon keeps 7.0 (stored as 6.9999999) from showing as 6.99.
        let truncated = (ratio * 100 + 1e-9).rounded(.down) / 100
        return String(format: "%.2f:1", locale: Locale(identifier: "en_US_POSIX"), truncated)
    }
}

/// One WCAG success criterion check, e.g. "Normal text, AA, needs 4.5:1".
public struct ContrastCheck: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case normalText, largeText, uiComponents }
    public enum Level: String, Sendable { case aa = "AA", aaa = "AAA" }

    public var kind: Kind
    public var level: Level
    public var minimum: Double
    public var passes: Bool

    public var id: String { "\(kind.rawValue)-\(level.rawValue)" }

    public var title: String {
        switch kind {
        case .normalText: "Normal text"
        case .largeText: "Large text"
        case .uiComponents: "Interface elements"
        }
    }
}

public struct ContrastReport: Equatable, Sendable {
    public var ratio: Double
    public var checks: [ContrastCheck]

    public init(text: ColorValue, background: ColorValue) {
        let ratio = Contrast.ratio(text, background)
        self.ratio = ratio
        let rules: [(ContrastCheck.Kind, ContrastCheck.Level, Double)] = [
            (.normalText, .aa, 4.5), (.normalText, .aaa, 7),
            (.largeText, .aa, 3), (.largeText, .aaa, 4.5),
            (.uiComponents, .aa, 3),
        ]
        checks = rules.map { ContrastCheck(kind: $0.0, level: $0.1, minimum: $0.2, passes: ratio >= $0.2) }
    }

    public var formattedRatio: String { Contrast.formatted(ratio) }

    /// A plain-text summary for the clipboard.
    public func summary(text: String, background: String) -> String {
        var lines = ["Contrast \(formattedRatio) (\(text) on \(background))"]
        for check in checks {
            lines.append("\(check.title) \(check.level.rawValue): \(check.passes ? "Pass" : "Fail")")
        }
        return lines.joined(separator: "\n")
    }
}
