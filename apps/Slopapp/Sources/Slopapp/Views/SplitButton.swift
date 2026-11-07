import AppKit
import SlopKit
import SwiftUI

// A split button: the main action on the left, an arrow on the right that drops down a
// native menu of the other actions. SwiftUI's own split button (`Menu` with
// `primaryAction`) can't take the prominent (accent-filled) style, and the main action
// here must read as the main action. Named so it can move to SlopKit later.

/// One menu row, or a separator.
struct MenuAction {
    var title: String
    var action: (() -> Void)?

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    private init() {
        title = ""
        action = nil
    }

    static var separator: MenuAction { MenuAction() }
    var isSeparator: Bool { action == nil }
}

struct SplitButton: View {
    let title: String
    var prominent: Bool
    var accessibilityLabel: String
    /// The arrow's name for VoiceOver ("More actions for Clips"); stays the same in every state.
    var menuLabel: String
    let action: () -> Void
    /// Built when the arrow is pressed, so it always reflects the current state.
    let items: () -> [MenuAction]
    @State private var controlFrame: CGRect = .zero

    init(title: String, prominent: Bool, accessibilityLabel: String, menuLabel: String,
         action: @escaping () -> Void, items: @escaping () -> [MenuAction]) {
        self.title = title
        self.prominent = prominent
        self.accessibilityLabel = accessibilityLabel
        self.menuLabel = menuLabel
        self.action = action
        self.items = items
    }

    var body: some View {
        // Two native buttons cut from one capsule (the shape of the other large buttons),
        // with a 1 pt gap between them. The arrow's label carries a hidden line of text so
        // both halves are exactly the same height.
        HStack(spacing: 1) {
            Button(action: action) {
                Text(title).frame(minWidth: 64)
            }
            .accessibilityLabel(accessibilityLabel)
            Button {
                PopUpMenu.show(items(), below: controlFrame)
            } label: {
                ZStack {
                    Text(verbatim: " ").hidden()
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .fontWeight(.semibold)
                }
                .frame(width: 12)
            }
            .accessibilityLabel(menuLabel)
            .help("More actions")
        }
        // The menu drops from the whole control's left edge, like a pop-up button's.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlFrame = $0 }
        .buttonBorderShape(.roundedRectangle(radius: 0))
        .modifier(SplitProminence(prominent: prominent))
        .controlSize(.large)
        .clipShape(Capsule())
        .fixedSize()
    }
}

/// A large bordered button with just a symbol, the same height as a text button beside it.
struct SymbolButton: View {
    let systemImage: String
    var tint: AnyShapeStyle = AnyShapeStyle(.primary)
    let action: () -> Void

    var body: some View {
        Button(action: action) { SymbolButtonLabel(systemImage: systemImage, tint: tint) }
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}

/// The label of a `SymbolButton` (also for `ShareLink`, which brings its own button).
struct SymbolButtonLabel: View {
    let systemImage: String
    var tint: AnyShapeStyle = AnyShapeStyle(.primary)

    var body: some View {
        ZStack {
            Text(verbatim: " ").hidden()
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .frame(width: 20)
    }
}

private struct SplitProminence: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Drops an NSMenu down from a SwiftUI frame in the key window.
@MainActor
enum PopUpMenu {
    private final class Target: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func show(_ items: [MenuAction], below frame: CGRect) {
        let menu = NSMenu()
        var targets: [Target] = []
        for item in items {
            if item.isSeparator {
                menu.addItem(.separator())
            } else if let run = item.action {
                let target = Target(run)
                targets.append(target)
                let menuItem = NSMenuItem(title: item.title, action: #selector(Target.fire), keyEquivalent: "")
                menuItem.target = target
                menu.addItem(menuItem)
            }
        }
        let library = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true && $0.isVisible }
        guard let window = library ?? NSApp.keyWindow, let content = window.contentView else { return }
        // SwiftUI's global frame is top-left based in the window's content; AppKit's isn't
        // unless the view is flipped.
        let y = content.isFlipped ? frame.maxY + Spacing.xs : content.bounds.height - frame.maxY - Spacing.xs
        _ = withExtendedLifetime(targets) {
            menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: y), in: content)
        }
    }
}
