import AppKit
import SlopKit
import SwiftUI

// Store-window chrome: no visible title bar or toolbar band, full-size window buttons, the
// sidebar running to the top of the window, and the content in an inset rounded panel.
// Generic (no Slopapp types), so it can move to SlopKit once another app wants it.

enum WindowChrome {
    /// The sidebar column, up to the content panel.
    static let sidebarWidth: CGFloat = 196
    /// Gap between the content panel and the window's top, right and bottom edges.
    static let panelInset: CGFloat = 6
    /// The window buttons' centre line, measured from the window's top. A unified toolbar
    /// puts them here on macOS 14 through 27; Back/Forward and the content header line up with it.
    static let buttonRowCenter: CGFloat = 26
    /// Height of the row the window buttons sit in (twice their centre line).
    static var buttonRowHeight: CGFloat { buttonRowCenter * 2 }
    /// The content panel's header row (search, status), which lines up with the window buttons.
    static var panelHeaderHeight: CGFloat { (buttonRowCenter - panelInset) * 2 }
    /// Where a page's content starts, from the window's top: below the header, plus the
    /// page's top margin. The sidebar's first row starts here too.
    static var pageTop: CGFloat { panelInset + panelHeaderHeight + Spacing.xxl }
}

extension View {
    /// Full-size window buttons over content that runs to the top of the window.
    ///
    /// The window gets a transparent title bar, a hidden title (it's still set, for the
    /// Window menu and VoiceOver) and an empty unified toolbar. The empty toolbar is what makes
    /// the title bar tall enough for full-size (16 pt) window buttons; a compact title bar
    /// gets the small ones. With no items in it, clicks there reach the SwiftUI content.
    func storeWindowChrome() -> some View {
        background(StoreWindowConfigurator().frame(width: 0, height: 0).accessibilityHidden(true))
            .modifier(HiddenToolbarBackground())
    }
}

/// macOS 26+ draws a blurred backdrop and the window title in a toolbar; the content draws
/// its own top row.
private struct HiddenToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // The title stays set (Window menu, VoiceOver) but isn't drawn in the toolbar.
            content
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
        } else {
            content.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

private struct StoreWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView() }
    func updateNSView(_ view: ConfiguringView, context: Context) { view.configure() }

    final class ConfiguringView: NSView {
        private var titleObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
            // SwiftUI shows the title again when the page's title changes; keep it hidden.
            titleObservation = window?.observe(\.titleVisibility, options: [.new]) { window, _ in
                MainActor.assumeIsolated {
                    if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                }
            }
        }

        func configure() {
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "store-window-chrome")
                toolbar.allowsUserCustomization = false
                toolbar.displayMode = .iconOnly
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
        }
    }
}

/// Empty chrome you can drag the window by (and double-click to zoom or minimize, as set in
/// System Settings), for the strips along the top that have no controls.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// The sidebar's translucent material, behind the whole window (the content panel covers
/// the rest).
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The inset, rounded content area beside the sidebar, its corners concentric with the
/// window's (SlopKit `windowConcentric`).
struct ContentPanel<Content: View>: View {
    /// The panel's surface (the launcher passes its Nordic paper).
    var fill: Color = Color(nsColor: .textBackgroundColor)
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A hairline keeps the paper panel distinct from the light sidebar; in dark mode
            // the darker panel stands out on its own.
            .windowConcentric(
                fill: fill,
                inset: WindowChrome.panelInset,
                hairline: Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.35 : 0.6)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 2, y: 1)
    }
}
