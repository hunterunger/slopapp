import Foundation

/// Hue, saturation and lightness/brightness, rounded the way CSS tools show them:
/// whole degrees (360 wraps to 0) and whole percent.
public struct HSL: Equatable, Sendable {
    public var hue: Int
    public var saturation: Int
    public var lightness: Int
}

public struct HSB: Equatable, Sendable {
    public var hue: Int
    public var saturation: Int
    public var brightness: Int
}

extension RGB {
    /// Hue in degrees 0..<360 from clamped components; 0 for grays.
    var hueDegrees: Double {
        let c = clamped
        let maxV = Swift.max(c.red, c.green, c.blue)
        let minV = Swift.min(c.red, c.green, c.blue)
        let d = maxV - minV
        guard d > 0 else { return 0 }
        var h: Double
        if maxV == c.red {
            h = (c.green - c.blue) / d
        } else if maxV == c.green {
            h = (c.blue - c.red) / d + 2
        } else {
            h = (c.red - c.green) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }

    public var hsl: HSL {
        let c = clamped
        let maxV = Swift.max(c.red, c.green, c.blue)
        let minV = Swift.min(c.red, c.green, c.blue)
        let d = maxV - minV
        let l = (maxV + minV) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return HSL(hue: Self.wrapHue(hueDegrees), saturation: Self.percent(s), lightness: Self.percent(l))
    }

    public var hsb: HSB {
        let c = clamped
        let maxV = Swift.max(c.red, c.green, c.blue)
        let minV = Swift.min(c.red, c.green, c.blue)
        let s = maxV == 0 ? 0 : (maxV - minV) / maxV
        return HSB(hue: Self.wrapHue(hueDegrees), saturation: Self.percent(s), brightness: Self.percent(maxV))
    }

    static func wrapHue(_ h: Double) -> Int {
        let r = Int(h.rounded())
        return r >= 360 ? r - 360 : r
    }

    static func percent(_ v: Double) -> Int {
        Int((v.clamped01 * 100).rounded())
    }
}
