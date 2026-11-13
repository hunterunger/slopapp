import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// `TRIGGERS_SNAPSHOT_DIR=/path` (with `TRIGGERS_DATA_DIR` and `TRIGGERS_FAKE_APPS`): renders the
/// editor, the trigger sheet and Settings offscreen in light and dark, then quits. For layout
/// review when the screen can't be driven. Materials and the toolbar don't render offscreen;
/// check those on screen with `scripts/drive shot`.
@MainActor
enum Snapshots {
    static func runIfAsked(model: AppModel) -> Bool {
        guard let directory = Diagnostics.snapshotDirectory, Diagnostics.isTestMode else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                model.replaceForSnapshot(Config())
                model.selection = .allApps
                render(EditorView(model: model).frame(width: 760, height: 520), "editor-firstrun-\(name)", directory)
                model.replaceForSnapshot(sampleConfig)
                model.selection = .allApps
                model.selectedBindings = [model.config.bindings[1].id]
                render(EditorView(model: model).frame(width: 760, height: 480), "editor-allapps-\(name)", directory)
                model.selection = .app("com.example.harbor")
                model.selectedBindings = []
                render(EditorView(model: model).frame(width: 760, height: 480), "editor-app-\(name)", directory)
                model.selection = .app("com.example.ledger")
                render(EditorView(model: model).frame(width: 760, height: 480), "editor-empty-app-\(name)", directory)
                model.selection = .allApps
                render(TriggerSheet(model: model, draft: model.newDraft(in: .allApps)), "sheet-new-\(name)", directory)
                render(TriggerSheet(model: model, draft: Draft(binding: model.config.bindings[2], isNew: false)), "sheet-edit-\(name)", directory)
                render(TriggerSheet(model: model, draft: Draft(binding: model.config.bindings[4], isNew: false)), "sheet-menu-\(name)", directory)
                render(TriggerSheet(model: model, draft: Draft(binding: model.config.bindings[8], isNew: false)), "sheet-steps-\(name)", directory)
                render(StepsPreview(model: model, binding: model.config.bindings[8]), "sheet-steps-lower-\(name)", directory)
                model.isPaused = true
                render(InfoBars(model: model).frame(width: 560), "infobars-\(name)", directory)
                model.isPaused = false
                render(SettingsView(model: model, info: AppInfo.current(fallbackName: "Triggers")), "settings-\(name)", directory)
            }
            NSApp.terminate(nil)
        }
        return true
    }

    static var sampleConfig: Config {
        let cmd = Modifiers.command
        var config = Config(bindings: [
            TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps),
            TriggerBinding(trigger: .gesture(.swipe(4, .left), modifiers: []), action: .window(.leftHalf), scope: .allApps),
            TriggerBinding(trigger: .gesture(.swipe(3, .up), modifiers: []), action: .pressKeys(KeyCombo(keyCode: 17, modifiers: cmd)), scope: .allApps),
            TriggerBinding(trigger: .keyCombo(KeyCombo(keyCode: 38, modifiers: [.control, .option])), action: .open(.app(bundleID: "com.example.atlas", name: "Atlas Notes")), scope: .allApps),
            TriggerBinding(trigger: .mouseButton(2, modifiers: .option), action: .menuItem(["View", "Show Sidebar"]), scope: .allApps, isEnabled: false),
            TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: cmd)), scope: .app(bundleID: "com.example.harbor")),
            TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .passThrough, scope: .app(bundleID: "com.example.harbor")),
            TriggerBinding(trigger: .gesture(.tap(4), modifiers: []), action: .runShortcut("Log Water"), scope: .allApps),
            TriggerBinding(trigger: .keySequence(.doubleTap(.command)), steps: [
                .action(.open(.app(bundleID: "com.example.atlas", name: "Atlas Notes"))),
                .waitUntil(.frontApp(bundleID: "com.example.atlas", name: "Atlas Notes", isFront: true), timeout: 5),
                .delay(0.25),
                .action(.pressKeys(KeyCombo(keyCode: 45, modifiers: cmd))),
            ], conditions: ConditionSet(match: .all, [.days([2, 3, 4, 5, 6]), .time(from: 9 * 60, to: 18 * 60)]), scope: .allApps),
            TriggerBinding(trigger: .gesture(.pinchOut(4), modifiers: []), action: .system(.missionControl), scope: .allApps),
            TriggerBinding(trigger: .gesture(.cornerTap(.topRight), modifiers: []), action: .media(.playPause),
                           conditions: ConditionSet([.power(.charger)]), scope: .allApps),
        ])
        config.addApp(bundleID: "com.example.harbor", name: "Harbor Browser")
        config.addApp(bundleID: "com.example.ledger", name: "Ledger")
        config.setUsesAllAppsTriggers(false, in: "com.example.canvas", name: "Canvas Studio")
        return config
    }

    private static func render<V: View>(_ view: V, _ name: String, _ directory: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
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
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}

/// The lower half of the trigger sheet (conditions and steps), for review without scrolling.
private struct StepsPreview: View {
    let model: AppModel
    @State var binding: TriggerBinding

    var body: some View {
        Form {
            ConditionsSection(model: model, conditions: $binding.conditions)
            StepsEditor(model: model, steps: $binding.steps, scope: binding.scope)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 540, height: 820)
    }
}
