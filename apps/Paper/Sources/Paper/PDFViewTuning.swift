import AppKit
import PDFKit

/// Since macOS 15, PDFView runs Vision on every visible page to find form fields and tables
/// in flat PDFs. It costs about 100 MB and Neural Engine time per page, it would add fields
/// Paper's undo and form tracking don't know about, and Paper's Text Box tool already covers
/// flat forms. There's no public switch, so this turns it off through PDFView's own
/// properties when they exist, and does nothing where they don't (macOS 14).
@MainActor
enum PDFViewTuning {
    static func disableAutomaticAnalysis(_ view: PDFView) {
        for key in ["documentAnalysisEnabled", "formDetectionEnabled"] {
            let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            guard view.responds(to: setter) else { continue }
            view.setValue(false, forKey: key)
        }
    }
}
