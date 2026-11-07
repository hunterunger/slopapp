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
    /// On a dark card: always use dark appearance.
    var dark = false
    /// Tinted with the accent colour (the file has its own setting here).
    var highlighted = false
    /// The window is key: the highlight is the accent, else grey (Golden Gate greys accents
    /// in windows you aren't using).
    var active = true
    /// A fixed size, so it lines up with SwiftUI buttons next to it (a width of 0 keeps
    /// its natural width). Nil: its natural size.
    var size: CGSize?
    /// A standard bordered pop-up (for forms, where it lines up with the other controls).
    var bordered = false
    let entries: () -> [BarMenuEntry]

    init(name: String, value: String, symbol: String, help: String, dark: Bool = false, highlighted: Bool = false,
         active: Bool = true, size: CGSize? = nil, bordered: Bool = false, entries: @escaping () -> [BarMenuEntry]) {
        self.name = name
        self.value = value
        self.symbol = symbol
        self.help = help
        self.dark = dark
        self.highlighted = highlighted
        self.active = active
        self.size = size
        self.bordered = bordered
        self.entries = entries
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Button, context: Context) -> CGSize? {
        guard let size else { return nil }
        let natural = nsView.intrinsicContentSize
        return CGSize(width: size.width > 0 ? size.width : natural.width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Reports its fixed name as the accessibility title (AppKit would use the value).
    final class Button: NSPopUpButton {
        var name = ""
        override func accessibilityTitle() -> String? { name }
        override func accessibilityLabel() -> String? { name }
    }

    func makeNSView(context: Context) -> Button {
        let button = Button(frame: .zero, pullsDown: true)
        button.isBordered = bordered
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
        let image = symbol.isEmpty ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        // On cards the symbols match the SwiftUI tool buttons beside them.
        titleItem?.image = dark ? image?.withSymbolConfiguration(CardTools.symbolConfiguration) : image
        button.imagePosition = value.isEmpty ? .imageOnly : .imageLeading
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = value.isEmpty ? .noArrow : .arrowAtBottom
        // Icon-only: centred in its box.
        button.alignment = value.isEmpty ? .center : .natural
        button.appearance = dark ? NSAppearance(named: .darkAqua) : nil
        button.contentTintColor = highlighted ? (active ? .controlAccentColor : .secondaryLabelColor) : nil
        if dark { button.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: highlighted ? .semibold : .regular) }
        button.synchronizeTitleAndSelectedItem()
        button.toolTip = help
        button.setAccessibilityLabel(name)
        button.setAccessibilityValue(value.isEmpty ? help : value)
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
