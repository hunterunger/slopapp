import Foundation

/// Free, open-source Mac apps we recommend instead of rebuilding.
public struct RecommendedApp: Sendable, Equatable, Identifiable {
    public var name: String
    public var summary: String
    public var website: URL
    /// To show "Installed" and Open when it's already on the Mac.
    public var bundleIDs: [String]
    /// An SF Symbol for the row (inside the app UI only).
    public var symbol: String

    public var id: String { name }

    public static let all: [RecommendedApp] = [
        RecommendedApp(
            name: "Rectangle", summary: "Move and resize windows with keyboard shortcuts and snap areas.",
            website: URL(string: "https://rectangleapp.com")!, bundleIDs: ["com.knollsoft.Rectangle"],
            symbol: "rectangle.split.2x1"
        ),
        RecommendedApp(
            name: "Maccy", summary: "A lightweight clipboard manager that stays out of the way.",
            website: URL(string: "https://maccy.app")!, bundleIDs: ["org.p0deje.Maccy"],
            symbol: "doc.on.clipboard"
        ),
        RecommendedApp(
            name: "IINA", summary: "A modern video player for macOS that plays nearly anything.",
            website: URL(string: "https://iina.io")!, bundleIDs: ["com.colliderli.iina"],
            symbol: "play.rectangle"
        ),
        RecommendedApp(
            name: "Keka", summary: "Create and extract archives: zip, 7z, rar and many more.",
            website: URL(string: "https://www.keka.io")!, bundleIDs: ["com.aone.keka"],
            symbol: "archivebox"
        ),
        RecommendedApp(
            name: "AlDente", summary: "Limit battery charging to keep a MacBook battery healthy.",
            website: URL(string: "https://apphousekitchen.com")!, bundleIDs: ["com.apphousekitchen.aldente-pro", "com.apphousekitchen.aldente"],
            symbol: "battery.75percent"
        ),
        RecommendedApp(
            name: "Stats", summary: "System monitor in the menu bar: CPU, memory, network, sensors.",
            website: URL(string: "https://github.com/exelban/stats")!, bundleIDs: ["eu.exelban.Stats"],
            symbol: "chart.bar.xaxis"
        ),
    ]
}
