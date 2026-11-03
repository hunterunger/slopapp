import __NAME__Core
import SlopKit
import SwiftUI

// Archetype: drop-in utility window or library window. See docs/design-system.md, 2b/2c.

@main
struct __NAME__App: App {
    @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
    private let info = AppInfo.current(fallbackName: "__NAME__")

    var body: some Scene {
        // One window. Closing it quits the app (SlopAppDelegate).
        Window("__NAME__", id: "main") {
            ContentView()
        }
        .defaultSize(Metrics.utilityWindowSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About __NAME__") { AboutWindow.show(info: info) }
            }
        }

        Settings {
            SlopSettings(info: info, isMenuBarApp: false)
        }
    }
}

struct ContentView: View {
    @State private var files: [URL] = []

    var body: some View {
        // Drop-in utilities start with a DropZone. Library apps: use NavigationSplitView.
        VStack(alignment: .leading, spacing: Spacing.m) {
            DropZone("Drop files here", types: [.item]) { files = $0 }
            if !files.isEmpty {
                Text(files.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(Spacing.windowMargin)
        .frame(minWidth: 420, minHeight: 320)
    }
}
