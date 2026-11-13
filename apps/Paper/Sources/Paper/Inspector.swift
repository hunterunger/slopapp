import PDFKit
import PaperCore
import SlopKit
import SwiftUI

struct InspectorActions {
    var setInfo: (DocumentInfo) -> Void
    var saveProtectedCopy: (Protection) -> Void
    var editSelection: () -> Void
    var deleteSelection: () -> Void
    var setAuthor: (String) -> Void
    var renameField: (String) -> Void
    var setTooltip: (String) -> Void
    var setFlag: (FormFieldFactory.Flag, Bool) -> Void
    var setOptions: ([String]) -> Void
    var setExportValue: (String) -> Void
    var setCalculation: (FieldCalculation?) -> Void
    var showCertificate: (SignatureStatus) -> Void
}

/// The trailing inspector (⌥⌘I): document info, security and the selected item's details.
/// The original keeps these in a floating panel; Paper docks them in the window so they
/// follow tabs and full screen (see the research doc's deviations).
struct InspectorView: View {
    @Bindable var model: DocumentModel
    let actions: InspectorActions

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector pane", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, Spacing.s)
            .frame(maxWidth: .infinity)
            .frame(height: PaperMetrics.barHeight)
            Hairline()
            Group {
                if model.isLocked {
                    FillingUnavailable("Locked", systemImage: "lock", description: Text("Unlock the document to see its details."))
                } else {
                    switch model.inspectorTab {
                    case .document: DocumentPane(model: model, actions: actions)
                    case .security: SecurityPane(model: model, actions: actions)
                    case .selection: SelectionPane(model: model, actions: actions)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 260)
    }
}

// MARK: Document

struct DocumentPane: View {
    @Bindable var model: DocumentModel
    let actions: InspectorActions
    @State private var draft = DocumentInfo()
    @FocusState private var focused: Field?

    enum Field: Hashable { case title, author, subject, keywords }

