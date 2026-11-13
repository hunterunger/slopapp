import AppKit
import PaperCore

/// How a document's zoom is chosen when it opens.
enum ZoomPreference: String, CaseIterable, Identifiable {
    case fitWidth, fitPage, actualSize
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fitWidth: "Fit Width"
        case .fitPage: "Fit Page"
        case .actualSize: "Actual Size"
        }
    }
}

/// UserDefaults keys and typed accessors. Settings binds to the same keys with @AppStorage.
enum Prefs {
    static let openZoom = "openZoom"
    static let reopenAtLastPage = "reopenAtLastPage"
    static let authorName = "authorName"
    static let highlightColor = "highlightColor"
    static let markupStyle = "markupStyle"
    static let shapeKind = "shapeKind"
    static let inkColor = "inkColor"
    static let lineWidth = "lineWidth"
    static let fontSize = "fontSize"
    static let textColor = "textColor"
    static let sidebarMode = "sidebarMode"
    static let drawUsesShape = "drawUsesShape"
    static let commentUsesNote = "commentUsesNote"
    static let hidesEditingBar = "hidesEditingBar"
    static let inspectorTab = "inspectorTab"
    static let formKind = "formKind"
    static let imageFormat = "imageExportFormat"
    static let imageDPI = "imageExportDPI"

    /// Test hook: PAPER_DEFAULTS_SUITE keeps snapshot and walkthrough runs out of the real
    /// preferences.
    nonisolated(unsafe) static let defaults: UserDefaults =
        ProcessInfo.processInfo.environment["PAPER_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:)) ?? .standard

    /// True when a test run keeps its preferences in a separate suite. Window frames, split
    /// positions and the toolbar layout aren't autosaved then, so nothing reaches the real domain.
    static let isTestSuite = ProcessInfo.processInfo.environment["PAPER_DEFAULTS_SUITE"] != nil

    static func register() {
        defaults.register(defaults: [
            openZoom: ZoomPreference.fitWidth.rawValue,
            reopenAtLastPage: true,
            highlightColor: InkColor.yellow.rawValue,
            markupStyle: MarkupStyle.highlight.rawValue,
            shapeKind: ShapeKind.rectangle.rawValue,
            inkColor: InkColor.red.rawValue,
            lineWidth: 2.0,
            fontSize: 12.0,
            textColor: InkColor.black.rawValue,
            imageFormat: ImageExport.Format.png.rawValue,
            imageDPI: 150,
        ])
    }

    static var zoom: ZoomPreference { ZoomPreference(rawValue: defaults.string(forKey: openZoom) ?? "") ?? .fitWidth }

    /// The name written into annotations. Defaults to the Mac account's full name.
    static var author: String {
        let custom = defaults.string(forKey: authorName)?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? NSFullUserName() : custom
    }
}
