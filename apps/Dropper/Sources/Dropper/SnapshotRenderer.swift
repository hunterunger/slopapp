import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// Test hook (`DROPPER_RENDER_DIR=/tmp/…`): renders the main views offscreen to PNGs in light
/// and dark, without showing anything or reading the screen. For layout checks when the
/// screen can't be used (locked Mac, CI).
@MainActor
enum SnapshotRenderer {
    static func renderIfRequested(_ controller: AppController) {
        guard let path = ProcessInfo.processInfo.environment["DROPPER_RENDER_DIR"], !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let look = NSAppearance(named: appearance)
            controller.panelState.list = nil
            render(PanelView(controller: controller, model: controller.model, settings: controller.settings)
                .background(Color(nsColor: .windowBackgroundColor)),
                   size: nil, appearance: look, to: dir.appendingPathComponent("panel-\(name).png"))
            if let first = controller.model.palettes.first {
                controller.panelState.list = .palette(first.id)
                render(PanelView(controller: controller, model: controller.model, settings: controller.settings)
                    .background(Color(nsColor: .windowBackgroundColor)),
                       size: nil, appearance: look, to: dir.appendingPathComponent("panel-palette-\(name).png"))
                controller.panelState.list = nil
            }
            render(ContrastView(controller: controller, state: controller.contrast, model: controller.model)
                .background(Color(nsColor: .windowBackgroundColor)),
                   size: nil, appearance: look, to: dir.appendingPathComponent("contrast-\(name).png"))
            if let item = controller.model.history.latest {
                render(ColorEditorView(controller: controller, item: item, list: .history)
                    .background(Color(nsColor: .windowBackgroundColor)),
                       size: CGSize(width: 420, height: 900), appearance: look, to: dir.appendingPathComponent("editor-\(name).png"))
            }
            let dockPalettes = controller.model.dockPalettes.isEmpty ? Array(controller.model.palettes.prefix(3)) : controller.model.dockPalettes
            for p in dockPalettes where !p.inDock { controller.model.setInDock(true, palette: p.id) }
            render(DockStripView(controller: controller, dock: controller.dock).background(Color(nsColor: .windowBackgroundColor)),
                   size: CGSize(width: ColorDockController.thickness, height: DockLayout.length(controller.model.dockPalettes)),
                   appearance: look, to: dir.appendingPathComponent("dock-\(name).png"))
            if let palette = controller.model.dockPalettes.first {
                render(DockFlyoutView(controller: controller, dock: controller.dock, palette: palette)
                    .background(Color(nsColor: .windowBackgroundColor)),
                       size: nil, appearance: look, to: dir.appendingPathComponent("flyout-\(name).png"))
            }
            render(SettingsView(controller: controller, model: controller.model, settings: controller.settings),
                   size: nil, appearance: look, to: dir.appendingPathComponent("settings-\(name).png"))
            render(LibraryView(controller: controller, model: controller.model, selection: controller.library),
                   size: CGSize(width: 980, height: 600), appearance: look, to: dir.appendingPathComponent("library-\(name).png"))
            if let first = controller.model.palettes.first, let color = first.colors.first {
                controller.library.list = .palette(first.id)
                controller.library.colors = [color.id]
                render(LibraryView(controller: controller, model: controller.model, selection: controller.library),
                       size: CGSize(width: 1100, height: 700), appearance: look, to: dir.appendingPathComponent("library-editor-\(name).png"))
                controller.library.list = .history
                controller.library.colors = []
            }
        }
        Diagnostics.record("rendered snapshots to \(dir.path)")
    }

    private static func render<V: View>(_ view: V, size: CGSize?, appearance: NSAppearance?, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: fitting), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
    }
}
