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

/// The editor, for SwiftUI: a scroll view holding a `SheetTextView`.
struct SheetEditor: NSViewRepresentable {
    let model: SheetModel
    let textSizeStep: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SheetScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let textView = SheetTextView.make()
        let coordinator = context.coordinator
        coordinator.textView = textView
        let size = TextSize.pointSize(step: textSizeStep)
        coordinator.applySize(size)

        textView.textStorage?.delegate = coordinator.styler
        textView.delegate = coordinator
        textView.string = model.text
        coordinator.styler.styleAll(textView.textStorage!)
        textView.onResultClick = { [weak model] line in model?.resultClicked(line: line) }

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        model.editor = textView
        model.onResultsChange = { [weak coordinator] in coordinator?.resultsChanged() }
        coordinator.resultsChanged()

        // Start at the end of the sheet, ready to type.
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let size = TextSize.pointSize(step: textSizeStep)
        if context.coordinator.pointSize != size {
            context.coordinator.applySize(size)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: SheetModel
        let styler = SheetStyler(pointSize: 15)
        weak var textView: SheetTextView?
        private(set) var pointSize: CGFloat = 0

        init(model: SheetModel) {
            self.model = model
        }

        func applySize(_ size: CGFloat) {
            pointSize = size
            styler.setPointSize(size)
            guard let tv = textView else { return }
            tv.font = styler.font
            tv.typingAttributes = styler.baseAttributes
            tv.defaultParagraphStyle = styler.paragraph
            tv.resultFont = .monospacedDigitSystemFont(ofSize: size, weight: .medium)
            tv.errorFont = .systemFont(ofSize: (size * 0.87).rounded())
            if let storage = tv.textStorage { styler.styleAll(storage) }
            tv.layoutColumns()
            tv.apply(displays: model.displays)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            let start = ContinuousClock.now
            model.textDidChange(tv.string)
            PerfLog.keystroke(total: ContinuousClock.now - start, evaluation: model.lastEvaluationMillis, lines: model.lines.count)
        }

        func resultsChanged() {
            textView?.apply(displays: model.displays)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            // Keep typing attributes plain after styled lines (headers, comments).
            textView.typingAttributes = styler.baseAttributes
            return true
        }
    }
}
