import AppKit
import SlopKit
import Testing
@testable import Tally
@testable import TallyCore

/// Polish pass: every theme's text reads against its background, and results line up with
/// their lines.
@MainActor @Suite struct ThemeContrast {
    /// The roles a theme draws as text, with the contrast each needs.
    static let roles: [(String, KeyPath<Theme, NSColor>, CGFloat)] = [
        ("text", \.text, 4.5), ("number", \.number, 4.5), ("keyword", \.keyword, 4.5),
        ("unit", \.unit, 4.5), ("variable", \.variable, 4.5), ("header", \.header, 4.5), ("result", \.result, 4.5),
        // Labels and comments are secondary text: at least the system's secondary label
        // colour (about 3.95:1, the floor the design system accepts). Our palettes give 4.6.
        ("label", \.label, 3.9), ("comment", \.comment, 3.9),
        // Errors are quiet (smaller type) but still readable: the system's secondary label
        // colour, the floor the design system accepts, is about 3.9:1 here.
        ("error", \.error, 3.8),
    ]

    func check(_ theme: Theme, appearance: NSAppearance.Name) {
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let background = theme.background.usingColorSpace(.sRGB)!
            for (name, path, target) in Self.roles {
                let colour = ReadableColor.flattened(theme[keyPath: path], over: background)
                let ratio = ReadableColor.ratio(colour, background)
                #expect(ratio >= target, "\(theme.name) \(appearance.rawValue) \(name): \(ratio)")
            }
        }
    }

    @Test func palettesPass() {
        for theme in Theme.all where theme.id != Theme.system.id {
            check(theme, appearance: theme.appearance ?? .aqua)
        }
    }

    @Test func systemThemePassesInLightAndDark() {
        check(.system, appearance: .aqua)
        check(.system, appearance: .darkAqua)
    }

    @Test func readableTextDarkensOnlyAsMuchAsNeeded() {
        let white = NSColor.white
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        let fixed = ReadableColor.adjusted(yellow, toReach: 4.5, on: white, towards: .black)
        #expect(ReadableColor.ratio(fixed, white) >= 4.5)
        // Already dark enough: unchanged.
        let ink = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.3, alpha: 1)
        #expect(ReadableColor.adjusted(ink, toReach: 4.5, on: white, towards: .black) == ink)
    }
}

@MainActor @Suite(.serialized) struct ResultLayout {
    func editor(_ text: String) -> (SheetModel, SheetTextView) {
        let model = SheetModel(libraryStorage: MemorySheetStorage(text), ratesStorage: EmptyRatesStorage(),
                               fetcher: NoNetwork(), clipboard: FakeClipboard())
        let view = SheetTextView.make()
        view.setFrameSize(NSSize(width: 500, height: 400))
        model.register(view)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        return (model, view)
    }

    /// Where the text column draws its baseline for `line`, in the results view.
    func resultBaseline(_ view: SheetTextView, _ line: Int) -> CGFloat? {
        guard let display = view.displays[line], let rect = view.resultsView.resultRect(line) else { return nil }
        let font = display.kind == .value ? view.resultFont : view.errorFont
        return rect.minY + view.baselineOffset(for: font)
    }

    @Test func valuesAndErrorsShareTheLinesBaseline() throws {
        let (_, view) = editor("2 + 3\n5 kg + 3 m\nprice * qty\n# Header\n10 km in mi")
        for line in [0, 1, 2, 4] {
            let text = try #require(view.baseline(ofLine: line))
            let result = try #require(resultBaseline(view, line))
            #expect(abs(text - result) < 0.01, "line \(line): text \(text), result \(result)")
        }
    }

    @Test func longResultsTruncateInTheMiddleAndSayWhy() throws {
        let (_, view) = editor("fromunix(1446587186)\n2 + 2")
        view.setFrameSize(NSSize(width: 220, height: 400))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        #expect(view.resultsView.isTruncated(0))
        #expect(!view.resultsView.isTruncated(1))
        let tip = try #require(view.resultsView.toolTip(for: 0))
        #expect(tip.hasPrefix(try #require(view.displays[0]).text))
    }
}
