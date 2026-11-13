import AppKit
import ApplicationServices
import SwitchboardCore

/// Reads another app's menu bar through Accessibility and presses its items. Needs the
/// Accessibility permission. Nothing here is Switchboard-specific (SlopKit candidate).
@MainActor
enum AXMenuReader {
    /// An app's top-level menus: the Apple menu, the app menu, then File, Edit, ….
    static func menuBar(of pid: pid_t, timeout: Float = 1) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return nil }
        return children(of: bar)
    }

    /// The File menu's items: the first menu after the Apple and app menus that has a
    /// "new" item (⌘N or ⇧⌘N). Found by shortcut, so the language doesn't matter.
    static func fileMenuItems(in bar: [AXUIElement]) -> [AXUIElement]? {
        for item in bar.dropFirst(2) {
            let items = items(ofMenuBarItem: item)
            let hasNew = snapshot(items, depth: 1).contains {
                $0.commandKey?.uppercased() == "N" && ($0.modifiers == 0 || $0.modifiers == MenuItemSnapshot.shiftMask)
            }
            if hasNew { return items }
        }
        return nil
    }

    /// The items of a menu bar item's menu ("File" → New Window, New Private Window, …).
    static func items(ofMenuBarItem item: AXUIElement) -> [AXUIElement] {
        guard let menu = children(of: item).first else { return [] }
        return children(of: menu)
    }

    /// A snapshot of `items` and their submenus, `depth` levels deep, for pure matching.
    static func snapshot(_ items: [AXUIElement], depth: Int = 2) -> [MenuItemSnapshot] {
        items.map { item in
            var snapshot = MenuItemSnapshot(
                (attribute(item, kAXTitleAttribute) as String?) ?? "",
                key: attribute(item, kAXMenuItemCmdCharAttribute) as String?,
                modifiers: (attribute(item, kAXMenuItemCmdModifiersAttribute) as NSNumber?)?.intValue ?? 0,
                isEnabled: (attribute(item, kAXEnabledAttribute) as NSNumber?)?.boolValue ?? true
            )
            if depth > 1, let submenu = children(of: item).first {
                snapshot.children = self.snapshot(children(of: submenu), depth: depth - 1)
            }
            return snapshot
        }
    }

    /// The live item at `path` (indexes as in the snapshot).
    static func item(at path: [Int], in items: [AXUIElement]) -> AXUIElement? {
        guard let first = path.first, items.indices.contains(first) else { return nil }
        let item = items[first]
        if path.count == 1 { return item }
        guard let submenu = children(of: item).first else { return nil }
        return self.item(at: Array(path.dropFirst()), in: children(of: submenu))
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// How many windows the app has (to notice a new one).
    static func windowCount(of pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let windows: [AXUIElement]? = attribute(app, kAXWindowsAttribute)
        return windows?.count ?? 0
    }

    /// One line per item for the diagnostics log: position, shortcut, enabled. Never titles:
    /// other apps put documents' and files' names in their menus.
    static func describe(_ items: [MenuItemSnapshot], path: String = "") -> [String] {
        items.enumerated().flatMap { index, item -> [String] in
            let here = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let key = item.commandKey.map { " key=\($0) mods=\(item.modifiers)" } ?? ""
            let line = "item \(here)\(item.title.isEmpty ? " separator" : "")\(key)\(item.isEnabled ? "" : " disabled")"
            return [line] + describe(item.children, path: here)
        }
    }

    // MARK: - Plumbing

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? []
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }
}
