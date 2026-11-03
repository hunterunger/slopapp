import Foundation

/// An sRGB color with alpha, components 0…1.
public struct RGBAColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value.isNaN ? 0 : value)) }

    var bytes: (Int, Int, Int, Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()), Int((alpha * 255).rounded()))
    }

    /// Hue 0…360, saturation and lightness 0…1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        return (hue(maxValue: maxValue, delta: delta), saturation, lightness)
    }

    /// Hue 0…360, saturation and brightness 0…1 (also called HSV).
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let delta = maxValue - minValue
        guard maxValue > 0 else { return (0, 0, 0) }
        return (delta > 0 ? hue(maxValue: maxValue, delta: delta) : 0, delta / maxValue, maxValue)
    }

    private func hue(maxValue: Double, delta: Double) -> Double {
        var hue: Double
        if maxValue == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return hue
    }

    public static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) -> RGBAColor {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b) = sector(h, c, x)
        return RGBAColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    public static func fromHSB(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> RGBAColor {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b) = sector(h, c, x)
        return RGBAColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    private static func sector(_ h: Double, _ c: Double, _ x: Double) -> (Double, Double, Double) {
        switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    public func contrast(with other: RGBAColor) -> Double {
        let a = luminance + 0.05, b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }
}

public enum ColorConverter {
    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unrecognized

        public var description: String {
            switch self {
            case .empty: "Type a color like #FF8800, rgb(255 136 0) or hsl(32 100% 50%)."
            case .unrecognized: "This isn't a color I recognize. Try #RGB, #RRGGBB, #RRGGBBAA, rgb(…), hsl(…) or hsb(…)."
            }
        }
    }

    public static func parse(_ text: String) throws -> RGBAColor {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        guard !trimmed.isEmpty else { throw ParseError.empty }
        let lower = trimmed.lowercased()
        if let color = parseHex(lower) { return color }
        if let open = lower.firstIndex(of: "("), lower.hasSuffix(")") {
            let name = lower[..<open].trimmingCharacters(in: .whitespaces)
            let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
            let parts = inner.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
                .split(separator: " ").map(String.init)
            guard parts.count == 3 || parts.count == 4 else { throw ParseError.unrecognized }
            let alpha = parts.count == 4 ? try fraction(parts[3]) : 1
            switch name {
            case "rgb", "rgba":
                return RGBAColor(red: try channel(parts[0]), green: try channel(parts[1]), blue: try channel(parts[2]), alpha: alpha)
            case "hsl", "hsla":
                return .fromHSL(hue: try degrees(parts[0]), saturation: try fraction(parts[1]), lightness: try fraction(parts[2]), alpha: alpha)
            case "hsb", "hsba", "hsv", "hsva":
                return .fromHSB(hue: try degrees(parts[0]), saturation: try fraction(parts[1]), brightness: try fraction(parts[2]), alpha: alpha)
            default:
                throw ParseError.unrecognized
            }
        }
        throw ParseError.unrecognized
    }

    static func parseHex(_ text: String) -> RGBAColor? {
        var body = Substring(text)
        if body.hasPrefix("#") { body = body.dropFirst() } else if body.hasPrefix("0x") { body = body.dropFirst(2) } else {
            // Bare hex only when it can't be anything else: 6 or 8 digits.
            guard body.count == 6 || body.count == 8 else { return nil }
        }
        guard [3, 4, 6, 8].contains(body.count), body.allSatisfy(\.isHexDigit) else { return nil }
        var digits = Array(body)
        if digits.count <= 4 { digits = digits.flatMap { [$0, $0] } }
        func byte(_ index: Int) -> Double { Double(Int(String(digits[index * 2...index * 2 + 1]), radix: 16)!) / 255 }
        return RGBAColor(red: byte(0), green: byte(1), blue: byte(2), alpha: digits.count == 8 ? byte(3) : 1)
    }

    static func number(_ text: String) throws -> Double {
        guard let value = Double(text), value.isFinite else { throw ParseError.unrecognized }
        return value
    }

    /// 0–255 or a percentage.
    static func channel(_ text: String) throws -> Double {
        if text.hasSuffix("%") { return try number(String(text.dropLast())) / 100 }
        return try number(text) / 255
    }

    /// 0–1 or a percentage.
    static func fraction(_ text: String) throws -> Double {
        if text.hasSuffix("%") { return try number(String(text.dropLast())) / 100 }
        let value = try number(text)
        return value > 1 ? value / 100 : value
    }

    static func degrees(_ text: String) throws -> Double {
        var body = text
        for unit in ["deg", "°"] where body.hasSuffix(unit) { body = String(body.dropLast(unit.count)) }
        if body.hasSuffix("turn") { return try number(String(body.dropLast(4))) * 360 }
        return try number(body)
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public static func rows(for color: RGBAColor) -> [Row] {
        let (r, g, b, a) = color.bytes
        let opaque = a == 255
        let hex = String(format: "#%02X%02X%02X", r, g, b) + (opaque ? "" : String(format: "%02X", a))
        let hsl = color.hsl
        let hsb = color.hsb
        func n(_ value: Double, _ digits: Int = 0) -> String {
            let text = String(format: "%.\(digits)f", value)
            return digits > 0 && text.contains(".") ? text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression) : text
        }
        let alpha = n(color.alpha, 2)
        func component(_ value: Double) -> String { String(format: "%.3f", value) }
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        return [
            Row("Hex", hex),
            Row("RGB", opaque ? "rgb(\(r) \(g) \(b))" : "rgb(\(r) \(g) \(b) / \(alpha))"),
            Row("RGB (legacy)", opaque ? "rgb(\(r), \(g), \(b))" : "rgba(\(r), \(g), \(b), \(alpha))"),
            Row("HSL", "hsl(\(n(hsl.hue)) \(n(hsl.saturation * 100))% \(n(hsl.lightness * 100))%" + (opaque ? ")" : " / \(alpha))")),
            Row("HSB", "hsb(\(n(hsb.hue)) \(n(hsb.saturation * 100))% \(n(hsb.brightness * 100))%" + (opaque ? ")" : " / \(alpha))")),
            Row("SwiftUI", "Color(red: \(component(color.red)), green: \(component(color.green)), blue: \(component(color.blue))" + (opaque ? ")" : ", opacity: \(component(color.alpha)))")),
            Row("AppKit", "NSColor(srgbRed: \(component(color.red)), green: \(component(color.green)), blue: \(component(color.blue)), alpha: \(component(color.alpha)))"),
            Row("Contrast", "\(n(color.contrast(with: white), 2)):1 on white, \(n(color.contrast(with: black), 2)):1 on black"),
        ]
    }

    /// True for text that is clearly a color literal: #hex or a CSS color function.
    public static func looksLikeColor(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("#") { return parseHex(lower) != nil }
        for prefix in ["rgb(", "rgba(", "hsl(", "hsla("] where lower.hasPrefix(prefix) {
            return (try? parse(text)) != nil
        }
        return false
    }
}
