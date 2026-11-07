import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// Diagnostics: `ZONES_SNAPSHOT_DIR=/tmp/x` renders the panel (each row style, moved in
/// time, light and dark) and the planner offscreen to PNGs, then quits. For reviewing the
/// design when the screen can't be driven (locked, or on CI). Use with
/// `ZONES_DEFAULTS_SUITE` so it never touches real settings.
@MainActor
enum Snapshots {
    static func runIfAsked(controller: AppController) async -> Bool {
        guard let path = ProcessInfo.processInfo.environment["ZONES_SNAPSHOT_DIR"] else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = controller.model
        let panel = controller.panel
        let original = model.preferences.rowStyle
        func shootPanel(_ name: String, _ appearance: String) {
            render(PanelView(model: model, panel: panel, controller: controller),
                   to: directory.appendingPathComponent("panel-\(name)-\(appearance).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for style in RowStyle.allCases {
                model.preferences.rowStyle = style
                shootPanel(style.rawValue, name)
            }
            model.preferences.rowStyle = .timeline
            model.step(.hour, by: 3)
            panel.stripAnchor = model.instant.addingTimeInterval(-3600)
            shootPanel("dragging", name)
            panel.stripAnchor = nil
            model.preferences.rowStyle = .standard
            shootPanel("scrubbed", name)
            panel.showsCalendar = true
            shootPanel("calendar", name)
            panel.showsCalendar = false
            model.resetToNow()

            // Selection, typing a time, messages under the list
            let second = model.rows.dropFirst().first?.id
            model.selection = second
            shootPanel("selected", name)
            if let second {
                panel.beginEditingTime(second, initialText: "3pm")
                shootPanel("editing", name)
                panel.editError = "Type a time like 3pm, 9:30 am or 15:30."
                shootPanel("error", name)
                panel.cancel()
            }
            model.selection = nil

            // Search: suggestions, matches, nothing found
            panel.beginSearch()
            await waitForSearch(panel)
            shootPanel("search-suggestions", name)
            panel.query = "san"
            shootPanel("search-results", name)
            panel.query = "qqxz"
            shootPanel("search-none", name)
            panel.cancel()

            let state = PlannerState(day: model.now, defaults: controller.defaults)
            state.selection = DayPlan.hours(ofDayContaining: model.now, in: model.localTimeZone)[10]
            for face in PlannerState.Face.allCases {
                state.face = face
                render(PlannerView(model: model, state: state, controller: controller),
                       size: NSSize(width: 980, height: 600),
                       to: directory.appendingPathComponent("planner-\(face.rawValue)-\(name).png"))
            }
            render(ZonesSettingsView(model: model, panel: panel, info: controller.info).environment(\.locale, .current),
                   to: directory.appendingPathComponent("settings-\(name).png"))
            panel.settingsTab = .places
            render(ZonesSettingsView(model: model, panel: panel, info: controller.info),
                   to: directory.appendingPathComponent("settings-places-\(name).png"))
            panel.settingsTab = .general
            render(PlacesSettingsTab(model: model, panel: panel).frame(width: Metrics.settingsWidth),
                   to: directory.appendingPathComponent("places-tab-\(name).png"))
            render(CreditedAboutView(info: controller.info),
                   to: directory.appendingPathComponent("about-\(name).png"))
        }
        // One planner kept on screen while the appearance flips: it must follow live
        // (no colour resolved once at creation).
        let live = PlannerState(day: model.now, defaults: controller.defaults)
        live.face = .analog
        renderLiveSwitch(PlannerView(model: model, state: live, controller: controller),
                         size: NSSize(width: 980, height: 600), directory: directory, name: "planner-live")
        renderLiveSwitch(PanelView(model: model, panel: panel, controller: controller),
                         size: nil, directory: directory, name: "panel-live")
        // Empty states last: they remove every place (only in the test defaults suite).
        if ProcessInfo.processInfo.environment["ZONES_DEFAULTS_SUITE"] != nil {
            for place in model.places { model.remove(place.id) }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                shootPanel("undo", name)
                model.panelDidClose()
                shootPanel("empty", name)
                model.preferences.showLocalTime = false
                shootPanel("empty-nolocal", name)
                model.preferences.showLocalTime = true
            }
        }
        model.preferences.rowStyle = original
        return true
    }

    /// The city list loads off the main thread the first time search opens.
    private static func waitForSearch(_ panel: PanelState) async {
        let deadline = Date().addingTimeInterval(5)
        while panel.isLoading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Renders the same view light, then switches that window to dark and renders it again.
    private static func renderLiveSwitch<V: View>(_ view: V, size: NSSize?, directory: URL, name: String) {
        NSApp.appearance = nil
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            capture(hosting, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
        window.close()
    }

    private static func capture(_ hosting: NSView, to url: URL) {
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
    }

    private static func render<V: View>(_ view: V, size: NSSize? = nil, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        // ARC owns it; `close()` mustn't release it a second time.
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        // Paint the window background first: materials don't render offscreen.
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
