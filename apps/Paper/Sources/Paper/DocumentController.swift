import AppKit
import PDFKit
import PaperCore
import UniformTypeIdentifiers

/// Opens images as new untitled PDFs and makes untitled documents for Combine and Extract.
@MainActor
final class PaperDocumentController: NSDocumentController {
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return imageTypes.contains { type.conforms(to: $0) }
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard Self.isImage(url) else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        guard let image = NSImage(contentsOf: url), let page = ImagePages.page(for: image) else {
            completionHandler(nil, false, PaperError.couldNotOpen(url.lastPathComponent))
            return
        }
        let pdf = PDFDocument()
        pdf.insert(page, at: 0)
        let document = openUntitled(pdf, name: url.deletingPathExtension().lastPathComponent)
        noteNewRecentDocumentURL(url)
        completionHandler(document, false, nil)
    }

    /// A new, unsaved document window for `pdf`. It counts as edited, so closing asks to save.
    @discardableResult
    func openUntitled(_ pdf: PDFDocument, name: String?) -> PaperDocument {
        let document = PaperDocument(untitled: pdf)
        if let name { document.displayName = name }
        addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        document.updateChangeCount(.changeDone)
        return document
    }
}

enum PaperError: LocalizedError {
    case couldNotOpen(String)
    case damaged(String)
    case unsafeToSave
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .couldNotOpen(let name): "Couldn't open “\(name)”."
        case .damaged(let name): "Couldn't open “\(name)”. It may be damaged or not a PDF."
        case .unsafeToSave: "Paper stopped this save because it would have applied redactions."
        case .writeFailed: "Paper couldn't write the file."
        }
    }

    var failureReason: String? {
        switch self {
        case .damaged: "It may be damaged or not a PDF."
        default: nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .couldNotOpen: "Make sure it's a PDF or an image, then try again."
        case .damaged: "Try downloading or exporting it again."
        case .unsafeToSave: "Your file hasn't changed. Use Apply Redactions to remove marked content."
        case .writeFailed: "Check there's enough space and that you can write to that folder."
        }
    }
}
