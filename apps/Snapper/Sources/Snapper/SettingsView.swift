import AppKit
import SlopKit
import SnapperCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: true) {
            Toggle("Show thumbnail after capture", isOn: afterCapture(.showCard))
            Toggle("Copy to clipboard after capture", isOn: afterCapture(.copy))
            Toggle("Save to folder after capture", isOn: afterCapture(.save))
            Picker("Thumbnail position", selection: $model.cardCorner) {
                ForEach(CardCorner.allCases) { Text($0.title).tag($0) }
            }
            Picker("Close thumbnails", selection: $model.autoClose) {
                ForEach(AutoClose.allCases) { Text($0.title).tag($0) }
            }
            if model.autoClose != .never {
                Picker("When closing by itself", selection: $model.autoCloseAction) {
                    ForEach(AutoCloseAction.allCases) { Text($0.title).tag($0) }
                }
            }
            Toggle("Close thumbnail after copying or saving", isOn: $model.closeAfterCopyOrSave)
            Toggle("Close thumbnail after dragging it out", isOn: $model.closeAfterDragging)
        } shortcuts: {
            LabeledShortcutRow("Capture area", name: .captureArea)
            LabeledShortcutRow("Capture window", name: .captureWindow)
            LabeledShortcutRow("Capture full screen", name: .captureFullScreen)
            LabeledShortcutRow("Capture previous area", name: .capturePreviousArea)
            Text("While selecting: Space switches between area and window, Shift makes a square, Option grows from the center, arrow keys move the pointer, Esc cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } advanced: {
            LabeledContent("Save folder") {
                HStack(spacing: Spacing.s) {
                    Text(model.saveFolder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(model.saveFolder.path(percentEncoded: false))
                    Button("Choose…") { chooseFolder() }
                        .disabled(model.saveFolderIsOverridden)
                }
            }
            if model.saveFolderIsOverridden {
                Text("Set by SNAPPER_SAVE_DIR for testing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.chosenFolder != nil {
                Button("Use Default Folder") { model.chosenFolder = nil }
            }
            Picker("File format", selection: $model.format) {
                ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Include window shadow", isOn: $model.includeWindowShadow)
            Toggle("Hide desktop icons in captures", isOn: $model.hideDesktopIcons)
            Toggle("Show magnifier while selecting", isOn: $model.showMagnifier)
            Toggle("Play sound", isOn: $model.playSound)
        }
    }

    private func afterCapture(_ option: AfterCapture) -> Binding<Bool> {
        Binding(
            get: { model.afterCapture.contains(option) },
            set: { on in
                if on { model.afterCapture.insert(option) } else { model.afterCapture.remove(option) }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.chosenFolder = url.path(percentEncoded: false)
        }
    }
}

/// SlopKit's `ShortcutRow`, but the recorder is named after its row for VoiceOver ("Capture
/// area" rather than an unnamed search field). Worth folding into SlopKit's row. The
/// recorder's ✕ is drawn by KeyboardShortcuts and isn't an accessibility element.
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
