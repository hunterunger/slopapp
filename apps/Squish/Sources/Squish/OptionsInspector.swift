import AppKit
import SlopKit
import SquishCore
import SwiftUI

/// The right-hand column: the preset, then every option in sections, and the batch total
/// with "Apply to All" at the bottom.
struct OptionsInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ImageQualitySection(model: model)
                ResizeSection(model: model)
                FormatSection(model: model)
                PDFSection(model: model)
                MetadataSection(model: model)
                SaveToSection(model: model)
            }
            .formStyle(.grouped)
            Hairline()
            ApplyFooter(model: model)
        }
        .toolbar {
            // Above the options, like a profile picker: the first thing to choose.
            ToolbarItem(placement: .automatic) {
                PresetPicker(model: model)
            }
        }
        .sheet(item: $model.presetSheet) { sheet in
            PresetNameSheet(model: model, sheet: sheet)
        }
    }
}

// MARK: Preset

struct PresetPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            PresetMenuItems(model: model)
        } label: {
            Label {
                // AppKit names the menu after its title, so the title carries the name too.
                Text(model.presetTitle).accessibilityLabel("Preset: \(model.presetTitle)")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .fixedSize()
        .help(model.currentPreset?.detail ?? "Your own settings")
        .accessibilityLabel("Preset")
        .accessibilityValue(model.presetTitle)
    }
}

/// The presets with checkmarks, then managing them. Shared by the picker and the
/// Compression menu (`withShortcuts` adds ⌘1–⌘9).
struct PresetMenuItems: View {
    @Bindable var model: AppModel
    var withShortcuts = false

    var body: some View {
        let all = model.presets.all
        ForEach(Array(all.enumerated()), id: \.element.id) { index, preset in
            let toggle = Toggle(isOn: Binding(get: { model.settings.presetID == preset.id && !model.presetIsEdited },
                                              set: { _ in model.apply(preset) })) {
                Text(preset.name)
                if !withShortcuts { Text(preset.detail) }
            }
            if withShortcuts, index < 9 {
                toggle.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            } else {
                toggle
            }
            if index == CompressionPreset.builtIns.count - 1, all.count > CompressionPreset.builtIns.count {
                Divider()
            }
        }
        Divider()
        Button("Save as New Preset…") { model.presetSheet = .saveNew }
        if let preset = model.currentPreset {
            if model.presetIsEdited {
                Button("Revert to “\(preset.name)”") { model.apply(preset) }
            }
            if !preset.isBuiltIn {
                Button("Update “\(preset.name)”") { model.updateCurrentPreset() }
                    .disabled(!model.presetIsEdited)
                Button("Rename “\(preset.name)”…") { model.presetSheet = .rename(preset) }
                Button("Delete “\(preset.name)”…") { model.deletePreset(id: preset.id) }
            }
        }
    }
}

struct PresetNameSheet: View {
    @Bindable var model: AppModel
    let sheet: PresetSheet
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        if case .rename = sheet { return "Rename Preset" }
        return "Save Preset"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(.headline)
            TextField("Name", text: $name, prompt: Text("Web Photos"))
                .onSubmit(save)
                .accessibilityLabel("Preset name")
            if case .saveNew = sheet {
                Text("Saves the quality, size, format, PDF and metadata options. Where files are saved isn't part of a preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(title == "Rename Preset" ? "Rename" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.windowMargin)
        .frame(width: 320)
        .onAppear {
            if case .rename(let preset) = sheet { name = preset.name }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch sheet {
        case .saveNew: model.saveNewPreset(named: name)
        case .rename(let preset): model.renamePreset(id: preset.id, to: name)
        }
        dismiss()
    }
}

// MARK: Sections

struct ImageQualitySection: View {
    @Bindable var model: AppModel

    private var percent: Binding<Int> {
        Binding(get: { Int((model.settings.quality * 100).rounded()) },
                set: { model.settings.quality = Double(min(100, max(10, $0))) / 100 })
    }

    var body: some View {
        Section("Images") {
            PercentSlider(title: "Quality", value: $model.settings.quality, percent: percent)
            Picker("PNG", selection: $model.settings.pngColors) {
                Text("Lossless").tag(Int?.none)
                ForEach([256, 128, 64], id: \.self) { Text("\($0) Colors").tag(Int?.some($0)) }
            }
            .help("Fewer colors make much smaller PNGs. Screenshots look the same at 256.")
        }
    }
}

/// "Quality  [——●——]  70 %" with a typeable number.
struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let percent: Binding<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.xs) {
                Slider(value: Binding(get: { value }, set: { value = ($0 * 100).rounded() / 100 }), in: 0.1...1)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue("\(percent.wrappedValue) percent")
                TextField(title + " percent", value: percent, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 36)
                Text("%").foregroundStyle(.secondary)
            }
        }
    }
}