    var body: some View {
        let _ = model.infoRevision
        let facts = FileFacts(model.pdf, fileURL: model.fileURL)
        Form {
            Section("Description") {
                field("Title", text: $draft.title, .title)
                field("Author", text: $draft.author, .author)
                field("Subject", text: $draft.subject, .subject)
                field("Keywords", text: $draft.keywords, .keywords)
            }
            .disabled(model.isReadOnly)
            Section("File") {
                row("Pages", "\(facts.pageCount)")
                if let size = facts.pageSize { row("Page size", size) }
                row("PDF version", facts.version)
                if let bytes = facts.fileSize { row("File size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
                if let created = facts.created { row("Created", created.formatted(date: .numeric, time: .shortened)) }
                if let modified = facts.modified { row("Modified", modified.formatted(date: .numeric, time: .shortened)) }
                if let creator = facts.creator { row("Made with", creator) }
                if let producer = facts.producer { row("Producer", producer) }
                row("Encrypted", facts.isEncrypted ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
        .onAppear { draft = DocumentInfo(model.pdf) }
        .onChange(of: model.infoRevision) { draft = DocumentInfo(model.pdf) }
        .onChange(of: focused) { old, _ in if old != nil { commit() } }
    }

    private func field(_ title: String, text: Binding<String>, _ id: Field) -> some View {
        TextField(title, text: text, prompt: Text("None"))
            .focused($focused, equals: id)
            .onSubmit(commit)
    }

    /// Label and value on one baseline; a long value wraps beside its label, right-aligned,
    /// instead of dropping below it.
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(title).fixedSize()
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func commit() {
        guard draft != DocumentInfo(model.pdf) else { return }
        actions.setInfo(draft)
    }
}

// MARK: Security

struct SecurityPane: View {
    @Bindable var model: DocumentModel
    let actions: InspectorActions
    @State private var protection = Protection()
    @State private var requireOpen = true
    @State private var restrict = false
    @State private var verify = ""

    var body: some View {
        Form {
            if !model.signatures.isEmpty {
                Section("Signatures") {
                    ForEach(model.signatures) { status in
                        SignatureRow(status: status, showCertificate: { actions.showCertificate(status) })
                    }
                }
            }
            Section("This Document") {
                LabeledContent("Password to open", value: model.facts.isEncrypted ? "Yes" : "None")
                LabeledContent("Printing", value: model.facts.allowsPrinting ? "Allowed" : "Not allowed")
                LabeledContent("Copying", value: model.facts.allowsCopying ? "Allowed" : "Not allowed")
                LabeledContent("Changes", value: model.facts.allowsChanges ? "Allowed" : "Not allowed")
            }
            Section {
                Toggle("Require a password to open", isOn: $requireOpen)
                if requireOpen {
                    SecureField("Password", text: $protection.openPassword, prompt: Text("Required"))
                    SecureField("Verify", text: $verify, prompt: Text("Required"))
                }
                Toggle("Restrict printing and editing", isOn: $restrict)
                if restrict {
                    SecureField("Permissions password", text: $protection.permissionsPassword, prompt: Text("Required"))
                    Toggle("Allow printing", isOn: $protection.allowPrinting)
                    Toggle("Allow copying text and images", isOn: $protection.allowCopying)
                    Toggle("Allow changing pages", isOn: $protection.allowChanges)
                    Toggle("Allow comments and form filling", isOn: $protection.allowComments)
                }
            } header: {
                Text("Protected Copy")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if let message {
                        Text(message).foregroundStyle(.textRed)
                    }
                    Button("Save Protected Copy…") { actions.saveProtectedCopy(effective) }
                        .disabled(!canSave)
                    Text("Writes a new file and leaves this one as it is. Paper can't recover a forgotten password.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
    }

    /// The settings as chosen (sections switched off don't count).
    private var effective: Protection {
        var value = protection
        if !requireOpen { value.openPassword = "" }
        if !restrict {
            value.permissionsPassword = ""
            value.allowPrinting = true
            value.allowCopying = true
            value.allowChanges = true
            value.allowComments = true
        }
        return value
    }

    private var passwordsMatch: Bool { !requireOpen || protection.openPassword == verify }

    private var canSave: Bool { passwordsMatch && effective.problem == nil }

    /// Only real mistakes are spelled out; an untouched form just has its button dimmed.
    private var message: String? {
        if requireOpen && !protection.openPassword.isEmpty && !verify.isEmpty && !passwordsMatch { return "The passwords don't match." }
        if let problem = effective.problem, problem != .nothingToProtect {
            if problem == .needsPermissionsPassword && protection.permissionsPassword.isEmpty { return nil }
            return problem.errorDescription
        }
        return nil
    }
}

// MARK: Selection

struct SelectionPane: View {
    @Bindable var model: DocumentModel
    let actions: InspectorActions
    @State private var author = ""

    var body: some View {
        let _ = model.annotationsRevision
        if let field = model.selectedAnnotation, field.type == "Widget", field.page != nil {
            FieldPane(model: model, field: field, actions: actions)
        } else if let annotation = model.selectedAnnotation, let page = annotation.page {
            Form {
                Section("Selection") {
                    LabeledContent("Kind", value: AnnotationNames.title(annotation))
                    LabeledContent("Page", value: "\(model.pdf.index(for: page) + 1)")
                    if let date = annotation.modificationDate {
                        LabeledContent("Modified", value: date.formatted(date: .numeric, time: .shortened))
                    }
                    TextField("Author", text: $author, prompt: Text("None"))
                        .onSubmit { actions.setAuthor(author) }
                        .disabled(model.isReadOnly || RedactionMarks.isMark(annotation))
                }
                if let contents = annotation.contents, !contents.isEmpty, ["FreeText", "Text"].contains(annotation.type ?? "") {
                    Section("Text") {
                        Text(contents).textSelection(.enabled).lineLimit(8)
                        Button("Edit Text", action: actions.editSelection).disabled(model.isReadOnly)
                    }
                }
                Section {
                    Button(RedactionMarks.isMark(annotation) ? "Remove Mark" : "Delete", role: .destructive, action: actions.deleteSelection)
                        .disabled(model.isReadOnly)
                } footer: {
                    Text("Color, line width and text size are in the editing bar above the page.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .font(.callout)
            .onAppear { author = annotation.userName ?? "" }
            .onChange(of: ObjectIdentifier(annotation)) { author = annotation.userName ?? "" }
        } else {
            FillingUnavailable("No Selection", systemImage: "cursorarrow.click",
                               description: Text("Select a highlight, note, shape or signature to see its details."))
        }
    }
}

/// Human names for annotations, shared by the Notes list and the inspector.
enum AnnotationNames {
    static func title(_ annotation: PDFAnnotation) -> String {
        if RedactionMarks.isMark(annotation) { return "Redaction mark" }
        if Signature.isSignature(annotation) { return "Signature" }
        switch annotation.type ?? "" {
        case "Highlight": return "Highlight"
        case "Underline": return "Underline"
        case "StrikeOut": return "Strikethrough"
        case "Text": return "Note"
        case "FreeText": return "Text box"
        case "Ink": return "Drawing"
        case "Square": return "Rectangle"
        case "Circle": return "Oval"
        case "Line": return annotation.endLineStyle == .none ? "Line" : "Arrow"
        default: return annotation.type ?? "Annotation"
        }
    }
}


// MARK: Signatures

struct SignatureRow: View {
    let status: SignatureStatus
    let showCertificate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label {
                Text(status.signerName).fontWeight(.semibold)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Text(status.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let reason = status.reason, !reason.isEmpty { Text("Reason: \(reason)").foregroundStyle(.secondary) }
            if let location = status.location, !location.isEmpty { Text("Location: \(location)").foregroundStyle(.secondary) }
            if let issuer = status.issuerName { Text("Issued by \(issuer)").foregroundStyle(.secondary) }
            if status.certificate != nil {
                Button("Show Certificate…", action: showCertificate)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        guard status.isValid else { return "xmark.seal" }
        return status.trusted ? "checkmark.seal" : "exclamationmark.triangle"
    }

    private var color: Color {
        guard status.isValid else { return .textRed }
        return status.trusted ? .textGreen : .secondary
    }
}

// MARK: Form fields

/// A form field's properties: name, tooltip, flags, options, export value and calculation.
struct FieldPane: View {
    @Bindable var model: DocumentModel
    let field: PDFAnnotation
    let actions: InspectorActions
    @State private var name = ""
    @State private var tooltip = ""
    @State private var options = ""
    @State private var exportValue = ""
    @State private var formula = ""
    @FocusState private var focus: Focus?

    enum Focus: Hashable { case name, tooltip, options, export, formula }

    enum Rule: Hashable {
        case none, aggregate(Calculation.Operation), formula, script
    }

    var body: some View {
        let _ = model.annotationsRevision
        let kind = FormFieldKind.of(field)
        Form {
            Section("Field") {
                LabeledContent("Kind", value: kind?.title ?? "Field")
                TextField(kind == .radio ? "Group" : "Name", text: $name)
                    .focused($focus, equals: .name)
                    .onSubmit { actions.renameField(name) }
                TextField("Tooltip", text: $tooltip, prompt: Text("None"))
                    .focused($focus, equals: .tooltip)
                    .onSubmit { actions.setTooltip(tooltip) }
                Toggle("Required", isOn: flag(.required))
                Toggle("Read only", isOn: flag(.readOnly))
                if kind == .text { Toggle("Several lines", isOn: flag(.multiline)) }
            }
            .disabled(model.isReadOnly)
            if kind == .dropdown {
                Section {
                    TextField("Choices", text: $options, prompt: Text("One per line"), axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focus, equals: .options)
                } header: {
                    Text("Choices")
                } footer: {
                    note("One choice per line.")
                }
            }
            if kind == .checkbox || kind == .radio {
                Section {
                    TextField("Value when on", text: $exportValue)
                        .focused($focus, equals: .export)
                        .onSubmit { actions.setExportValue(exportValue) }
                } header: {
                    Text(kind == .radio ? "This Button" : "Checkbox")
                } footer: {
                    note(kind == .radio ? "Buttons with the same group name work together: choosing one clears the others." : "What the form sends when it's checked.")
                }
            }
            if kind == .text, let fieldName = field.fieldName {
                calculation(for: fieldName)
            }
            Section {
                Button("Delete Field", role: .destructive, action: actions.deleteSelection)
                    .disabled(model.isReadOnly)
            } footer: {
                note("The Fields sidebar (⌥⌘5) sets the order Tab moves through the fields.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
        .onAppear(perform: load)
        .onChange(of: ObjectIdentifier(field)) { load() }
        .onChange(of: focus) { old, _ in commit(old) }
    }

    @ViewBuilder private func calculation(for fieldName: String) -> some View {
        let current = model.formScripts.calculations[fieldName]
        let others = FormFields.widgets(in: model.pdf).compactMap { $0.annotation.widgetFieldType == .text ? $0.annotation.fieldName : nil }
            .filter { $0 != fieldName }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        Section {
            Picker("Value", selection: Binding(get: { rule(current?.rule) }, set: { setRule($0, current: current, others: others) })) {
                Text("Typed in").tag(Rule.none)
                ForEach(Calculation.Operation.allCases, id: \.self) { Text("\($0.title) of fields").tag(Rule.aggregate($0)) }
                Text("Formula").tag(Rule.formula)
                if case .script = current?.rule { Text("Script from another app").tag(Rule.script) }
            }
            switch current?.rule {
            case .aggregate(let op, let fields):
                if others.isEmpty {
                    note("Add more text fields to calculate with.")
                }
                ForEach(others, id: \.self) { other in
                    Toggle(other, isOn: Binding(get: { fields.contains(other) }, set: { on in
                        let list = on ? others.filter { fields.contains($0) || $0 == other } : fields.filter { $0 != other }
                        actions.setCalculation(FieldCalculation(.aggregate(op, fields: list), decimals: current?.decimals))
                    }))
                }
            case .formula:
                TextField("Formula", text: $formula, prompt: Text("qty * price"))
                    .focused($focus, equals: .formula)
                    .onSubmit { commit(.formula) }
                if let problem = formulaProblem(others: others) { Text(problem).foregroundStyle(.textRed) }
            case .script:
                note("Paper keeps this script but doesn't run it. Acrobat and other viewers that run form scripts will.")
            case nil:
                EmptyView()
            }
            if let current, !current.rule.isScript {
                Stepper("Decimals: \(current.decimals ?? 2)", value: Binding(get: { current.decimals ?? 2 }, set: {
                    actions.setCalculation(FieldCalculation(current.rule, decimals: $0))
                }), in: 0...4)
            }
        } header: {
            Text("Calculation")
        } footer: {
            note("Paper calculates as you fill the form. The rule is saved as a standard form script, so Acrobat and other viewers that run them calculate too.")
        }
        .disabled(model.isReadOnly)
    }

    private func rule(_ calculation: Calculation?) -> Rule {
        switch calculation {
        case .aggregate(let op, _): .aggregate(op)
        case .formula: .formula
        case .script: .script
        case nil: .none
        }
    }

    private func setRule(_ rule: Rule, current: FieldCalculation?, others: [String]) {
        let decimals = current?.decimals ?? 2
        switch rule {
        case .none: actions.setCalculation(nil)
        case .aggregate(let op):
            var fields: [String] = []
            if case .aggregate(_, let existing) = current?.rule { fields = existing }
            actions.setCalculation(FieldCalculation(.aggregate(op, fields: fields), decimals: decimals))
        case .formula:
            let text = formula.isEmpty ? others.prefix(2).map(FormulaParser.escape).joined(separator: " * ") : formula
            formula = text
            actions.setCalculation(FieldCalculation(.formula(text.isEmpty ? "0" : text), decimals: decimals))
        case .script: break
        }
    }

    private func formulaProblem(others: [String]) -> String? {
        do {
            let expression = try FormulaParser.parse(formula)
            let unknown = expression.fieldNames.filter { !others.contains($0) }
            return unknown.isEmpty ? nil : "No field is named “\(unknown[0])”. Names with spaces need a backslash: unit\\ price."
        } catch {
            return (error as? LocalizedError)?.errorDescription
        }
    }

    private func flag(_ flag: FormFieldFactory.Flag) -> Binding<Bool> {
        Binding(get: { FormFieldFactory.has(flag, field) }, set: { actions.setFlag(flag, $0) })
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        name = field.fieldName ?? ""
        tooltip = FormFieldFactory.tooltip(of: field)
        options = (field.choices ?? []).joined(separator: "\n")
        exportValue = field.buttonWidgetStateString
        if case .formula(let text) = model.formScripts.calculations[field.fieldName ?? ""]?.rule { formula = text } else { formula = "" }
    }

    private func commit(_ which: Focus?) {
        switch which {
        case .name: if name != field.fieldName { actions.renameField(name) }
        case .tooltip: if tooltip != FormFieldFactory.tooltip(of: field) { actions.setTooltip(tooltip) }
        case .options:
            let list = options.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if list != (field.choices ?? []) { actions.setOptions(list) }
        case .export: if exportValue != field.buttonWidgetStateString { actions.setExportValue(exportValue) }
        case .formula:
            guard let fieldName = field.fieldName, (try? FormulaParser.parse(formula)) != nil else { return }
            let current = model.formScripts.calculations[fieldName]
            if current?.rule != .formula(formula) {
                actions.setCalculation(FieldCalculation(.formula(formula), decimals: current?.decimals ?? 2))
            }
        case nil: break
        }
    }
}
