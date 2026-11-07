import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// Settings: General, Picker, Formats, Shortcuts, About. Same pieces as `SlopSettings`
/// (General and About tabs, grouped forms), with two extra tabs the original also has.
struct SettingsView: View {
    let controller: AppController
    @Bindable var model: DropperModel
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: controller.info.name) {
                generalRows
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            SettingsForm { pickerRows }
                .tabItem { Label("Picker", systemImage: "eyedropper") }
            FormatsSettings(model: model)
                .tabItem { Label("Formats", systemImage: "curlybraces") }
            SettingsForm {
                ShortcutRow("Pick color", name: .pickColor)
                ShortcutRow("Pick multiple colors", name: .pickMultiple)
                ShortcutRow("Open contrast checker", name: .contrastChecker)
                ShortcutRow("Show the Dropper panel", name: .showPanel)
                ShortcutRow("Open the Library", name: .showLibrary)
                ShortcutRow("Show or hide the Color Dock", name: .toggleDock)
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }
            AboutSettingsTab(info: controller.info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }

    @ViewBuilder private var generalRows: some View {
        Picker(selection: $model.preferences.options.space) {
            ForEach(OutputSpace.allCases) { space in
                Text(space.title).tag(space)
            }
        } label: {
            Text("Color space")
            Text(spaceHelp)
        }
        Toggle("Uppercase hex", isOn: $model.preferences.options.hexUppercase)
        Toggle("Start hex with #", isOn: $model.preferences.options.hexPrefix)
        Picker(selection: $settings.iconStyle) {
            ForEach(AppSettings.IconStyle.allCases) { Text($0.title).tag($0) }
        } label: {
            Text("Menu bar icon")
            Text(settings.iconStyle == .split
                 ? "Click the eyedropper to pick, the arrow to open the panel. Right-click always opens the panel."
                 : "Clicking the icon opens the panel.")
        }
        Toggle("Show the last color in the menu bar icon", isOn: $settings.tintIcon)
        Toggle(isOn: $settings.showDock) {
            Text("Show the Color Dock")
            Text("A strip on the screen edge with the palettes you add to it (palette ••• › Add to Color Dock). Drag it to any edge.")
        }
        LabeledContent(model.history.latest == nil ? "Example" : "Last color") {
            HStack(spacing: Spacing.s) {
                SwatchView(color: exampleColor, size: 16)
                Text(model.text(for: exampleColor))
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var pickerRows: some View {
        Section {
            Picker(selection: $settings.pickerEngine) {
                ForEach(AppSettings.PickerEngine.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Pick with")
                Text(settings.pickerEngine == .system
                     ? "The macOS magnifier. Needs no permission."
                     : "A loupe with a pixel grid, the value in your format, arrow keys to move one pixel, and adjustable size and zoom. Needs Screen Recording, used only to read the pixels under the loupe.")
            }
            .pickerStyle(.radioGroup)
        }
        if settings.pickerEngine == .precise {
            Section {
                PermissionGate(.screenRecording, reason: "Dropper’s loupe reads the pixels under it from a still image of the screen. Until it’s allowed, Dropper uses the macOS magnifier.") {
                    Label("Screen Recording is allowed.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Size") {
                    Stepper(value: Binding(get: { settings.loupe.sizeStep }, set: { settings.loupe.sizeStep = $0 }),
                            in: 0...(LoupeGeometry.diameters.count - 1)) {
                        Text("\(Int(settings.loupe.diameter)) pt")
                            .monospacedDigit()
                            // One width for both values, so the two steppers line up.
                            .frame(minWidth: Self.stepperValueWidth, alignment: .trailing)
                    }
                }
                LabeledContent("Zoom") {
                    Stepper(value: Binding(get: { settings.loupe.zoomStep }, set: { settings.loupe.zoomStep = $0 }),
                            in: 0...(LoupeGeometry.cellSizes.count - 1)) {
                        Text("\(Int(settings.loupe.cellSize))×")
                            .monospacedDigit()
                            // One width for both values, so the two steppers line up.
                            .frame(minWidth: Self.stepperValueWidth, alignment: .trailing)
                    }
                }
            } header: {
                Text("Loupe")
            } footer: {
                Text("While picking: + and − change the size, ⌥+ and ⌥− the zoom, arrows move one pixel (⇧: ten).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            Toggle("Play a sound when a color is copied", isOn: $settings.playSound)
        }
    }

    /// Fits "256 pt" in the body font.
    private static let stepperValueWidth: CGFloat = 52

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

/// The copy format and which formats appear in menus, with a live example of each.
private struct FormatsSettings: View {
    @Bindable var model: DropperModel

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.preferences.format) {
                    ForEach(ColorFormat.groups) { group in
                        Section(group.title) {
                            ForEach(group.formats) { Text($0.title).tag($0) }
                        }
                    }
                } label: {
                    Text("Copy format")
                    Text("Switch formats off to keep menus short. The copy format always stays on.")
                }
            }
            AppFormatsSection(model: model)
            ForEach(ColorFormat.groups) { group in
                Section(group.title) {
                    ForEach(group.formats) { format in
                        Toggle(isOn: binding(format)) {
                            Text(format.title)
                            Text(ColorFormatter.string(example, as: format, options: model.preferences.options))
                                .font(.caption.monospaced())
                        }
                        .disabled(format == model.preferences.format)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }

    private var example: ColorValue {
        model.history.latest?.color ?? ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    }

    private func binding(_ format: ColorFormat) -> Binding<Bool> {
        Binding(get: { !model.preferences.hiddenFormats.contains(format) },
                set: { on in
                    if on { model.preferences.hiddenFormats.remove(format) } else { model.preferences.hiddenFormats.insert(format) }
                })
    }
}

/// Per-app formats: picking while Xcode is in front copies SwiftUI, and so on.
private struct AppFormatsSection: View {
    @Bindable var model: DropperModel

    var body: some View {
        Section {
            Toggle("Use a different format in some apps", isOn: Binding(get: { model.preferences.usesAppFormats }, set: { on in
                model.preferences.usesAppFormats = on
                if on, model.preferences.appFormats.isEmpty {
                    model.preferences.appFormats = Preferences.suggestedAppFormats.filter { AppNames.isInstalled($0.key) }
                }
            }))
            if model.preferences.usesAppFormats {
                ForEach(model.preferences.appFormats.keys.sorted { AppNames.name($0) < AppNames.name($1) }, id: \.self) { app in
                    HStack {
                        Picker(AppNames.name(app), selection: Binding(get: { model.preferences.appFormats[app] ?? .hex },
                                                                     set: { model.preferences.appFormats[app] = $0 })) {
                            ForEach(ColorFormat.groups) { group in
                                Section(group.title) { ForEach(group.formats) { Text($0.title).tag($0) } }
                            }
                        }
                        Button {
                            model.preferences.appFormats[app] = nil
                        } label: {
                            Label("Remove \(AppNames.name(app))", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add App") {
                    ForEach(AppNames.runningApps.filter { model.preferences.appFormats[$0.id] == nil }, id: \.id) { app in
                        Button(app.name) { model.preferences.appFormats[app.id] = model.preferences.format }
                    }
                }
                .fixedSize()
            }
        } footer: {
            Text("Picks made while one of these apps is in front are copied in its format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
enum AppNames {
    static func name(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Regular apps that are running now (the usual way to find the one you want).
    static var runningApps: [(id: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { app -> (id: String, name: String)? in
                guard let id = app.bundleIdentifier, id != own else { return nil }
                return (id, app.localizedName ?? id)
            }
        var seen = Set<String>()
        return apps.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
