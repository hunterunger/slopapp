import AppKit
import RulerCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility + a full-screen overlay (the measuring session). See
// docs/design-system.md, section 2.

extension KeyboardShortcuts.Name {
    // ⌥⇧M ("measure"). Clear of macOS and of the suite's ⌥⇧V (Clips) and ⌥⇧C (Dropper).
    static let measure = Self("measure", default: .init(.m, modifiers: [.option, .shift]))
}

@main
struct RulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Ruler")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            RulerMenu(model: model, info: info)
        } label: {
            Image(systemName: model.isMeasuring ? "ruler.fill" : "ruler")
                .accessibilityLabel("Ruler")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// Like the original's status menu: Measure → session actions → options → footer.
struct RulerMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        if !model.hasPermission {
            // A section header, not a disabled item that looks like an unavailable action.
            Section("Screen Recording Is Off") {
                Button("Allow Screen Recording…") { PermissionWindow.show() }
            }
            Divider()
        }
        measureButton
        Button("Clear Measurements") { model.stopMeasuring() }
            .disabled(model.state != .background)
        Button("Restore Last Session") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.restoreLastSession() }
        }
        .disabled(!model.hasSavedSession)
        Divider()
        Picker("Edge Tolerance", selection: $model.tolerance) {
            ForEach(Tolerance.allCases) { Text($0.title).tag($0) }
        }
        Picker("Units", selection: $model.unit) {
            ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
        }
        Picker("Scale", selection: $model.designScale) {
            ForEach(ScaleChoice.choices(including: model.designScale)) { Text($0.title).tag($0.value) }
        }
        Picker("Copy Format", selection: $model.copyFormat) {
            ForEach(CopyFormat.allCases) { Text($0.shortTitle).tag($0) }
        }
        MenuFooter(info: info)
            .onAppear { model.refreshPermission() }
    }

    @ViewBuilder
    private var measureButton: some View {
        let button = Button(model.state == .background ? "Resume Measuring" : "Measure") {
            // Let the menu close before the screen freezes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.toggleMeasuring() }
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .measure), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }
}

/// A design-scale menu entry: the presets, plus a custom value set in Settings.
struct ScaleChoice: Identifiable, Hashable {
    let value: Double
    var id: Double { value }
    var title: String { DesignScale.title(value) }

    static func choices(including current: Double) -> [ScaleChoice] {
        var values = DesignScale.presets
        if !values.contains(current) { values.append(current) }
        return values.map(ScaleChoice.init(value:))
    }
}

extension KeyboardShortcuts.Shortcut {
    /// The shortcut as a SwiftUI key equivalent, so the menu shows it. Letters and digits only.
    var menuKey: KeyEquivalent? {
        guard let last = description.last, last.isLetter || last.isNumber else { return nil }
        return KeyEquivalent(Character(last.lowercased()))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        KeyboardShortcuts.onKeyDown(for: .measure) { model.toggleMeasuring(started: Diagnostics.now()) }
        if Diagnostics.testHooks { installTestHooks(model) }
        TestScene.showIfRequested()
        Diagnostics.record("launched permission=\(model.hasPermission) testScene=\(Diagnostics.testScene)")
    }

    private func installTestHooks(_ model: AppModel) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.ruler.test."
        let actions: [String: @MainActor (String?) -> Void] = [
            "measure": { _ in if MeasureOverlay.current == nil { model.toggleMeasuring(started: Diagnostics.now()) } },
            "close": { _ in MeasureOverlay.current?.close() },
            "toggle": { _ in model.toggleMeasuring(started: Diagnostics.now()) },
            "background": { _ in MeasureOverlay.current?.enterBackground(returnFocus: true) },
            "resume": { _ in MeasureOverlay.current?.resume(started: Diagnostics.now()) },
            "restore": { _ in model.restoreLastSession() },
            "selfcheck": { _ in MeasureOverlay.current?.selfCheck() },
            "leakcheck": { _ in MeasureOverlay.current?.screenshotLeakCheck() },
            // object: a .png path; the whole overlay as drawn (test scene only)
            "dump": { object in if let object { MeasureOverlay.current?.dump(to: object) } },
            // object: a letter, as if typed on the overlay at the test pointer
            "key": { object in if let object { MeasureOverlay.current?.testKey(object) } },
            // object: "x,y" in test-scene points (top-left origin)
            "hover": { object in
                guard let p = Self.numbers(object), p.count == 2 else { return }
                MeasureOverlay.current?.testHover(scenePoint: CGPoint(x: p[0], y: p[1]))
            },
            // object: "x1,y1,x2,y2[,1 = shift[,1 = keep the button down]]" in test-scene points: a
            // real-style mouse drag (held: stops before mouse-up, to see the box being drawn)
            "mousedrag": { object in
                guard let p = Self.numbers(object), p.count >= 4 else { return }
                MeasureOverlay.current?.testMouseDrag(from: CGPoint(x: p[0], y: p[1]), to: CGPoint(x: p[2], y: p[3]),
                                                      shift: p.count > 4 && p[4] != 0, release: !(p.count > 5 && p[5] != 0))
            },
            // object: "light", "dark" or "system": switch the app's appearance live, to check
            // that every layer and window follows (the system setting is never touched)
            "appearance": { object in
                NSApp.appearance = switch object {
                case "light": NSAppearance(named: .aqua)
                case "dark": NSAppearance(named: .darkAqua)
                default: nil
                }
                Diagnostics.record("appearance set=\(object ?? "system")")
            },
            // Makes the test scene the key window, so Settings can be checked inactive
            "focusscene": { _ in TestScene.window?.makeKeyAndOrderFront(nil) },
            // object: "shift", "command" or "none": modifier keys as if held on the overlay
            "flags": { object in MeasureOverlay.current?.testFlags(object ?? "none") },
            // object: "x,y,w,h[,free]" in test-scene points
            "drag": { object in
                guard let p = Self.numbers(object), p.count >= 4 else { return }
                MeasureOverlay.current?.testDrag(sceneRect: CGRect(x: p[0], y: p[1], width: p[2], height: p[3]), free: p.count > 4 && p[4] != 0)
            },
        ]
        for (name, action) in actions {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { note in
                let object = note.object as? String
                MainActor.assumeIsolated { action(object) }
            }
        }
    }

    private static func numbers(_ text: String?) -> [CGFloat]? {
        text?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard MeasureOverlay.current == nil else { return }
        standard.applicationDidBecomeActive(notification)
        AppModel.shared.refreshPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting mid-session (or with measurements kept on screen) keeps them for Restore.
        MeasureOverlay.current?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
