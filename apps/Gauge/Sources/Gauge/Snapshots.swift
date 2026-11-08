import AppKit
import GaugeCore
import SlopKit
import SwiftUI

/// Diagnostics: `GAUGE_SNAPSHOT_DIR=/tmp/x` renders the panel (every section), Settings and the
/// menu bar item offscreen to PNGs in light and dark, from demo data, then quits. For reviewing
/// the design when the screen can't be driven (locked, asleep, or CI). Materials don't render
/// offscreen, so the panel is drawn on the window background colour.
@MainActor
enum Snapshots {
    static func runIfAsked(controller: AppController) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["GAUGE_SNAPSHOT_DIR"] else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let clock = SystemClock()
        let world = DemoWorld(clock: clock)
        let sources = world.makeSources()
        let session = GaugeSession(sources: sources.tick, processes: sources.processes,
                                   preferences: controller.store.preferences, hasBattery: true, appName: controller.info.name)
        ReviewHooks.seedHistory(session: session, world: world, now: clock.now())
        session.setPanelOpen(true)
        _ = session.tick(at: clock.now(), interval: 1)
        world.setTime(clock.now() + 1)
        let output = session.tick(at: clock.now() + 1, interval: 1)
        world.setTime(nil)
        guard let data = output.panel else { return false }
        let model = controller.panelModel
        model.hasBattery = true
        model.thermal = .nominal
        model.apply(PanelUpdate(data: data, volumes: DemoWorldVolumes.all, battery: sources.battery.read(details: true),
                                network: sources.network.primary()))

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for section in PanelSection.allCases {
                model.selection = section
                model.selectedRow = section == .cpu ? 1 : nil
                render(PanelView(model: model, store: controller.store, actions: PanelActions(controller: controller)),
                       to: directory.appendingPathComponent("panel-\(section.rawValue)-\(name).png"))
            }
            render(GaugeSettingsView(store: controller.store, info: controller.info, hasBattery: true),
                   to: directory.appendingPathComponent("settings-\(name).png"))
            renderMenuBar(session: session, preferences: controller.store.preferences, appearance: appearance,
                          to: directory.appendingPathComponent("menubar-\(name).png"))
        }
        return true
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.borderless],
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

    /// Several readout sets, each as the menu bar would tint the template image.
    private static func renderMenuBar(session: GaugeSession, preferences: Preferences, appearance: NSAppearance.Name, to url: URL) {
        let sets: [[Readout]] = [[.cpu, .network], [.cpu, .memory, .gpu], [.disk, .battery, .network], []]
        let dark = appearance == .darkAqua
        var images: [NSImage] = []
        for readouts in sets {
            var shown = preferences
            shown.readouts = readouts
            session.preferences = shown
            let content = session.forceMenuBar(at: 0, interval: 2)
            images.append(MenuBarLayout(content: content).image(for: content))
        }
        let scale: CGFloat = 2
        let width = (images.map(\.size.width).max() ?? 100) + 32
        let rowHeight: CGFloat = 28
        let size = NSSize(width: width, height: rowHeight * CGFloat(images.count))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, image) in images.enumerated() {
            let y = size.height - rowHeight * CGFloat(index + 1) + (rowHeight - image.size.height) / 2
            let rect = NSRect(x: 16, y: y, width: image.size.width, height: image.size.height)
            // A template image is drawn as a mask in the menu bar's text colour.
            let tinted = NSImage(size: image.size, flipped: false) { bounds in
                image.draw(in: bounds)
                (dark ? NSColor.white : NSColor.black).set()
                bounds.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
