import SlopKit
import SquishCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    let info: AppInfo

    private var suffixIsEmpty: Bool {
        model.settings.suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            // Each explanation sits under its own label, as the system's Settings do.
            LabeledContent {
                TextField("Name suffix", text: $model.settings.suffix, prompt: Text(SquishSettings.defaultSuffix))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .onSubmit(restoreEmptySuffix)
                    .onDisappear(perform: restoreEmptySuffix)
            } label: {
                Text("Name suffix")
                Text(suffixIsEmpty
                     ? "Copies need a name that differs from the original, so an empty suffix goes back to “\(SquishSettings.defaultSuffix)”."
                     : "Copies saved next to originals are named like “photo\(model.settings.effectiveSuffix).jpg”.")
            }
            Toggle(isOn: $model.settings.keepFileDates) {
                Text("Keep file dates")
                Text("Compressed files get the original's created and modified dates.")
            }
        }
    }

    private func restoreEmptySuffix() {
        if suffixIsEmpty { model.settings.suffix = SquishSettings.defaultSuffix }
    }
}
