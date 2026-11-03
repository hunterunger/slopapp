import AppKit
import ServiceManagement
import SlopKit
import SwiftUI
import SwitchboardCore

/// Settings: General, Browsers, Rules, About. Built from SlopKit's pieces; Switchboard needs
/// two custom tabs, so it composes them instead of using `SlopSettings`.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                DefaultBrowserRow(model: model)
                if let notice = model.recoveryNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            BrowsersTab(model: model)
                .tabItem { Label("Browsers", systemImage: "safari") }

            RulesTab(model: model)
                .tabItem { Label("Rules", systemImage: "arrow.triangle.branch") }

            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
        .onAppear {
            model.refreshDefaultStatus()
            model.refreshInstalledApps()
        }
    }
}

struct DefaultBrowserRow: View {
    @Bindable var model: AppModel

    var body: some View {
        LabeledContent("Default browser") {
            if model.isDefaultBrowser {
                Label("Switchboard", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Make Default Browser…") { model.makeDefaultBrowser() }
            }
        }
        Text(model.isDefaultBrowser
             ? "Links you click in other apps come to Switchboard first."
             : "Switchboard only sees links once it's the default browser. macOS will ask you to confirm.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if model.isDefaultBrowser, model.launchAtLoginWasTurnedOn, SMAppService.mainApp.status == .enabled {
            Text("Becoming the default browser turned on Launch at login, so links never wait for Switchboard to start. You can turn it off above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
