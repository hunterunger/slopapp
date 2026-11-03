import AppKit
import DropperCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility (docs/design-system.md 2a), plus a small Contrast Checker window.

@main
struct DropperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var controller = AppController.shared
    private let info = AppInfo.current(fallbackName: "Dropper")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            DropperMenu(controller: controller, model: controller.model)
            MenuFooter(info: info)
        } label: {
            Image(systemName: controller.model.isPicking ? "eyedropper.full" : "eyedropper")
                .accessibilityLabel("Dropper")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: controller.model, info: info)
        }
        .commands { DropperCommands(controller: controller) }
    }
}

/// Pick → last color in every format → recent colors → options → footer.
struct DropperMenu: View {
    let controller: AppController
    @Bindable var model: DropperModel

    var body: some View {
        Button("Pick Color") { controller.pickAndCopy() }
            .globalShortcut(.pickColor)
        Button("Contrast Checker…") { controller.showContrastChecker() }
            .keyboardShortcut("k")
        Divider()

        if let last = model.history.latest {
            Section(lastColorHeader(last.color)) {
                ForEach(ColorFormat.allCases) { format in
                    Button {
                        controller.copy(last, as: format)
                    } label: {
                        Label {
                            Text(model.text(for: last.color, as: format))
                        } icon: {
                            Image(nsImage: SwatchImage.image(for: last.color))
                        }
                    }
                    .accessibilityLabel("Copy as \(format.title): \(model.text(for: last.color, as: format))")
                }
            }
            let recent = Array(model.history.items.dropFirst().prefix(10))
            if !recent.isEmpty {
                Divider()
                Section("Recent Colors") {
                    ForEach(recent) { item in
                        Button {
                            controller.copy(item)
                        } label: {
                            Label {
                                Text(model.menuTitle(for: item.color))
                            } icon: {
                                Image(nsImage: SwatchImage.image(for: item.color))
                            }
                        }
                    }
                }
            }
            Button("Clear History…") { controller.clearHistory() }
        } else {
            Text(emptyLine)
        }
        if let error = model.historyLoadError {
            Text(error)
        }
        Divider()

        Picker("Copy Format", selection: $model.preferences.format) {
            ForEach(ColorFormat.allCases) { format in
                Text(format.title).tag(format)
            }
        }
        Picker("Color Space", selection: $model.preferences.options.space) {
            ForEach(OutputSpace.allCases) { space in
                Text(space.title).tag(space)
            }
        }
    }

    private func lastColorHeader(_ color: ColorValue) -> String {
        let space = model.preferences.options.space
        if color.isOutside(space) { return "Last Color · outside \(space.title)" }
        return "Last Color · \(space.title)"
    }

    private var emptyLine: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .pickColor) {
            return "No colors yet. Press \(shortcut) to pick one."
        }
        return "No colors yet. Choose Pick Color to pick one."
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Settings always opens on General (SwiftUI would restore the last tab).
        UserDefaults.standard.removeObject(forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController.shared
        KeyboardShortcuts.onKeyDown(for: .pickColor) { controller.pickAndCopy() }
        KeyboardShortcuts.onKeyDown(for: .contrastChecker) { controller.showContrastChecker() }
        if Diagnostics.testHooks { installTestHooks(controller) }
    }

    private func installTestHooks(_ controller: AppController) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.dropper.test."
        center.addObserver(forName: .init(prefix + "pick"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { controller.pickAndCopy() }
        }
        center.addObserver(forName: .init(prefix + "contrast"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { controller.showContrastChecker() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
