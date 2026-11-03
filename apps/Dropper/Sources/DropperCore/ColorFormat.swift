import Foundation

/// The text formats a color can be copied as.
public enum ColorFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case hex
    case cssRGB
    case cssHSL
    case hsb
    case swiftUI
    case nsColor
    case uiColor
    case cssDisplayP3

    public var id: String { rawValue }

    /// Name in menus and Settings ("Copy as Hex").
    public var title: String {
        switch self {
        case .hex: "Hex"
        case .cssRGB: "RGB"
        case .cssHSL: "HSL"
        case .hsb: "HSB"
        case .swiftUI: "SwiftUI"
        case .nsColor: "NSColor"
        case .uiColor: "UIColor"
        case .cssDisplayP3: "CSS Display P3"
        }
    }

    /// Formats whose numbers depend on the chosen output space. CSS Display P3 is always P3.
    public var followsOutputSpace: Bool { self != .cssDisplayP3 }
}

/// Everything that changes how a color is written out.
public struct FormatOptions: Equatable, Codable, Sendable {
    public var space: OutputSpace
    public var hexUppercase: Bool
    public var hexPrefix: Bool

    public init(space: OutputSpace = .sRGB, hexUppercase: Bool = true, hexPrefix: Bool = true) {
        self.space = space
        self.hexUppercase = hexUppercase
        self.hexPrefix = hexPrefix
    }

    public static let standard = FormatOptions()
}

public enum ColorFormatter {
    /// The color as text in `format`. Numbers always use "." decimals, whatever the locale.
    public static func string(_ color: ColorValue, as format: ColorFormat, options: FormatOptions = .standard) -> String {
        let space = format.followsOutputSpace ? options.space : .displayP3
        let c = color.components(in: space).quantized
        let p3 = space == .displayP3
        switch format {
        case .hex:
            return hex(c, uppercase: options.hexUppercase, prefix: options.hexPrefix)
        case .cssRGB:
            let b = c.bytes
            return "rgb(\(b.red), \(b.green), \(b.blue))"
        case .cssHSL:
            let h = c.hsl
            return "hsl(\(h.hue), \(h.saturation)%, \(h.lightness)%)"
        case .hsb:
            let h = c.hsb
            return "hsb(\(h.hue), \(h.saturation)%, \(h.brightness)%)"
        case .swiftUI:
            let args = "red: \(unit(c.red)), green: \(unit(c.green)), blue: \(unit(c.blue))"
            return p3 ? "Color(.displayP3, \(args))" : "Color(red: \(unit(c.red)), green: \(unit(c.green)), blue: \(unit(c.blue)))"
        case .nsColor:
            let rest = "green: \(unit(c.green)), blue: \(unit(c.blue)), alpha: 1"
            return p3 ? "NSColor(displayP3Red: \(unit(c.red)), \(rest))" : "NSColor(srgbRed: \(unit(c.red)), \(rest))"
        case .uiColor:
            let rest = "green: \(unit(c.green)), blue: \(unit(c.blue)), alpha: 1"
            return p3 ? "UIColor(displayP3Red: \(unit(c.red)), \(rest))" : "UIColor(red: \(unit(c.red)), \(rest))"
        case .cssDisplayP3:
            return "color(display-p3 \(unit(c.red)) \(unit(c.green)) \(unit(c.blue)))"
        }
    }

    public static func hex(_ c: RGB, uppercase: Bool = true, prefix: Bool = true) -> String {
        let b = c.bytes
        let digits = String(format: uppercase ? "%02X%02X%02X" : "%02x%02x%02x", b.red, b.green, b.blue)
        return prefix ? "#" + digits : digits
    }

    /// A 0...1 component with at most 3 decimals and no trailing zeros: 0.2, 0.333, 1, 0.
    public static func unit(_ value: Double) -> String {
        let rounded = (value.clamped01 * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        if rounded == 1 { return "1" }
        var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
