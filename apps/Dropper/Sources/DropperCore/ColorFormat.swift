import Foundation

/// The text formats a color can be copied as. Raw values are stored in preferences: never
/// rename one.
public enum ColorFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    // Web
    case hex
    case cssRGB
    case cssRGBA
    case cssHSL
    case cssHSLA
    case cssHWB
    case cssOKLCH
    case cssLab
    case cssLCH
    case cssDisplayP3
    case cssCMYK
    case hsb
    // Apple
    case swiftUI
    case swiftUIHSB
    case nsColor
    case nsColorHSB
    case uiColor
    case uiColorHSB
    case cgColor
    case objcNSColor
    case objcUIColor
    // Android and Flutter
    case androidARGB
    case androidXML
    case compose
    case flutter
    // Other
    case dotNetRGB
    case dotNetARGB
    case javaRGB
    case javaRGBA
    case unitRGB
    case unitRGBA

    public var id: String { rawValue }

    /// Name in menus and Settings ("Copy as Hex").
    public var title: String {
        switch self {
        case .hex: "Hex"
        case .cssRGB: "RGB"
        case .cssRGBA: "RGBA"
        case .cssHSL: "HSL"
        case .cssHSLA: "HSLA"
        case .cssHWB: "HWB"
        case .cssOKLCH: "OKLCH"
        case .cssLab: "Lab"
        case .cssLCH: "LCH"
        case .cssDisplayP3: "CSS Display P3"
        case .cssCMYK: "CMYK"
        case .hsb: "HSB"
        case .swiftUI: "SwiftUI"
        case .swiftUIHSB: "SwiftUI HSB"
        case .nsColor: "NSColor"
        case .nsColorHSB: "NSColor HSB"
        case .uiColor: "UIColor"
        case .uiColorHSB: "UIColor HSB"
        case .cgColor: "CGColor"
        case .objcNSColor: "NSColor (Objective-C)"
        case .objcUIColor: "UIColor (Objective-C)"
        case .androidARGB: "Android ARGB"
        case .androidXML: "Android XML"
        case .compose: "Jetpack Compose"
        case .flutter: "Flutter"
        case .dotNetRGB: ".NET RGB"
        case .dotNetARGB: ".NET ARGB"
        case .javaRGB: "Java RGB"
        case .javaRGBA: "Java RGBA"
        case .unitRGB: "Unit RGB (OpenGL)"
        case .unitRGBA: "Unit RGBA (OpenGL)"
        }
    }

    /// Which numbers a format reports.
    public enum SpaceRule: Sendable {
        /// The chosen output space (sRGB or Display P3).
        case output
        /// Always sRGB: the platform has no wide-color form of it.
        case sRGB
        /// Always Display P3.
        case displayP3
        /// A device-independent space (OKLCH, Lab): computed from the color as the chosen
        /// space shows it, so it matches the hex.
        case absolute
    }

    public var spaceRule: SpaceRule {
        switch self {
        case .cssDisplayP3: .displayP3
        case .cssOKLCH, .cssLab, .cssLCH: .absolute
        case .swiftUIHSB, .nsColorHSB, .uiColorHSB, .androidARGB, .androidXML, .compose, .flutter,
             .dotNetRGB, .dotNetARGB, .javaRGB, .javaRGBA:
            .sRGB
        default: .output
        }
    }

    /// Formats whose numbers depend on the chosen output space.
    public var followsOutputSpace: Bool {
        switch spaceRule {
        case .output, .absolute: true
        case .sRGB, .displayP3: false
        }
    }

    /// The space whose 8-bit grid the value is written from.
    public func space(for options: FormatOptions) -> OutputSpace {
        switch spaceRule {
        case .output, .absolute: options.space
        case .sRGB: .sRGB
        case .displayP3: .displayP3
        }
    }

    /// Groups, in menu order.
    public struct Group: Identifiable, Sendable {
        public var title: String
        public var formats: [ColorFormat]
        public var id: String { title }
    }

    public static let groups: [Group] = [
        Group(title: "Web", formats: [.hex, .cssRGB, .cssRGBA, .cssHSL, .cssHSLA, .cssHWB, .cssOKLCH, .cssLab, .cssLCH,
                                      .cssDisplayP3, .cssCMYK, .hsb]),
        Group(title: "Apple", formats: [.swiftUI, .swiftUIHSB, .nsColor, .nsColorHSB, .uiColor, .uiColorHSB, .cgColor,
                                        .objcNSColor, .objcUIColor]),
        Group(title: "Android and Flutter", formats: [.androidARGB, .androidXML, .compose, .flutter]),
        Group(title: "Other", formats: [.dotNetRGB, .dotNetARGB, .javaRGB, .javaRGBA, .unitRGB, .unitRGBA]),
    ]

    /// Short tag for compact lists ("CSS", "Swift").
    public var groupTitle: String {
        Self.groups.first { $0.formats.contains(self) }?.title ?? ""
    }
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
    /// `name` is used by formats that carry one (Android XML); it defaults to the color's
    /// plain name.
    public static func string(_ color: ColorValue, as format: ColorFormat, options: FormatOptions = .standard,
                              name: String? = nil) -> String {
        let space = format.space(for: options)
        let c = color.components(in: space).quantized
        let p3 = space == .displayP3
        let b = c.bytes
        let r = unit(c.red), g = unit(c.green), bl = unit(c.blue)
        switch format {
        case .hex:
            return hex(c, uppercase: options.hexUppercase, prefix: options.hexPrefix)
        case .cssRGB:
            return "rgb(\(b.red), \(b.green), \(b.blue))"
        case .cssRGBA:
            return "rgba(\(b.red), \(b.green), \(b.blue), 1)"
        case .cssHSL:
            let h = c.hsl
            return "hsl(\(h.hue), \(h.saturation)%, \(h.lightness)%)"
        case .cssHSLA:
            let h = c.hsl
            return "hsla(\(h.hue), \(h.saturation)%, \(h.lightness)%, 1)"
        case .cssHWB:
            let minV = min(c.red, c.green, c.blue), maxV = max(c.red, c.green, c.blue)
            return "hwb(\(c.hsl.hue) \(RGB.percent(minV))% \(RGB.percent(1 - maxV))%)"
        case .cssOKLCH:
            let lch = ColorMath.oklch(fromSRGB: absolute(c, from: space))
            return "oklch(\(number(lch.l * 100, 1))% \(number(lch.c, 3)) \(number(lch.h, 1)))"
        case .cssLab:
            let lab = ColorMath.lab(fromSRGB: absolute(c, from: space))
            return "lab(\(number(lab.l, 2))% \(number(lab.a, 2)) \(number(lab.b, 2)))"
        case .cssLCH:
            let lch = ColorMath.lch(fromSRGB: absolute(c, from: space))
            return "lch(\(number(lch.l, 2))% \(number(lch.c, 2)) \(number(lch.h, 2)))"
        case .cssDisplayP3:
            return "color(display-p3 \(r) \(g) \(bl))"
        case .cssCMYK:
            let k = c.cmyk
            return "device-cmyk(\(RGB.percent(k.c))% \(RGB.percent(k.m))% \(RGB.percent(k.y))% \(RGB.percent(k.k))%)"
        case .hsb:
            let h = c.hsb
            return "hsb(\(h.hue), \(h.saturation)%, \(h.brightness)%)"
        case .swiftUI:
            return p3 ? "Color(.displayP3, red: \(r), green: \(g), blue: \(bl))" : "Color(red: \(r), green: \(g), blue: \(bl))" // lint:allow generated SwiftUI code text, not a colour we draw
        case .swiftUIHSB:
            let h = c.hsbUnits
            return "Color(hue: \(unit(h.hue)), saturation: \(unit(h.saturation)), brightness: \(unit(h.brightness)))"
        case .nsColor:
            let rest = "green: \(g), blue: \(bl), alpha: 1"
            return p3 ? "NSColor(displayP3Red: \(r), \(rest))" : "NSColor(srgbRed: \(r), \(rest))"
        case .nsColorHSB:
            let h = c.hsbUnits
            return "NSColor(hue: \(unit(h.hue)), saturation: \(unit(h.saturation)), brightness: \(unit(h.brightness)), alpha: 1)"
        case .uiColor:
            let rest = "green: \(g), blue: \(bl), alpha: 1"
            return p3 ? "UIColor(displayP3Red: \(r), \(rest))" : "UIColor(red: \(r), \(rest))" // lint:allow generated UIKit code text, not a colour we draw
        case .uiColorHSB:
            let h = c.hsbUnits
            return "UIColor(hue: \(unit(h.hue)), saturation: \(unit(h.saturation)), brightness: \(unit(h.brightness)), alpha: 1)"
        case .cgColor:
            return p3
                ? "CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [\(r), \(g), \(bl), 1])!"
                : "CGColor(srgbRed: \(r), green: \(g), blue: \(bl), alpha: 1)"
        case .objcNSColor:
            return p3 ? "[NSColor colorWithDisplayP3Red:\(r) green:\(g) blue:\(bl) alpha:1]"
                : "[NSColor colorWithSRGBRed:\(r) green:\(g) blue:\(bl) alpha:1]"
        case .objcUIColor:
            return p3 ? "[UIColor colorWithDisplayP3Red:\(r) green:\(g) blue:\(bl) alpha:1]"
                : "[UIColor colorWithRed:\(r) green:\(g) blue:\(bl) alpha:1]"
        case .androidARGB:
            return "#" + argbDigits(c, uppercase: options.hexUppercase)
        case .androidXML:
            let resource = resourceName(name ?? ColorNamer.name(for: color))
            return "<color name=\"\(resource)\">#\(argbDigits(c, uppercase: options.hexUppercase))</color>"
        case .compose:
            return "Color(0x\(argbDigits(c, uppercase: true)))"
        case .flutter:
            return "Color.fromARGB(255, \(b.red), \(b.green), \(b.blue))"
        case .dotNetRGB:
            return "Color.FromArgb(\(b.red), \(b.green), \(b.blue))"
        case .dotNetARGB:
            return "Color.FromArgb(255, \(b.red), \(b.green), \(b.blue))"
        case .javaRGB:
            return "new Color(\(b.red), \(b.green), \(b.blue))"
        case .javaRGBA:
            return "new Color(\(b.red), \(b.green), \(b.blue), 255)"
        case .unitRGB:
            return "\(r), \(g), \(bl)"
        case .unitRGBA:
            return "\(r), \(g), \(bl), 1"
        }
    }

    public static func hex(_ c: RGB, uppercase: Bool = true, prefix: Bool = true) -> String {
        let b = c.bytes
        let digits = String(format: uppercase ? "%02X%02X%02X" : "%02x%02x%02x", b.red, b.green, b.blue)
        return prefix ? "#" + digits : digits
    }

    static func argbDigits(_ c: RGB, uppercase: Bool) -> String {
        (uppercase ? "FF" : "ff") + hex(c, uppercase: uppercase, prefix: false)
    }

    /// The color the quantized components describe, as extended sRGB.
    static func absolute(_ c: RGB, from space: OutputSpace) -> RGB {
        ColorValue(c, in: space).sRGB
    }

    /// "Dark Blue" → "dark_blue" (Android resource names).
    public static func resourceName(_ name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        let joined = words.joined(separator: "_")
        guard let first = joined.first else { return "color" }
        return first.isLetter ? joined : "color_" + joined
    }

    /// A 0...1 component with at most 3 decimals and no trailing zeros: 0.2, 0.333, 1, 0.
    public static func unit(_ value: Double) -> String {
        let rounded = (value.clamped01 * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        if rounded == 1 { return "1" }
        return number(rounded, 3)
    }

    /// `value` with at most `decimals` decimals, trailing zeros trimmed, never "-0".
    public static func number(_ value: Double, _ decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }
}
