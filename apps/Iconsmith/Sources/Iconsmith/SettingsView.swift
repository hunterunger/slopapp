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
                    Toggle("Show exported files in Finder", isOn: $model.prefs.revealAfterExport)
                    Text("Selects the new file in Finder, reusing a window that already shows its folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}
