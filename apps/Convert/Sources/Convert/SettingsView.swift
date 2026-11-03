import ConvertCore
import SlopKit
import SwiftUI

/// General and About. No "Launch at login": Convert is a window you open when you have
/// files to convert, so starting it at login would only cost memory (owner decision).
/// Formats, quality and destination live in the window's format bar, not here.
struct SettingsView: View {
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}

struct GeneralSettings: View {
    @AppStorage(AppModel.playSoundKey) private var playSound = true
    @Bindable private var model = AppModel.shared

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $playSound) {
                    Text("Play sound when done")
                    Text("When a conversion that took a while finishes.")
                }
                Toggle(isOn: $model.settings.keepDates) {
                    Text("Keep original file dates")
                    Text("New files get the original's creation and modification dates.")
                }
            }
        }
    }
}
