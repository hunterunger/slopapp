import AppKit
import CrateCore
import SlopKit

/// Files opened with Crate (Open With, the Dock icon, `open -a`), the Finder services, and
/// a confirmation before quitting mid-job. Wraps SlopKit's standard delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()
    private let services = ServiceProvider()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["CRATE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let support = try? AppPaths.applicationSupport {
            WorkFolderLedger.shared.configure(file: support.appendingPathComponent("work-folders.txt"))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        SnapshotHook.start()
        // Leftovers from a crash or force quit.
        let cleanup = Task.detached(priority: .utility) {
            WorkFolderLedger.shared.cleanUpLeftovers()
            TemporaryFiles.cleanUp()
        }
        _ = cleanup
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.open(urls, explicit: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.isBusy || model.queue.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop and quit?"
        alert.informativeText = "The job that's running will stop, and anything it hasn't finished is removed. Your archives and files aren't affected."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        model.browse?.cancel()
        model.create?.cancel()
        model.queue.cancelAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        TemporaryFiles.cleanUp()
    }
}

/// "Extract with Crate" and "Compress with Crate" in Finder's Services menu.
final class ServiceProvider: NSObject {
    @objc func extractFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated {
            NSApp.activate()
            let archives = Router.distinctSets(urls.filter { ArchiveTypes.isArchive($0, explicitOpen: true) })
            if !archives.isEmpty { AppModel.shared.extractInQueue(archives) }
        }
    }

    @objc func extractFilesTo(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated {
            NSApp.activate()
            let archives = Router.distinctSets(urls.filter { ArchiveTypes.isArchive($0, explicitOpen: true) })
            guard !archives.isEmpty else { return }
            let model = AppModel.shared
            model.chooseFolder(message: "Choose where to put the extracted files.", prompt: "Extract Here", near: archives.first) { folder in
                model.settings.noteRecentFolder(folder)
                model.extractInQueue(archives, to: folder)
            }
        }
    }

    @objc func openFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated {
            NSApp.activate()
            AppModel.shared.open(urls, explicit: true, optionHeld: false)
        }
    }

    @objc func compressFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated {
            NSApp.activate()
            guard !urls.isEmpty, !AppModel.shared.isBusy else { return }
            AppModel.shared.screen = .create(CreateModel(sources: urls, app: AppModel.shared))
        }
    }
}
