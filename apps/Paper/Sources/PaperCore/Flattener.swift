import AppKit
import PDFKit

public enum FlattenError: Error, LocalizedError, Equatable {
    case unreadable
    case writeFailed
    case annotationsLeft(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Paper couldn't read this document to flatten it."
        case .writeFailed: "Paper couldn't write the flattened copy."
        case .annotationsLeft(let count): "The flattened copy still had \(count) editable items, so it wasn't saved."
        }
    }
}

/// Bakes annotations, signatures and form values into the page (research P7).
public enum Flattener {
    /// A flattened copy of `source`. Pending redaction marks are left out: flattening isn't
    /// redaction, and a baked-in red box over intact text would look like it was.
    public static func flatten(_ source: Data) throws -> Data {
        guard let document = AnnotationTags.open(source), !document.isLocked else { throw FlattenError.unreadable }
        for mark in RedactionMarks.marks(in: document) {
            document.page(at: mark.pageIndex)?.removeAnnotation(mark.annotation)
        }
        refreshButtonAppearances(document)
        guard let data = document.dataRepresentation(options: [PDFDocumentWriteOption.burnInAnnotationsOption: true]),
              let check = PDFDocument(data: data) else { throw FlattenError.writeFailed }
        let left = editableCount(check)
        guard left == 0 else { throw FlattenError.annotationsLeft(left) }
        return data
    }

    /// Annotations left after flattening. Links don't count: they're navigation, not content.
    public static func editableCount(_ document: PDFDocument) -> Int {
        (0..<document.pageCount).reduce(0) { total, index in
            total + (document.page(at: index)?.annotations.filter { $0.type != "Link" }.count ?? 0)
        }
    }

    /// Checkboxes and radios loaded from a file can draw their "off" look when burned in
    /// (research P7). Setting the state again makes PDFKit rebuild the appearance.
    static func refreshButtonAppearances(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.widgetFieldType == .button {
                let state = annotation.buttonWidgetState
                annotation.buttonWidgetState = state == .onState ? .offState : .onState
                annotation.buttonWidgetState = state
            }
        }
    }
}
