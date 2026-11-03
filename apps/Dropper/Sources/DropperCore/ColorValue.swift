import Foundation

/// The output color spaces Dropper can report values in.
public enum OutputSpace: String, CaseIterable, Codable, Sendable, Identifiable {
    case sRGB
    case displayP3

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        }
    }
}

/// Three color components in some RGB space, gamma-encoded (the numbers apps show).
public struct RGB: Equatable, Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var components: [Double] { [red, green, blue] }

    /// Each component clamped to 0...1.
    public var clamped: RGB {
        RGB(red: red.clamped01, green: green.clamped01, blue: blue.clamped01)
    }

    /// Each component rounded to the nearest of 256 steps (what hex shows), after clamping.
    public var bytes: (red: Int, green: Int, blue: Int) {
        (Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    /// The color snapped to 8 bits per channel, as 0...1 components. Every format is written
    /// from this so that, say, the hex and the SwiftUI value of one pick describe the same color.
    public var quantized: RGB {
        let b = bytes
        return RGB(red: Double(b.red) / 255, green: Double(b.green) / 255, blue: Double(b.blue) / 255)
    }

    static func byte(_ value: Double) -> Int {
        Int((value.clamped01 * 255).rounded())
    }
}

/// A picked or typed color. Stored as extended sRGB: components may fall outside 0...1 when
/// the color is more vivid than sRGB can show (a Display P3 red is about (1.09, -0.23, -0.15)).
public struct ColorValue: Equatable, Hashable, Codable, Sendable {
    /// Extended-range, gamma-encoded sRGB.
    public var sRGB: RGB

    public init(sRGB: RGB) {
        self.sRGB = sRGB
    }

    public init(red: Double, green: Double, blue: Double) {
        self.init(sRGB: RGB(red: red, green: green, blue: blue))
    }

    /// A color given in Display P3 components.
    public init(displayP3: RGB) {
        self.init(sRGB: ColorMath.p3ToSRGB(displayP3))
    }

    public init(_ components: RGB, in space: OutputSpace) {
        switch space {
        case .sRGB: self.init(sRGB: components)
        case .displayP3: self.init(displayP3: components)
        }
    }

    /// Display P3 components (unclamped).
    public var displayP3: RGB { ColorMath.sRGBToP3(sRGB) }

    /// The components to report in `space`, unclamped.
    public func components(in space: OutputSpace) -> RGB {
        switch space {
        case .sRGB: sRGB
        case .displayP3: displayP3
        }
    }

    /// How far outside 0...1 a component may land before we call the color out of gamut.
    /// Sampling and color-matching add noise of about 0.0003; half an 8-bit step is 0.002.
    public static let gamutTolerance = 0.5 / 255

    /// True when sRGB can't show this color (hex and rgb() values are clamped).
    public var isOutsideSRGB: Bool {
        sRGB.components.contains { $0 < -Self.gamutTolerance || $0 > 1 + Self.gamutTolerance }
    }

    /// True when reporting in `space` has to clamp the color.
    public func isOutside(_ space: OutputSpace) -> Bool {
        components(in: space).components.contains { $0 < -Self.gamutTolerance || $0 > 1 + Self.gamutTolerance }
    }

    /// Identity for de-duplicating history: same 8-bit color, including how far out of sRGB
    /// it is (so a P3 red and sRGB red stay separate).
    public var identityKey: [Int] {
        sRGB.components.map { Int(($0 * 255).rounded()) }
    }
}

/// sRGB and Display P3 share the D65 white point and the sRGB transfer curve, so converting
/// is: decode the curve, multiply by a 3×3 matrix, encode the curve. Negative and >1 values
/// are mirrored through the curve (the "extended" convention ColorSync uses).
public enum ColorMath {
    // Linear sRGB -> linear Display P3, and back (D65; CSS Color 4 values).
    static let sRGBToP3Matrix: [[Double]] = [
        [0.8224619687143623, 0.17753803128563775, 0],
        [0.0331941988509616, 0.9668058011490384, 0],
        [0.017082630205428403, 0.07239744066396348, 0.9105199291306081],
    ]
    static let p3ToSRGBMatrix: [[Double]] = [
        [1.2249401762805598, -0.22494017628055996, 0],
        [-0.04205695470968816, 1.0420569547096882, 0],
        [-0.019637554590334432, -0.07863604555063184, 1.0982736001409663],
    ]

    public static func sRGBToP3(_ c: RGB) -> RGB {
        encode(multiply(sRGBToP3Matrix, decode(c)))
    }

    public static func p3ToSRGB(_ c: RGB) -> RGB {
        encode(multiply(p3ToSRGBMatrix, decode(c)))
    }

    /// The sRGB transfer curve, gamma-encoded -> linear.
    public static func linear(_ v: Double) -> Double {
        let a = abs(v)
        let l = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return v < 0 ? -l : l
    }

    /// Linear -> gamma-encoded.
    public static func gamma(_ v: Double) -> Double {
        let a = abs(v)
        let g = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return v < 0 ? -g : g
    }

    static func decode(_ c: RGB) -> [Double] { c.components.map(linear) }

    static func encode(_ v: [Double]) -> RGB {
        RGB(red: gamma(v[0]), green: gamma(v[1]), blue: gamma(v[2]))
    }

    static func multiply(_ m: [[Double]], _ v: [Double]) -> [Double] {
        m.map { row in row[0] * v[0] + row[1] * v[1] + row[2] * v[2] }
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
