import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// Status line → main actions → options → notices → footer (Settings…, About, Quit).
struct FocusMenu: View {
    @Bindable var controller: FocusController
    let info: AppInfo
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(controller.headline)
        Text(controller.todayText)
        Divider()

        actions

        Divider()
        lengthMenu
        Button(controller.label == nil ? "Add Label…" : "Change Label…") { askForLabel() }
            .keyboardShortcut("l")
        if controller.label != nil {
            Button("Clear Label") { controller.setLabel(nil) }
        }

        notices

        MenuFooter(info: info)
    }

    @ViewBuilder private var actions: some View {
        let settings = controller.settings
        if let phase = controller.runningPhase {
            if controller.isPaused {
                Button("Resume") { controller.resume() }
                    .keyboardShortcut("p")
            } else {
                Button("Pause") { controller.pause() }
                    .keyboardShortcut("p")
            }
            if phase.isBreak {
                Button("Skip Break") { controller.skipBreak() }
                    .keyboardShortcut(.rightArrow)
            }
            Button("Stop") { controller.stop() }
                .keyboardShortcut(".")
            Button("Add \(TimerSettings.minutesAdded) Minutes") { controller.addTime() }
                .keyboardShortcut("+")
        } else if let pending = controller.state.pendingBreak {
            Button("Start Break (\(TimeText.duration(minutes: settings.minutes(for: pending))))") { controller.startBreak() }
                .keyboardShortcut(.return)
            Button("Start Focus (\(TimeText.duration(minutes: settings.focusMinutes)))") { controller.startFocus() }
        } else {
            Button("Start Focus (\(TimeText.duration(minutes: settings.focusMinutes)))") { controller.startFocus() }
                .keyboardShortcut(.return)
        }
    }

    private var lengthMenu: some View {
        Menu("Focus Length") {
            let current = controller.settings.focusMinutes
            ForEach(TimerSettings.focusPresets, id: \.self) { minutes in
                Toggle(TimeText.minutesTitle(minutes), isOn: Binding(
                    get: { current == minutes },
                    set: { _ in controller.updateSettings { $0.focusMinutes = minutes } }
                ))
            }
            if !TimerSettings.focusPresets.contains(current) {
                Toggle("\(TimeText.minutesTitle(current)) (Custom)", isOn: .constant(true))
            }
            Divider()
            Button("Custom…") { openSettings(tab: .timer) }
        }
    }

    @ViewBuilder private var notices: some View {
        if controller.permission == .denied {
            Divider()
            Text("Notifications are off for \(info.name).")
            Button("Open Notification Settings…") {
                NSWorkspace.shared.open(SystemNotifier.settingsURL)
            }
        }
        if let error = controller.automationError {
            Divider()
            Text(error)
            Button("Dismiss") { controller.dismissAutomationError() }
        }
        if let error = controller.saveError {
            Divider()
            Text(error)
        }
    }

    private func askForLabel() {
        let current = controller.label
        // After the menu has closed, so the alert gets the keyboard.
        DispatchQueue.main.async {
            if let label = LabelPrompt.ask(current: current) {
                controller.setLabel(label)
            }
        }
    }

    private func openSettings(tab: SettingsTab) {
        SettingsTab.select(tab)
        AppActivation.activate()
        openSettings()
        SettingsWindow.bringToFront()
    }
}