struct ResizeSection: View {
    @Bindable var model: AppModel

    private var kind: Binding<ResizeMode.Kind> {
        Binding(get: { model.settings.resize.kind },
                set: { model.settings.resize = model.settings.resize.switching(to: $0) })
    }

    private func pixels(_ get: @escaping (ResizeMode) -> Int, _ make: @escaping (Int) -> ResizeMode) -> Binding<Int> {
        Binding(get: { get(model.settings.resize) },
                set: { model.settings.resize = make(min(ResizeMode.validPixels.upperBound, max(ResizeMode.validPixels.lowerBound, $0))) })
    }

    var body: some View {
        Section {
            Picker("Resize", selection: kind) {
                ForEach(ResizeMode.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                    if kind == .none { Divider() }
                }
            }
            switch model.settings.resize {
            case .none:
                EmptyView()
            case .longestEdge(let px):
                PixelField(title: "Longest edge", value: pixels({ _ in px }, ResizeMode.longestEdge))
            case .width(let px):
                PixelField(title: "Width", value: pixels({ _ in px }, ResizeMode.width))
            case .height(let px):
                PixelField(title: "Height", value: pixels({ _ in px }, ResizeMode.height))
            case .fit(let w, let h):
                PixelField(title: "Width", value: pixels({ _ in w }, { .fit(width: $0, height: h) }))
                PixelField(title: "Height", value: pixels({ _ in h }, { .fit(width: w, height: $0) }))
            case .percent(let p):
                PixelField(title: "Scale", unit: "%", common: PixelField.commonPercents,
                           value: Binding(get: { p }, set: {
                               model.settings.resize = .percent(min(ResizeMode.validPercent.upperBound, max(ResizeMode.validPercent.lowerBound, $0)))
                           }))
            }
        } header: {
            Text("Size")
        } footer: {
            if model.settings.resize != .none {
                FormNote("Smaller images keep their size. PDFs use the dpi setting below.")
            }
        }
    }
}

/// A pixel count (or a percentage) with a menu of common values. Every resize row uses it,
/// so the fields, units and menus line up from row to row.
struct PixelField: View {
    let title: String
    var unit = "px"
    var common = PixelField.commonPixels
    @Binding var value: Int
    static let commonPixels = [3840, 2560, 1920, 1600, 1280, 1024, 800, 640]
    static let commonPercents = [75, 50, 33, 25]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.xs) {
                TextField("\(title) in \(unit == "%" ? "percent" : "pixels")", value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 64)
                // Fixed slot, so "px" and "%" rows end at the same place.
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                Menu {
                    ForEach(common, id: \.self) { amount in
                        Button("\(String(amount)) \(unit)") { value = amount }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                // Centres the chevron under the pop-up buttons' indicators above (measured).
                .padding(.trailing, Spacing.xs)
                .help(unit == "%" ? "Common scales" : "Common sizes")
                .accessibilityLabel(unit == "%" ? "Common scales" : "Common \(title.lowercased()) sizes")
            }
        }
    }
}

struct FormatSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Format") {
            Picker("Save as", selection: $model.settings.format) {
                ForEach(model.capabilities.formatChoices) { format in
                    Text(format.title).tag(format)
                    if format == .original { Divider() }
                }
            }
            if model.settings.format == .original || model.settings.format == .jpeg {
                Toggle("Progressive JPEG", isOn: $model.settings.progressiveJPEG)
                    .help("Loads blurry-first on slow connections. Sometimes slightly smaller.")
            }
        }
    }
}

struct PDFSection: View {
    @Bindable var model: AppModel
    static let resolutions = [72, 96, 120, 144, 150, 200, 220, 300, 600]

    private var percent: Binding<Int> {
        Binding(get: { Int((model.settings.pdfQuality * 100).rounded()) },
                set: { model.settings.pdfQuality = Double(min(100, max(10, $0))) / 100 })
    }

    var body: some View {
        Section("PDFs") {
            PercentSlider(title: "Image quality", value: $model.settings.pdfQuality, percent: percent)
            Picker("Image resolution", selection: $model.settings.pdfResolution) {
                ForEach(resolutions, id: \.self) { Text("\(String($0)) dpi").tag($0) }
            }
            .help("Images in PDFs are scaled down to this. 144 dpi looks sharp on screen; 300 dpi is for print.")
            if PDFCompressor.canGrayscale {
                Toggle("Grayscale", isOn: $model.settings.pdfGrayscale)
                    .help("Turns pages gray, for printing or forms. Files get only a little smaller.")
            }
        }
    }

    /// The common stops, plus the current value if it's something else.
    private var resolutions: [Int] {
        let current = model.settings.pdfResolution
        return Self.resolutions.contains(current) ? Self.resolutions : (Self.resolutions + [current]).sorted()
    }
}

