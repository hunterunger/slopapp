import AppKit
import IconsmithCore
import SwiftUI

/// Test-only hook, off unless `ICONSMITH_DEBUG_DIR` is set: takes commands over a
/// distributed notification (`app.slopapp.iconsmith.debug`, object = command) and renders
/// Iconsmith's own windows to PNGs in that folder. For checking the UI when Accessibility
/// and screen capture can't see the screen (locked display). Never captures other apps.
///
///     shot:<name>  open:<path>|<path>  blank  shape:<raw>  mode:create|restore
///     show:adjust|text|export  hide  text:<string>  textpos:<raw>  color:<r>,<g>,<b>  swatch:<name>  bg:<raw>
///     format:<raw>  rotate:<deg>  select:<i>  cutout  undo  redo  appearance:light|dark
///     export:<format>:<path>  exportall:<format>:<folder>  apply:<path>  remove:<path>
///     confirmapps  useappicon  appearances:on|off  platforms:macOS,iOS,watchOS  reveal:on|off
///     winsize:<w>,<h>
@MainActor
enum DebugHarness {
    static let notification = Notification.Name("app.slopapp.iconsmith.debug")
    static var folder: URL?

    static func startIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["ICONSMITH_DEBUG_DIR"], !path.isEmpty else { return }
        folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command) }
        }
    }

    static func run(_ command: String) {
        let model = AppModel.shared
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let verb = parts.first ?? "", arg = parts.count > 1 ? parts[1] : ""
        switch verb {
        case "shot": shoot(arg)
        case "open": model.load(arg.split(separator: "|").map { URL(fileURLWithPath: String($0)) })
        case "blank": model.newBlank()
        case "shape": if let shape = IconShape(rawValue: arg) { model.setShape(shape) }
        case "mode": model.mode = arg == "restore" ? .restore : .create
        case "show":
            model.showsAdjust = arg == "adjust"
            model.showsText = arg == "text"
            model.showsExport = arg == "export"
        case "hide":
            model.showsAdjust = false
            model.showsText = false
            model.showsExport = false
        case "text": model.edit("Change Text") { $0.text.string = arg }
        case "textpos": if let p = IconText.Position(rawValue: arg) { model.edit("Change Text") { $0.text.position = p } }
        case "color":
            let c = arg.split(separator: ",").compactMap { Double($0) }
            if c.count == 3 { model.edit("Change Color") { $0.background = .color; $0.color = RGBA(c[0], c[1], c[2]) } }
        case "swatch":
            if let swatch = ColorControls.swatches.first(where: { $0.name == arg }),
               let rgba = RGBA(swatch.color.usingColorSpace(.sRGB)?.cgColor ?? swatch.color.cgColor) {
                model.edit("Change Color") { $0.background = .color; $0.color = rgba.opaque }
            }
        case "bg": if let mode = BackgroundMode(rawValue: arg) { model.edit("Change Background") { $0.background = mode } }
        case "format": if let format = ExportFormat(rawValue: arg) { model.prefs.format = format }
        case "rotate": model.rotate(by: Double(arg) ?? 0)
        case "select": model.select(Int(arg) ?? 0)
        case "cutout": model.removeBackground()
        case "dismiss":
            model.error = nil
            model.pendingApps = nil
        case "confirmapps": if let pending = model.pendingApps { model.confirmApps(pending) }
        case "useappicon": if let pending = model.pendingApps { model.useAppIcon(pending) }
        case "appearances": model.prefs.options.xcodeAppearances = arg == "on"
        case "platforms":
            model.prefs.options.xcodePlatforms = Set(arg.split(separator: ",").compactMap { XcodePlatform(rawValue: String($0)) })
        case "winsize":
            let v = arg.split(separator: ",").compactMap { Double($0) }
            if v.count == 2, let window = MainWindow.current {
                var frame = window.frame
                frame.origin.y += frame.height - v[1]
                frame.size = CGSize(width: v[0], height: v[1])
                window.setFrame(frame, display: true)
            }
        case "reveal": model.prefs.revealAfterExport = arg == "on"
        case "undo": model.undo()
        case "redo": model.redo()
        case "appearance": NSApp.appearance = NSAppearance(named: arg == "dark" ? .darkAqua : .aqua)
        case "export", "exportall":
            let rest = arg.split(separator: ":", maxSplits: 1).map(String.init)
            guard rest.count == 2, let format = ExportFormat(rawValue: rest[0]) else { return }
            model.prefs.format = format
            model.debugWrite(format, to: URL(fileURLWithPath: rest[1]), all: verb == "exportall")
        case "apply": model.dropOnCanvas(arg.split(separator: "|").map { URL(fileURLWithPath: String($0)) })
        case "remove": model.removeIcons(from: arg.split(separator: "|").map { URL(fileURLWithPath: String($0)) })
        default: NSLog("Iconsmith debug: unknown command %@", command)
        }
    }

    /// Every visible window of ours (main, popovers, sheets, alerts) as `<name>-<n>.png`.
    static func shoot(_ name: String) {
        guard let folder else { return }
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        for (n, window) in windows.enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let suffix = window === MainWindow.current ? "main" : "\(n)"
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name)-\(suffix).png"))
        }
    }
}

extension AppModel {
    /// Export without a panel (the debug hook): `all` writes the batch into `url` (a folder).
    func debugWrite(_ format: ExportFormat, to url: URL, all: Bool) {
        if all { writeBatchForDebug(format, into: url) } else { writeForDebug(format, to: url) }
    }
}
