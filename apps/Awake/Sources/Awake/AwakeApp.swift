import AppKit
import AwakeCore
import SlopKit
import SwiftUI

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var controller: AwakeController
    private let info = AppInfo.current(fallbackName: "Awake")

    init() {
        let controller = AwakeController(assertion: IOKitPowerAssertion(), scheduler: TimerScheduler())

        // AWAKE_ACTIVATE=15m (or 2h, forever...) starts a session at launch.
        // Handy for testing and for scripting: `open -a Awake --env AWAKE_ACTIVATE=1h`.
        if let value = ProcessInfo.processInfo.environment["AWAKE_ACTIVATE"],
           let duration = AwakeDuration(parsing: value) {
            controller.start(duration)
        }

        // Timers don't count time asleep, so re-check the clock on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { controller.refresh() }
        }

        _controller = State(initialValue: controller)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            AwakeMenu(controller: controller, info: info)
        } label: {
            Image(systemName: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .accessibilityLabel(controller.isActive ? "Awake: on" : "Awake: off")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SlopSettings(info: info, isMenuBarApp: true)
        }
    }
}

struct AwakeMenu: View {
    @Bindable var controller: AwakeController
    let info: AppInfo

    var body: some View {
        if let status = controller.statusText {
            Text(status)
            Button("Turn Off") { controller.stop() }
                .keyboardShortcut("t")
            Divider()
        }
        if let error = controller.lastError {
            Text(error)
            Divider()
        }

        Section("Keep Awake For") {
            ForEach(AwakeDuration.presets) { duration in
                Toggle(duration.title, isOn: Binding(
                    get: { controller.session?.duration == duration },
                    set: { isOn in isOn ? controller.start(duration) : controller.stop() }
                ))
            }
        }
        Divider()
        Toggle("Keep Display On", isOn: $controller.keepDisplayOn)

        MenuFooter(info: info)
    }
}
