import PDFKit
import PaperCore
import SlopKit
import SwiftUI

struct HeaderActions {
    var applyRedactions: () -> Void
    var removeMarks: () -> Void
    var setColor: (InkColor) -> Void
    var setLineWidth: (CGFloat) -> Void
    var setFontSize: (CGFloat) -> Void
    var setFill: (Bool) -> Void
    var setMarkupStyle: (MarkupStyle) -> Void
    var setShape: (ShapeKind) -> Void
    var deleteSelection: () -> Void
    var editSelection: () -> Void
    var toggleFields: () -> Void
    var duplicate: () -> Void
}

/// Slim bars above the page: document notices, then the style strip for the current tool
/// or selected annotation. Empty (zero height) when there's nothing to say.
struct CanvasHeader: View {
    @Bindable var model: DocumentModel
    let actions: HeaderActions

    var body: some View {
        VStack(spacing: 0) {
            if model.isLocked {
                EmptyView()
            } else {
                notices
                if let style = styleContext {
                    StyleStrip(model: model, context: style, actions: actions)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if model.facts.isReadOnly {
            InfoBar(symbol: "lock", text: "This PDF has restrictions set by its owner, so Paper opens it read-only and won't change it.")
        }
        if model.facts.hasXFA {
            InfoBar(symbol: "exclamationmark.triangle", text: "This is a dynamic (XFA) form. It may only work in Adobe Acrobat Reader.")
        }
        if model.facts.hasDigitalSignature, !model.facts.isReadOnly {
            InfoBar(symbol: "checkmark.seal", text: "This PDF is digitally signed. Saving changes will invalidate the signature.") {
                Button("Duplicate", action: actions.duplicate)
            }
        } else if model.facts.isPDFA, !model.facts.isReadOnly {
            InfoBar(symbol: "archivebox", text: "This is an archival (PDF/A) file. Saving changes may break its archival format.") {
                Button("Duplicate", action: actions.duplicate)
            }
        }
        if model.importedRedactions > 0, !model.dismissedImportNotice {
            InfoBar(symbol: "exclamationmark.shield",
                    text: "\(model.importedRedactions == 1 ? "1 redaction was" : "\(model.importedRedactions) redactions were") marked in another app. They're shown as pending marks. Nothing is removed until you apply them.") {
                Button("OK") { model.dismissedImportNotice = true }
            }
        }
        if model.markSummary.markCount > 0, !model.facts.isReadOnly {
            InfoBar(symbol: "rectangle.dashed", text: "\(model.markSummary.text) marked for redaction. The text is still there until you apply.") {
                Button("Remove All", action: actions.removeMarks)
                Button("Apply Redactions…", action: actions.applyRedactions)
                    .buttonStyle(.borderedProminent)
            }
        }
        if model.facts.formFieldCount > 0, !model.dismissedFormBar {
            InfoBar(symbol: "list.bullet.rectangle",
                    text: "This form has \(model.facts.formFieldCount) \(model.facts.formFieldCount == 1 ? "field" : "fields"). Click a field to fill it, Tab moves to the next.") {
                Toggle("Highlight Fields", isOn: Binding(get: { model.highlightFields }, set: { _ in actions.toggleFields() }))
                    .toggleStyle(.button)
                Button {
                    model.dismissedFormBar = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide")
                .accessibilityLabel("Hide form notice")
            }
        }
    }

    private var styleContext: StyleStrip.Context? {
        if let annotation = model.selectedAnnotation, annotation.page != nil, !model.isReadOnly {
            if RedactionMarks.isMark(annotation) { return .mark }
            switch annotation.type ?? "" {
            case "Highlight", "Underline", "StrikeOut": return .selectedMarkup
            case "FreeText": return .selectedText
            case "Text": return .selectedNote
            case "Square", "Circle": return .selectedShape(fillable: true)
            case "Line", "Ink": return .selectedShape(fillable: false)
            default: return .selectedOther
            }
        }
        switch model.tool {
        case .highlight: return .markupTool
        case .draw: return .drawTool
        case .shape: return .shapeTool
        case .text: return .textTool
        case .redact: return .redactTool
        case .sign: return model.pendingSignature == nil ? nil : .signTool
        case .select, .note: return nil
        }
    }
}

struct InfoBar<Buttons: View>: View {
    let symbol: String
    let text: String
    let buttons: Buttons

    init(symbol: String, text: String, @ViewBuilder buttons: () -> Buttons = { EmptyView() }) {
        self.symbol = symbol
        self.text = text
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.s)
                buttons.controlSize(.small)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 6)
            Divider()
        }
        .background(.bar)
    }
}

/// Color, width and size controls for the current tool or selected annotation.
struct StyleStrip: View {
    enum Context: Equatable {
        case markupTool, drawTool, shapeTool, textTool, redactTool, signTool
        case selectedMarkup, selectedText, selectedNote, selectedShape(fillable: Bool), selectedOther, mark
    }

