import DropperCore
import SlopKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: DropperModel
    let info: AppInfo

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: true) {
            Picker("Copy format", selection: $model.preferences.format) {
                ForEach(ColorFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            Picker("Color space", selection: $model.preferences.options.space) {
                ForEach(OutputSpace.allCases) { space in
                    Text(space.title).tag(space)
                }
            }
            Text(spaceHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Uppercase hex", isOn: $model.preferences.options.hexUppercase)
            Toggle("Start hex with #", isOn: $model.preferences.options.hexPrefix)
            LabeledContent(model.history.latest == nil ? "Example" : "Last color") {
                HStack(spacing: Spacing.s) {
                    SwatchView(color: exampleColor, size: 16, cornerRadius: 4)
                    Text(model.text(for: exampleColor))
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        } shortcuts: {
            ShortcutRow("Pick color", name: .pickColor)
            ShortcutRow("Open contrast checker", name: .contrastChecker)
        }
    }

    private var exampleColor: ColorValue {
        model.history.latest?.color ?? ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    }

    private var spaceHelp: String {
        switch model.preferences.options.space {
        case .sRGB: "Matches CSS, Figma and most web tools. Colors more vivid than sRGB are copied as the closest sRGB value."
        case .displayP3: "For P3 asset catalogs and wide-color designs. Hex and RGB values are Display P3 numbers."
        }
    }
}
