import AppKit
import CoreText
import SpecimenCore

/// Design review without the screen (locked, or CI): `SPECIMEN_SNAPSHOT_DIR=/tmp/x` walks the
/// main window through its screens in light and dark, writes a PNG of the app's own window
/// (and any sheet) for each, then quits. Only Specimen's windows are drawn, never the screen.
/// Use with `SPECIMEN_DATA_DIR` (a scratch folder: it creates sample tags there) and
/// `SPECIMEN_TEST_FONTS`; preferences are never saved in this mode.
@MainActor
enum Snapshots {
    /// When the process started (the snapshot log reports load times from it).
    static var launched: Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1e6)
    }

    static func startIfAsked(model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["SPECIMEN_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            while !model.hasLoaded || model.isIndexing || model.isScanningFolders { try? await Task.sleep(for: .milliseconds(100)) }
            log.append("loaded \(model.faces.count) faces (\(model.libraryFaces.count) from library folders) in \(Int(Date().timeIntervalSince(launched) * 1000)) ms after launch")
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
            // OpenType features (Avenir Next ships with macOS), with old-style figures on.
            if let avenir = model.families.first(where: { $0.name == "Avenir Next" }), let face = avenir.representative {
                model.openDetail(face: face)
                if let type = PreviewRenderer.shared.featureTypes(for: face).first(where: { $0.name == "Number Case" }),
                   let oldStyle = type.selectors.first(where: { $0.openTypeTag == "onum" }) {
                    model.detailFeatures.choose(oldStyle, in: type)
                }
                model.detailTab = .features
                await shot(window, "detail-features", suffix, folder, wait: 1.2)
                model.detailFeatures.reset()
            }
            model.detailTab = .styles
            model.screen = .grid
            // Library folders and documents (test mode: SPECIMEN_DATA_DIR's folders.json).
            if let library = model.folders.first {
                let path = model.folderTrees[library.path]?.children?.first?.path ?? library.path
                model.sidebar = .folder(path)
                await shot(window, "grid-folder", suffix, folder)
                model.viewMode = .list
                await shot(window, "list-folder", suffix, folder)
                model.viewMode = .grid
            }
            if let document = model.documents.first {
                model.sidebar = .document(document.id)
                await shot(window, "grid-document", suffix, folder)
            }
            model.sidebar = .all
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
        if model.environment.isTestMode, !model.folders.isEmpty {
            await runFlows(model: model, window: window, folder: folder)
        }
        try? log.joined(separator: "\n").write(to: folder.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.appearance = nil
    }

    /// The library-folder flows end to end, with real files, FSEvents and CoreText (test
    /// mode: everything registered at session scope, under the test folder, and undone).
    /// Results go to log.txt, so they can be checked with the screen locked.
    private static func runFlows(model: AppModel, window: NSWindow, folder: URL) async {
        guard let root = model.folders.first?.path, let test = model.environment.testFontsDirectory else { return }
        let clock = ContinuousClock()
        func wait(_ what: String, timeout: Double = 8, _ done: () -> Bool) async {
            let start = clock.now
            while !done(), clock.now - start < .seconds(timeout) { try? await Task.sleep(for: .milliseconds(20)) }
            log.append("\(done() ? "ok" : "FAILED") \(what): \(Int((clock.now - start) / .milliseconds(1))) ms")
            try? log.joined(separator: "\n").write(to: folder.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        }
        func family(_ name: String) -> FontFamily? { model.family(named: name) }
        func systemWide(_ postScript: String) -> Bool {
            CTFontCopyPostScriptName(CTFontCreateWithName(postScript as CFString, 12, nil)) as String == postScript
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        model.sidebar = .all
        model.screen = .grid

        // Watched folder: add, rename, delete a font file.
        let newFolder = URL(fileURLWithPath: root).appendingPathComponent("Clients/Newco")
        let source = test.appendingPathComponent("Silkscreen-Regular.ttf")
        let file = (try? FixtureFonts.makeLibrary(from: source, into: newFolder, prefix: "Watch Test", count: 1))?.first
        await wait("new file appears") { family("Watch Test 1") != nil }
        log.append("  sidebar has Newco: \(model.folderNodePaths.contains(newFolder.path))")
        if let file {
            let renamed = newFolder.appendingPathComponent("Renamed.ttf")
            try? FileManager.default.moveItem(at: file, to: renamed)
            await wait("rename shows the new path") { family("Watch Test 1")?.faces.first?.path == renamed.path }
            try? FileManager.default.removeItem(at: renamed)
            await wait("deleted file goes away") { family("Watch Test 1") == nil }
        }

        // Temporary activation of a library family, visible to other apps.
        if let acme = family("Acme Sans") {
            model.request(true, faces: acme.faces, temporary: true)
            await wait("Acme Sans active temporarily") { family("Acme Sans")?.state == .temporary }
            log.append("  scope \(model.registrar.scope(of: acme.faces[0].path ?? "")?.rawValue ?? "none"), system-wide: \(systemWide("AcmeSans-Regular")), saved: \(TemporaryStore(directory: model.environment.dataDirectory).load().count) file(s)")
            await shot(window, "flow-temporary", "light", folder)
            // Keep it on after quitting.
            model.request(true, faces: family("Acme Sans")?.faces ?? [])
            await wait("Acme Sans kept active") { family("Acme Sans")?.state == .active }
            // (Undo isn't scripted here: offscreen there are no input events to close
            // AppKit's undo groups. ActivationUndo is unit-tested.)
        }
        // Activate for good (test mode: session scope that reports itself as persistent).
        if let beacon = family("Beacon Mono") {
            model.request(true, faces: beacon.faces)
            await wait("Beacon Mono active") { family("Beacon Mono")?.state == .active }
            log.append("  reported scope \(model.registrar.scope(of: beacon.faces[0].path ?? "")?.rawValue ?? "none")")
        }
        // Two copies of one font in two projects: activate one, then swap to the other.
        if let shared = family("Shared Display"), shared.faces.count == 2 {
            let acmeCopy = shared.faces.first { $0.path?.contains("/Acme/") == true }!
            let archiveCopy = shared.faces.first { $0.path?.contains("/Archive") == true }!
            model.request(true, faces: [acmeCopy])
            await wait("Acme copy of Shared Display on") { model.face(id: acmeCopy.id)?.isEnabled == true }
            model.request(true, faces: [model.face(id: archiveCopy.id) ?? archiveCopy])
            if case .swap(let plan) = model.pending {
                log.append("ok swap offered for the other copy")
                model.confirm(plan, swap: true)
            } else {
                log.append("FAILED no swap offered")
            }
            await wait("Archive copy on, Acme copy off") {
                model.face(id: archiveCopy.id)?.isEnabled == true && model.face(id: acmeCopy.id)?.isEnabled == false
            }
        }
        // A document: its fonts, then activate what's missing.
        if let poster = model.documents.first(where: { $0.name == "Acme Poster.pdf" }) {
            model.sidebar = .document(poster.id)
            await wait("poster's fonts matched") { !(model.documentMatches[poster.id] ?? []).isEmpty }
            let statuses = (model.documentMatches[poster.id] ?? []).map { "\($0.reference.name)=\($0.status)" }
            log.append("  poster: \(statuses.joined(separator: ", "))")
            model.request(true, faces: model.inactiveFaces(inDocument: poster.id), temporary: true)
            await wait("poster's fonts all active") { (model.documentMatches[poster.id] ?? []).allSatisfy { $0.status == .active } }
            await shot(window, "flow-document", "light", folder)
        }
        for document in model.documents where document.name != "Acme Poster.pdf" {
            let statuses = (model.documentMatches[document.id] ?? []).map { "\($0.reference.name)=\($0.status)\($0.reference.isProvidedByDocument ? " (provided)" : "")" }
            log.append("  \(document.name): \(model.documentProblems[document.id] ?? statuses.joined(separator: ", "))")
        }
        // Deactivate every temporary font.
        model.deactivateTemporaryFonts()
        await wait("temporary fonts deactivated") { model.temporaryFaces.isEmpty && model.temporaryPaths.isEmpty }
        // Removing the folder turns off what's on from it.
        if let library = model.folders.first {
            model.sidebar = .all
            let active = model.activeFaces(inFolder: library.path).count
            model.requestRemove(library)
            log.append("  remove asks first: \(model.pendingFolderRemoval != nil) (\(active) active)")
            model.remove(library)
            await wait("folder removed and its fonts off") {
                model.folders.isEmpty && !model.faces.contains { $0.path.map { LibraryPaths.isInside($0, folder: library.path) } == true }
            }
            log.append("  still registered under the test folder: \(model.registeredPaths.filter { $0.hasPrefix(library.path) }.count)")
        }
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
