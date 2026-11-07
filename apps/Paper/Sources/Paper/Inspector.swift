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
        if let annotation = model.selectedAnnotation, let page = annotation.page {
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
