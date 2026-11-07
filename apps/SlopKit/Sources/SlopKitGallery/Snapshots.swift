import AppKit
import SlopKit
import SwiftUI

/// `GALLERY_SNAPSHOT_DIR=/tmp/x` renders every page and component offscreen to PNGs in light
/// and dark, then quits. For reviewing when the screen can't be driven (locked, or CI).
/// Materials (glass, popover) don't render offscreen: panels are drawn on the window
/// background instead, so check those on screen with `scripts/drive shot`.
@MainActor
enum GallerySnapshots {
    static func runIfAsked() {
        guard let path = ProcessInfo.processInfo.environment["GALLERY_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            let demo = DemoQueue.shared
            demo.fill()
            // Let the fast demo files finish and the slow ones start.
            try? await Task.sleep(for: .seconds(2.5))
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                for page in GalleryPage.allCases {
                    render(PageView(page: page).frame(width: 640), to: directory.appendingPathComponent("page-\(page.rawValue)-\(name).png"))
                }
                render(FileQueueView(queue: demo.queue, selection: .constant(Set(demo.queue.items.prefix(1).map(\.id))), dropTitle: "Drop any files here")
                        .frame(width: Metrics.utilityWindowSize.width, height: Metrics.utilityWindowSize.height),
                       to: directory.appendingPathComponent("queue-\(name).png"))
                render(FileQueueView(queue: FileQueue(processor: DemoProcessor(), acceptedTypes: [.item]), selection: .constant([]),
                                     dropTitle: "Drop any files here")
                        .frame(width: Metrics.utilityWindowSize.width, height: Metrics.utilityWindowSize.height),
                       to: directory.appendingPathComponent("queue-empty-\(name).png"))
                render(PickerList(model: PickerModel(options: PickerDemo.options)),
                       to: directory.appendingPathComponent("picker-\(name).png"))
                render(AboutView(info: galleryInfo), to: directory.appendingPathComponent("about-\(name).png"))
                render(GeneralSettingsTab(isMenuBarApp: true, appName: galleryInfo.name) {
                    Toggle("An app-specific option", isOn: .constant(true))
                }.frame(width: Metrics.settingsWidth), to: directory.appendingPathComponent("settings-general-\(name).png"))
                render(SettingsForm { ShortcutRow("Show the picker", name: .galleryPanel) }.frame(width: Metrics.settingsWidth),
                       to: directory.appendingPathComponent("settings-shortcuts-\(name).png"))
                render(AboutSettingsTab(info: galleryInfo).frame(width: Metrics.settingsWidth),
                       to: directory.appendingPathComponent("settings-about-\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        hosting.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        hosting.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}

/// One page's content, as the detail column shows it.
struct PageView: View {
    let page: GalleryPage

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            switch page {
            case .corners: CornersPage()
            case .colour: ColourPage()
            case .dropzone: DropZonePage()
            case .queue: QueuePage()
            case .panels: PanelsPage()
            case .capture: CapturePage()
            case .permissions: PermissionsPage()
            case .settings: SettingsPage()
            case .about: AboutPage()
            case .type: TypePage()
            }
        }
        .padding(Spacing.windowMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
