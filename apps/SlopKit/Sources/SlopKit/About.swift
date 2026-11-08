import AppKit
import SwiftUI

/// The standard Slopapp About view: icon, name, tagline, version, where it comes from, and
/// Report a Problem… (`IssueReport`).
/// The only place besides the app icon where the brand appears.
public struct AboutView: View {
    let info: AppInfo
    /// In `AboutWindow`: the title bar is transparent and untitled, like the system About
    /// panels, so the icon starts right under the window buttons.
    var fillsWindow = false

    public init(info: AppInfo) {
        self.info = info
    }

    init(info: AppInfo, fillsWindow: Bool) {
        self.info = info
        self.fillsWindow = fillsWindow
    }

    public var body: some View {
        VStack(spacing: Spacing.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
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
            // Two lines on purpose, so it breaks between the sentences, not mid-phrase.
            Text("Part of \(Brand.name).\nFree and open source (\(Brand.license) license).")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("View source on GitHub", destination: Brand.repoURL)
                .font(.callout)
            // Opens the pre-filled issue form in the browser; nothing is sent from the app.
            Link(IssueReport.Kind.problem.title, destination: IssueReport.url(.problem, info: info))
                .font(.callout)
        }
        .padding([.horizontal, .bottom], Spacing.xxl)
        // In the window the transparent title bar above already gives the icon room.
        .padding(.top, fillsWindow ? 0 : Spacing.xxl)
        // 360 leaves 312 pt for the tagline, enough that the suite's taglines don't strand
        // a word on a line of its own.
        .frame(width: 360)
    }
}

/// Opens the About view in a small window. Menu bar apps have no window scene to host
/// it, so we manage one NSWindow ourselves.
@MainActor
public enum AboutWindow {
    private static var window: NSWindow?

    public static func show(info: AppInfo) {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView(info: info, fillsWindow: true))
            let newWindow = NSWindow(contentViewController: hosting)
            // Kept for the Window menu and VoiceOver, but not drawn: like the system About
            // panels, the window is just the close button over the content.
            newWindow.title = "About \(info.name)"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.titlebarSeparatorStyle = .none
            newWindow.isMovableByWindowBackground = true
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        // Shown from a menu bar menu, where the cooperative `NSApp.activate()` can be declined.
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
