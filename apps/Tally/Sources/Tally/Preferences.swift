import AppKit
import SwiftUI

/// UserDefaults keys and defaults, in one place.
enum Pref {
    static let downloadRates = "downloadRates"
    static let dollarCode = "dollarCode"
    static let copyIncludesUnit = "copyIncludesUnit"
    static let textSizeStep = "textSizeStep"
    static let settingsTab = "settingsTab"

    static var defaults: UserDefaults { .standard }

    static var isDownloadingRates: Bool { defaults.bool(forKey: downloadRates) }
    static var dollar: String { defaults.string(forKey: dollarCode) ?? "USD" }
    static var includesUnit: Bool { defaults.object(forKey: copyIncludesUnit) as? Bool ?? true }
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
