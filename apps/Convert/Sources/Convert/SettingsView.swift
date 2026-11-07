import ConvertCore
import SlopKit
import SwiftUI

/// General (starting and when done), Destination, Presets, About. No "Launch at login":
/// Convert is a window you open when you have files to convert (owner decision).
struct SettingsView: View {
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DestinationSettings()
                .tabItem { Label("Destination", systemImage: "folder") }
            PresetSettings()
                .tabItem { Label("Presets", systemImage: "square.stack.3d.up") }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}

struct GeneralSettings: View {
    @AppStorage(AppModel.autoStartKey) private var autoStart = true
    @AppStorage(AppModel.playSoundKey) private var playSound = true
    @AppStorage(AppModel.removeFinishedKey) private var removeFinished = false
    @AppStorage(AppModel.trashOriginalsKey) private var trashOriginals = false
    @AppStorage(AppModel.quitWhenDoneKey) private var quitWhenDone = false

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $autoStart) {
                    Text("Start converting as soon as files are added")
                    Text("Turn off to adjust each file first, then press Start (⌘↩).")
                }
            }
            Section("When Done") {
                Toggle(isOn: $playSound) {
                    Text("Play a sound")
                    Text("When a conversion that took a while finishes.")
                }
                Toggle(isOn: $removeFinished) {
                    Text("Remove finished files from the list")
                    Text("Undo (⌘Z) brings them back.")
                }
                Toggle(isOn: $trashOriginals) {
                    Text("Move originals to the Trash")
                    Text("Only once the new file is saved. Unchanged or failed files are kept.")
                }
                Toggle(isOn: $quitWhenDone) {
                    Text("Quit Convert")
                }
            }
        }
    }
}

struct DestinationSettings: View {
    @Bindable private var model = AppModel.shared

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent {
                    BarMenuButton(name: "Save To", value: DestinationText.short(model.settings.destination),
                                  symbol: model.settings.destination == .alongside ? "doc.on.doc" : "folder",
                                  help: DestinationText.help(model.settings.destination), bordered: true) {
                        MenuEntries.destination(model)
                    }
                    .fixedSize()
                } label: {
                    Text("Save new files")
                    // A no-break space keeps the example name on one line.
                    Text("Nothing is overwritten: if a name is taken, the new file gets a number (“clip\u{00A0}2.mp4”).")
                }
            }
            Section {
                Toggle(isOn: $model.settings.keepDates) {
                    Text("Keep original file dates")
                    Text("New files get the original's creation and modification dates.")
                }
            }
        }
    }
}

/// Built-in presets (read-only) and the user's own (rename, reorder, delete).
struct PresetSettings: View {
    @Bindable private var model = AppModel.shared
    @State private var selection: Preset.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            List(selection: $selection) {
                Section("Built In") {
                    ForEach(Preset.available(model.capabilities)) { preset in
                        row(preset)
                    }
                }
                Section("Yours") {
                    if model.presets.saved.isEmpty {
                        Text("Set formats, quality and size in the window, then Save Current Settings.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.presets.saved) { preset in
                        row(preset)
                    }
                    .onMove { model.presets.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in offsets.map { model.presets.saved[$0].id }.forEach { model.presets.delete($0) } }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            // Tall enough for every built-in preset and the start of "Yours".
            .frame(height: 360)
            .onDeleteCommand { deleteSelected() }
            // Double-click (or Return) uses a preset.
            .contextMenu(forSelectionType: Preset.ID.self) { ids in
                if let id = ids.first, let preset = preset(id) {
                    Button("Use") { model.apply(preset) }
                    if !preset.isBuiltIn {
                        Button("Rename…") { rename(preset) }
                        Button("Delete") { model.presets.delete(id) }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let preset = preset(id) { model.apply(preset) }
            }
            HStack {
                Button("Use") { use() }
                    .disabled(selectedPreset == nil)
                Button("Save Current Settings…") { model.saveCurrentAsPreset() }
                Spacer()
                Button("Rename…") { rename(selectedPreset) }
                    .disabled(selectedPreset?.isBuiltIn ?? true)
                Button("Delete") { deleteSelected() }
                    .disabled(selectedPreset?.isBuiltIn ?? true)
            }
        }
        .padding(Spacing.xl)
    }

    private var selectedPreset: Preset? {
        selection.flatMap(preset)
    }

    private func preset(_ id: Preset.ID) -> Preset? {
        (Preset.builtIn + model.presets.saved).first { $0.id == id }
    }

    private func row(_ preset: Preset) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: preset.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                Text(preset.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if preset.matches(model.settings) {
                InUseMark()
            }
        }
        .tag(preset.id)
        .accessibilityElement(children: .combine)
    }

    private func use() {
        if let preset = selectedPreset { model.apply(preset) }
    }

    private func deleteSelected() {
        guard let preset = selectedPreset, !preset.isBuiltIn else { return }
        model.presets.delete(preset.id)
        selection = nil
    }

    private func rename(_ preset: Preset?) {
        guard let preset, !preset.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Preset"
        let field = NSTextField(string: preset.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.setAccessibilityLabel("Preset name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn { model.presets.rename(preset.id, to: field.stringValue) }
    }
}

/// The "in use" checkmark on a preset row: the accent (grey in a background window), and the
/// selected-row text colour on a selected row, where the accent would vanish.
private struct InUseMark: View {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: "checkmark")
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.windowAccent(activeState)))
            .accessibilityLabel("In use")
    }
}
