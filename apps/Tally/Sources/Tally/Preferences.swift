import AppKit
import SwiftUI
import TallyCore

/// UserDefaults keys and defaults, in one place.
enum Pref {
    static let downloadRates = "downloadRates"
    static let dollarCode = "dollarCode"
    static let copyIncludesUnit = "copyIncludesUnit"
    static let textSizeStep = "textSizeStep"
    static let settingsTab = "settingsTab"
    static let theme = "theme"
    static let showsMenuBarIcon = "showsMenuBarIcon"
    static let showsDockIcon = "showsDockIcon"
    static let suggestsNames = "suggestsNames"
    static let cssEm = "cssEm"
    static let cssPPI = "cssPPI"
    static let floatsOnTop = "floatsOnTop"
    static let showsSidebar = "showsSidebar"

    /// `TALLY_DEFAULTS_SUITE` keeps tests and walkthroughs out of the real settings.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["TALLY_DEFAULTS_SUITE"], !suite.isEmpty,
           let d = UserDefaults(suiteName: suite) {
            return d
        }
        return .standard
    }()

    static var isDownloadingRates: Bool { defaults.bool(forKey: downloadRates) }
    static var dollar: String { defaults.string(forKey: dollarCode) ?? "USD" }
    static var includesUnit: Bool { defaults.object(forKey: copyIncludesUnit) as? Bool ?? true }
    static var themeID: String { defaults.string(forKey: theme) ?? Theme.system.id }
    static var isMenuBarIconShown: Bool { defaults.bool(forKey: showsMenuBarIcon) }
    /// The Dock icon can only be hidden while the menu bar icon is shown.
    static var isDockIconShown: Bool { !isMenuBarIconShown || (defaults.object(forKey: showsDockIcon) as? Bool ?? true) }
    static var isSuggestingNames: Bool { defaults.object(forKey: suggestsNames) as? Bool ?? true }

    static var css: CSSMetrics {
        let em = defaults.double(forKey: cssEm), ppi = defaults.double(forKey: cssPPI)
        return CSSMetrics(ppi: ppi > 0 ? Decimal(ppi) : 96, em: em > 0 ? Decimal(em) : 16)
    }
}

/// Text sizes, relative to the system's Title 3 style so they follow the system's type.
enum TextSize {
    static let multipliers: [CGFloat] = [0.7, 0.8, 0.87, 0.93, 1, 1.13, 1.27, 1.47, 1.73, 2.07, 2.47]
    static let defaultStep = 4

    static var base: CGFloat { NSFont.preferredFont(forTextStyle: .title3).pointSize }

    static func pointSize(step: Int) -> CGFloat {
        (base * multipliers[clamp(step)]).rounded()
    }

    static func clamp(_ step: Int) -> Int { min(max(step, 0), multipliers.count - 1) }
}
