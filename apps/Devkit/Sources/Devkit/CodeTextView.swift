import AppKit
import SwiftUI

// A plain-text code editor/viewer for SwiftUI: monospaced, no smart quotes or spelling
// fixes, find bar, undo, placeholder, and fast highlighting through temporary attributes
// (TextKit 1, so 50 MB documents stay responsive). Candidate for SlopKit.

/// Lets a model act on the editor it feeds: undoable whole-text replacement, focus, selection.
@MainActor
final class EditorHandle {
    fileprivate weak var textView: NSTextView?

    var isAttached: Bool { textView?.window != nil }

    /// Replaces the whole text as one undoable edit. Returns false when no editor is showing.
    @discardableResult
    func replaceAll(with text: String, actionName: String) -> Bool {
        guard let textView, textView.isEditable, textView.window != nil, approximateSize(text) <= LargeText.limit else { return false }
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        guard textView.shouldChangeText(in: range, replacementString: text) else { return false }
        textView.textStorage?.replaceCharacters(in: range, with: CodeTextView.attributed(text))
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        return true
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Selects a UTF-8 byte offset (as JSON errors report) and scrolls to it.
    func revealUTF8Offset(_ offset: Int) {
        guard let textView else { return }
        let string = textView.string
        let utf8 = string.utf8
        let index = utf8.index(utf8.startIndex, offsetBy: min(offset, utf8.count), limitedBy: utf8.endIndex) ?? utf8.endIndex
        let location = string.utf16.distance(from: string.utf16.startIndex, to: index)
        let length = location < (string as NSString).length ? 1 : 0
        let range = NSRange(location: location, length: length)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }
}

/// A styled range: foreground or background color applied without touching the text.
struct TextStyleRun: Equatable {
    enum Style: Equatable {
        case key, string, number, keyword
        case match(Int)
        case added, removed
        case addedStrong, removedStrong
        case hunkHeader
    }

    var range: NSRange
    var style: Style
}

struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var placeholder = ""
    var accessibilityLabel: String
    var handle: EditorHandle?
    var styles: [TextStyleRun] = []
    /// Changes whenever `styles` changes, so they're only re-applied when needed.
    var stylesVersion = 0
    var wraps = true
    /// Called with a dropped file; when nil, dropped text files are loaded into the editor.
    var onFileDrop: ((URL) -> Void)?
    /// Pasted or dropped text too large to edit comfortably goes here instead of the editor.
    var onLargeText: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CodeNSTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wraps
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.widthTracksTextView = wraps
            if !wraps { container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) }
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wraps
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.coordinator = context.coordinator
        apply(to: textView, coordinator: context.coordinator, initial: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeNSTextView else { return }
        context.coordinator.text = $text
        apply(to: textView, coordinator: context.coordinator, initial: false)
    }

    private func apply(to textView: CodeNSTextView, coordinator: Coordinator, initial: Bool) {
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.placeholder = placeholder
        textView.onFileDrop = onFileDrop
        textView.onLargeText = onLargeText
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityPlaceholderValue(placeholder.isEmpty ? nil : placeholder)
        handle?.textView = textView
        // Only push text into the view when the model changed it (not on every keystroke).
        // Editors never take huge text: InputEditor swaps in a summary for that, and this view
        // may get one last update before it's removed.
        let tooLarge = isEditable && approximateSize(text) > LargeText.limit
        if !tooLarge, initial || text != coordinator.lastText {
            coordinator.lastText = text
            if !initial, isEditable {
                // The model changed the text (swap, undo of a field, file open): make it an
                // ordinary undoable edit so the text view's undo history stays consistent.
                let range = NSRange(location: 0, length: (textView.string as NSString).length)
                if textView.shouldChangeText(in: range, replacementString: text) {
                    textView.textStorage?.replaceCharacters(in: range, with: Self.attributed(text))
                    textView.didChangeText()
                }
            } else {
                let selection = textView.selectedRanges
                textView.string = text
                let length = (text as NSString).length
                textView.selectedRanges = selection.compactMap { value in
                    let range = value.rangeValue
                    return range.location <= length ? NSValue(range: NSRange(location: range.location, length: min(range.length, length - range.location))) : nil
                }.nilIfEmpty ?? [NSValue(range: NSRange(location: 0, length: 0))]
            }
            coordinator.appliedStylesVersion = -1
        }
        if coordinator.appliedStylesVersion != stylesVersion {
            coordinator.appliedStylesVersion = stylesVersion
            applyStyles(to: textView)
        }
        textView.needsDisplay = true
    }

    private func applyStyles(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        let whole = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        for run in styles {
            guard run.range.location + run.range.length <= length else { continue }
            let (key, color) = Self.attribute(for: run.style)
            layoutManager.addTemporaryAttribute(key, value: color, forCharacterRange: run.range)
        }
    }

    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    /// Plain text in the editor's font, for replacing the storage directly.
    static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    static func attribute(for style: TextStyleRun.Style) -> (NSAttributedString.Key, NSColor) {
        switch style {
        case .key: (.foregroundColor, SyntaxColor.key)
        case .string: (.foregroundColor, SyntaxColor.string)
        case .number: (.foregroundColor, SyntaxColor.number)
        case .keyword: (.foregroundColor, SyntaxColor.keyword)
        case let .match(index):
            (.backgroundColor, NSColor.controlAccentColor.withAlphaComponent(index.isMultiple(of: 2) ? 0.28 : 0.16))
        case .added: (.backgroundColor, NSColor.systemGreen.withAlphaComponent(0.16))
        case .removed: (.backgroundColor, NSColor.systemRed.withAlphaComponent(0.16))
        case .addedStrong: (.backgroundColor, NSColor.systemGreen.withAlphaComponent(0.4))
        case .removedStrong: (.backgroundColor, NSColor.systemRed.withAlphaComponent(0.4))
        case .hunkHeader: (.foregroundColor, .secondaryLabelColor)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastText = ""
        var appliedStylesVersion = -1
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let value = textView.string
            lastText = value
            text.wrappedValue = value
        }
    }
}

extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

/// Draws a placeholder and takes file drops.
final class CodeNSTextView: NSTextView {
    var placeholder = "" {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }

    var onFileDrop: ((URL) -> Void)?
    var onLargeText: ((String) -> Void)?
    weak var coordinator: CodeTextView.Coordinator?

    // Huge pastes would make the layout manager hold glyphs for every character (gigabytes
    // for 50 MB). Hand them to the model, which shows a summary instead of the text.
    override func paste(_ sender: Any?) {
        if let onLargeText, let text = NSPasteboard.general.string(forType: .string), approximateSize(text) > LargeText.limit {
            onLargeText(text)
            return
        }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        let width = bounds.width - origin.x * 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? CodeTextView.font,
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        (placeholder as NSString).draw(with: NSRect(x: origin.x, y: origin.y, width: max(0, width), height: bounds.height),
                                      options: [.usesLineFragmentOrigin], attributes: attributes)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    // MARK: File drops

    private func droppedFile(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFile(sender) != nil, isEditable || onFileDrop != nil { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFile(sender) != nil, isEditable || onFileDrop != nil { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedFile(sender) else { return super.performDragOperation(sender) }
        if let onFileDrop {
            onFileDrop(url)
            return true
        }
        guard isEditable else { return false }
        if let onLargeText, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > LargeText.limit,
           let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            onLargeText(text)
            return true
        }
        return loadTextFile(url)
    }

    /// Replaces the text with a dropped UTF-8 text file (undoable).
    private func loadTextFile(_ url: URL) -> Bool {
        let maximum = 100 * 1024 * 1024
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximum,
              let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            NSSound.beep()
            return false
        }
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: range, replacementString: text) else { return false }
        textStorage?.replaceCharacters(in: range, with: CodeTextView.attributed(text))
        didChangeText()
        undoManager?.setActionName("Open File")
        return true
    }
}

enum LargeText {
    /// Inputs above this size (UTF-8 bytes, roughly) aren't shown in an editor.
    static let limit = 8 * 1024 * 1024
}

/// The highlight theme: system colours, darkened in light mode so they read as body text on
/// the editor background (measured on textBackgroundColor: systemBlue 3.5:1, systemRed 3.6:1,
/// systemPurple 4.2:1 and systemPink 3.7:1 in light mode; 5.8–6.6:1 darkened by 30%). Dark mode
/// keeps the system colours (4.6–5.2:1). Dynamic, so they follow an appearance change live.
enum SyntaxColor {
    static let lightModeDarkening: CGFloat = 0.3

    static let key = readable(.systemBlue)
    static let string = readable(.systemRed)
    static let number = readable(.systemPurple)
    static let keyword = readable(.systemPink)

    static func readable(_ base: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua else { return base }
            var resolved = base
            appearance.performAsCurrentDrawingAppearance { resolved = base.usingColorSpace(.sRGB) ?? base }
            return resolved.blended(withFraction: lightModeDarkening, of: .black) ?? resolved
        }
    }
}
