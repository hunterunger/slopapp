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
    var recognizeText: () -> Void
    var replaceImage: () -> Void
    var deleteImage: () -> Void
    var addImage: () -> Void
    var crop: (PaperWindowController.CropScope) -> Void
    var removeCrop: () -> Void
    var setFormKind: (FormFieldKind) -> Void
    var renameField: (String) -> Void
    var showFieldDetails: () -> Void
    var showSignatures: () -> Void
    var cancelCertificate: () -> Void
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
                // The editing bar: always there (View > Hide Editing Bar), like the original's
                // second toolbar row; controls that don't apply are dimmed.
                if model.showsEditingBar {
                    StyleStrip(model: model, context: styleContext ?? .idle, actions: actions)
                    Hairline()
                }
                notices
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
        if let status = signatureSummary {
            InfoBar(symbol: status.symbol, text: status.text) {
                Button("Details…", action: actions.showSignatures)
                if !model.facts.isReadOnly { Button("Duplicate", action: actions.duplicate) }
            }
        } else if model.facts.hasDigitalSignature, !model.facts.isReadOnly {
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
        if !model.hasTextLayer, !model.dismissedScanBar, !model.facts.isReadOnly {
            InfoBar(symbol: "doc.viewfinder", text: "This looks like a scan, so its text can't be searched or selected yet.") {
                Button("Recognize Text…", action: actions.recognizeText)
                Button {
                    model.dismissedScanBar = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide")
                .accessibilityLabel("Hide scan notice")
            }
        }
        if model.facts.formFieldCount > 0, !model.dismissedFormBar {
            InfoBar(symbol: "list.bullet.rectangle",
                    text: "This form has \(model.facts.formFieldCount) \(model.facts.formFieldCount == 1 ? "field" : "fields"). "
                        + (model.tool == .form ? "The Fields sidebar (⌥⌘5) sets the order Tab moves through them." : "Click a field to fill it, Tab moves to the next.")) {
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

    /// One line about the document's certificate signatures: the newest signature's status,
    /// or the first problem.
    private var signatureSummary: (symbol: String, text: String)? {
        let statuses = model.signatures
        guard let last = statuses.last else { return nil }
        let edit = model.facts.isReadOnly ? "" : " Saving changes in Paper will break it; sign or share a duplicate instead."
        if let bad = statuses.first(where: { !$0.isValid }) {
            return ("xmark.seal", bad.summary + (statuses.count > 1 ? " (\(statuses.count) signatures)" : ""))
        }
        let all = statuses.count > 1 ? "\(statuses.count) signatures, all valid. Newest: " : ""
        return (last.trusted ? "checkmark.seal" : "exclamationmark.triangle", all + last.summary + edit)
    }

    private var styleContext: StyleStrip.Context? {
        if model.tool == .edit, !model.isReadOnly {
            if model.editNotice != nil { return .editingText }
            if model.imageTarget != nil { return .editImage }
            return .editTool
        }
        if model.tool == .crop, !model.isReadOnly { return .cropTool }
        if model.tool == .sign, model.certificatePlan != nil { return .certificateTool }
        if let annotation = model.selectedAnnotation, annotation.page != nil, !model.isReadOnly, annotation.type == "Widget" {
            return .selectedField
        }
        if model.tool == .form, !model.isReadOnly { return .formTool }
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
        case .select, .note, .edit, .form, .crop: return nil
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
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: PaperMetrics.barHeight)
            Hairline()
        }
        .background(.bar)
    }
}

/// Color, width and size controls for the current tool or selected annotation.
struct StyleStrip: View {
    enum Context: Equatable {
        case idle, markupTool, drawTool, shapeTool, textTool, redactTool, signTool
        case selectedMarkup, selectedText, selectedNote, selectedShape(fillable: Bool), selectedOther, mark
        case editTool, editingText, editImage, cropTool, formTool, selectedField, certificateTool
    }

    @Bindable var model: DocumentModel
    let context: Context
    let actions: HeaderActions
    @Environment(\.appearsActive) private var appearsActive
    /// Narrow windows drop the pop-ups' labels so the controls still fit.
    @State private var isCompact = false

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
                sizePicker(Binding(get: { selectedFontSize ?? model.fontSize }, set: actions.setFontSize))
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
            case .editTool:
                Button("Add Image…", action: actions.addImage)
                hint("Click text to change it, or an image to move, resize or replace it.")
            case .editingText:
                if model.editNoticeIsWarning {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                hint(model.editNotice.map { model.editNoticeIsWarning ? $0 : "Font: \($0). Esc or a click outside finishes." })
            case .editImage:
                Button("Replace Image…", action: actions.replaceImage)
                Button(role: .destructive, action: actions.deleteImage) { Label("Delete Image", systemImage: "trash") }
                hint("Drag to move. Drag a corner to resize; Shift lets it stretch.")
            case .cropTool:
                if model.cropDraft != nil {
                    Button("Crop This Page") { actions.crop(.page) }.keyboardShortcut(.defaultAction)
                    if model.selectedPages.count > 1 { Button("Crop Selected Pages") { actions.crop(.selected) } }
                    Button("Crop All Pages") { actions.crop(.all) }
                }
                Button("Remove Crop", action: actions.removeCrop)
                    .disabled(!(0..<model.pdf.pageCount).contains { model.pdf.page(at: $0).map(PageCrop.isCropped) ?? false })
                hint(model.cropDraft == nil ? "Drag over the part of the page to keep. Nothing outside it is deleted." : "Return crops this page. Esc cancels.")
            case .formTool:
                Picker("Field", selection: Binding(get: { model.formKind }, set: actions.setFormKind)) {
                    ForEach(FormFieldKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                hint("Click or drag on the page to add a field. Click a field to move or resize it.")
            case .selectedField:
                FieldNameField(model: model, rename: actions.renameField)
                Button("Properties…", action: actions.showFieldDetails)
            case .certificateTool:
                Button("Cancel", action: actions.cancelCertificate)
                hint("Drag a box where the signature should appear. Esc cancels.")
            case .selectedOther:
                Spacer()
            case .idle:
                swatches(InkColor.allCases, selected: nil)
                    .disabled(true)
                widthPicker.disabled(true)
                sizePicker(.constant(model.fontSize)).disabled(true)
                hint(model.tool == .note ? "Click where the note goes." : "Select an annotation or pick a tool to set its color and size.")
            }
            if isSelection {
                Button(role: .destructive, action: actions.deleteSelection) {
                    Label(context == .mark ? "Remove Mark" : "Delete", systemImage: "trash")
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, PaperMetrics.pageGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PaperMetrics.barHeight)
        // If it still doesn't fit, it's cut at the trailing end, never centred off both sides.
        .clipped()
        .onGeometryChange(for: Bool.self) { $0.size.width < 520 } action: { isCompact = $0 }
        .background(.bar)
    }

    private var isSelection: Bool {
        switch context {
        case .selectedMarkup, .selectedText, .selectedNote, .selectedShape, .selectedOther, .mark, .selectedField: true
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
        labeled("Width") {
            Picker("Width", selection: Binding(get: { selectedWidth ?? model.lineWidth }, set: actions.setLineWidth)) {
                ForEach(Self.widths, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
        }
    }

    private func sizePicker(_ selection: Binding<CGFloat>) -> some View {
        labeled("Size") {
            Picker("Size", selection: selection) {
                ForEach(Self.fontSizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
        }
    }

    /// A pop-up with its label in the strip's text style (a Picker's own label comes out a
    /// size larger than its small pop-up).
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ picker: () -> Content) -> some View {
        HStack(spacing: Spacing.xs) {
            if !isCompact {
                Text(title).font(.callout).foregroundStyle(.secondary).fixedSize().accessibilityHidden(true)
            }
            picker().labelsHidden().fixedSize()
        }
    }

    private var selectedWidth: CGFloat? {
        guard let width = model.selectedAnnotation?.border?.lineWidth else { return nil }
        return Self.widths.min { abs($0 - width) < abs($1 - width) }
    }

    private func swatches(_ colors: [InkColor], selected: InkColor?) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(colors, id: \.self) { color in
                Button {
                    actions.setColor(color)
                } label: {
                    // 16 pt swatch, 1 pt gap, 2 pt ring: concentric circles in a 22 pt target.
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        // Stronger than a separator, so black reads on the dark bar and
                        // yellow on the light one.
                        .hairlineBorder(Circle(), color: Color(nsColor: .tertiaryLabelColor))
                        .frame(width: 16, height: 16)
                        .padding(3) // lint:allow 1 pt gap + 2 pt ring around a 16 pt swatch
                        .overlay(Circle().strokeBorder(appearsActive ? Color.accentColor : Color(nsColor: .systemGray), lineWidth: 2)
                            .opacity(selected == color ? 1 : 0))
                        .contentShape(Circle())
                }
                .buttonStyle(PressDimmingButtonStyle())
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selected == color ? .isSelected : [])
            }
        }
    }

    /// The hint takes what's left of the bar, and leaves altogether when a whole sentence
    /// doesn't fit (a sentence cut to "Sel…" reads worse than none).
    @ViewBuilder private func hint(_ text: String?) -> some View {
        if let text {
            ViewThatFits(in: .horizontal) {
                Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            .layoutPriority(-1)
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
        HStack(spacing: Spacing.xs) {
            ForEach(InkColor.highlighters, id: \.self) { color in
                Button { actions.highlight(color) } label: {
                    Circle().fill(Color(nsColor: color.nsColor)).hairlineBorder(Circle()).frame(width: 14, height: 14)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .help("Highlight \(color.title)")
                .accessibilityLabel("Highlight \(color.title)")
            }
            Hairline(axis: .vertical).frame(height: 16)
            button("underline", "Underline", actions.underline)
            button("strikethrough", "Strikethrough", actions.strike)
            button("note.text.badge.plus", "Add Note", actions.note)
            button("rectangle.fill.badge.xmark", "Mark for Redaction", actions.redact)
            button("doc.on.doc", "Copy", actions.copy)
        }
        .buttonStyle(PressDimmingButtonStyle())
        .foregroundStyle(.primary)
        // 20 pt items with 4 pt around them: a 28 pt capsule, and the first swatch's centre sits
        // 14 pt from the edge, concentric with the capsule's end cap.
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(.thickMaterial, in: Capsule())
        .hairlineBorder(Capsule())
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
                    .foregroundStyle(.textRed)
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

/// A plain button (swatches, the selection bar's symbols) that shows it was pressed and dims
/// when disabled, which `.plain` doesn't do on its own.
struct PressDimmingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
    }
}


/// The selected field's name in the editing bar; renames on Return or when focus leaves.
struct FieldNameField: View {
    @Bindable var model: DocumentModel
    let rename: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let _ = model.annotationsRevision
        HStack(spacing: Spacing.xs) {
            Text(model.selectedAnnotation.flatMap(FormFieldKind.of)?.title ?? "Field")
                .font(.callout).foregroundStyle(.secondary).fixedSize()
                .accessibilityHidden(true)
            TextField("Field name", text: $draft)
                .frame(width: 160)
                .focused($focused)
                .onSubmit { rename(draft) }
                .onChange(of: focused) { _, now in if !now { rename(draft) } }
        }
        .onAppear { draft = model.selectedAnnotation?.fieldName ?? "" }
        .onChange(of: model.selectedAnnotation.map(ObjectIdentifier.init)) { draft = model.selectedAnnotation?.fieldName ?? "" }
    }
}
