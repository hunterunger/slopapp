import AppKit
import PaperCore
import SlopKit
import UniformTypeIdentifiers

/// Paper's app delegate. It can't be `SlopAppDelegate`: that one quits when the last window
/// closes, which is right for single-window utilities and wrong for a document app.
@MainActor
final class PaperAppDelegate: NSObject, NSApplicationDelegate {
    let info = AppInfo.current(fallbackName: "Paper")

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.register()
        ShareFiles.clearOld()
        // Test hook: screenshot light and dark without changing the system appearance.
        switch ProcessInfo.processInfo.environment["PAPER_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// Document apps stay open with no windows (File > Open, the Dock icon).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching with no document, or clicking the Dock icon with no windows, shows the Open
    /// panel (as TextEdit does). Paper doesn't create empty documents.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        ProcessInfo.processInfo.environment["SLOPAPP_SMOKE_TEST"] == nil && !Snapshots.isActive
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshots.runIfAsked()
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        LaunchOpenPanel.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showAbout(_ sender: Any?) { AboutWindow.show(info: info) }

    @objc func showSettings(_ sender: Any?) { SettingsWindow.show(info: info) }

    @objc func showCombine(_ sender: Any?) { CombineWindow.show() }

    @objc func showHelp(_ sender: Any?) {
        NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Paper#readme"))
    }
}

/// The Open panel shown when Paper launches with nothing to open. Same as File > Open, but it
/// appears without the window animation so the first window is up quickly.
@MainActor
enum LaunchOpenPanel {
    static func show() {
        let panel = NSOpenPanel()
        panel.animationBehavior = .none
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf] + PaperDocumentController.imageTypes
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK else { return }
                for url in panel.urls {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
        }
    }
}

