import IconsmithCore
import SlopKit
import SwiftUI

/// General and About. No "Launch at login": a window app you open when you need it.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        TabView {
            SettingsForm {
                Section {
                    Toggle(isOn: $model.prefs.revealAfterExport) {
                        Text("Show exported files in Finder")
                        Text("Selects the new file, reusing an open Finder window.")
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}