    @Bindable var model: DocumentModel
    let context: Context
    let actions: HeaderActions

    static let widths: [CGFloat] = [1, 2, 3, 5, 8]
    static let fontSizes: [CGFloat] = [9, 10, 11, 12, 14, 18, 24, 36]

    var body: some View {
        // PDFAnnotation isn't observable; the revision changes after every edit.
        let _ = model.annotationsRevision
        HStack(spacing: Spacing.m) {
            switch context {
            case .markupTool, .selectedMarkup:
                if context == .markupTool {
                    Picker("Style", selection: Binding(get: { model.markupStyle }, set: actions.setMarkupStyle)) {
                        ForEach(MarkupStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                swatches(InkColor.highlighters + [.red], selected: selectedColor ?? model.highlightColor)
                hint(context == .markupTool ? "Drag across text. Esc returns to Select." : nil)
            case .drawTool, .shapeTool, .selectedShape:
                if context == .shapeTool {
                    Picker("Shape", selection: Binding(get: { model.shapeKind }, set: actions.setShape)) {
                        ForEach(ShapeKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                swatches(InkColor.allCases, selected: selectedColor ?? model.inkColor)
                widthPicker
                if context == .shapeTool || context == .selectedShape(fillable: true) {
                    Toggle("Fill", isOn: Binding(get: { selectedFill ?? model.fillShapes }, set: actions.setFill))
                        .toggleStyle(.checkbox)
                        .disabled(context == .shapeTool && !(model.shapeKind == .rectangle || model.shapeKind == .oval))
                }
                hint(context == .drawTool ? "Draw on the page. Esc returns to Select." : context == .shapeTool ? "Drag on the page. Shift keeps it square or straight." : nil)
            case .textTool, .selectedText:
                swatches([.black, .red, .blue, .green, .purple], selected: selectedColor ?? model.textColor)
                Picker("Size", selection: Binding(get: { selectedFontSize ?? model.fontSize }, set: actions.setFontSize)) {
                    ForEach(Self.fontSizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
                }
                .fixedSize()
                if context == .selectedText { Button("Edit Text", action: actions.editSelection) }
                hint(context == .textTool ? "Click where the text goes. Works on flat forms too." : nil)
            case .selectedNote:
                Button("Edit Note", action: actions.editSelection)
                Spacer()
            case .redactTool:
                hint("Drag across text, or drag a box over images and signatures. Marks stay pending until you apply them.")
            case .signTool:
                hint("Click where the signature goes. Esc cancels.")
            case .mark:
                hint("Pending redaction mark. Delete removes it.")
            case .selectedOther:
                Spacer()
            }
            if isSelection {
                Button(role: .destructive, action: actions.deleteSelection) {
                    Label(context == .mark ? "Remove Mark" : "Delete", systemImage: "trash")
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var isSelection: Bool {
        switch context {
        case .selectedMarkup, .selectedText, .selectedNote, .selectedShape, .selectedOther, .mark: true
        default: false
        }
    }

    private var selectedColor: InkColor? {
        guard let annotation = model.selectedAnnotation else { return nil }
        return InkColor.nearest(to: annotation.type == "FreeText" ? annotation.fontColor : annotation.color)
    }

    private var selectedFill: Bool? {
        guard let annotation = model.selectedAnnotation else { return nil }
        return (annotation.interiorColor?.alphaComponent ?? 0) > 0
    }

    private var selectedFontSize: CGFloat? {
        guard let annotation = model.selectedAnnotation, annotation.type == "FreeText" else { return nil }
        let size = annotation.font?.pointSize ?? 12
        return Self.fontSizes.min { abs($0 - size) < abs($1 - size) }
    }

    private var widthPicker: some View {
        Picker("Width", selection: Binding(get: { selectedWidth ?? model.lineWidth }, set: actions.setLineWidth)) {
            ForEach(Self.widths, id: \.self) { Text("\(Int($0)) pt").tag($0) }
        }
        .fixedSize()
    }

    private var selectedWidth: CGFloat? {
        guard let width = model.selectedAnnotation?.border?.lineWidth else { return nil }
        return Self.widths.min { abs($0 - width) < abs($1 - width) }
    }

    private func swatches(_ colors: [InkColor], selected: InkColor?) -> some View {
        HStack(spacing: 6) {
            ForEach(colors, id: \.self) { color in
                Button {
                    actions.setColor(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .overlay(Circle().strokeBorder(.separator))
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected == color ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selected == color ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func hint(_ text: String?) -> some View {
        if let text {
            Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        }
        Spacer(minLength: 0)
    }
}

struct SelectionActions {
    var highlight: (InkColor) -> Void
    var underline: () -> Void
    var strike: () -> Void
    var note: () -> Void
    var redact: () -> Void
    var copy: () -> Void
}

/// Floats over selected text: one click to highlight, underline, strike, note, redact or copy.
struct SelectionBar: View {
    let actions: SelectionActions

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InkColor.highlighters, id: \.self) { color in
                Button { actions.highlight(color) } label: {
                    Circle().fill(Color(nsColor: color.nsColor)).overlay(Circle().strokeBorder(.separator)).frame(width: 14, height: 14)
                }
                .help("Highlight \(color.title)")
                .accessibilityLabel("Highlight \(color.title)")
            }
            Divider().frame(height: 16)
            button("underline", "Underline", actions.underline)
            button("strikethrough", "Strikethrough", actions.strike)
            button("note.text.badge.plus", "Add Note", actions.note)
            button("rectangle.fill.badge.xmark", "Mark for Redaction", actions.redact)
            button("doc.on.doc", "Copy", actions.copy)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .fixedSize()
    }

    private func button(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
    }
}

struct NoteEditor: View {
    @Bindable var state: NoteState
    let onDelete: () -> Void
    let onDone: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextEditor(text: $state.text)
                .font(.body)
                .focused($focused)
                .frame(width: 260, height: 120)
                .accessibilityLabel("Note text")
            HStack {
                Button("Delete Note", role: .destructive, action: onDelete)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(Spacing.m)
        .onAppear { focused = true }
    }
}

/// Shown instead of the page while a password-protected PDF is locked.
struct LockedView: View {
    let name: String
    let unlock: (String) -> Bool
    @State private var password = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "lock.doc")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("“\(name)” is password-protected.").font(.title3)
            Text("Enter its password to open it.").foregroundStyle(.secondary)
            HStack {
                SecureField("Password", text: $password)
                    .focused($focused)
                    .frame(width: 220)
                    .onSubmit(tryUnlock)
                Button("Unlock", action: tryUnlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            if failed {
                Text("That password didn't work. Check it and try again.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { focused = true }
    }

    private func tryUnlock() {
        failed = !unlock(password)
        if failed { password = "" }
    }
}
