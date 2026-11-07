import AppKit
import FocusCore

/// The menu bar item: a symbol, plus the time left while a phase runs.
///
/// Drawn as one template image so the digits can be monospaced (the item doesn't shift
/// sideways as they change) and macOS tints it for light, dark and the selected state.
@MainActor
enum StatusImage {
    enum Symbol: String {
        case idle = "stopwatch"
        case focus = "stopwatch.fill"
        case rest = "leaf.fill"
        case paused = "pause.circle"
        case attention = "bell.fill"
    }

    static func symbol(for controller: FocusController) -> Symbol {
        if controller.isFlashing { return .attention }
        guard let phase = controller.runningPhase else { return .idle }
        if controller.isPaused { return .paused }
        return phase.isBreak ? .rest : .focus
    }

    static func make(_ symbol: Symbol, text: String?) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize + 1, weight: .regular)
        let glyph = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let glyphSize = glyph.size
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        // Width reserved for the widest text of the same shape ("9m" reserves "00m", "9:59"
        // reserves "00:00"), so the item doesn't narrow when 10m becomes 9m and push the
        // menu bar items to its left.
        let textSize = text.map { (TimeText.widthTemplate(for: $0) as NSString).size(withAttributes: attributes) } ?? .zero
        let gap: CGFloat = text == nil ? 0 : 4
        let height = ceil(max(glyphSize.height, font.ascender - font.descender))
        let width = ceil(glyphSize.width + gap + textSize.width)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            glyph.draw(in: NSRect(x: 0, y: (height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height))
            if let text {
                // Centre the digits' cap height on the symbol's middle.
                let baseline = (height - font.capHeight) / 2
                (text as NSString).draw(at: NSPoint(x: glyphSize.width + gap, y: baseline + font.descender), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
