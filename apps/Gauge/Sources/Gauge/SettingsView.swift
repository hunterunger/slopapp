import GaugeCore
import SlopKit
import SwiftUI

/// General: launch at login, menu bar visibility (SlopKit), what the menu bar shows and how
/// often it updates. Shortcuts: open the panel. About.
struct GaugeSettingsView: View {
    @Bindable var store: PreferencesStore
    let info: AppInfo
    let hasBattery: Bool

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: true) {
            ReadoutPicker(store: store, hasBattery: hasBattery, hasGPU: AppController.shared.panelModel.hasGPU)
            Picker("Update every", selection: $store.preferences.interval) {
                ForEach(UpdateInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            Toggle(isOn: $store.preferences.slowDownInLowPowerMode) {
                Text("Slow down in Low Power Mode")
                Text("Updates every 5 seconds while Low Power Mode is on.")
            }
            Picker("Network speeds in", selection: $store.preferences.rateUnit) {
                ForEach(RateUnit.allCases, id: \.self) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Toggle(isOn: $store.preferences.groupProcessesByApp) {
                Text("Combine helper processes into their app")
                Text("A browser and all its helpers show as one row.")
            }
        } shortcuts: {
            ShortcutRow("Open Gauge", subtitle: "Opens the panel from any app, even when the menu bar is too full to show Gauge.",
                        name: .togglePanel)
        }
    }
}

/// "Menu bar shows": up to three readouts, in order.
struct ReadoutPicker: View {
    @Bindable var store: PreferencesStore
    let hasBattery: Bool
    let hasGPU: Bool

    private var available: [Readout] {
        Readout.allCases.filter { readout in
            switch readout {
            case .battery: hasBattery
            case .gpu: hasGPU
            default: true
            }
        }
    }

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Shown ones first, in menu bar order, then the rest.
                let shown = store.preferences.readouts.filter(available.contains)
                let rest = available.filter { !shown.contains($0) }
                ForEach(shown + rest) { readout in
                    row(readout, position: shown.firstIndex(of: readout), count: shown.count)
                }
            }
        } label: {
            Text("Menu bar shows")
            Text("Up to three, left to right.")
        }
    }

    private func row(_ readout: Readout, position: Int?, count: Int) -> some View {
        HStack(spacing: 0) {
            Toggle(readout.title, isOn: Binding(
                get: { store.preferences.shows(readout) },
                set: { store.preferences.set(readout, shown: $0) }
            ))
            .disabled(!store.preferences.canAdd(readout))
            Spacer(minLength: Spacing.s)
            if let position {
                Button {
                    store.preferences.move(readout, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .disabled(position == 0)
                .accessibilityLabel("Move \(readout.title) left")
                .help("Move left")
                Button {
                    store.preferences.move(readout, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .disabled(position == count - 1)
                .accessibilityLabel("Move \(readout.title) right")
                .help("Move right")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .frame(width: 220)
    }
}
