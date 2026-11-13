import AppKit
import ConvertCore

/// For scripted reviews when screen capture isn't available (a locked screen): with
/// CONVERT_SNAPSHOT=<folder>, every 2 seconds the app writes a PNG of each of its own
/// visible windows into that folder. Only its own windows, never the screen.
/// Not used in normal runs.
@MainActor
enum Snapshot {
    static func startIfAsked() {
        // CONVERT_REVIEW=flip: 4 s after launch, switch light ↔ dark while running, to check
        // every surface follows a live appearance change (as when the system switches).
        if ProcessInfo.processInfo.environment["CONVERT_REVIEW"] == "flip" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                NSApp.appearance = NSAppearance(named: isDark ? .aqua : .darkAqua)
            }
        }
        guard let folder = ProcessInfo.processInfo.environment["CONVERT_SNAPSHOT"] else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        // CONVERT_REVIEW=trim|crop|merge|settings opens that view once files are in, to capture it.
        if let review = ProcessInfo.processInfo.environment["CONVERT_REVIEW"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let model = AppModel.shared
                let videos = model.entries.filter { model.kind(of: $0.input) != .image }
                switch review {
                case "trim": model.trimming = videos.first { model.canTrim($0) }
                case "crop": model.cropping = model.entries.first { model.canCrop($0) }
                case "merge": model.merge(videos)
                case "settings":
                    NSApp.activate()
                    // The app menu's Settings… item (SwiftUI's Settings scene).
                    if let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }),
                       let action = item.action {
                        NSApp.sendAction(action, to: item.target, from: item)
                    }
                case "edits":
                    // Each kind gets its own settings, as the card tools would set them.
                    let byKind = { (kind: MediaKind) in model.entries.filter { model.kind(of: $0.input) == kind } }
                    if let video = byKind(.video).first(where: model.canTrim) {
                        model.updateOptions(for: [video]) {
                            $0.video = .mp4HEVC
                            $0.trim = TrimRange(start: 0.5, end: 2)
                        }
                    }
                    if let image = byKind(.image).first {
                        model.updateOptions(for: [image]) { $0.transform = $0.transform.rotatedRight() }
                    }
                    if let sound = byKind(.audio).first {
                        model.updateOptions(for: [sound]) { $0.audio = .wav }
                    }
                    model.selection = Set(byKind(.image).prefix(1).map(\.id))
                default: break
                }
            }
        }
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(2))
                for (i, window) in NSApp.windows.enumerated() where window.isVisible {
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let name = window.title.isEmpty ? "window\(i)" : window.title.replacingOccurrences(of: "/", with: "-")
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
                }
            }
        }
    }
}
