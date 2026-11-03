import AppKit
import SlopKit
import SnapperCore
import SwiftUI

// Archetype: menu bar utility + overlays (the capture overlay, capture cards, pins) + a
// document-style window (the annotation editor). See docs/design-system.md, section 2.

extension KeyboardShortcuts.Name {
    // ⌥⇧⌘ + 3/4/5: the familiar digits, clear of macOS's own (⇧⌘3/4/5, ⌃⇧⌘3/4), of the
    // popular screenshot apps' ⇧⌘2–5, and of typing (⌥⇧+digit types symbols; ⌘ prevents it).
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.option, .shift, .command]))
    static let captureWindow = Self("captureWindow", default: .init(.five, modifiers: [.option, .shift, .command]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.three, modifiers: [.option, .shift, .command]))
    static let capturePreviousArea = Self("capturePreviousArea")
}

@main
struct SnapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Snapper")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            SnapperMenu(model: model, info: info)
        } label: {
            Image(systemName: model.isCapturing ? "camera.fill" : "camera")
                .accessibilityLabel("Snapper")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CaptureCommands(model: model)
            EditorCommands()
        }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// File-menu captures and Help, for when Snapper is the active app (status item hidden
/// by the notch, or simply quicker from the menu bar).
struct CaptureCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            ForEach([(CaptureMode.area, KeyboardShortcuts.Name.captureArea), (.window, .captureWindow),
                     (.fullScreen, .captureFullScreen), (.previousArea, .capturePreviousArea)], id: \.0) { mode, name in
                captureButton(mode, name)
            }
            Divider()
            Button("Annotate Clipboard Image") { model.annotateClipboard() }
            Button("Pin Clipboard Image") { model.pinClipboard() }
            Button("Annotate Image File…") { model.chooseImage { EditorWindowController.open($0, model: model) } }
                .keyboardShortcut("o")
            Button("Pin Image File…") { model.chooseImage { model.pins.pin($0) } }
            Divider()
            Button("Reopen Last Capture") { model.reopenLastCapture() }
        }
        CommandGroup(replacing: .help) {
            Button("Snapper Help") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Snapper"))
            }
        }
    }

    @MainActor
    private func captureButton(_ mode: CaptureMode, _ name: KeyboardShortcuts.Name) -> some View {
        let button = Button(mode.title) {
            // Let the menu close (and our windows step aside) before the screen freezes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.capture(mode) }
        }
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        return button.keyboardShortcut(shortcut?.menuKey.map { KeyboardShortcut($0, modifiers: shortcut!.eventModifiers) })
    }
}

/// Status line → captures → images → open captures → options → footer.
struct SnapperMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        if !model.hasPermission {
            Text("Screen Recording is off")
            Button("Allow Screen Recording…") { PermissionWindow.show() }
            Divider()
        }

        captureButton(.area, shortcut: .captureArea)
        captureButton(.window, shortcut: .captureWindow)
        captureButton(.fullScreen, shortcut: .captureFullScreen)
        captureButton(.previousArea, shortcut: .capturePreviousArea)
        Divider()

        Button("Annotate Clipboard Image") { model.annotateClipboard() }
        Button("Pin Clipboard Image") { model.pinClipboard() }
        Button("Annotate Image File…") { model.chooseImage { EditorWindowController.open($0, model: model) } }
        Button("Pin Image File…") { model.chooseImage { model.pins.pin($0) } }
        Divider()

        Button("Reopen Last Capture") { model.reopenLastCapture() }
            .disabled(model.lastClosed == nil)
        Button("Close All Thumbnails") { model.cards.closeAll() }
            .disabled(model.openCards == 0)
        Button("Close All Pins") { model.pins.closeAll() }
            .disabled(model.openPins == 0)
        Divider()

        Toggle("Hide Desktop Icons in Captures", isOn: $model.hideDesktopIcons)

        MenuFooter(info: info)
            .onAppear { model.refreshPermission() }
    }

    @ViewBuilder
    private func captureButton(_ mode: CaptureMode, shortcut name: KeyboardShortcuts.Name) -> some View {
        let button = Button(mode.title) {
            // Let the menu close before the overlay freezes the screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.capture(mode) }
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: name), let key = shortcut.menuKey {
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
        TemporaryFiles.clear()
        AppPresence.start()
        let model = AppModel.shared
        KeyboardShortcuts.onKeyDown(for: .captureArea) { model.capture(.area, started: Diagnostics.now()) }
        KeyboardShortcuts.onKeyDown(for: .captureWindow) { model.capture(.window, started: Diagnostics.now()) }
        KeyboardShortcuts.onKeyDown(for: .captureFullScreen) { model.capture(.fullScreen, started: Diagnostics.now()) }
        KeyboardShortcuts.onKeyDown(for: .capturePreviousArea) { model.capture(.previousArea, started: Diagnostics.now()) }
        if Diagnostics.testHooks { installTestHooks(model) }
        TestScene.showIfRequested()
        Diagnostics.record("launched permission=\(model.hasPermission)")
    }

    /// Finder ▸ Open With, `open -a Snapper image.png`, or a drop on the Dock icon: each
    /// image opens in the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        var opened = 0
        for url in urls {
            guard let image = NSImage(contentsOf: url), let item = AppModel.item(from: image) else { continue }
            item.sourceName = url.deletingPathExtension().lastPathComponent
            EditorWindowController.open(item, model: model)
            opened += 1
        }
        Diagnostics.record("opened files=\(urls.count) images=\(opened)")
        if opened == 0, !urls.isEmpty {
            HUD.show("Snapper can only open images", systemImage: "photo")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TemporaryFiles.clear()
    }

    private func installTestHooks(_ model: AppModel) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.snapper.test."
        for mode in CaptureMode.allCases {
            center.addObserver(forName: .init(prefix + mode.rawValue), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { model.capture(mode, started: Diagnostics.now()) }
            }
        }
        let actions: [String: @MainActor () -> Void] = [
            "cancel": { RegionOverlay.current?.cancel() },
            "closeCards": { model.cards.closeAll() },
            "closePins": { model.pins.closeAll() },
        ]
        for (name, action) in actions {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
        AppModel.shared.refreshPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
