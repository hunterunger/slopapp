import AppKit
import SwiftUI

/// One entry in a bar menu.
enum BarMenuEntry {
    /// A checkmarked choice with an optional one-line subtitle.
    case choice(String, detail: String?, isOn: Bool, action: () -> Void)
    case action(String, action: () -> Void)
    /// A disabled line of explanation.
    case note(String)
    case separator
}

/// A borderless pull-down button with an icon and the current value, for option bars.
/// AppKit, not a SwiftUI `Menu`, so its accessibility name stays fixed ("Image format") with
/// the current value separate: SwiftUI's menu button renamed itself to its value once another
/// view took keyboard focus (blind test round 2, F3). Menu items are rebuilt each time it
/// opens, so they always show the current state. Named so it could move to SlopKit.
struct BarMenuButton: NSViewRepresentable {
    let name: String
    let value: String
    let symbol: String
    let help: String
    let entries: () -> [BarMenuEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Reports its fixed name as the accessibility title (AppKit would use the value).
    final class Button: NSPopUpButton {
        var name = ""
        override func accessibilityTitle() -> String? { name }
        override func accessibilityLabel() -> String? { name }
    }

    func makeNSView(context: Context) -> Button {
        let button = Button(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.menu?.delegate = context.coordinator
        button.menu?.addItem(NSMenuItem()) // the title item a pull-down shows
        button.setContentHuggingPriority(.required, for: .horizontal)
        update(button, context: context)
        return button
    }

    func updateNSView(_ button: Button, context: Context) {
        update(button, context: context)
    }

    private func update(_ button: Button, context: Context) {
        button.name = name
        context.coordinator.entries = entries
        let titleItem = button.menu?.items.first
        titleItem?.title = value
        titleItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.synchronizeTitleAndSelectedItem()
        button.toolTip = help
        button.setAccessibilityLabel(name)
        button.setAccessibilityValue(value)
        button.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var entries: () -> [BarMenuEntry] = { [] }
        private var actions: [() -> Void] = []

        func menuNeedsUpdate(_ menu: NSMenu) {
            // Keep the title item (index 0) and rebuild the rest.
            while menu.items.count > 1 { menu.removeItem(at: 1) }
            actions = []
            for entry in entries() {
                switch entry {
                case .choice(let title, let detail, let isOn, let action):
                    let item = add(title, action, to: menu)
                    item.state = isOn ? .on : .off
                    if let detail, #available(macOS 14.4, *) { item.subtitle = detail }
                case .action(let title, let action):
                    add(title, action, to: menu)
                case .note(let text):
                    let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                case .separator:
                    menu.addItem(.separator())
                }
            }
        }

        @discardableResult
        private func add(_ title: String, _ action: @escaping () -> Void, to menu: NSMenu) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            actions.append(action)
            menu.addItem(item)
            return item
        }

        @objc func fire(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
        }
    }
}