struct MetadataSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Picker("Camera and location", selection: $model.settings.metadata) {
                ForEach(MetadataPolicy.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Metadata")
        } footer: {
            FormNote(caption)
        }
    }

    private var caption: String {
        switch model.settings.metadata {
        case .removeAll: "Removes location, camera, dates and author. Orientation and color profile are kept."
        case .removeLocation: "Removes GPS and place names. Camera details and dates stay."
        case .keepAll: "Everything stays, including where photos were taken."
        }
    }
}

struct SaveToSection: View {
    @Bindable var model: AppModel

    /// Picker tags: "alongside", "subfolder", "folder:<path>", "choose", "replace".
    private var choice: Binding<String> {
        Binding(get: {
            switch model.settings.destination {
            case .alongside: "alongside"
            case .subfolder: "subfolder"
            case .folder(let url): "folder:" + url.path
            case .replaceOriginal: "replace"
            }
        }, set: { tag in
            switch tag {
            case "alongside": model.settings.destination = .alongside
            case "subfolder": model.useSubfolder()
            case "choose": model.chooseFolder()
            case "replace": model.requestReplaceOriginals()
            default:
                if tag.hasPrefix("folder:") { model.useFolder(URL(fileURLWithPath: String(tag.dropFirst(7)))) }
            }
        })
    }

    private var subfolder: Binding<String> {
        Binding(get: {
            if case .subfolder(let name) = model.settings.destination { return name }
            return model.subfolderName
        }, set: { model.settings.destination = .subfolder($0) })
    }

    var body: some View {
        Section {
            Picker("Location", selection: choice) {
                Text("Next to Originals").tag("alongside")
                Text("Subfolder of Originals").tag("subfolder")
                Divider()
                ForEach(model.recentFolders, id: \.self) { folder in
                    Text(folder.lastPathComponent).tag("folder:" + folder.path)
                }
                Text("Choose Folder…").tag("choose")
                Divider()
                Text("Replace Originals").tag("replace")
            }
            switch model.settings.destination {
            case .alongside:
                TextField("Name ends with", text: $model.settings.suffix, prompt: Text(SquishSettings.defaultSuffix))
                    .onSubmit { if model.settings.suffix.trimmingCharacters(in: .whitespaces).isEmpty { model.settings.suffix = SquishSettings.defaultSuffix } }
            case .subfolder:
                TextField("Folder name", text: subfolder, prompt: Text(SquishSettings.defaultSubfolder))
            case .folder, .replaceOriginal:
                EmptyView()
            }
            Toggle("Keep file dates", isOn: $model.settings.keepFileDates)
                .help("Give compressed files the original's created and modified dates.")
        } header: {
            Text("Save To")
        } footer: {
            FormNote(note)
        }
    }

    private var note: String {
        switch model.settings.destination {
        case .alongside:
            "Saved as “photo\(model.settings.effectiveSuffix).jpg” next to each original."
        case .subfolder:
            "Saved into “\(Destination.cleanSubfolderName(subfolder.wrappedValue))” inside each original's folder, with the same name."
        case .folder(let url):
            "Saved into \((url.path as NSString).abbreviatingWithTildeInPath), with the same names."
        case .replaceOriginal:
            "Compressed files take the originals' place. Originals go to the Trash; Edit ▸ Undo puts them back."
        }
    }
}

/// A section's footnote in the grouped options form: secondary caption text under the
/// section, lined up with the rows' labels.
struct FormNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The batch total and "Apply to All", where the originals keep their Export button.
/// Its edges line up with the sections above: the button with the section cards, the
/// total with the rows' labels.
struct ApplyFooter: View {
    @Bindable var model: AppModel

    var body: some View {
        let outdated = model.queue.isBusy ? 0 : model.outdatedItems.count
        VStack(spacing: Spacing.s) {
            Text(model.footerText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, InspectorMetrics.formInset)
            applyButton(outdated: outdated)
                .controlSize(.large)
                .disabled(outdated == 0)
                .help(outdated > 0 ? "Compress the files made with older settings again, with these"
                                    : "Files in the list already use these settings. New files use them as you add them.")
        }
        .padding(.horizontal, InspectorMetrics.formInset)
        .padding(.vertical, Spacing.m)
    }

    /// Prominent only when there's something to apply: a disabled prominent button still
    /// reads as the accent colour in dark mode.
    @ViewBuilder private func applyButton(outdated: Int) -> some View {
        let button = Button {
            model.redoOutdated()
        } label: {
            Label(outdated > 0 ? "Apply to \(outdated) \(outdated == 1 ? "File" : "Files")" : "Apply to All",
                  systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        if outdated > 0 {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

enum InspectorMetrics {
    /// How far a grouped `Form` insets its section cards from the column's sides, and its
    /// rows' content from the cards' (measured on macOS 26: 10 pt each).
    static let formInset: CGFloat = 10
}
