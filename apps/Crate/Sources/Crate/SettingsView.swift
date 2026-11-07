import CrateCore
import SlopKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @State private var savedCount = 0
    @State private var confirmForget = false
    @State private var showingFileTypes = false

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            // Each explanation sits under its own label, as the system's Settings do.
            Picker(selection: $model.settings.openBehavior) {
                Text("Show What's Inside").tag(CrateSettings.OpenBehavior.browse)
                Text("Extract It Right Away").tag(CrateSettings.OpenBehavior.extract)
            } label: {
                Text("When you open an archive")
                Text("Hold Option (⌥) to do the other.")
            }
            Picker("Extract to", selection: destinationChoice) {
                Text("Next to Archive").tag(0)
                Text("Ask Each Time").tag(1)
                if case .folder(let path) = model.settings.destination {
                    Text(FileManager.default.displayName(atPath: path)).tag(2)
                }
                Divider()
                Text("Choose Folder…").tag(3)
            }
            Picker(selection: $model.settings.afterExtracting) {
                Text("Keep Archive").tag(CrateSettings.AfterExtracting.keep)
                Text("Move Archive to Trash").tag(CrateSettings.AfterExtracting.trash)
            } label: {
                Text("After extracting")
                Text("Only after a complete extraction with nothing skipped. Edit ▸ Undo puts it back.")
            }
            Toggle("Show extracted files in Finder", isOn: $model.settings.revealAfterExtracting)
            Picker("When you add files to compress", selection: $model.settings.reviewFilesFirst) {
                Text("Show the List First").tag(true)
                Text("Go Straight to the Format").tag(false)
            }
            LabeledContent {
                Button("Choose…") { showingFileTypes = true }
            } label: {
                Text("File types")
                Text("Which archives open in Crate when you double-click them.")
            }
            .sheet(isPresented: $showingFileTypes) { FileTypesSheet() }
        } advanced: {
            Toggle(isOn: $model.settings.rememberPasswords) {
                Text("Remember passwords in the Keychain")
                Text("Passwords that open an archive are saved in your Keychain and tried first on the next one.")
            }
            LabeledContent("Saved passwords") {
                HStack {
                    Text(savedCount == 0 ? "None" : savedCount == 1 ? "1" : "\(savedCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Forget All…") { confirmForget = true }
                        .disabled(savedCount == 0)
                }
            }
            .confirmationDialog("Forget all saved passwords?", isPresented: $confirmForget) {
                Button("Forget All", role: .destructive) {
                    model.savedPasswords.forgetAll()
                    savedCount = 0
                }
            } message: {
                Text("They're removed from your Keychain. Archives will ask for their passwords again.")
            }
            .onAppear { savedCount = model.savedPasswords.count }
            .onChange(of: model.settings.rememberPasswords) { savedCount = model.savedPasswords.count }
            Toggle(isOn: $model.settings.leaveOutMacFiles) {
                Text("Leave out Mac-only files when compressing")
                Text(".DS_Store, “._” files, __MACOSX and custom folder icons mean nothing on other computers.")
            }
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
