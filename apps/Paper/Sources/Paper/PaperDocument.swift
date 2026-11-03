import AppKit
import PDFKit
import PaperCore

/// One open PDF. Standard document behaviour: autosave in place with Versions, Revert To,
/// Duplicate, Rename, Move To. Redaction and flattening never go through here: they write
/// new files (see RedactionFlow and Exporting).
@objc(PaperDocument)
final class PaperDocument: NSDocument {
    private(set) var pdf = PDFDocument()
    private(set) var facts = DocumentFacts()
    /// `Redact` annotations from another app that were turned into pending marks on open.
    private(set) var importedRedactions = 0
    /// The password the person typed to unlock, kept so saving keeps the file protected.
    private(set) var password: String?
    /// Pending widget values captured to spot form edits (see FormTracker).
    let formTracker = FormTracker()

    override init() {
        super.init()
    }

    convenience init(untitled pdf: PDFDocument) {
        self.init()
        fileType = "com.adobe.pdf"
        adopt(pdf, raw: nil)
    }

    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { ["com.adobe.pdf"] }
    override class var writableTypes: [String] { ["com.adobe.pdf"] }
    override class func isNativeType(_ type: String) -> Bool { type == "com.adobe.pdf" }
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(PaperWindowController(document: self))
    }

    var windowController: PaperWindowController? { windowControllers.first as? PaperWindowController }

    // MARK: Reading

    override func read(from url: URL, ofType typeName: String) throws {
        // Mapped, so a 300 MB scan isn't copied into memory, and an autosave that replaces the
        // file can't change the bytes under PDFKit.
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        try read(from: data, ofType: typeName, name: url.lastPathComponent)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try read(from: data, ofType: typeName, name: displayName ?? "document")
    }

    private func read(from data: Data, ofType typeName: String, name: String) throws {
        guard let document = PDFDocument(data: data), document.isLocked || document.pageCount > 0 else {
            throw PaperError.damaged(name)
        }
        adopt(document, raw: data)
        windowController?.documentDidReload()
    }

    private func adopt(_ document: PDFDocument, raw: Data?) {
        pdf = document
        password = nil
        guard !document.isLocked else {
            facts = DocumentFacts()
            facts.isEncrypted = true
            return
        }
        facts = DocumentFacts.inspect(document, raw: raw)
        // Research P4: PDFKit applies `Redact` annotations on every write. Convert them to
        // pending marks in memory so no save can apply them; the change isn't saved until the
        // person edits something, and the info bar says what happened.
        importedRedactions = RedactionMarks.convertRedactAnnotations(in: document)
        facts.pendingMarkCount += importedRedactions
        formTracker.reset(document)
    }

    /// Unlocks a password-protected document. Returns false for a wrong password.
    func unlock(with password: String) -> Bool {
        guard pdf.unlock(withPassword: password) else { return false }
        self.password = password
        let unlocked = pdf
        adopt(unlocked, raw: nil)
        self.password = password
        facts.isEncrypted = true
        return true
    }

    func replace(with document: PDFDocument) {
        undoManager?.removeAllActions()
        adopt(document, raw: nil)
        windowController?.documentDidReload()
    }

    // MARK: Writing

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        windowController?.commitEditing()
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard !pdf.isLocked else { throw PaperError.writeFailed }
        // Defense in depth for P4: never write while a `Redact` annotation is in the document.
        guard RedactionMarks.redactAnnotations(in: pdf).isEmpty else { throw PaperError.unsafeToSave }
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let password {
            options[.userPasswordOption] = password
            options[.ownerPasswordOption] = password
        }
        guard let data = options.isEmpty ? pdf.dataRepresentation() : pdf.dataRepresentation(options: options) else {
            throw PaperError.writeFailed
        }
        return data
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let operation = pdf.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw PaperError.writeFailed
        }
        operation.jobTitle = displayName
        return operation
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(printDocument(_:)) {
            return !pdf.isLocked && facts.allowsPrinting
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// Spots form edits made inside PDFView's own field editors, so they mark the document
/// edited and can be undone like everything else.
@MainActor
final class FormTracker {
    struct Value: Equatable {
        var text: String?
        var state: Int
    }

    private var snapshot: [ObjectIdentifier: Value] = [:]
    private var widgets: [ObjectIdentifier: PDFAnnotation] = [:]

    func reset(_ document: PDFDocument) {
        snapshot = [:]
        widgets = [:]
        for index in 0..<document.pageCount {
            for annotation in document.page(at: index)?.annotations ?? [] where annotation.type == "Widget" {
                let id = ObjectIdentifier(annotation)
                widgets[id] = annotation
                snapshot[id] = Self.value(of: annotation)
            }
        }
    }

    var isEmpty: Bool { widgets.isEmpty }

    static func value(of annotation: PDFAnnotation) -> Value {
        Value(text: annotation.widgetStringValue, state: annotation.buttonWidgetState.rawValue)
    }

    /// Fields whose value changed since the last check, with their old values.
    func changes() -> [(PDFAnnotation, Value)] {
        var changed: [(PDFAnnotation, Value)] = []
        for (id, annotation) in widgets {
            let now = Self.value(of: annotation)
            if let old = snapshot[id], old != now {
                changed.append((annotation, old))
                snapshot[id] = now
            }
        }
        return changed
    }

    func record(_ annotation: PDFAnnotation) {
        snapshot[ObjectIdentifier(annotation)] = Self.value(of: annotation)
    }

    static func apply(_ value: Value, to annotation: PDFAnnotation) {
        if annotation.widgetFieldType == .button {
            annotation.buttonWidgetState = PDFWidgetCellState(rawValue: value.state) ?? .offState
        } else {
            annotation.widgetStringValue = value.text
        }
    }
}
