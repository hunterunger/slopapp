import AppKit
import RulerCore
import SlopKit
import SwiftUI

/// Settings in the original's tab order (General, Screenshots, Appearance-ish), built from
/// SlopKit's tab pieces because `SlopSettings` only has General/Shortcuts/Advanced/About.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo
    /// "Custom" picked while the value is still a preset (the field shows, ready for one).
    @State private var choseCustomScale = false

    private static let customScaleTag = -1.0

    private var isCustomScale: Bool { choseCustomScale || !DesignScale.presets.contains(model.designScale) }

    /// The Scale menu: a preset, or "Custom" with the field below it.
    private var scaleChoice: Binding<Double> {
        Binding {
            isCustomScale ? Self.customScaleTag : model.designScale
        } set: { value in
            if value == Self.customScaleTag {
                choseCustomScale = true
            } else {
                choseCustomScale = false
                model.designScale = value
            }
        }
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                generalRows
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            SettingsForm { appearanceRows }
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            SettingsForm { screenshotRows }
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            SettingsForm { shortcutRows }
                .tabItem { Label("Shortcuts", systemImage: "command") }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }

    // MARK: General

    @ViewBuilder
    private var generalRows: some View {
        Picker(selection: $model.unit) {
            ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
        } label: {
            Text("Units")
            Text("Points match design tools and code. Pixels are the display's own pixels (two per point on Retina).")
        }
        Picker(selection: scaleChoice) {
            ForEach(DesignScale.presets, id: \.self) { Text(DesignScale.title($0)).tag($0) }
            Divider()
            Text("Custom").tag(Self.customScaleTag)
        } label: {
            Text("Scale")
            Text("Divides every number: @2x for a mockup exported at 2× and viewed at 100%, or 50% Zoom when a design tool is zoomed out.")
        }
        if isCustomScale {
            CustomScaleField(scale: $model.designScale)
        }
        Picker("Edge tolerance", selection: $model.tolerance) {
            ForEach(Tolerance.allCases) { Text($0.title).tag($0) }
        }
        Picker("Copy format", selection: $model.copyFormat) {
            ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
        }
    }

    // MARK: Appearance

    @ViewBuilder
    private var appearanceRows: some View {
        Section {
            Picker("Line color", selection: $model.lineColor) {
                ForEach(LineColor.allCases) { color in
                    Label {
                        Text(color.title)
                    } icon: {
                        Image(nsImage: Self.swatch(color.color))
                    }
                    .tag(color)
                }
            }
            Toggle("Show units in labels", isOn: $model.showUnits)
            Toggle("Show key hints while measuring", isOn: $model.showHints)
            Toggle("Show magnifier while measuring", isOn: $model.showMagnifier)
        }
        Section("Aspect Ratio") {
            Toggle("Show on areas", isOn: $model.ratioOnAreas)
            Toggle("Show on distances", isOn: $model.ratioOnDistances)
            Picker("Format", selection: $model.ratioStyle) {
                ForEach(AspectRatioStyle.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!model.ratioOnAreas && !model.ratioOnDistances)
        }
    }

    /// A small filled circle for the color menu (menus drop SwiftUI shape colors).
    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: CGSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.accessibilityDescription = nil
        return image
    }

    // MARK: Screenshots

    @ViewBuilder
    private var screenshotRows: some View {
        Section {
            LabeledContent("Save to") {
                HStack(spacing: Spacing.s) {
                    Label {
                        Text(FileManager.default.displayName(atPath: model.screenshotFolder.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.screenshotFolder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    .help(model.screenshotFolder.path)
                    Button("Choose…") { chooseFolder() }
                }
            }
            Picker("Format", selection: $model.screenshotFormat) {
                ForEach(ScreenshotFormat.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Padding") {
                HStack {
                    // Snaps to 4 pt without `step:`, which draws 25 tick dots under the track.
                    Slider(value: Binding { model.screenshotPadding } set: { model.screenshotPadding = ($0 / 4).rounded() * 4 },
                           in: 0...96)
                        .accessibilityLabel("Padding")
                        .accessibilityValue("\(Int(model.screenshotPadding)) points")
                    Text("\(Int(model.screenshotPadding)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.primary) // the only readout of the value
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("Save Retina screenshots at 1×", isOn: $model.screenshotAt1x)
        } footer: {
            Text("While measuring, S saves and C copies a screenshot of the area under the pointer (or of everything measured) with the measurements drawn in. Hold ⌥ to switch the padding off or on for one shot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = model.screenshotFolder
        if panel.runModal() == .OK, let url = panel.url { model.screenshotFolderPath = url.path }
    }

    // MARK: Shortcuts

    @ViewBuilder
    private var shortcutRows: some View {
        LabeledShortcutRow("Measure", name: .measure,
                           subtitle: "Press it again to keep your measurements on screen while you work (or to close, if there are none), and once more to pick them back up.")
        Section("While Measuring") {
            // A compact cheat sheet, not a row per key: sixteen form rows made the window
            // taller than a small display, and forms here don't scroll.
            // Every row the same height, keycaps or not, so the list keeps one rhythm.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Self.keys) { row in
                    HStack(spacing: Spacing.m) {
                        Text(row.action)
                        Spacer(minLength: Spacing.s)
                        KeyList(tokens: row.keys)
                    }
                    .frame(height: KeyCap.height + 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    struct KeyRow: Identifiable {
        let action: String
        let keys: [KeyToken]
        var id: String { action }
    }

    static let keys: [KeyRow] = [
        KeyRow(action: "Measure an element (snaps to it)", keys: [.word("drag")]),
        KeyRow(action: "Box without snapping", keys: [.key("⌘"), .word("drag, or right-drag")]),
        KeyRow(action: "Measure the space under the pointer", keys: [.word("click")]),
        KeyRow(action: "Resize a box (⇧ keeps its shape)", keys: [.word("drag a side or corner")]),
        KeyRow(action: "Add a horizontal / vertical guide", keys: [.key("H"), .key("V")]),
        KeyRow(action: "Hold the distance / width / height", keys: [.key("P"), .key("X"), .key("Y")]),
        KeyRow(action: "Crosshair", keys: [.word("hold"), .key("⇧")]),
        KeyRow(action: "Save / copy a screenshot (⌥: padding)", keys: [.key("S"), .key("C")]),
        KeyRow(action: "Save a screenshot of the area you drag", keys: [.key("⌘S")]),
        KeyRow(action: "Copy dimensions", keys: [.key("Return"), .key("⌘C")]),
        KeyRow(action: "Edge tolerance", keys: [.key("="), .key("−"), .key("T")]),
        KeyRow(action: "Units, magnifier, key hints", keys: [.key("U"), .key("Z"), .key("?")]),
        KeyRow(action: "Delete, clear all, undo", keys: [.key("⌫"), .key("⌘⌫"), .key("⌘Z")]),
        KeyRow(action: "Move the pointer 1 (⇧: 10)", keys: [.word("arrow keys")]),
        KeyRow(action: "Keep on screen and step back", keys: [.key("B")]),
        KeyRow(action: "Done", keys: [.key("Esc")]),
    ]
}

/// One part of a key list: a key (drawn as a keycap) or a gesture word.
enum KeyToken: Hashable {
    case key(String)
    case word(String)
}

/// Keys as small keycaps, gestures as plain words, in a row.
struct KeyList: View {
    let tokens: [KeyToken]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .key(let key): KeyCap(key)
                case .word(let word): Text(word)
                }
            }
        }
        .fixedSize()
    }
}

/// A key name in a small rounded cap, like the keyboard's own.
struct KeyCap: View {
    static let height: CGFloat = 18
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.callout)
            .padding(.horizontal, Spacing.xs)
            .frame(minWidth: Self.height + 2, minHeight: Self.height)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .accessibilityLabel(Self.spoken[key] ?? key)
    }

    private static let spoken: [String: String] = [
        "⌘": "Command", "⇧": "Shift", "⌫": "Delete", "⌘⌫": "Command Delete", "⌘Z": "Command Z",
        "⌘S": "Command S", "⌘C": "Command C", "−": "Minus", "=": "Equals", "?": "Question mark",
    ]
}

/// A text field for a scale outside the presets ("1.5" divides by 1.5).
private struct CustomScaleField: View {
    @Binding var scale: Double
    @State private var text = ""

    var body: some View {
        LabeledContent("Divide by") {
            // Bordered: a bare number in a form row doesn't read as something to edit.
            TextField("Divide by", text: $text, prompt: Text("1.5"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .onSubmit(apply)
                .onAppear { text = format(scale) }
                .onChange(of: scale) { _, new in text = format(new) }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func apply() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else {
            text = format(scale)
            return
        }
        scale = DesignScale.clamped(value)
    }
}

/// SlopKit's `ShortcutRow`, but the recorder is named after its row for VoiceOver (same as
/// Snapper's; worth folding into SlopKit).
struct LabeledShortcutRow: View {
    let title: String
    let name: KeyboardShortcuts.Name
    var subtitle: String?

    init(_ title: String, name: KeyboardShortcuts.Name, subtitle: String? = nil) {
        self.title = title
        self.name = name
        self.subtitle = subtitle
    }

    var body: some View {
        LabeledContent {
            NamedRecorder(title: title, name: name)
                .fixedSize()
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
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
