import AppKit
import SlopKit
import SwitchboardCore

/// `SWITCHBOARD_INBOX`: links dropped into a folder as `*.link` files are routed as if macOS
/// had sent them, with the modifier keys and source app the file names. A test hook: off
/// unless the variable is set. Event-driven (a folder watch), no polling.
@MainActor
final class TestInbox {
    static var shared: TestInbox?

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?

    /// One dropped link.
    struct Entry: Equatable {
        var url: URL
        var modifiers: Modifiers = []
        var sourceBundleID: String?
        var forcePicker = false
    }

    init(directory: URL) {
        self.directory = directory
    }

    static func startIfRequested() {
        guard let directory = Diagnostics.inboxDirectory else { return }
        let inbox = TestInbox(directory: directory)
        inbox.start()
        shared = inbox
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = Darwin.open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            Diagnostics.record("inbox couldn't watch \(directory.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        Diagnostics.record("inbox watching \(directory.path)")
        drain()
    }

    private func drain() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "link" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: file)
            if Self.runCommand(text) { continue }
            guard let entry = Self.parse(text) else {
                Diagnostics.record("inbox skipped \(file.lastPathComponent): no url= line")
                continue
            }
            Diagnostics.record("inbox \(file.lastPathComponent)")
            LinkRouter.shared.receive(entry.url, forcePicker: entry.forcePicker,
                                      simulated: (entry.modifiers, entry.sourceBundleID))
        }
    }

    /// Test-only commands: `tab=<name>` shows a Settings tab, `sheet=<name>` opens a sheet,
    /// `render=<name>` draws our visible windows to `SWITCHBOARD_RENDER_DIR`.
    private static func runCommand(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "tab":
            SettingsWindow.open()
            NotificationCenter.default.post(name: .switchboardShowTab, object: parts[1])
        case "tab-behind":
            // Opens Settings without activating, behind other apps' windows, so a test can read
            // it through Accessibility without taking the keyboard from whoever is at the Mac.
            if SettingsWindow.window == nil, let item = Self.settingsItem(in: NSApp.mainMenu), let menu = item.menu {
                menu.performActionForItem(at: menu.index(of: item))
            }
            NotificationCenter.default.post(name: .switchboardShowTab, object: parts[1])
            DispatchQueue.main.async { SettingsWindow.window?.orderBack(nil) }
        case "sheet":
            NotificationCenter.default.post(name: .switchboardOpenSheet, object: parts[1])
        case "render":
            if let directory = Diagnostics.renderDirectory {
                WindowRenderer.renderVisibleWindows(named: parts[1], into: directory)
            }
        case "close":
            NSApp.keyWindow?.attachedSheet.map { NSApp.keyWindow?.endSheet($0) }
        default:
            return false
        }
        Diagnostics.record("inbox command \(line)")
        return true
    }

    private static func settingsItem(in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command { return item }
            if let found = settingsItem(in: item.submenu) { return found }
        }
        return nil
    }

    static func parse(_ text: String) -> Entry? {
        var entry: Entry?
        var modifiers: Modifiers = []
        var source: String?
        var pick = false
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "url": if let url = URL(string: parts[1]) { entry = Entry(url: url) }
            case "source": source = parts[1].isEmpty ? nil : parts[1]
            case "pick": pick = parts[1] == "1"
            case "modifiers":
                for name in parts[1].lowercased().split(separator: ",") {
                    switch name.trimmingCharacters(in: .whitespaces) {
                    case "control", "ctrl": modifiers.insert(.control)
                    case "option", "alt": modifiers.insert(.option)
                    case "shift": modifiers.insert(.shift)
                    case "command", "cmd": modifiers.insert(.command)
                    case "fn", "function": modifiers.insert(.function)
                    default: break
                    }
                }
            default: break
            }
        }
        entry?.modifiers = modifiers
        entry?.sourceBundleID = source
        entry?.forcePicker = pick
        return entry
    }
}
