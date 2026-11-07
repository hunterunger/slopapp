import AppKit
import SlopKit
import SwiftUI
import TallyCore

/// The editor's colours. "System" follows the Mac's appearance and accent colour; the others
/// are Tally's own palettes (a deliberate design-system deviation: the original offers
/// themes, so we do too, with our own colours).
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    /// Forces the window's appearance (so scrollers, the find bar and the caret match); nil
    /// follows the system.
    let appearance: NSAppearance.Name?
    let background: NSColor
    let text: NSColor
    let number: NSColor
    let keyword: NSColor
    let unit: NSColor
    let variable: NSColor
    let label: NSColor
    let comment: NSColor
    let header: NSColor
    let result: NSColor
    let error: NSColor
    let caret: NSColor

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    func color(for kind: Highlighter.Kind) -> NSColor {
        switch kind {
        case .number: number
        case .keyword: keyword
        case .unit: unit
        case .variable: variable
        case .label: label
        case .comment: comment
        case .header: header
        }
    }

    var swiftUIBackground: Color { Color(nsColor: background) }

    /// The comment colour composited over the background: opaque, for controls AppKit draws
    /// with its own translucency on top (a menu's label).
    var opaqueComment: NSColor {
        let comment = comment, background = background
        return NSColor(name: nil) { appearance in
            var flat = comment
            appearance.performAsCurrentDrawingAppearance {
                flat = ReadableColor.flattened(comment, over: background.usingColorSpace(.sRGB) ?? background)
            }
            return flat
        }
    }
    var colorScheme: ColorScheme? {
        switch appearance {
        case .some(.darkAqua): .dark
        case .some(.aqua): .light
        default: nil
        }
    }

    /// Theme palettes are data (the user picks a theme), not UI colours.
    private static func hex(_ value: UInt32) -> NSColor { // lint:allow theme palette data
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Semantic colours only. The system pink, indigo, teal and the user's accent are
    /// darkened in light mode just enough to read as text (teal is about 2:1 on white
    /// otherwise, a yellow accent worse). Errors are quiet by size, not by a fainter colour.
    static let system = Theme(
        id: "system", name: "System", appearance: nil,
        background: .textBackgroundColor, text: .labelColor, number: .labelColor, keyword: .readable(.systemPink),
        unit: .readable(.systemIndigo), variable: .readable(.systemTeal), label: .secondaryLabelColor,
        comment: .secondaryLabelColor, header: .labelColor, result: .readable(.controlAccentColor),
        error: .secondaryLabelColor, caret: .controlAccentColor)

    /// Warm paper, ink-blue words, brick answers.
    static let paper = Theme(
        id: "paper", name: "Paper", appearance: .aqua,
        background: hex(0xF8F4EA), text: hex(0x3B362E), number: hex(0x1F1B16), keyword: hex(0x2F5DA8),
        unit: hex(0x7A5C2E), variable: hex(0x1C7C72), label: hex(0x71695A), comment: hex(0x746E62),
        header: hex(0x1F1B16), result: hex(0xB4462B), error: hex(0x7D7668), caret: hex(0xB4462B))

    /// Deep navy, periwinkle words, peach answers.
    static let midnight = Theme(
        id: "midnight", name: "Midnight", appearance: .darkAqua,
        background: hex(0x141A2B), text: hex(0xC9D1E6), number: hex(0xF2F5FC), keyword: hex(0x93A4FF),
        unit: hex(0xB9C2DE), variable: hex(0x6FD3C7), label: hex(0x7E88A4), comment: hex(0x7B849E),
        header: hex(0xF2F5FC), result: hex(0xFFB38A), error: hex(0x727C96), caret: hex(0xFFB38A))

    /// Plum dusk, rose words, lemon answers.
    static let dusk = Theme(
        id: "dusk", name: "Dusk", appearance: .darkAqua,
        background: hex(0x231A2E), text: hex(0xE4DAF0), number: hex(0xFFFFFF), keyword: hex(0xFF8FB8),
        unit: hex(0xC7B6E0), variable: hex(0x8FD0FF), label: hex(0x9485A7), comment: hex(0x8E81A0),
        header: hex(0xFFFFFF), result: hex(0xF5E27A), error: hex(0x877A99), caret: hex(0xF5E27A))

    /// Graphite with lilac words and amber answers: high contrast for long sheets.
    static let graphite = Theme(
        id: "graphite", name: "Graphite", appearance: .darkAqua,
        background: hex(0x1C1D1F), text: hex(0xD4D6DA), number: hex(0xFFFFFF), keyword: hex(0xC4A7FF),
        unit: hex(0xBBBFC6), variable: hex(0x7FD1B9), label: hex(0x878B92), comment: hex(0x82868C),
        header: hex(0xFFFFFF), result: hex(0xF2B84B), error: hex(0x7A7E84), caret: hex(0xF2B84B))

    // Contrast against the background (ThemeContrastTests): text, numbers, words and answers
    // at least 4.5:1; labels and comments 4.5:1; errors 4:1 (quiet, still readable).

    static let all: [Theme] = [system, paper, midnight, dusk, graphite]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? system
    }

    static var current: Theme { named(Pref.themeID) }
}
