import AppKit
import SlopKit
import SwiftUI

// The hub's own About. SlopKit's AboutView says "Part of Slopapp", which reads oddly in
// Slopapp itself, so the hub has this variant and uses it everywhere About appears (app
// menu, menu bar menu, Settings). Named so it can move into SlopKit as a "hub" option.

struct HubAboutView: View {
    let info: AppInfo

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(info.name).font(.title2.bold())
            if !info.tagline.isEmpty {
                Text(info.tagline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(info.versionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Hairline().padding(.vertical, Spacing.xs)
            Text("Free and open source (\(Brand.license) license). No account, no tracking: Slopapp only downloads the catalog and the apps you choose.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("View source on GitHub", destination: Brand.repoURL)
                .font(.callout)
        }
        .padding(Spacing.xxl)
        .frame(width: 320)
    }
}

@MainActor
enum HubAboutWindow {
    private static var window: NSWindow?

    static func show(info: AppInfo) {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: HubAboutView(info: info)))
            // Titled (for the Window menu and VoiceOver) but drawn like the system's About
            // panels: no visible title, no separator, the content up to the window buttons.
            newWindow.title = "About \(info.name)"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.titlebarSeparatorStyle = .none
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// SlopKit's MenuFooter (Settings…, About, Quit) with the hub's About.
struct HubMenuFooter: View {
    let info: AppInfo
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Divider()
        Button("Settings…") {
            NSApp.activate()
            openSettings()
            SettingsWindow.bringToFront()
        }
        .keyboardShortcut(",")
        Button("About \(info.name)") { HubAboutWindow.show(info: info) }
        Divider()
        Button("Quit \(info.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
