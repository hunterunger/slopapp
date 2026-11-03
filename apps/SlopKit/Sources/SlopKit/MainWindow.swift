import AppKit
import SwiftUI

/// Brings back a single-window app's main `Window` scene after the user closed it, from
/// anywhere: the Dock icon (reopen), files opened with the app, a Services call, or the
/// Window ▸ <App> menu item (⌘0).
///
///     Window("Squish", id: "main") { MainView() }
///         .commands { MainWindowCommands(title: "Squish", id: "main") }   // Window ▸ Squish ⌘0
///
///     // App delegate:
///     func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
///         if !hasVisibleWindows { MainWindow.show() }
///         return true
///     }
///     func application(_: NSApplication, open urls: [URL]) { MainWindow.show(); model.add(urls) }
///
/// `MainWindowCommands` registers SwiftUI's `openWindow` action at launch, so `show()`
/// works even when no view of the app exists.
@MainActor
public enum MainWindow {
    private static var open: OpenWindowAction?
    public private(set) static var id = "main"

    /// Called by `MainWindowCommands`; call it yourself if you don't use them.
    public static func register(_ openWindow: OpenWindowAction, id: String) {
        open = openWindow
        self.id = id
    }

    /// The main window if it exists (visible or not).
    public static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id || $0.identifier?.rawValue.hasPrefix(id + "-") == true }
    }

    /// Shows the main window, recreating it if it was closed, and brings the app forward.
    public static func show() {
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            open?(id: id)
        }
        NSApp.activate()
    }
}

/// Adds Window ▸ <title> (⌘0) and registers the scene with `MainWindow`.
public struct MainWindowCommands: Commands {
    let title: String
    let id: String
    @Environment(\.openWindow) private var openWindow

    public init(title: String, id: String = "main") {
        self.title = title
        self.id = id
    }

    public var body: some Commands {
        // Registering here (commands are built at launch) is what lets `MainWindow.show()`
        // work from the app delegate before or after any window exists.
        let _ = MainWindow.register(openWindow, id: id)
        CommandGroup(before: .windowList) {
            Button(title) { MainWindow.show() }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
