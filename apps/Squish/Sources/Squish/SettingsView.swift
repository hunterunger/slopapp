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
            TextField("Name suffix", text: $model.settings.suffix, prompt: Text(SquishSettings.defaultSuffix))
                .onSubmit(restoreEmptySuffix)
                .onDisappear(perform: restoreEmptySuffix)
            Text(suffixIsEmpty
                 ? "Copies need a name that differs from the original, so an empty suffix goes back to “\(SquishSettings.defaultSuffix)”."
                 : "Copies saved next to originals are named like “photo\(model.settings.effectiveSuffix).jpg”.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Remove metadata", isOn: $model.settings.stripMetadata)
            Text("Removes location, camera and editing details. Orientation and color profile are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restoreEmptySuffix() {
        if suffixIsEmpty { model.settings.suffix = SquishSettings.defaultSuffix }
    }
}
