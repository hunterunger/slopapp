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

    static var defaults: UserDefaults { .standard }

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
        ])
    }

    static var zoom: ZoomPreference { ZoomPreference(rawValue: defaults.string(forKey: openZoom) ?? "") ?? .fitWidth }

    /// The name written into annotations. Defaults to the Mac account's full name.
    static var author: String {
        let custom = defaults.string(forKey: authorName)?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? NSFullUserName() : custom
    }
}
