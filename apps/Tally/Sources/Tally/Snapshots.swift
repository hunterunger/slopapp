import AppKit
import SlopKit
import SwiftUI
import TallyCore

/// Diagnostics: `TALLY_SNAPSHOT_DIR=/tmp/x` renders Tally's own windows offscreen to PNGs
/// (every theme, sidebar shown and hidden, the menu bar panel, Settings), then quits. For
/// reviewing the design when the screen can't be driven (locked, or on CI). Refuses to run
/// unless `TALLY_DATA_DIR` and `TALLY_DEFAULTS_SUITE` keep it away from real data.
@MainActor
enum Snapshots {
    /// While rendering, closing the offscreen windows mustn't quit the app.
    static private(set) var isRunning = false

    static let showcase = """
    # Weekend in Lisbon
    flights = $420 * 2
    hotel = €135 * 3
    1 EUR = 1.08 USD
    hotel in USD
    Dinner: $186.40 + 18%
    20% of what is $30
    // Getting around
    42 km / 35 min in km/h
    3pm PST in Lisbon
    today + 3 weeks
    16 px in em
    0xFF & 0b1010
    5 kg + 3 m
    trip = fli
    """

    static func markRunning() { isRunning = true }

    static func runIfAsked() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["TALLY_SNAPSHOT_DIR"], !path.isEmpty else { return false }
        guard env["TALLY_DATA_DIR"]?.isEmpty == false, env["TALLY_DEFAULTS_SUITE"]?.isEmpty == false else {
            FileHandle.standardError.write(Data("Tally: snapshots need TALLY_DATA_DIR and TALLY_DEFAULTS_SUITE\n".utf8))
            exit(2)
        }
        isRunning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            render(into: URL(fileURLWithPath: path, isDirectory: true))
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = SheetModel.shared
        WindowToggler.mainWindow?.orderOut(nil)
        model.newSheet(text: "# Groceries\nmilk = $3.49 * 2\nbread = $4.25\nsum")
        model.newSheet(text: "# Rent split\nrent = 2450\nrent / 3")
        model.newSheet(text: showcase)
        let size = NSSize(width: 720, height: 520)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for theme in Theme.all where theme.id == Theme.system.id || name == "light" {
                model.setTheme(theme.id)
                let suffix = theme.id == Theme.system.id ? "system-\(name)" : theme.id
                Pref.defaults.set(false, forKey: Pref.showsSidebar)
                render(ContentView(model: model), size: size, to: directory.appendingPathComponent("main-\(suffix).png"),
                       suggest: true)
                if theme.id == Theme.system.id || theme.id == Theme.midnight.id {
                    Pref.defaults.set(true, forKey: Pref.showsSidebar)
                    render(ContentView(model: model), size: NSSize(width: 900, height: 520),
                           to: directory.appendingPathComponent("sidebar-\(suffix).png"))
                }
            }
            model.setTheme(Theme.system.id)
            render(QuickPanel(model: model, close: {}), size: MenuBarController.panelSize,
                   to: directory.appendingPathComponent("menubar-panel-\(name).png"))
            for tab in ["general", "appearance"] {
                Pref.defaults.set(tab, forKey: Pref.settingsTab)
                render(SettingsView(model: model, info: AppInfo.current(fallbackName: "Tally")), size: nil,
                       to: directory.appendingPathComponent("settings-\(tab)-\(name).png"))
            }
        }
        model.setTheme(Theme.midnight.id)
        render(QuickPanel(model: model, close: {}), size: MenuBarController.panelSize,
               to: directory.appendingPathComponent("menubar-panel-midnight.png"))
        model.setTheme(Theme.system.id)
        // An empty sheet.
        NSApp.appearance = NSAppearance(named: .aqua)
        model.newSheet()
        Pref.defaults.set(false, forKey: Pref.showsSidebar)
        render(ContentView(model: model), size: size, to: directory.appendingPathComponent("main-empty-light.png"))
        model.saveNow()
    }

    private static func findEditor(in view: NSView) -> SheetTextView? {
        if let editor = view as? SheetTextView { return editor }
        for sub in view.subviews {
            if let found = findEditor(in: sub) { return found }
        }
        return nil
    }

    private static func render<V: View>(_ view: V, size: NSSize?, to url: URL, suggest: Bool = false) {
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if suggest, let editor = findEditor(in: hosting) {
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            editor.updateSuggestion()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
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
        window.contentView = nil
        window.close()
    }
}

/// Diagnostics: `TALLY_PERF_SIM=1` opens a 1,000-line sheet in an offscreen window, types
/// 41 characters into the middle of it through the real text view, and prints how long each
/// keystroke took end to end (edit, re-evaluate, results, re-wrap, layout and drawing), then
/// quits. Measures keystroke latency when the screen can't be driven. Same data guards as
/// snapshots.
@MainActor
enum PerfSimulation {
    static func runIfAsked() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["TALLY_PERF_SIM"] == "1" else { return false }
        guard env["TALLY_DATA_DIR"]?.isEmpty == false, env["TALLY_DEFAULTS_SUITE"]?.isEmpty == false else {
            FileHandle.standardError.write(Data("Tally: the perf simulation needs TALLY_DATA_DIR and TALLY_DEFAULTS_SUITE\n".utf8))
            exit(2)
        }
        Snapshots.markRunning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            run()
            NSApp.terminate(nil)
        }
        return true
    }

    private static func run() {
        let model = SheetModel.shared
        WindowToggler.mainWindow?.orderOut(nil)
        var lines: [String] = []
        var block = 0
        let sample = SheetText.welcome.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            + Snapshots.showcase.split(separator: "\n").map(String.init) + [""]
        while lines.count < 1000 {
            for line in sample where lines.count < 1000 {
                lines.append(line.replacingOccurrences(of: "flights", with: "flights\(block)"))
            }
            block += 1
        }
        model.newSheet(text: lines.joined(separator: "\n"))
        let hosting = NSHostingView(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 800), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let editor = findEditor(in: hosting) else { return }
        window.makeFirstResponder(editor)
        // The middle of the sheet, at the end of a line with an answer.
        let middle = editor.characterRange(ofLine: 500)
        editor.setSelectedRange(NSRange(location: NSMaxRange(middle), length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        window.displayIfNeeded()
        var times: [Double] = []
        var evals: [Double] = []
        for (i, ch) in " + 12 * 3 - flights1 in EUR // done  ".enumerated() {
            let start = ContinuousClock.now
            editor.insertText(String(ch), replacementRange: editor.selectedRange())
            editor.layoutManager?.ensureLayout(for: editor.textContainer!)
            window.displayIfNeeded()
            let elapsed = ContinuousClock.now - start
            let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            if i > 0 { times.append(ms) }
            evals.append(model.lastEvaluationMillis)
        }
        times.sort()
        evals.sort()
        let p = { (q: Double) in times[min(times.count - 1, Int(Double(times.count) * q))] }
        print(String(format: "TALLY_PERF_SIM lines=%d keystrokes=%d median_ms=%.2f p95_ms=%.2f max_ms=%.2f evaluate_median_ms=%.2f",
                     model.lines.count, times.count, p(0.5), p(0.95), times.last ?? 0, evals[evals.count / 2]))
        window.contentView = nil
        window.close()
    }

    private static func findEditor(in view: NSView) -> SheetTextView? {
        if let editor = view as? SheetTextView { return editor }
        for sub in view.subviews {
            if let found = findEditor(in: sub) { return found }
        }
        return nil
    }
}
