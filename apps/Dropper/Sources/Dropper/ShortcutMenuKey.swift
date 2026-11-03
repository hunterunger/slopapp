import SlopKit
import SwiftUI

// Shared with Clips (which has its own copy): candidates to move into SlopKit.

extension KeyboardShortcuts.Shortcut {
    /// The shortcut as a SwiftUI key equivalent, so a menu item can show it. Letters and
    /// digits only.
    var menuKey: KeyEquivalent? {
        guard let last = description.last, last.isLetter || last.isNumber else { return nil }
        return KeyEquivalent(Character(last.lowercased()))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

extension View {
    /// Shows a global shortcut next to a menu item (it fires globally either way).
    @ViewBuilder
    func globalShortcut(_ name: KeyboardShortcuts.Name) -> some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name), let key = shortcut.menuKey {
            keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}
