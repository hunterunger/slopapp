import AppKit
import SwiftUI
import TallyCore

/// Keeps the text view exactly as wide as the visible area.
final class SheetScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let doc = documentView else { return }
        let width = contentSize.width
        if abs(doc.frame.width - width) > 0.5 {
            doc.setFrameSize(NSSize(width: width, height: max(doc.frame.height, contentSize.height)))
        }
    }
}

/// The editor, for SwiftUI: a scroll view holding a `SheetTextView` that shows the model's
/// current sheet. Several can be open at once (the window and the menu bar panel); they
/// share the sheet's text storage.
struct SheetEditor: NSViewRepresentable {
    let model: SheetModel
    /// Gets keyboard focus when it appears.
    var focusOnAppear = true

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SheetScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let textView = SheetTextView.make()
        let coordinator = context.coordinator
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.baseAttributes = model.styler.baseAttributes
        textView.onResultClick = { [weak model] line in model?.resultClicked(line: line) }
        textView.variableNames = { [weak model] in model?.current.variableNames ?? [] }
        textView.suggestsInline = { Pref.isSuggestingNames }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        model.register(textView)

        if focusOnAppear {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        // Theme or size changed: the model already restyled; refresh the view's own settings.
        if tv.theme != model.theme || tv.font?.pointSize != model.pointSize {
            tv.baseAttributes = model.styler.baseAttributes
            tv.applyTheme(model.theme, pointSize: model.pointSize)
            tv.apply(displays: model.displays)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let tv = coordinator.textView { coordinator.model.unregister(tv) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: SheetModel
        weak var textView: SheetTextView?

        init(model: SheetModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            let start = ContinuousClock.now
            model.storageDidChange()
            PerfLog.keystroke(total: ContinuousClock.now - start, evaluation: model.lastEvaluationMillis, lines: model.lines.count)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            model.selectionChanged(tv.selectedRange(), lineStarts: tv.lineStarts)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            model.current.undoManager
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            // Keep typing attributes plain after styled lines (headers, comments).
            textView.typingAttributes = model.styler.baseAttributes
            return true
        }
    }
}
