import AppKit
import SwiftUI

/// Asks before the main window closes while files are still compressing. Closing the last
/// window quits the app (SlopAppDelegate), so without this, ⌘W or the close button would
/// throw away the batch. It takes over the window's close button (and ⌘W goes through
/// `WindowCloser`), leaving SwiftUI's window delegate alone.
///
/// Suite note: the cleaner fix is a "busy" hook on SlopKit's SlopAppDelegate that window
/// apps can set, so every drop-in app gets this for free.
struct CloseGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ view: GuardView, context: Context) {}

    final class GuardView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let button = window.standardWindowButton(.closeButton) else { return }
            CloseConfirmation.mainWindow = window
            button.target = CloseConfirmation.shared
            button.action = #selector(CloseConfirmation.closeButtonClicked(_:))
        }
    }
}

@MainActor
final class CloseConfirmation: NSObject {
    static let shared = CloseConfirmation()
    static weak var mainWindow: NSWindow?
    private var asking = false

    @objc func closeButtonClicked(_ sender: Any?) {
        guard let window = (sender as? NSView)?.window ?? Self.mainWindow else { return }
        close(window)
    }

    /// Closes `window`, first asking (as a sheet) if it's the main window and work is running.
    func close(_ window: NSWindow) {
        guard window === Self.mainWindow, AppModel.shared.queue.isBusy else {
            window.close()
            return
        }
        guard !asking else { return }
        asking = true
        let alert = NSAlert()
        alert.messageText = "Stop compressing and quit?"
        alert.informativeText = "Files that haven't finished won't be saved. Your originals aren't affected."
        // The safe choice is the default, so a stray Return doesn't throw the batch away.
        alert.addButton(withTitle: "Keep Compressing")
        let quit = alert.addButton(withTitle: "Stop and Quit")
        quit.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                self?.asking = false
                guard response == .alertSecondButtonReturn else { return }
                AppModel.shared.queue.cancelAll()
                window.close()
            }
        }
    }
}
