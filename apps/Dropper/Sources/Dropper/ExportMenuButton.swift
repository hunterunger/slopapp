import AppKit
import DropperCore
import SwiftUI

/// A bordered "Export" button that opens the palette file formats as a menu under itself.
/// In a grouped `Form` on macOS 26 a SwiftUI `Menu` draws as plain text (or text and a round
/// arrow), which sat lighter and lower than the bordered buttons next to it.
struct ExportMenuButton: View {
    let export: (PaletteFileFormat) -> Void
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            anchor.popUp(items: PaletteFileFormat.allCases.map { format in (format.title, { export(format) }) })
        } label: {
            Text("Export")
        }
        .background(MenuAnchorView(anchor: anchor))
        .accessibilityHint("Shows the file formats")
    }
}

/// Holds the NSView a menu pops up under.
@MainActor
final class MenuAnchor {
    weak var view: NSView?

    func popUp(items: [(String, () -> Void)]) {
        let menu = NSMenu()
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let target = MenuAction(action)
            item.target = target
            item.representedObject = target // the item keeps its target alive
            menu.addItem(item)
        }
        guard let view else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        // Just under the button, leading edges aligned, like a pull-down.
        let below = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        menu.popUp(positioning: nil, at: CGPoint(x: view.bounds.minX, y: below), in: view)
    }
}

private final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
