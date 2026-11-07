import AppKit
import Observation
import PDFKit
import PaperCore

enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, draw, text, note, shape, sign, redact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .draw: "Draw"
        case .text: "Text Box"
        case .note: "Note"
        case .shape: "Shapes"
        case .sign: "Sign"
        case .redact: "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .draw: "scribble"
        case .text: "character.textbox"
        case .note: "note.text"
        case .shape: "square.on.circle"
        case .sign: "signature"
        case .redact: "rectangle.fill.badge.xmark"
        }
    }

    /// ⌘1–⌘9 (⌘7 is left free, per the research doc's menu plan).
    var shortcut: String {
        switch self {
        case .select: "1"
        case .highlight: "2"
        case .draw: "3"
        case .text: "4"
        case .note: "5"
        case .shape: "6"
        case .sign: "8"
        case .redact: "9"
        }
    }

    /// Tools that change the document; off in read-only documents.
    var edits: Bool { self != .select }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case document, security, selection
    var id: String { rawValue }
    var title: String {
        switch self {
        case .document: "Document"
        case .security: "Security"
        case .selection: "Selection"
        }
    }
    var symbol: String {
        switch self {
        case .document: "info.circle"
        case .security: "lock"
        case .selection: "slider.horizontal.3"
        }
    }
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case thumbnails, outline, annotations, search, redact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thumbnails: "Thumbnails"
        case .outline: "Outline"
        case .annotations: "Notes"
        case .search: "Search Results"
        case .redact: "Find and Redact"
        }
    }
}

struct PageItem: Identifiable, Hashable {
    let id: ObjectIdentifier
    let page: PDFPage
    static func == (a: PageItem, b: PageItem) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// State for one document window, shared by the AppKit canvas and the SwiftUI panels.
@Observable
@MainActor
final class DocumentModel {
    var pdf: PDFDocument

    // Tools and their styles (remembered across documents).
    var tool: Tool = .select
    var markupStyle: MarkupStyle = MarkupStyle(rawValue: Prefs.defaults.string(forKey: Prefs.markupStyle) ?? "") ?? .highlight {
        didSet { Prefs.defaults.set(markupStyle.rawValue, forKey: Prefs.markupStyle) }
    }
    var highlightColor: InkColor = InkColor(rawValue: Prefs.defaults.string(forKey: Prefs.highlightColor) ?? "") ?? .yellow {
        didSet { Prefs.defaults.set(highlightColor.rawValue, forKey: Prefs.highlightColor) }
    }
    var shapeKind: ShapeKind = ShapeKind(rawValue: Prefs.defaults.string(forKey: Prefs.shapeKind) ?? "") ?? .rectangle {
        didSet { Prefs.defaults.set(shapeKind.rawValue, forKey: Prefs.shapeKind) }
    }
    var inkColor: InkColor = InkColor(rawValue: Prefs.defaults.string(forKey: Prefs.inkColor) ?? "") ?? .red {
        didSet { Prefs.defaults.set(inkColor.rawValue, forKey: Prefs.inkColor) }
    }
    var lineWidth: CGFloat = CGFloat(Prefs.defaults.double(forKey: Prefs.lineWidth)) {
        didSet { Prefs.defaults.set(Double(lineWidth), forKey: Prefs.lineWidth) }
    }
    var fontSize: CGFloat = CGFloat(Prefs.defaults.double(forKey: Prefs.fontSize)) {
        didSet { Prefs.defaults.set(Double(fontSize), forKey: Prefs.fontSize) }
    }
    var textColor: InkColor = InkColor(rawValue: Prefs.defaults.string(forKey: Prefs.textColor) ?? "") ?? .black {
        didSet { Prefs.defaults.set(textColor.rawValue, forKey: Prefs.textColor) }
    }
    var fillShapes = false
    /// The Draw group's button repeats the last drawing tool: freehand, or the last shape.
    var drawUsesShape = Prefs.defaults.bool(forKey: Prefs.drawUsesShape) {
        didSet { Prefs.defaults.set(drawUsesShape, forKey: Prefs.drawUsesShape) }
    }
    /// The Comment group's button repeats the last of Text Box and Note.
    var commentUsesNote = Prefs.defaults.bool(forKey: Prefs.commentUsesNote) {
        didSet { Prefs.defaults.set(commentUsesNote, forKey: Prefs.commentUsesNote) }
    }
    /// The editing bar under the toolbar (View > Hide Editing Bar).
    var showsEditingBar = !Prefs.defaults.bool(forKey: Prefs.hidesEditingBar) {
        didSet { Prefs.defaults.set(!showsEditingBar, forKey: Prefs.hidesEditingBar) }
    }
    var inspectorTab: InspectorTab = InspectorTab(rawValue: Prefs.defaults.string(forKey: Prefs.inspectorTab) ?? "") ?? .document {
        didSet { Prefs.defaults.set(inspectorTab.rawValue, forKey: Prefs.inspectorTab) }
    }
    /// Bumped when title/author/subject/keywords change, so the inspector re-reads them.
    var infoRevision = 0
    /// Page count/size or the file changed (inspector facts).
    var fileURL: URL?
    /// The signature waiting to be placed with the next click.
    var pendingSignature: Signature?

