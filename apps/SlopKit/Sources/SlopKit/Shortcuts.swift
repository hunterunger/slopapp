@_exported import KeyboardShortcuts
import SwiftUI

// Global shortcuts come from sindresorhus/KeyboardShortcuts, re-exported here so apps only
// `import SlopKit`. Declare names in the app:
//
//     extension KeyboardShortcuts.Name {
//         static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.option, .shift]))
//     }
//     KeyboardShortcuts.onKeyUp(for: .togglePanel) { ... }

/// One labeled shortcut recorder for the Shortcuts tab in Settings, with an optional
/// explanation shown as the row's subtitle (secondary text under the title, like every
/// Settings explanation):
///
///     ShortcutRow("Show or hide Tally", subtitle: "Works from any app.", name: .toggleWindow)
public struct ShortcutRow: View {
    let title: String
    let subtitle: String?
    let name: KeyboardShortcuts.Name

    public init(_ title: String, subtitle: String? = nil, name: KeyboardShortcuts.Name) {
        self.title = title
        self.subtitle = subtitle
        self.name = name
    }

    public var body: some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
        } label: {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
            }
        }
    }
}

// KeyboardShortcuts 1.10 predates Swift 6 and doesn't mark `Name` as Sendable, so
// `static let` names fail strict concurrency checking. `Name` is an immutable value
// (a raw string plus an optional default shortcut), so the conformance is safe.
extension KeyboardShortcuts.Name: @retroactive @unchecked Sendable {}
