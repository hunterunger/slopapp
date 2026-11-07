import AppKit

/// Test mode only (`CRATE_SNAPSHOT_DIR=/tmp/…`): writing a name into `<dir>/request` makes
/// Crate render its own windows to `<dir>/<name>.png` (sheets as `<name>-sheet.png`). It
/// draws the windows offscreen, so it works when screen capture can't (a locked screen)
/// and never sees anything but Crate. Writing `appearance:dark|light` switches Crate's own
/// appearance live. Off unless the variable is set.
@MainActor
enum SnapshotHook {
    private static var timer: Timer?

    static func start() {
        guard let path = ProcessInfo.processInfo.environment["CRATE_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { poll(folder) }
        }
    }

    private static func poll(_ folder: URL) {
        let request = folder.appendingPathComponent("request")
        guard let text = try? String(contentsOf: request, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: request)
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "appearance:dark" / "appearance:light" switches Crate's appearance live, to check
        // that every surface follows a change while the app runs (Crate's windows only).
        if name.hasPrefix("appearance:") {
            switch name.dropFirst("appearance:".count) {
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            default: NSApp.appearance = nil
            }
            return
        }
        guard !name.isEmpty, !name.contains("/") else { return }
        let windows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil }
            .sorted { $0.identifier?.rawValue == "main" && $1.identifier?.rawValue != "main" }
        for (index, window) in windows.enumerated() {
            let suffix = index == 0 ? "" : "-\(index + 1)"
            render(window, to: folder.appendingPathComponent("\(name)\(suffix).png"))
            if let sheet = window.attachedSheet {
                render(sheet, to: folder.appendingPathComponent("\(name)\(suffix)-sheet.png"))
            }
        }
    }

    private static func render(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