    // Sidebar.
    var sidebarMode: SidebarMode = SidebarMode(rawValue: Prefs.defaults.string(forKey: Prefs.sidebarMode) ?? "") ?? .thumbnails {
        didSet {
            if sidebarMode == .thumbnails || sidebarMode == .outline || sidebarMode == .annotations {
                Prefs.defaults.set(sidebarMode.rawValue, forKey: Prefs.sidebarMode)
            }
        }
    }
    var pages: [PageItem] = []
    var selectedPages: Set<ObjectIdentifier> = []
    /// Bumped when a page's look changes, so its thumbnail re-renders.
    var pageVersions: [ObjectIdentifier: Int] = [:]
    var currentPageIndex = 0
    var hasOutline = false

    // Annotations.
    var selectedAnnotation: PDFAnnotation?
    var annotationsRevision = 0
    var markSummary = MarkSummary(markCount: 0, pageCount: 0)

    // Search.
    var searchQuery = ""
    var searchHits: [TextHit] = []
    var searchIndex: Int?
    var isSearching = false
    var searchedQuery = ""

    // Find and Redact.
    var redactQuery = ""
    var redactOptions = MatchOptions()
    var redactHits: [TextHit] = []
    var redactChecked: Set<String> = []
    var redactSearched = false

    // Document facts and info bars.
    var facts = DocumentFacts()
    var importedRedactions = 0
    var dismissedImportNotice = false
    var dismissedFormBar = false
    var dismissedScanBar = false
    var highlightFields = false
    var isLocked = false
    var hasTextLayer = true

    init(pdf: PDFDocument) {
        self.pdf = pdf
        if lineWidth <= 0 { lineWidth = 2 }
        if fontSize <= 0 { fontSize = 12 }
    }

    var isReadOnly: Bool { isLocked || facts.isReadOnly }

    var pageCount: Int { pdf.pageCount }

    func refreshPages() {
        pages = (0..<pdf.pageCount).compactMap { index in
            pdf.page(at: index).map { PageItem(id: ObjectIdentifier($0), page: $0) }
        }
        let valid = Set(pages.map(\.id))
        selectedPages = selectedPages.intersection(valid)
        refreshMarks()
    }

    func refreshMarks() {
        markSummary = MarkSummary(pageIndexes: RedactionMarks.marks(in: pdf).map(\.pageIndex))
        annotationsRevision += 1
    }

    func touch(_ page: PDFPage?) {
        guard let page else { return }
        pageVersions[ObjectIdentifier(page), default: 0] += 1
    }

    /// Selected pages as indexes, ascending. Falls back to the current page.
    var selectedIndexes: IndexSet {
        let indexes = IndexSet(selectedPages.compactMap { id in pages.firstIndex { $0.id == id } })
        if indexes.isEmpty, currentPageIndex < pdf.pageCount { return [currentPageIndex] }
        return indexes
    }

    func selectPages(_ indexes: IndexSet) {
        selectedPages = Set(indexes.compactMap { $0 < pages.count ? pages[$0].id : nil })
    }

    var authorFactory: AnnotationFactory { AnnotationFactory(author: Prefs.author) }
}
