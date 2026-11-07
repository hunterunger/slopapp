import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// Edits one saved color: name, the color itself (saturation/brightness square, hue slider,
/// hex and channel fields, or a new pick), notes, and shows it in every format.
/// Changes are saved when a drag ends or a field is submitted.
struct ColorEditorView: View {
    let controller: AppController
    let item: PickedColor
    let list: ColorListID

    enum Channels: String, CaseIterable, Identifiable {
        case rgb = "RGB", hsb = "HSB", hsl = "HSL"
        var id: String { rawValue }
    }

    @State private var name = ""
    @State private var note = ""
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 0.0
    @State private var hexField = ""
    @State private var channels: Channels = .rgb
    @State private var refused: String?
    @AppStorage("editorChannels") private var storedChannels = Channels.rgb.rawValue

    private var model: DropperModel { controller.model }
    private var space: OutputSpace { model.preferences.options.space }
    private var locked: Bool { model.isLocked(list) }

    /// The color the controls describe right now (may differ from the saved one mid-drag).
    private var draft: ColorValue {
        ColorValue(RGB.fromHSB(hue: hue, saturation: saturation, brightness: brightness), in: space)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                TextField("Name", text: $name, prompt: Text(ColorNamer.name(for: draft)))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onSubmit(saveName)
                    .accessibilityLabel("Color name")

                SaturationBrightnessSquare(hue: hue, saturation: $saturation, brightness: $brightness, onEnd: commit)
                    .frame(height: 190)

                HStack(spacing: Spacing.m) {
                    Button {
                        pickReplacement()
                    } label: {
                        Label("Pick a New Color from the Screen", systemImage: "eyedropper")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("Replace this color with one picked from the screen")
                    GradientSlider(label: "Hue", value: $hue, colors: hueStops,
                                   knob: Color(hue: hue, saturation: 1, brightness: 1),
                                   onEditingChanged: { if !$0 { commit() } },
                                   valueDescription: { "\(Int(($0 * 360).rounded())) degrees" })
                    RoundSwatch(color: draft, vision: controller.settings.colorVision, size: 40)
                }

                fields

                TextField("Notes", text: $note, prompt: Text("Notes"), axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit(saveNote)
                    .accessibilityLabel("Notes")

                if let refused {
                    Label(refused, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                valuesSection
                infoSection
                actions
            }
            .padding(Spacing.windowMargin)
            .disabled(locked)
        }
        .overlay(alignment: .top) {
            if locked {
                Label("This palette is locked. Unlock it to edit.", systemImage: "lock.fill")
                    .font(.callout)
                    .padding(Spacing.s)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, Spacing.s)
            }
        }
        .navigationTitle(item.displayName)
        .onAppear(perform: load)
        .onDisappear {
            saveName()
            saveNote()
        }
        .onChange(of: model.preferences.options) { _, _ in load() }
        .onChange(of: channels) { _, new in storedChannels = new.rawValue }
    }

    // MARK: Fields

    /// Two rows in a grid so the hex field and the channel fields share one line, whatever
    /// the heights of the caption and the channel menu above them.
    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
            GridRow(alignment: .center) {
                Text("Hex").font(.caption).foregroundStyle(.secondary)
                Picker("Channels", selection: $channels) {
                    ForEach(Channels.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
            }
            GridRow(alignment: .center) {
                TextField("Hex", text: $hexField)
                    .font(.body.monospaced())
                    .frame(width: 96)
                    .onSubmit(applyHex)
                    .accessibilityLabel("Hex value")
                HStack(spacing: Spacing.s) {
                    ForEach(0..<3, id: \.self) { index in
                        ChannelField(label: channelLabels[index], value: channelValue(index), range: channelRange(index)) {
                            setChannel(index, to: $0)
                        }
                    }
                }
            }
        }
    }

    private var channelLabels: [String] {
        switch channels {
        case .rgb: ["R", "G", "B"]
        case .hsb: ["H", "S", "B"]
        case .hsl: ["H", "S", "L"]
        }
    }

    private func channelRange(_ index: Int) -> ClosedRange<Int> {
        switch channels {
        case .rgb: 0...255
        case .hsb, .hsl: index == 0 ? 0...359 : 0...100
        }
    }

    private func channelValue(_ index: Int) -> Int {
        let c = draft.components(in: space).quantized
        switch channels {
        case .rgb:
            let b = c.bytes
            return [b.red, b.green, b.blue][index]
        case .hsb:
            return [Int((hue * 360).rounded()) % 360, Int((saturation * 100).rounded()), Int((brightness * 100).rounded())][index]
        case .hsl:
            let h = c.hsl
            return [Int((hue * 360).rounded()) % 360, h.saturation, h.lightness][index]
        }
    }

    private func setChannel(_ index: Int, to value: Int) {
        switch channels {
        case .rgb:
            var b = draft.components(in: space).quantized.bytes
            switch index {
            case 0: b.red = value
            case 1: b.green = value
            default: b.blue = value
            }
            setControls(from: ColorValue(RGB(red: Double(b.red) / 255, green: Double(b.green) / 255, blue: Double(b.blue) / 255), in: space))
        case .hsb:
            switch index {
            case 0: hue = Double(value) / 360
            case 1: saturation = Double(value) / 100
            default: brightness = Double(value) / 100
            }
        case .hsl:
            let current = draft.components(in: space).hslUnits
            var h = hue * 360, s = current.saturation, l = current.lightness
            switch index {
            case 0: h = Double(value)
            case 1: s = Double(value) / 100
            default: l = Double(value) / 100
            }
            let rgb = ColorParser.hslToRGB(h: h.truncatingRemainder(dividingBy: 360), s: s, l: l)
            setControls(from: ColorValue(rgb, in: space), keepHue: h / 360)
        }
        commit()
    }

    // MARK: Values and info

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Values").font(.headline)
            // A grid, so the names' column is as wide as the longest name
            // ("Unit RGBA (OpenGL)") and no name wraps.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
            ForEach(model.preferences.visibleFormats) { format in
                let value = model.text(for: draft, as: format, name: item.name)
                GridRow {
                    Text(format.title)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Text(value)
                        .font(.callout.monospaced())
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        controller.copy(item, as: format)
                    } label: {
                        Label("Copy \(format.title)", systemImage: "doc.on.doc")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy \(value)")
                }
                .font(.callout)
            }
            }
            if draft.isOutside(space) {
                Text("Outside \(space.title): values are the closest \(space.title) color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Information").font(.headline)
            LabeledContent("Added", value: item.date.formatted(date: .abbreviated, time: .shortened))
            if let modified = item.modified {
                LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
            }
            let palettes = model.palettes.filter { $0.contains(item.color) }.map(\.name)
            LabeledContent("In palettes", value: palettes.isEmpty ? "None" : palettes.joined(separator: ", "))
        }
        .font(.callout)
    }

    private var actions: some View {
        HStack {
            Menu("Check Contrast") {
                Button("As Text Color") { controller.checkContrast(draft, as: .text) }
                Button("As Background Color") { controller.checkContrast(draft, as: .background) }
            }
            .fixedSize()
            Menu("Add to Palette") {
                ForEach(model.palettes.filter { list != .palette($0.id) }) { palette in
                    Button(palette.name) { model.add([item], to: palette.id) }
                        .disabled(palette.isLocked || palette.contains(item.color))
                }
                if !model.palettes.isEmpty { Divider() }
                Button("New Palette with This Color") { controller.newPalette(colors: [item]) }
            }
            .fixedSize()
            Spacer()
            Button(role: .destructive) {
                model.remove([item.id], from: list)
                controller.library.colors = []
            } label: {
                Label(list == .history ? "Remove from History" : "Remove from Palette", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help(list == .history ? "Remove from history" : "Remove from palette")
        }
    }

    // MARK: State

    private func load() {
        name = item.name ?? ""
        note = item.note ?? ""
        channels = Channels(rawValue: storedChannels) ?? .rgb
        setControls(from: item.color)
    }

    private func setControls(from color: ColorValue, keepHue: Double? = nil) {
        let units = color.components(in: space).hsbUnits
        if let keepHue { hue = keepHue } else if units.saturation > 0, units.brightness > 0 { hue = units.hue }
        saturation = units.saturation
        brightness = units.brightness
        hexField = ColorFormatter.string(color, as: .hex, options: model.preferences.options)
    }

    private func applyHex() {
        guard let color = ColorParser.color(hexField, in: space) else {
            refused = "Type a color like #3366CC, rgb(51, 102, 204) or hsl(220, 60%, 50%)."
            return
        }
        setControls(from: color)
        commit()
    }

    /// Saves the color the controls describe.
    private func commit() {
        let color = ColorValue(draft.components(in: space).quantized, in: space)
        guard color.identityKey != item.color.identityKey else {
            refused = nil
            hexField = ColorFormatter.string(draft, as: .hex, options: model.preferences.options)
            return
        }
        var edited = item
        edited.color = color
        if model.update(edited, in: list) {
            refused = nil
            hexField = ColorFormatter.string(color, as: .hex, options: model.preferences.options)
        } else {
            refused = locked ? "This palette is locked." : "That color is already in this palette."
            setControls(from: item.color)
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != (item.name ?? "") else { return }
        var edited = item
        edited.name = trimmed.isEmpty ? nil : trimmed
        model.update(edited, in: list)
    }

    private func saveNote() {
        guard note != (item.note ?? "") else { return }
        var edited = item
        edited.note = note.isEmpty ? nil : note
        model.update(edited, in: list)
    }

    private func pickReplacement() {
        Task {
            guard let color = await model.sampler.sample(prompt: "Pick the new color") else { return }
            setControls(from: color)
            commit()
        }
    }
}

/// One numeric channel ("R 51"). Commits on Return or when focus leaves.
private struct ChannelField: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(label, text: $text)
                .font(.body.monospacedDigit())
                .frame(width: 44)
                .focused($focused)
                .onSubmit(commit)
                .accessibilityLabel(channelName)
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, new in if !focused { text = "\(new)" } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private var channelName: String {
        switch label {
        case "R": "Red"
        case "G": "Green"
        case "B": "Blue"
        case "H": "Hue"
        case "S": "Saturation"
        case "L": "Lightness"
        default: label
        }
    }

    private func commit() {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else {
            text = "\(value)"
            return
        }
        let clamped = min(max(n, range.lowerBound), range.upperBound)
        text = "\(clamped)"
        if clamped != value { onCommit(clamped) }
    }
}

/// The saturation (across) × brightness (up) square for one hue.
struct SaturationBrightnessSquare: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double
    var onEnd: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                // The square itself is colour math (pure white and black are the point).
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                // The knob sits on colour, not chrome: overlay colours, the same in both modes.
                Circle()
                    .strokeBorder(Color(nsColor: OverlayPalette.paper), lineWidth: 2.5)
                    .shadow(color: Color(nsColor: OverlayPalette.ink).opacity(0.5), radius: 1.5)
                    .frame(width: 16, height: 16)
                    .position(x: saturation * size.width, y: (1 - brightness) * size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .modifier(SwatchEdge(shape: RoundedRectangle(cornerRadius: Radius.l, style: .continuous)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                saturation = Double(g.location.x / max(size.width, 1)).clamped01
                brightness = Double(1 - g.location.y / max(size.height, 1)).clamped01
            }.onEnded { _ in onEnd() })
        }
        .accessibilityElement()
        .accessibilityLabel("Saturation and brightness")
        .accessibilityValue("Saturation \(Int((saturation * 100).rounded())) percent, brightness \(Int((brightness * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: saturation = min(saturation + 0.05, 1)
            case .decrement: saturation = max(saturation - 0.05, 0)
            @unknown default: break
            }
            onEnd()
        }
        .accessibilityAction(named: "Brighter") { brightness = min(brightness + 0.05, 1); onEnd() }
        .accessibilityAction(named: "Darker") { brightness = max(brightness - 0.05, 0); onEnd() }
    }
}
