import AppKit
import SpecimenCore

/// Design review without the screen (locked, or CI): `SPECIMEN_SNAPSHOT_DIR=/tmp/x` walks the
/// main window through its screens in light and dark, writes a PNG of the app's own window
/// (and any sheet) for each, then quits. Only Specimen's windows are drawn, never the screen.
/// Use with `SPECIMEN_DATA_DIR` (a scratch folder: it creates sample tags there) and
/// `SPECIMEN_TEST_FONTS`; preferences are never saved in this mode.
@MainActor
enum Snapshots {
    static func startIfAsked(model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["SPECIMEN_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            while !model.hasLoaded || model.isIndexing { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(600))
            await run(model: model, folder: folder)
            // A sheet still on its way out blocks quitting; wait for it.
            model.sheet = nil
            for _ in 0..<50 where NSApp.windows.contains(where: { $0.attachedSheet != nil }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            NSApp.terminate(nil)
        }
    }

    private static func run(model: AppModel, folder: URL) async {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.contentView != nil })
            ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }

        // Sample data: two tags, a smart collection, a few fonts in the compare tray.
        let names = model.families.map(\.name)
        let pick = { (wanted: [String]) in wanted.filter(names.contains) }
        let display = pick(["Didot", "Futura", "Baskerville", "Avenir Next", "Silkscreen", "Gill Sans"])
        let code = pick(["Menlo", "Courier New", "Andale Mono", "Silkscreen"])
        model.createTag("Headlines", families: display)
        model.createTag("Code", families: code)
        model.saveSmartCollection(SmartCollection(name: "Mono I can turn off", rules: SmartRules(category: .monospaced, source: .yours)))
        model.sidebar = .all
        var tray = CompareTray()
        for name in pick(["Didot", "Futura", "Baskerville", "American Typewriter"]) {
            if let face = model.family(named: name)?.representative { tray.add(face.id) }
        }
        model.setTray(tray)
        model.previewText = "Typography"
        model.previewSize = 36
        if let futura = model.items.first(where: { $0.family.name == "Futura" }) { model.selection = [futura.id] }

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            FontCardView.clearSymbolCache()
            model.viewMode = .grid
            model.screen = .grid
            await shot(window, "grid", suffix, folder)
            model.sidebar = .tag("Headlines")
            await shot(window, "grid-tag", suffix, folder)
            model.sidebar = .all
            model.viewMode = .list
            await shot(window, "list", suffix, folder)
            model.viewMode = .grid

            if let family = model.families.first(where: { $0.name == "Futura" }) ?? model.families.first {
                model.openDetail(face: family.representative ?? family.faces[0])
                for tab in [DetailTab.styles, .characters, .text, .info] {
                    model.detailTab = tab
                    await shot(window, "detail-\(tab.rawValue)", suffix, folder, wait: tab == .characters ? 1.6 : 0.8)
                }
            }
            if let variable = model.families.first(where: { $0.name == "Skia" && $0.isVariable }) ?? model.families.first(where: \.isVariable) {
                model.openDetail(face: variable.representative ?? variable.faces[0])
                model.detailTab = .variables
                await shot(window, "detail-variables", suffix, folder, wait: 1.2)
            }
            model.detailTab = .styles
            model.screen = .grid
            model.openCompare()
            await shot(window, "compare", suffix, folder)
            model.goBack()

            model.sheet = .tags
            await shot(window, "sheet-tags", suffix, folder)
            model.sheet = .smartCollection(SmartCollection(name: "Monospaced", rules: SmartRules(category: .monospaced, state: .active)), isNew: true)
            await shot(window, "sheet-smart", suffix, folder)
            model.sheet = nil
            try? await Task.sleep(for: .milliseconds(400))

            // Text most fonts can't show: the coverage filter hides them.
            model.previewText = "Привет мир"
            let started = Date()
            model.hideUncovered = true
            while model.isCheckingCoverage { try? await Task.sleep(for: .milliseconds(20)) }
            log.append("coverage \(suffix): \(Int(Date().timeIntervalSince(started) * 1000)) ms for \(model.faces.count) faces, \(model.items.count) families shown")
            await shot(window, "grid-coverage", suffix, folder)
            model.hideUncovered = false
            model.previewText = "Typography"
        }
        // Add Fonts… with a copy of an installed test font and a damaged file: nothing is
        // installed, and the report explains both.
        if let test = model.environment.testFontsDirectory, let fixture = TestFonts.fontFiles(in: test).first {
            NSApp.appearance = NSAppearance(named: .aqua)
            let drop = folder.appendingPathComponent("drop", isDirectory: true)
            try? FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
            let copy = drop.appendingPathComponent("Copy of \(fixture.lastPathComponent)")
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: fixture, to: copy)
            let broken = drop.appendingPathComponent("Broken.ttf")
            try? Data("not a font".utf8).write(to: broken)
            model.addFonts([drop])
            await shot(window, "sheet-install", "light", folder)
            model.sheet = nil
        }
        // SPECIMEN_SNAPSHOT_ADD=/path/a.ttf:/path/b.ttf adds those (test mode installs into the
        // test folder, registered for the session only) and records what got selected.
        if model.environment.isTestMode, let paths = ProcessInfo.processInfo.environment["SPECIMEN_SNAPSHOT_ADD"] {
            model.addFonts(paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
            try? await Task.sleep(for: .seconds(2.5))
            let selected = model.selectedItems.map(\.family.name)
            log.append("added: selected \(selected), sheet \(model.sheet == nil ? "none" : "shown")")
            NSApp.appearance = NSAppearance(named: .aqua)
            await shot(window, "grid-added", "light", folder)
        }
        try? log.joined(separator: "\n").write(to: folder.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.appearance = nil
    }

    private static var log: [String] = []

    private static func shot(_ window: NSWindow, _ name: String, _ suffix: String, _ folder: URL, wait: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(wait))
        let target = window.attachedSheet ?? window
        guard let view = target.contentView?.superview ?? target.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        // Materials don't draw offscreen: paint the window background first.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
    }
}
