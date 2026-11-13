import AppKit

/// Test hook (`SWITCHBOARD_RENDER_DIR`): draws the app's own visible windows into PNGs from
/// inside the process. Works when the screen is locked or capture isn't allowed, because it
/// never reads the screen, only our views. Materials draw flatter than on screen. Nothing here
/// is Switchboard-specific (SlopKit candidate).
@MainActor
enum WindowRenderer {
    static func renderVisibleWindows(named name: String, into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && $0.frame.width > 40 && $0.frame.height > 40 }
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let file = directory.appending(path: "\(name)-\(index).png")
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: file)
                Diagnostics.record("rendered \(file.lastPathComponent) title=\"\(window.title)\" size=\(Int(view.bounds.width))x\(Int(view.bounds.height))")
            }
        }
        if windows.isEmpty { Diagnostics.record("rendered nothing: no visible windows") }
    }
}

extension Notification.Name {
    /// Test hook: show a Settings tab (`object` = SettingsTab raw value).
    static let switchboardShowTab = Notification.Name("SwitchboardShowTab")
    /// Test hook: open a sheet (`object` = "webmail", "rule-email", "rule-file", "rewrite",
    /// "safari-profile").
    static let switchboardOpenSheet = Notification.Name("SwitchboardOpenSheet")
}
