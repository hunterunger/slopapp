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
            WindowLayout.upgradeIfNeeded(window)
            // Don't start with the cursor in an options field: typing (or an arrow key)
            // would change a setting. The list takes focus once it has files.
            DispatchQueue.main.async {
                if window.firstResponder is NSText { window.makeFirstResponder(nil) }
            }
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

/// Squish 0.1 had a compact one-column window (560 pt). The three-column layout needs more
/// room, so the first launch after the change widens a remembered small window once.
@MainActor
enum WindowLayout {
    private static let key = "threeColumnLayout"

    static func upgradeIfNeeded(_ window: NSWindow) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.async {
            guard window.frame.width < 1000, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let size = CGSize(width: min(1080, visible.width), height: min(660, visible.height))
            var frame = CGRect(x: window.frame.midX - size.width / 2, y: window.frame.maxY - size.height, width: size.width, height: size.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
