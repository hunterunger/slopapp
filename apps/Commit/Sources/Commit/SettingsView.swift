import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// General (launch at login, auto-fetch, untracked files), Advanced (which git, shell PATH), About.
struct SettingsView: View {
    let app: AppModel
    let info: AppInfo
    @AppStorage(Preference.autoFetchMinutes) private var autoFetch = 0
    @AppStorage(Preference.showUntracked) private var showUntracked = true
    @AppStorage(Preference.useShellPath) private var useShellPath = true
    @AppStorage(Preference.gitOverride) private var gitOverride = ""

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            Picker("Fetch automatically", selection: $autoFetch) {
                Text("Off").tag(0)
                Text("Every 5 minutes").tag(5)
                Text("Every 15 minutes").tag(15)
                Text("Every 30 minutes").tag(30)
            }
            Text("Fetches from your remotes while a repository window is open. Off means Commit only talks to your remotes when you fetch, pull or push.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show untracked files", isOn: $showUntracked)
        } advanced: {
            LabeledContent("Git") {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text(gitDescription)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: Spacing.s) {
                        if !gitOverride.isEmpty {
                            Button("Use Automatic") {
                                gitOverride = ""
                                app.reloadGit()
                            }
                        }
                        Button("Choose…", action: chooseGit)
                    }
                    .controlSize(.small)
                }
            }
            Toggle("Use my login shell's PATH for Git and hooks", isOn: $useShellPath)
                .onChange(of: useShellPath) { _, _ in app.reloadGit() }
            Text("Hooks, Git LFS and GPG then find the same tools as in Terminal. Commit reads your shell's PATH once when it starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: autoFetch) { _, _ in notifyWindows() }
        .onChange(of: showUntracked) { _, _ in notifyWindows() }
    }

    private var gitDescription: String {
        switch app.installation {
        case .found(let path, let version): "\(path) (\(version))"
        case .tooOld(let path, let version): "\(path) (\(version), too old)"
        case .badOverride(let path): "\(path) doesn't run"
        case .missing: "Not installed"
        case nil: "Looking…"
        }
    }

    private func chooseGit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.message = "Choose a git executable."
        panel.prompt = "Use This Git"
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        gitOverride = url.path
        app.reloadGit()
    }

    private func notifyWindows() {
        NotificationCenter.default.post(name: .commitSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let commitSettingsChanged = Notification.Name("app.slopapp.commit.settingsChanged")
}
