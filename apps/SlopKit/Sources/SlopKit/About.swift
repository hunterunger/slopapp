import AppKit
import SwiftUI

/// The standard Slopapp About view: icon, name, tagline, version, and where it comes from.
/// The only place besides the app icon where the brand appears.
public struct AboutView: View {
    let info: AppInfo

    public init(info: AppInfo) {
        self.info = info
    }

    public var body: some View {
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
            Divider().padding(.vertical, Spacing.xs)
            Text("Part of \(Brand.name). Free and open source (\(Brand.license) license).")
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

/// Opens the About view in a small window. Menu bar apps have no window scene to host
/// it, so we manage one NSWindow ourselves.
@MainActor
public enum AboutWindow {
    private static var window: NSWindow?

    public static func show(info: AppInfo) {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView(info: info))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "About \(info.name)"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        // Shown from a menu bar menu, where the cooperative `NSApp.activate()` can be declined.
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
