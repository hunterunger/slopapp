import AppKit
import AwakeCore
import SlopKit

/// Diagnostics: `AWAKE_SELFTEST=1` (with `AWAKE_DEFAULTS_SUITE`) exercises the real UI objects
/// without a mouse: builds the status item menu and runs its items, simulates icon clicks,
/// opens Settings on the Triggers tab and the Keep Awake window, then prints PASS/FAIL lines
/// and quits. For when the screen can't be driven (locked, CI). Holds real assertions
/// briefly, like a normal session.
@MainActor
enum SelfTest {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["AWAKE_SELFTEST"] != nil }

    private static var failures = 0

    private static func check(_ condition: Bool, _ name: String) {
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL") \(name)")
    }

    static func run(_ app: AppController) {
        let controller = app.controller
        let items = app.statusItem

        check(items.button != nil, "status item has a button")
        check(items.button?.accessibilityLabel() == app.info.name, "status button is labelled")
        check(items.button?.toolTip?.contains("Right-click for options") == true, "tooltip explains the right-click")

        // Left click toggles, right-click opens the menu (default setting).
        items.simulateClick(right: false)
        check(controller.isActive, "left click turns on")
        check(controller.session?.duration == app.preferences.defaultDuration, "left click uses the default duration")
        items.simulateClick(right: false)
        check(!controller.isActive, "second left click turns off")
        check(items.whatClickDoes(right: true) == .openMenu, "right-click opens the menu")
        check(items.whatClickDoes(right: false, option: true) == .openMenu, "Option-click opens the menu")
        app.preferences.leftClick = .openMenu
        check(items.whatClickDoes(right: false) == .openMenu, "swapped: left click opens the menu")
        check(items.whatClickDoes(right: true) == .toggle, "swapped: right-click toggles")
        app.preferences.leftClick = .toggle

        // The real NSMenu, built from the same entries, and its items' actions.
        let menu = MenuBuilder(app: app).build(MenuContent.entries(for: controller, appName: app.info.name))
        let titles = menu.items.map(\.title)
        check(titles.first == "Turn On", "menu starts with Turn On")
        check(titles.contains("Until…") && titles.contains("Custom Duration…"), "menu has Until… and Custom Duration…")
        check(titles.last == "Quit \(app.info.name)", "menu ends with Quit")
        check(menu.items.first { $0.title == "Quit \(app.info.name)" }?.keyEquivalent == "q", "Quit has ⌘Q")
        check(menu.items.contains { $0.title == "While App Is Running" && ($0.submenu?.items.count ?? 0) > 0 },
              "While App Is Running lists apps")
        func run(_ title: String, in menu: NSMenu) {
            guard let item = menu.items.first(where: { $0.title == title }) else {
                check(false, "menu item \(title) exists")
                return
            }
            menu.performActionForItem(at: menu.index(of: item))
        }
        run("30 Minutes", in: menu)
        check(controller.session?.duration == .minutes(30), "menu: 30 Minutes starts a session")
        let active = MenuBuilder(app: app).build(MenuContent.entries(for: controller, appName: app.info.name))
        check(active.items.first?.title == "30 min left", "menu shows time left")
        check(active.items.contains { $0.title == "30 Minutes" && $0.state == .on }, "menu checks the running preset")
        run("Add 30 Minutes", in: active)
        check(controller.statusText == "1 hr left", "menu: Add 30 Minutes extends")
        let before = app.preferences.keepDisplayOn
        run("Allow Display Sleep", in: active)
        check(app.preferences.keepDisplayOn == !before, "menu: Allow Display Sleep toggles")
        app.preferences.keepDisplayOn = before
        run("Turn Off", in: active)
        check(!controller.isActive, "menu: Turn Off")

        // Settings opens, on the Triggers tab from "Set Up Triggers…".
        app.perform(.setUpTriggers)
        wait(1.0)
        check(app.settingsTab == .triggers, "Set Up Triggers… selects the Triggers tab")
        check(SettingsWindow.window?.isVisible == true, "Settings window opens")
        SettingsWindow.window?.close()

        // Until… opens the Keep Awake window.
        app.perform(.until)
        wait(0.3)
        let keepAwake = NSApp.windows.first { $0.title == "Keep Awake" }
        check(keepAwake?.isVisible == true, "Until… opens the Keep Awake window")
        keepAwake?.orderOut(nil)

        // Show time left in the menu bar.
        app.preferences.showTimeInMenuBar = true
        controller.start(.hours(1))
        wait(0.2)
        check(items.button?.title.contains("1h 00m") == true, "menu bar shows time left (\(items.button?.title ?? "nil"), \(controller.menuBarText ?? "nil"))")
        controller.stop()
        app.preferences.showTimeInMenuBar = false
        wait(0.2)
        check(items.button?.title.isEmpty == true, "menu bar title clears")

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    private static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
