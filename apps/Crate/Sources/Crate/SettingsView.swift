import CrateCore
import SlopKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            Picker("When you open an archive", selection: $model.settings.openBehavior) {
                Text("Show What's Inside").tag(CrateSettings.OpenBehavior.browse)
                Text("Extract It Right Away").tag(CrateSettings.OpenBehavior.extract)
            }
            Text("Hold Option (⌥) while dropping or opening to do the other.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Extract to", selection: destinationChoice) {
                Text("Next to Archive").tag(0)
                Text("Ask Each Time").tag(1)
                if case .folder(let path) = model.settings.destination {
                    Text(FileManager.default.displayName(atPath: path)).tag(2)
                }
                Divider()
                Text("Choose Folder…").tag(3)
            }
            Picker("After extracting", selection: $model.settings.afterExtracting) {
                Text("Keep Archive").tag(CrateSettings.AfterExtracting.keep)
                Text("Move Archive to Trash").tag(CrateSettings.AfterExtracting.trash)
            }
            Text("Archives only go to the Trash after a complete extraction with nothing skipped. Edit ▸ Undo puts them back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show extracted files in Finder", isOn: $model.settings.revealAfterExtracting)
        } advanced: {
            Toggle("Leave out Mac-only files when compressing", isOn: $model.settings.leaveOutMacFiles)
            Text(".DS_Store, “._” files, __MACOSX and custom folder icons mean nothing on other computers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationChoice: Binding<Int> {
        Binding(
            get: {
                switch model.settings.destination {
                case .nextToArchive: 0
                case .ask: 1
                case .folder: 2
                }
            },
            set: { value in
                switch value {
                case 0: model.settings.destination = .nextToArchive
                case 1: model.settings.destination = .ask
                case 3:
                    model.chooseFolder(message: "Choose where extracted files go.", prompt: "Choose", near: nil) { url in
                        model.settings.destination = .folder(url.path)
                    }
                default: break
                }
            }
        )
    }
}
