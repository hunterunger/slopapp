import SlopappCore
import SlopKit
import SwiftUI

struct SettingsView: View {
    let store: Store
    let info: AppInfo
    @AppStorage("openAfterInstall") private var openAfterInstall = true

    var body: some View {
        // SlopSettings' layout (General, About), with the hub's About text.
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                Toggle("Open apps after installing", isOn: $openAfterInstall)
                LabeledContent("Apps install to") {
                    Text(displayPath(store.config.roots.installDirectory)).textSelection(.enabled)
                }
                LabeledContent("Updates") {
                    HStack {
                        Text(store.lastCheck.map { "Checked \(relativeDate($0).lowercasedFirst)" } ?? "Not checked yet")
                            .foregroundStyle(.secondary)
                        Button("Check Now") { Task { await store.refresh() } }
                            .disabled(store.isChecking)
                    }
                }
                Text("Slopapp checks the catalog at most every 6 hours while it's running, and installs only what you ask for. It sends nothing about you or your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            HubAboutView(info: info)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}
