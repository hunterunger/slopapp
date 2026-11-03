import AppKit
import SwiftUI

// A single-line text field for code-like values: monospaced, no autocorrect or smart
// quotes, and, unlike SwiftUI's TextField, it notices when assistive technology sets its
// value (VoiceOver, Voice Control, automation). Candidate for SlopKit.

struct CodeField: NSViewRepresentable {
    enum Size { case regular, large }

    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var size: Size = .regular
    /// Take keyboard focus when first shown.
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> AXNotifyingTextField {
        let field = AXNotifyingTextField()
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.onAccessibilityValueChange = { [weak coordinator = context.coordinator] value in
            coordinator?.commit(value)
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if focusOnAppear {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        update(field, context: context)
        return field
    }

    func updateNSView(_ field: AXNotifyingTextField, context: Context) {
        context.coordinator.text = $text
        update(field, context: context)
    }

    private func update(_ field: AXNotifyingTextField, context: Context) {
        let pointSize = size == .large ? NSFont.preferredFont(forTextStyle: .title3).pointSize : NSFont.systemFontSize
        let font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        if field.font != font { field.font = font }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(accessibilityLabel)
        if field.stringValue != text, field.currentEditor() == nil || context.coordinator.lastCommitted != text {
            field.stringValue = text
            context.coordinator.lastCommitted = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastCommitted = ""

        init(text: Binding<String>) {
            self.text = text
        }

        func commit(_ value: String) {
            lastCommitted = value
            if text.wrappedValue != value { text.wrappedValue = value }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commit(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Esc while editing: leave the field rather than clearing it.
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

final class AXNotifyingTextField: NSTextField {
    var onAccessibilityValueChange: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isAutomaticTextCompletionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        super.setAccessibilityValue(accessibilityValue)
        if let value = accessibilityValue as? String {
            stringValue = value
            onAccessibilityValueChange?(value)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // Plain-text editing: no smart quotes, dashes or spelling fixes in code values.
        if became, let editor = currentEditor() as? NSTextView {
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
        }
        return became
    }
}
