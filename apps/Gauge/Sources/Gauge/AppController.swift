import AppKit
import GaugeCore
import IOKit.ps
import SlopKit
import SwiftUI

/// Owns the sampler, the status item and the panel, and wires them to the system's events.
@MainActor
final class AppController {
    static let shared = AppController()

    let info = AppInfo.current(fallbackName: "Gauge")
    let store: PreferencesStore
    let panelModel: PanelModel
    private(set) var hasBattery = true

    private let environment = ProcessInfo.processInfo.environment
    private var sampler: Sampler!
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var started = false
    private var systemAsleep = false
    private var screensAsleep = false
    private var batterySource: CFRunLoopSource?
    private var appliedIconVisibility = true

    init() {
        // GAUGE_DEFAULTS_SUITE=<name> keeps test runs out of the real settings.
        let defaults = environment["GAUGE_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:)) ?? .standard
        if environment["GAUGE_RESET"] == "1" { defaults.removeObject(forKey: PreferencesCodec.key) }
        store = PreferencesStore(defaults: defaults)
        panelModel = PanelModel(defaults: defaults)
        ReviewHooks.applyPreferenceOverrides(to: store, environment: environment)
    }

    func start() {
        guard !started else { return }
        started = true
        if Snapshots.runIfAsked(controller: self) {
            NSApp.terminate(nil)
            return
        }
        let clock = SystemClock()
        let isDemo = ReviewHooks.isDemo(environment)
        let tick: TickSources
        let processes: any ProcessSource
        let volumes: any VolumeSource
        let battery: any BatterySource
        let ps: (any PSRunner)?
        var world: DemoWorld?
        if isDemo {
            let demo = DemoWorld(clock: clock)
            let made = demo.makeSources()
            (tick, processes, volumes, battery, ps) = (made.tick, made.processes, made.volumes, made.battery, nil)
            world = demo
        } else {
            tick = TickSources(cpu: SystemCPU(), memory: SystemMemory(), network: SystemNetwork(), gpu: SystemGPU(),
                               diskIO: SystemDiskIO(), load: SystemLoadSource())
            (processes, volumes, battery, ps) = (SystemProcesses(), SystemVolumes(), SystemBattery(), SystemPS())
        }
        hasBattery = battery.read(details: false) != nil
        let session = GaugeSession(sources: tick, processes: processes, preferences: store.preferences,
                                   hasBattery: hasBattery, appName: info.name)
        if let world { ReviewHooks.seedHistory(session: session, world: world, now: clock.now()) }

        statusItem = StatusItemController()
        sampler = Sampler(session: session, clock: clock, volumes: volumes, battery: battery, ps: ps,
                          onMenuBar: { content in AppController.shared.statusItem.render(content) },
                          onPanel: { update in AppController.shared.panelModel.apply(update) })
        panel = PanelController(model: panelModel, statusItem: statusItem, sampler: sampler, controller: self)
        panelModel.hasBattery = hasBattery
        panelModel.thermal = Self.thermalLevel()

        statusItem.onPress = { [weak self] in self?.panel.buttonPressed() }
        statusItem.onSessionBegin = { [weak self] in self?.panel.sessionBegan() }
        statusItem.onSessionEnd = { [weak self] in self?.panel.sessionEnded() }
        statusItem.onRemoved = { MenuBarIcon.isVisible = false }
        store.onChange = { [weak self] preferences in self?.sampler.setPreferences(preferences) }

        applyIconVisibility()
        observeSystem(observeBattery: hasBattery && !isDemo)
        sampler.start(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggleFromShortcut() }
        ReviewHooks.run(environment, controller: self, sampler: sampler)
    }

    var statusItemForProbe: StatusItemController { statusItem }

    // MARK: Actions

    func togglePanel() { panel.toggleFromShortcut() }
    func showPanel() { panel.show() }
    func closePanel() { panel.close() }

    func openSettings() {
        panel.close()
        SettingsWindow.open()
    }

    func showAbout() {
        panel.close()
        AboutWindow.show(info: info)
    }

    func openActivityMonitor() {
        panel.close()
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        if environment["GAUGE_NO_OPEN"] != nil {
            HUD.show("Would open Activity Monitor", systemImage: "arrow.up.forward.app")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    // MARK: System events

    private func observeSystem(observeBattery: Bool) {
        let workspace = NSWorkspace.shared.notificationCenter
        let observe: (NotificationCenter, Notification.Name, @escaping @MainActor () -> Void) -> Void = { center, name, action in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { action() } }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.systemAsleep = true; self?.updatePause() }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.systemAsleep = false; self?.updatePause() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.screensAsleep = true; self?.updatePause() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.screensAsleep = false; self?.updatePause() }
        observe(workspace, NSWorkspace.didMountNotification) { [weak self] in self?.sampler.volumesChanged() }
        observe(workspace, NSWorkspace.didUnmountNotification) { [weak self] in self?.sampler.volumesChanged() }
        observe(workspace, NSWorkspace.didRenameVolumeNotification) { [weak self] in self?.sampler.volumesChanged() }
        observe(.default, .NSProcessInfoPowerStateDidChange) { [weak self] in
            self?.sampler.setLowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { [weak self] in
            self?.panelModel.thermal = Self.thermalLevel()
        }
        // Setting `isVisible` itself writes to UserDefaults (the autosave), so only react to a
        // real change of the setting, and apply it outside the notification.
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            guard let self, MenuBarIcon.isVisible != self.appliedIconVisibility else { return }
            DispatchQueue.main.async { self.applyIconVisibility() }
        }
        if observeBattery { startBatteryNotifications() }
    }

    private func updatePause() {
        if systemAsleep || screensAsleep {
            panel.close()
            sampler.pause()
        } else {
            sampler.resume()
        }
    }

    private func applyIconVisibility() {
        appliedIconVisibility = MenuBarIcon.isVisible
        statusItem.isVisible = appliedIconVisibility
    }

    /// IOPowerSources calls back on the main run loop whenever the battery changes: plugging
    /// in, a percent, a new time estimate. Nothing polls the battery.
    private func startBatteryNotifications() {
        let callback: IOPowerSourceCallbackType = { _ in
            MainActor.assumeIsolated { AppController.shared.sampler.batteryChanged() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        batterySource = source
    }

    static func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
