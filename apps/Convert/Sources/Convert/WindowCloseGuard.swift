import AppKit
import SwiftUI

/// Asks before the main window closes (close button, ⌘W) while files are converting.
/// Closing the window quits Convert, so Cancel must keep the window and the work.
///
/// It only retargets the window's close button; it never replaces the window's delegate.
/// (Round 2: wrapping SwiftUI's window delegate made SwiftUI lose track of its window, so
/// opening a file from Finder closed the window and quit the app.)
/// Named so it could move to SlopKit as a "confirm close while busy" option for window apps.
struct WindowCloseGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GuardView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? GuardView)?.attach()
    }

    final class GuardView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            guard let button = window?.standardWindowButton(.closeButton), button.target !== CloseConfirmer.shared else { return }
            button.target = CloseConfirmer.shared
            button.action = #selector(CloseConfirmer.closeClicked(_:))
        }
    }
}

@MainActor
final class CloseConfirmer: NSObject {
    static let shared = CloseConfirmer()

    @objc func closeClicked(_ sender: NSButton) {
        guard let window = sender.window else { return }
        close(window)
    }

    /// Closes `window`, asking first if files are converting. Used by the close button and ⌘W.
    func close(_ window: NSWindow) {
        guard confirmStop() else { return }
        if window.delegate?.windowShouldClose?(window) == false { return }
        window.close()
    }

    /// True when nothing is converting, or the user chose to stop it.
    func confirmStop() -> Bool {
        let queue = AppModel.shared.queue
        guard queue.isBusy else { return true }
        let alert = NSAlert()
        let remaining = queue.summary.remaining
        alert.messageText = remaining == 1 ? "Stop converting and close?" : "Stop \(remaining) conversions and close?"
        alert.informativeText = "Closing the window quits Convert. Files that haven't finished won't be saved. Your originals aren't affected."
        alert.addButton(withTitle: "Stop and Close")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        queue.cancelAll()
        return true
    }
}
