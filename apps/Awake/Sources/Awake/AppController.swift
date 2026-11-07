import AppKit
import AwakeCore
import SlopKit
import SwiftUI

/// Settings tabs, so the menu's "Set Up Triggers…" can open the right one.
enum SettingsTab: Hashable {
    case general, triggers, shortcuts, advanced, about
}

/// Wires the core to the system: status item, global shortcut, URL scheme, wake, windows.
@MainActor
@Observable
final class AppController {
    static let shared = ReviewHooks.isDemo
        ? AppController(assertion: NoopAssertion(), monitors: ReviewHooks.demoMonitors())
        : AppController()

    let info = AppInfo.current(fallbackName: "Awake")
    let preferences: AwakePreferences
    let controller: AwakeController
    var settingsTab: SettingsTab = .general

    @ObservationIgnored private(set) lazy var statusItem = StatusItemController(app: self)
    @ObservationIgnored private lazy var customWindow = CustomSessionWindow(controller: controller)

    /// `AWAKE_DEFAULTS_SUITE=name` keeps Awake's settings in a separate domain, so tests and
    /// diagnostics never touch the real ones.
    static var defaults: UserDefaults {
        ProcessInfo.processInfo.environment["AWAKE_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    init(
        preferences: AwakePreferences = AwakePreferences(defaults: AppController.defaults),
        assertion: any PowerAssertion = IOKitPowerAssertion(),
        monitors: SystemMonitors = .live()
    ) {
        self.preferences = preferences
        controller = AwakeController(
            assertion: assertion, scheduler: TimerScheduler(), preferences: preferences, monitors: monitors
        )
    }

    func start() {
        statusItem.install()
        KeyboardShortcuts.onKeyUp(for: .toggleAwake) { [weak self] in self?.toggleFromShortcut() }

        // Timers don't count time asleep, so re-check the clock on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refresh() }
        }

        // AWAKE_ACTIVATE=15m (or 2h, forever...) starts a session at launch, for testing and
        // scripting: `open -a Awake --env AWAKE_ACTIVATE=1h`. Otherwise "Turn on when Awake opens".
        if let value = ProcessInfo.processInfo.environment["AWAKE_ACTIVATE"],
           let duration = AwakeDuration(parsing: value) {
            controller.start(duration)
        } else if preferences.activateAtLaunch {
            controller.startDefault()
        }
        ReviewHooks.showIfAsked(self)
        if SelfTest.isRequested {
            // A run-loop timer, not the main queue: the test spins the run loop and needs
            // main-queue work (observation updates) to keep flowing.
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                MainActor.assumeIsolated { SelfTest.run(AppController.shared) }
            }
        }
    }

    /// The global shortcut. The menu bar icon may be hidden, so confirm with a HUD.
    func toggleFromShortcut() {
        controller.toggle()
        HUD.show(controller.confirmationText, systemImage: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
    }

    func open(_ url: URL) {
        guard let command = URLCommand(url: url) else { return }
        controller.perform(command)
    }

    // MARK: Menu commands

    func perform(_ command: MenuCommand) {
        switch command {
        case .turnOn: controller.startDefault()
        case .turnOff: controller.stop()
        case .start(let duration): controller.start(duration)
        case .until: customWindow.show(mode: .until)
        case .customDuration: customWindow.show(mode: .duration)
        case .whileRunning(let app): controller.start(.whileRunning(app))
        case .extend: controller.extend()
        case .toggleDisplaySleep: preferences.keepDisplayOn.toggle()
        case .toggleTriggers: preferences.triggersEnabled.toggle()
        case .setUpTriggers: showSettings(tab: .triggers)
        case .settings: showSettings(tab: .general)
        case .about: AboutWindow.show(info: info)
        case .quit: NSApp.terminate(nil)
        }
    }

    func showSettings(tab: SettingsTab) {
        settingsTab = tab
        SettingsOpener.open()
    }
}
