import AppKit
import SlopKit

/// Files opened with Squish (Finder's Open With, the Dock icon, `open -a`), the Finder
/// service, and a confirmation before quitting mid-batch. Wraps SlopKit's standard delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()
    private let services = ServiceProvider()
    static var quitAlertOpen = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["SQUISH_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        Diagnostics.start()
        // Esc closes the About window, like other small info windows.
        // (Suite note: SlopKit's AboutWindow could do this itself.)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, let window = NSApp.keyWindow, window.title.hasPrefix("About ") else { return event }
            window.close()
            return nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainWindow.show()
        AppModel.shared.add(urls)
    }

    /// Dock icon or `open -a` with the window closed: bring the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MainWindow.window?.isVisible != true { MainWindow.show() }
        return standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never start quitting on our own while a batch runs (the close guard asks first).
        !AppModel.shared.queue.isBusy && standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = AppModel.shared.queue
        guard queue.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop compressing and quit?"
        alert.informativeText = "Files that haven't finished won't be saved. Your originals aren't affected."
        // The safe choice is the default, so a stray Return doesn't throw the batch away.
        alert.addButton(withTitle: "Keep Compressing")
        let quit = alert.addButton(withTitle: "Stop and Quit")
        quit.hasDestructiveAction = true
        // If the batch finishes while the user is deciding, there's nothing left to lose:
        // quit as they asked.
        AppDelegate.quitAlertOpen = true
        defer { AppDelegate.quitAlertOpen = false }
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        queue.cancelAll()
        return .terminateNow
    }
}

/// "Compress with Squish" in Finder's Quick Actions / Services menu.
final class ServiceProvider: NSObject {
    @objc func compressFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated {
            MainWindow.show()
            AppModel.shared.add(urls)
        }
    }
}
