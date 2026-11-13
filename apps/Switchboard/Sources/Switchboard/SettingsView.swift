import AppKit
import ServiceManagement
import SlopKit
import SwiftUI
import SwitchboardCore

/// Settings: General, Browsers, Rules, About. Built from SlopKit's pieces; Switchboard needs
/// two custom tabs, so it composes them instead of using `SlopSettings`.
enum SettingsTab: String, Hashable {
    case general, browsers, email, files, rules, rewrite, about
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @State private var tab = Diagnostics.initialSettingsTab ?? .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                DefaultBrowserRow(model: model)
                Picker("Picker size", selection: $model.config.pickerSize) {
                    ForEach(PickerSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                SettingsFileRow(model: model)
                if let notice = model.recoveryNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tag(SettingsTab.general)
            .tabItem { Label("General", systemImage: "gearshape") }

            BrowsersTab(model: model)
                .tag(SettingsTab.browsers)
                .tabItem { Label("Browsers", systemImage: "safari") }

            EmailTab(model: model)
                .tag(SettingsTab.email)
                .tabItem { Label("Email", systemImage: "envelope") }

            FilesTab(model: model)
                .tag(SettingsTab.files)
                .tabItem { Label("Files", systemImage: "doc") }

            RulesTab(model: model)
                .tag(SettingsTab.rules)
                .tabItem { Label("Rules", systemImage: "arrow.triangle.branch") }

            RewriteTab(model: model)
                .tag(SettingsTab.rewrite)
                .tabItem { Label("Rewrite", systemImage: "wand.and.rays") }

            AboutSettingsTab(info: info)
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
        .onReceive(NotificationCenter.default.publisher(for: .switchboardShowTab)) { note in
            if let name = note.object as? String, let next = SettingsTab(rawValue: name) { tab = next }
        }
        .onAppear {
            model.refreshInstalledApps()
            model.refreshMailApps()
            model.refreshDefaultStatus()
        }
    }
}

struct DefaultBrowserRow: View {
    @Bindable var model: AppModel

    var body: some View {
        // The explanation is the row's subtitle, not a row of its own.
        LabeledContent {
            if model.isDefaultBrowser {
                Label {
                    Text("Switchboard")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
            } else {
                Button("Make Default Browser…") { model.makeDefaultBrowser() }
            }
        } label: {
            Text("Default browser")
            Text(subtitle)
        }
    }

    private var subtitle: String {
        guard model.isDefaultBrowser else {
            return "Switchboard only sees links once it's the default browser. macOS will ask you to confirm."
        }
        let base = "Links you click in other apps come to Switchboard first."
        guard model.launchAtLoginWasTurnedOn, SMAppService.mainApp.status == .enabled else { return base }
        return base + " Becoming the default browser turned on Launch at login, so links never wait for Switchboard to start. You can turn it off above."
    }
}

// MARK: - Shared list chrome

/// The standard macOS +/− bar under a list.
struct ListButtonBar<Add: View, Trailing: View>: View {
    let canRemove: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let remove: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    @ViewBuilder let add: () -> Add
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            add()
            Button(action: remove) {
                Label("Remove", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(!canRemove)
            .help("Remove (Delete)")
            .accessibilityLabel("Remove")
            trailing()
            Spacer()
            Button(action: moveUp) {
                Label("Move Up", systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(!canMoveUp)
            .help("Move up")
            .accessibilityLabel("Move Up")
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button(action: moveDown) {
                Label("Move Down", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(!canMoveDown)
            .help("Move down")
            .accessibilityLabel("Move Down")
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
        .buttonStyle(.borderless)
    }
}

extension Array {
    mutating func moveElement(at index: Int, by offset: Int) {
        let destination = index + offset
        guard indices.contains(index), indices.contains(destination) else { return }
        swapAt(index, destination)
    }
}

extension ListButtonBar where Trailing == EmptyView {
    init(
        canRemove: Bool, canMoveUp: Bool, canMoveDown: Bool,
        remove: @escaping () -> Void, moveUp: @escaping () -> Void, moveDown: @escaping () -> Void,
        @ViewBuilder add: @escaping () -> Add
    ) {
        self.init(canRemove: canRemove, canMoveUp: canMoveUp, canMoveDown: canMoveDown,
                  remove: remove, moveUp: moveUp, moveDown: moveDown, add: add, trailing: { EmptyView() })
    }
}

/// "Undo" next to a list after something was removed. Menu bar apps don't show their menu
/// bar, so Edit ▸ Undo (⌘Z) exists but nobody can see it; this makes it visible.
struct UndoRemovalButton: View {
    let label: String
    @Binding var isVisible: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if isVisible {
            Button(label) {
                undoManager?.undo()
                isVisible = false
            }
            .help("Undo (⌘Z)")
            .task(id: isVisible) {
                try? await Task.sleep(for: .seconds(10))
                isVisible = false
            }
        }
    }
}
