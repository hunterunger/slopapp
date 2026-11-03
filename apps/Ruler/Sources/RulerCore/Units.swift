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

/// Turns pixel counts into readable numbers for one display.
public struct Readout: Sendable {
    public var scale: Double
    public var unit: MeasureUnit
    public var locale: Locale

    public init(scale: Double, unit: MeasureUnit, locale: Locale = .current) {
        self.scale = scale
        self.unit = unit
        self.locale = locale
    }

    /// The value in the chosen unit, to one decimal (points on Retina can be x.5).
    public func value(_ pixels: Int) -> Double {
        switch unit {
        case .pixels: Double(pixels)
        case .points: (Double(pixels) / max(scale, 0.01) * 10).rounded() / 10
        }
    }

    /// "100.5" (with the locale's decimal separator).
    public func number(_ pixels: Int) -> String {
        Self.format(value(pixels), locale: locale)
    }

    /// "100.5 pt"
    public func length(_ pixels: Int) -> String {
        "\(number(pixels)) \(unit.suffix)"
    }

    /// "200 × 120 pt"
    public func size(width: Int, height: Int) -> String {
        "\(number(width)) × \(number(height)) \(unit.suffix)"
    }

    /// "200 by 120 points", for VoiceOver.
    public func spokenSize(width: Int, height: Int) -> String {
        "\(number(width)) by \(number(height)) \(unit.spoken)"
    }

    static func format(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
    }
}

/// What Return / ⌘C put on the clipboard.
public enum CopyFormat: String, CaseIterable, Sendable, Identifiable {
    case plain
    case css
    case swiftUI

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: "Plain (200 × 120)"
        case .css: "CSS"
        case .swiftUI: "SwiftUI"
        }
    }

    /// Short name for menus.
    public var shortTitle: String {
        switch self {
        case .plain: "Plain"
        case .css: "CSS"
        case .swiftUI: "SwiftUI"
        }
    }

    /// The clipboard text for a width and height. Code formats always use "." decimals.
    public func text(width: Int, height: Int, readout: Readout) -> String {
        let code = Locale(identifier: "en_US_POSIX")
        let w = Readout.format(readout.value(width), locale: code)
        let h = Readout.format(readout.value(height), locale: code)
        switch self {
        case .plain:
            return "\(readout.number(width)) × \(readout.number(height))"
        case .css:
            return "width: \(w)px;\nheight: \(h)px;"
        case .swiftUI:
            return ".frame(width: \(w), height: \(h))"
        }
    }
}
