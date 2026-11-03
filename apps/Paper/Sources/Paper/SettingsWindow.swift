import AppKit
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(info: AppInfo) {
        if window == nil {
            let hosting = NSHostingController(rootView: SlopSettings(info: info, isMenuBarApp: false) { PaperGeneralSettings() })
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Paper Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.setFrameAutosaveName("PaperSettings")
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PaperGeneralSettings: View {
    @AppStorage(Prefs.openZoom) private var zoom = ZoomPreference.fitWidth.rawValue
    @AppStorage(Prefs.reopenAtLastPage) private var reopenAtLastPage = true
    @AppStorage(Prefs.authorName) private var author = ""
    @State private var isDefault = SettingsDefaultApp.isPaperDefault

    var body: some View {
        Picker("Open documents at", selection: $zoom) {
            ForEach(ZoomPreference.allCases) { Text($0.title).tag($0.rawValue) }
        }
        Toggle("Reopen documents at the last page viewed", isOn: $reopenAtLastPage)
        TextField("Author name for notes", text: $author, prompt: Text(NSFullUserName()))
        LabeledContent("Default PDF app") {
            if isDefault {
                Text("Paper opens PDFs").foregroundStyle(.secondary)
            } else {
                Button("Make Paper the Default") {
                    SettingsDefaultApp.makeDefault { isDefault = SettingsDefaultApp.isPaperDefault }
                }
            }
        }
    }
}

/// Paper never asks to become the default PDF app; this is the only way, and only on request.
@MainActor
enum SettingsDefaultApp {
    static var isPaperDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: .pdf)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault(done: @escaping @MainActor () -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf) { _ in
            Task { @MainActor in done() }
        }
    }
}
