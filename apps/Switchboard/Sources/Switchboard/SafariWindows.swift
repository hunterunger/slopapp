import AppKit
import ApplicationServices
import SwitchboardCore

/// Opens a Safari private window or profile window, then gives Safari the link. Safari has no
/// API, command line or scripting for either, so this picks the item from Safari's File menu
/// (Accessibility), waits for the new window, and opens the link, which lands in the front
/// window. Behind a protocol so the router can be exercised without Safari.
@MainActor
protocol SafariWindowOpening {
    func open(_ request: SafariWindowRequest, url: URL, safariURL: URL) async throws
    /// The profile names in Safari's File ▸ New Window menu (Safari must be running).
    func profileNames(safariURL: URL) -> [String]?
}

enum SafariWindowError: Error, Equatable {
    case needsAccessibility
    case didntStart
    case noMenu
    case noSuchProfile(String)
    case noPrivateWindowItem
    case windowDidntOpen

    /// What the HUD says.
    var message: String {
        switch self {
        case .needsAccessibility:
            "Safari profiles and private windows need Accessibility. Turn it on in Switchboard's Settings › Browsers."
        case .didntStart:
            "Safari didn't start. Try again."
        case .noMenu:
            "Couldn't read Safari's menus. Try again once Safari has finished opening."
        case .noSuchProfile(let name):
            "Safari has no profile named “\(name)”. Check the name in Switchboard's Settings › Browsers."
        case .noPrivateWindowItem:
            "Couldn't find New Private Window in Safari's File menu."
        case .windowDidntOpen:
            "Safari didn't open the new window, so the link wasn't opened there."
        }
    }
}

@MainActor
struct AccessibilitySafariOpener: SafariWindowOpening {
    func open(_ request: SafariWindowRequest, url: URL, safariURL: URL) async throws {
        guard AXIsProcessTrusted() else { throw SafariWindowError.needsAccessibility }
        let safari = try await runningSafari(at: safariURL)
        NSApp.yieldActivation(to: safari)
        safari.activate()

        // Safari's menus exist a moment after launch: wait up to 5 s for File.
        var fileItems: [AXUIElement] = []
        for _ in 0..<100 {
            if let bar = AXMenuReader.menuBar(of: safari.processIdentifier), let items = AXMenuReader.fileMenuItems(in: bar) {
                fileItems = items
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !fileItems.isEmpty else { throw SafariWindowError.noMenu }

        let snapshot = AXMenuReader.snapshot(fileItems)
        guard let path = SafariMenu.path(for: request, inFileMenu: snapshot),
              let item = AXMenuReader.item(at: path, in: fileItems) else {
            switch request {
            case .privateWindow: throw SafariWindowError.noPrivateWindowItem
            case .profile(let name): throw SafariWindowError.noSuchProfile(name)
            }
        }
        let before = AXMenuReader.windowCount(of: safari.processIdentifier)
        guard AXMenuReader.press(item) else { throw SafariWindowError.noMenu }

        // The link goes to whichever window is in front, so only open it once the new one is.
        var opened = false
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(50))
            if AXMenuReader.windowCount(of: safari.processIdentifier) > before { opened = true; break }
        }
        guard opened else { throw SafariWindowError.windowDidntOpen }
        // A beat for Safari to make it the key window.
        try await Task.sleep(for: .milliseconds(80))

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        try await NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: configuration)
    }

    func profileNames(safariURL: URL) -> [String]? {
        guard AXIsProcessTrusted(),
              let id = Bundle(url: safariURL)?.bundleIdentifier,
              let safari = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
              let bar = AXMenuReader.menuBar(of: safari.processIdentifier),
              let items = AXMenuReader.fileMenuItems(in: bar) else { return nil }
        return SafariMenu.profileNames(inFileMenu: AXMenuReader.snapshot(items))
    }

    private func runningSafari(at url: URL) async throws -> NSRunningApplication {
        let id = Bundle(url: url)?.bundleIdentifier ?? "com.apple.Safari"
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated }) {
            return running
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let launched = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else {
            throw SafariWindowError.didntStart
        }
        for _ in 0..<100 where !launched.isFinishedLaunching {
            try await Task.sleep(for: .milliseconds(50))
        }
        return launched
    }
}
