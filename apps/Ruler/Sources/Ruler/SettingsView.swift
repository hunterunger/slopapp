import RulerCore
import SlopKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: true) {
            Picker("Units", selection: $model.unit) {
                ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
            }
            Text("Points match design tools and code. Pixels are the display's own pixels (two per point on Retina).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Copy format", selection: $model.copyFormat) {
                ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show magnifier while measuring", isOn: $model.showMagnifier)
        } shortcuts: {
            LabeledShortcutRow("Measure", name: .measure)
            Text("While measuring: drag around something to measure it (⌘ keeps the box as drawn), click to measure the space under the pointer, H and V add guides, P pins a distance, hold ⇧ for a crosshair, = and − change edge tolerance, U switches units, Z shows the magnifier, Return copies, ⌫ deletes, ⌘Z undoes, arrow keys move the pointer, Esc closes. Right-click for every action.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// SlopKit's `ShortcutRow`, but the recorder is named after its row for VoiceOver (same as
/// Snapper's; worth folding into SlopKit).
struct LabeledShortcutRow: View {
    let title: String
    let name: KeyboardShortcuts.Name

    init(_ title: String, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    var body: some View {
        LabeledContent(title) {
            NamedRecorder(title: title, name: name)
                .fixedSize()
        }
    }
}

private struct NamedRecorder: NSViewRepresentable {
    let title: String
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.setAccessibilityLabel(title)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {}
}
