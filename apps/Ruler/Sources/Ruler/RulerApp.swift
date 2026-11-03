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

/// Status line (if needed) → Measure → options → footer.
struct RulerMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        if !model.hasPermission {
            Text("Screen Recording is off")
            Button("Allow Screen Recording…") { PermissionWindow.show() }
            Divider()
        }
        measureButton
        Divider()
        Picker("Units", selection: $model.unit) {
            ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
        }
        Picker("Copy Format", selection: $model.copyFormat) {
            ForEach(CopyFormat.allCases) { Text($0.shortTitle).tag($0) }
        }
        MenuFooter(info: info)
            .onAppear { model.refreshPermission() }
    }

    @ViewBuilder
    private var measureButton: some View {
        let button = Button("Measure") {
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
            "selfcheck": { _ in MeasureOverlay.current?.selfCheck() },
            // object: "x,y" in test-scene points (top-left origin)
            "hover": { object in
                guard let p = Self.numbers(object), p.count == 2 else { return }
                MeasureOverlay.current?.testHover(scenePoint: CGPoint(x: p[0], y: p[1]))
            },
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
