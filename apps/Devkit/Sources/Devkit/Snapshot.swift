import AppKit
import DevkitCore
import SwiftUI

/// Design review when the screen can't be captured (locked, or CI): with
/// `DEVKIT_SNAPSHOT=<folder>`, Devkit shows each tool with its sample input, draws its own
/// main window (never the screen) to `<tool>-light.png` / `<tool>-dark.png`, does the same for
/// Settings, then quits. `DEVKIT_SNAPSHOT_TOOLS=json,jwt` limits the tools.
/// Use with `DEVKIT_DEFAULTS`, `DEVKIT_PASTEBOARD`, `DEVKIT_NOW` and `DEVKIT_SEED`.
@MainActor
enum Snapshot {
    static func runIfAsked() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DEVKIT_SNAPSHOT"] else { return false }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tools = environment["DEVKIT_SNAPSHOT_TOOLS"].map { $0.split(separator: ",").compactMap { Tool(rawValue: String($0)) } } ?? Tool.allCases
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let model = AppModel.shared
            guard let window = model.mainWindow else {
                FileHandle.standardError.write(Data("snapshot: no main window\n".utf8))
                NSApp.terminate(nil)
                return
            }
            window.setContentSize(NSSize(width: 1100, height: 680))
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                // The empty state first.
                model.selection = .json
                model.setInput("", on: model.json, actionName: "Snapshot")
                try? await Task.sleep(for: .milliseconds(400))
                capture(window, to: folder.appendingPathComponent("empty-\(name).png"))
                for tool in tools {
                    model.selection = tool
                    try? await Task.sleep(for: .milliseconds(250))
                    if model.current.input.isEmpty { model.loadSample() }
                    if tool == .qrCode, model.qrCode.input.isEmpty { model.loadSample() }
                    try? await Task.sleep(for: .milliseconds(550))
                    capture(window, to: folder.appendingPathComponent("\(tool.rawValue)-\(name).png"))
                }
                // A JWT signed with a public key, to show the key field.
                if tools.contains(.jwt) {
                    model.selection = .jwt
                    model.setInput(SnapshotFixtures.es256, on: model.jwt, actionName: "Snapshot")
                    model.jwt.publicKey = SnapshotFixtures.ecJWK
                    try? await Task.sleep(for: .milliseconds(500))
                    capture(window, to: folder.appendingPathComponent("jwt-es256-\(name).png"))
                }
                // QR read mode with the generated code fed back in.
                if tools.contains(.qrCode), let png = model.qrCode.pngData {
                    model.selection = .qrCode
                    model.qrCode.read(imageData: png)
                    try? await Task.sleep(for: .milliseconds(500))
                    capture(window, to: folder.appendingPathComponent("qrCode-read-\(name).png"))
                    model.qrCode.mode = .generate
                }
                await captureSettings(folder: folder, name: name)
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func captureSettings(folder: URL, name: String) async {
        NSApp.activate(ignoringOtherApps: true)
        if let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
        try? await Task.sleep(for: .milliseconds(700))
        guard let settings = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue != "main" && $0.contentView != nil && $0.frame.width > 200 }) else { return }
        // Settings reopens on the last tab; start from General.
        if let toolbar = settings.toolbar, let first = toolbar.items.first {
            toolbar.selectedItemIdentifier = first.itemIdentifier
            if let action = first.action { NSApp.sendAction(action, to: first.target, from: first) }
            try? await Task.sleep(for: .milliseconds(500))
        }
        capture(settings, to: folder.appendingPathComponent("settings-general-\(name).png"))
        // The other tabs, through the toolbar.
        for (index, tab) in ["shortcuts", "advanced"].enumerated() {
            if let toolbar = settings.toolbar, toolbar.items.count > index + 1 {
                let item = toolbar.items[index + 1]
                toolbar.selectedItemIdentifier = item.itemIdentifier
                if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
                try? await Task.sleep(for: .milliseconds(500))
                capture(settings, to: folder.appendingPathComponent("settings-\(tab)-\(name).png"))
            }
        }
        settings.close()
    }

    static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        // Paint the window background first: materials don't render offscreen.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// RFC 7515 Appendix A.3 (ES256) token and its public key.
enum SnapshotFixtures {
    static let es256 = "eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.DtEhU3ljbEg8L38VWAfUAqOyKAM6-Xx-F4GawxaepmXFCgfTjDxw5djxLa8ISlSApmWQxfKTUJqPP3-Kg6NU1Q"
    static let ecJWK = #"{"kty":"EC","crv":"P-256","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"}"#
}
