import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

// The popovers that hang off the icon's buttons: Adjust (top-right corner), Text and Export
// (under the icon).

// MARK: Adjust

/// Size, position, rotation and the colour behind (or of) the template, each with a reset.
struct AdjustPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Picture") {
                SliderRow(title: "Size", value: Binding(get: { model.style.scale }, set: { v in model.change("Change Size") { $0.scale = v } }),
                          range: IconStyle.scaleRange, text: "\(Int((model.style.scale * 100).rounded()))%", model: model) {
                    model.resetSize()
                }
                SliderRow(title: "Horizontal", value: Binding(get: { model.style.offset.x }, set: { v in model.change("Move Picture") { $0.offset.x = v } }),
                          range: -IconStyle.offsetLimit...IconStyle.offsetLimit, text: offsetText(model.style.offset.x), model: model) {
                    model.edit("Move Picture") { $0.offset.x = 0 }
                }
                SliderRow(title: "Vertical", value: Binding(get: { model.style.offset.y }, set: { v in model.change("Move Picture") { $0.offset.y = v } }),
                          range: -IconStyle.offsetLimit...IconStyle.offsetLimit, text: offsetText(model.style.offset.y), model: model) {
                    model.edit("Move Picture") { $0.offset.y = 0 }
                }
                SliderRow(title: "Rotation", value: Binding(get: { model.style.rotation }, set: { v in model.change("Rotate") { $0.rotation = v.rounded() } }),
                          range: IconStyle.rotationRange, text: "\(Int(model.style.rotation))°", model: model) {
                    model.edit("Rotate") { $0.rotation = 0 }
                }
                Picker("Framing", selection: Binding(get: { model.style.fill }, set: { model.setFill($0) })) {
                    Text("Fit").tag(false)
                    Text("Fill").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Fit shows the whole picture. Fill covers the shape and crops what doesn’t fit.")
            }
            // No header: the picker's own label says Background / Folder Color.
            Section {
                ColorControls(model: model)
            }
        }
        .formStyle(.grouped)
        .frame(width: PopoverMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Reset All") { model.resetAdjustments() }
                    .help("Size, position and rotation back to how the picture first appeared")
            }
            .popoverFooter()
        }
    }

    private func offsetText(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent == 0 ? "0" : "\(percent > 0 ? "+" : "")\(percent)"
    }
}

/// A labelled slider with its value and a per-row reset, one undo step per drag.
struct SliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let text: String
    let model: AppModel
    let reset: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.s) {
                Slider(value: value, in: range) { editing in
                    if !editing { model.endContinuousEdit() }
                }
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(text)
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset \(title.lowercased())")
                .accessibilityLabel("Reset \(title)")
            }
        }
    }
}

/// Background (app icon templates) or folder colour, with quick swatches. Every row is
/// always there (the colour well too), so choosing a mode never resizes the popover.
struct ColorControls: View {
    @Bindable var model: AppModel

    static let swatches: [(name: String, color: NSColor)] = [
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink), ("Red", .systemRed),
        ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen), ("Teal", .systemTeal),
        ("Gray", .systemGray), ("Black", .black), ("White", .white),
    ]

    private var colorBinding: Binding<Color> {
        Binding(get: {
            let c = model.style.color
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { newColor in
            if let rgba = RGBA(NSColor(newColor).cgColor) { model.changeSettling("Change Color") { $0.background = .color; $0.color = rgba } }
        })
    }

    var body: some View {
        let shape = model.style.shape
        if !shape.usesBackground {
            Text("\(shape.title) icons have no background.")
                .foregroundStyle(.secondary)
        } else {
            if shape.isFolder {
                Picker(selection: Binding(get: { model.style.background == .color },
                                          set: { custom in model.edit("Change Folder Color") { $0.background = custom ? .color : .automatic } })) {
                    Text("Standard").tag(false)
                    Text("Custom").tag(true)
                } label: {
                    Text("Folder Color")
                    Text(caption)
                }
            } else {
                Picker(selection: Binding(get: { model.style.background },
                                          set: { mode in model.edit("Change Background") { $0.background = mode } })) {
                    ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Background")
                    Text(caption)
                }
            }
            HStack(spacing: Spacing.s) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    let rgba = RGBA(swatch.color.usingColorSpace(.sRGB)?.cgColor ?? swatch.color.cgColor)?.opaque
                    Button {
                        if let rgba {
                            model.edit(shape.isFolder ? "Change Folder Color" : "Change Background") {
                                $0.background = .color
                                $0.color = rgba
                            }
                        }
                    } label: {
                        Circle().fill(Color(nsColor: swatch.color))
                    }
                    .buttonStyle(SwatchStyle(selected: model.style.background == .color && rgba.map { model.style.color.isClose(to: $0) } == true))
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(model.style.background == .color && rgba.map { model.style.color.isClose(to: $0) } == true ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            ColorPicker(shape.isFolder ? "Custom Folder Color" : "Custom Color", selection: colorBinding, supportsOpacity: false)
        }
    }

    /// One line, whatever the mode, so the row never changes height.
    private var caption: String {
        let style = model.style
        if style.shape.isFolder {
            return style.background == .color ? "Tinted; the shading stays." : "Finder’s own folder."
        }
        switch style.background {
        case .none: return "Transparent."
        case .color: return "A solid color."
        case .automatic:
            guard let source = model.source else { return "" }
            return source.edges.color != nil ? "Matches the picture’s edges." : "White: the edges are clear."
        }
    }
}

/// An 18 pt colour dot with a hairline; hover darkens the hairline, and the chosen one gets a
/// ring around it (outside its slot, so selecting never moves the row).
struct SwatchStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    static let side: CGFloat = 18
    static let ringGap: CGFloat = 1.5
    static let ringWidth: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Self.side, height: Self.side)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(hovering || configuration.isPressed ? 0.45 : 0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .background {
                if selected {
                    Circle()
                        .strokeBorder(Color.selectionRing(activeState), lineWidth: Self.ringWidth)
                        .padding(-(Self.ringGap + Self.ringWidth))
                }
            }
            .contentShape(Circle())
            .onHover { hovering = $0 }
    }
}

/// Shared by the three popovers: same width, and the footer buttons line up with the edges
/// of the grouped form's sections.
enum PopoverMetrics {
    static let width: CGFloat = 360
    /// A grouped `Form` in a popover insets its sections 10 pt from the popover's edge.
    static let formInset: CGFloat = 10
}

extension View {
    /// Footer buttons under a grouped form: 10 pt from the popover's sides and bottom, and
    /// 10 pt under the last section (the form leaves 18 pt of its own margin there, so the
    /// footer moves up into 8 of it), the same as the gap between sections.
    func popoverFooter() -> some View {
        padding(.horizontal, PopoverMetrics.formInset)
            .padding(.bottom, PopoverMetrics.formInset)
            .padding(.top, -Spacing.s)
    }
}

// MARK: Text

/// Text or emoji on the icon: a word on a folder, a label, or a corner badge.
struct TextPanel: View {
    @Bindable var model: AppModel
    @FocusState private var fieldFocused: Bool

    private var text: IconText { model.style.text }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.s) {
                    TextField("Text", text: Binding(get: { text.string }, set: { v in model.changeSettling("Change Text") { $0.text.string = v } }),
                              prompt: Text("Text or emoji"))
                        .labelsHidden()
                        .focused($fieldFocused)
                        .onSubmit { model.endContinuousEdit() }
                    Button {
                        fieldFocused = true
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Image(systemName: "face.smiling")
                    }
                    .buttonStyle(.borderless)
                    .help("Emoji & Symbols (⌃⌘Space)")
                    .accessibilityLabel("Emoji & Symbols")
                }
                // Too wide to share a line with its label: label above, control across the row.
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Position")
                        .accessibilityHidden(true)
                    Picker("Position", selection: Binding(get: { text.position }, set: { p in model.edit("Change Text") { $0.text.position = p } })) {
                        ForEach(IconText.Position.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section("Style") {
                Picker("Font", selection: Binding(get: { text.design }, set: { d in model.edit("Change Font") { $0.text.design = d } })) {
                    ForEach(IconText.Design.allCases) { Text($0.title).tag($0) }
                }
                Picker("Weight", selection: Binding(get: { text.weight }, set: { w in model.edit("Change Font") { $0.text.weight = w } })) {
                    ForEach(IconText.Weight.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Fit Automatically", isOn: Binding(get: { text.autoSize }, set: { on in model.edit("Change Text Size") { $0.text.autoSize = on } }))
                if !text.autoSize {
                    SliderRow(title: "Size", value: Binding(get: { text.size }, set: { v in model.change("Change Text Size") { $0.text.size = v } }),
                              range: IconText.sizeRange, text: "\(Int((text.size * 100).rounded()))%", model: model) {
                        model.edit("Change Text Size") { $0.text.size = IconText().size }
                    }
                }
                Picker("Color", selection: Binding(get: { text.color != nil }, set: { custom in
                    model.edit("Change Text Color") { style in
                        style.text.color = custom ? (model.renderer?.textColor(for: style) ?? .black) : nil
                    }
                })) {
                    Text("Automatic").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                if text.color != nil {
                    ColorPicker("Text Color", selection: colorBinding(\.color, fallback: .black, name: "Change Text Color"), supportsOpacity: true)
                }
                if text.position == .badge {
                    ColorPicker("Badge Color", selection: colorBinding(\.badgeColor, fallback: IconText.defaultBadge, name: "Change Badge Color"),
                                supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: PopoverMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Remove Text") { model.removeText() }
                    .disabled(text.visible == nil)
                Spacer()
                Button("Done") {
                    model.endContinuousEdit()
                    model.showsText = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .popoverFooter()
        }
        .onAppear { fieldFocused = true }
        .onDisappear { model.endContinuousEdit() }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<IconText, RGBA?>, fallback: RGBA, name: String) -> Binding<Color> {
        Binding(get: {
            let c = model.style.text[keyPath: keyPath] ?? fallback
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { newColor in
            if let rgba = RGBA(NSColor(newColor).cgColor) { model.changeSettling(name) { $0.text[keyPath: keyPath] = rgba } }
        })
    }
}

// MARK: Export

/// Every format as a tile, the chosen one's options underneath, then Export.
struct ExportPanel: View {
    @Bindable var model: AppModel
    @State private var all = true
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Export As")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element) { index, format in
                    FormatTile(format: format, selected: model.prefs.format == format) { model.prefs.format = format }
                        .help("\(format.title) (⌥⌘\(index + 1))")
                }
            }
            Hairline()
                .padding(.bottom, -HairlineGap.unusedHalf)
            // Every format's options laid out at once, invisibly: the area is always as tall as
            // the tallest, so picking a format never resizes the popover or moves Export….
            ZStack(alignment: .topLeading) {
                ForEach(ExportFormat.allCases) { format in
                    ExportOptionsView(model: model, format: format)
                        .hidden()
                }
                ExportOptionsView(model: model, format: model.prefs.format)
            }
            if model.isBatch {
                Toggle("All \(model.sources.count) pictures, into one folder", isOn: $all)
            }
            HStack {
                Spacer()
                Button(model.isBatch && all ? "Export \(model.sources.count)…" : "Export…") {
                    let exportAll = all
                    model.showsExport = false
                    // Let the popover close before the save panel slides down.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        model.export(all: exportAll)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.prefs.format == .xcode && model.prefs.options.xcodePlatforms.isEmpty)
            }
        }
        .padding(Spacing.l)
        .frame(width: PopoverMetrics.width)
    }
}

struct FormatTile: View {
    let format: ExportFormat
    let selected: Bool
    let action: () -> Void
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: format.systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 26)
                Text(format.shortTitle)
                    .font(.callout)
            }
            .foregroundStyle(selected ? Color.windowAccent(activeState) : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
        }
        .buttonStyle(TileStyle(selected: selected))
        .accessibilityLabel(format.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A format tile: faint fill, a touch more on hover and while pressed; the chosen one
/// tinted with the accent and outlined.
struct TileStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    static let radius = Radius.l

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        configuration.label
            .background {
                shape.fill(selected ? Color.selectionTint(activeState, opacity: configuration.isPressed ? 0.22 : 0.15)
                           : Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0.04))
                if selected { shape.strokeBorder(Color.selectionRing(activeState), lineWidth: 1.5) }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// The options of a format (shared by the export panel and the save panel).
struct ExportOptionsView: View {
    @Bindable var model: AppModel
    var format: ExportFormat?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch format ?? model.prefs.format {
            case .xcode:
                HStack(spacing: Spacing.l) {
                    ForEach(XcodePlatform.allCases) { platform in
                        Toggle(platform.title, isOn: Binding(
                            get: { model.prefs.options.xcodePlatforms.contains(platform) },
                            set: { on in
                                if on { model.prefs.options.xcodePlatforms.insert(platform) } else { model.prefs.options.xcodePlatforms.remove(platform) }
                            }))
                    }
                }
                Toggle("iOS dark and tinted icons", isOn: $model.prefs.options.xcodeAppearances)
                    .disabled(!model.prefs.options.xcodePlatforms.contains(.iOS))
                    .help("Adds iOS 18 dark (picture on transparency) and tinted (greyscale) variants")
            case .png, .jpg:
                Picker("Size", selection: $model.prefs.options.pngSize) {
                    ForEach(ExportOptions.pngSizes, id: \.self) { Text("\($0) × \($0) pixels").tag($0) }
                }
                .fixedSize()
            default:
                EmptyView()
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: String {
        let format = format ?? model.prefs.format
        var text = format.detail
        if format == .xcode {
            if model.prefs.options.xcodePlatforms.isEmpty {
                text += " Choose at least one platform."
            } else if model.prefs.options.xcodePlatforms.contains(where: { $0 != .macOS }),
                      let renderer = model.renderer, renderer.opaqueNeedsFill(model.style) {
                text += " iOS and watchOS icons can’t be transparent, so they’ll get a white background."
            }
        }
        return text
    }
}

/// The last export, at the leading end of the bottom bar: what was saved, plus small buttons.
struct ExportStatusLine: View {
    let model: AppModel
    let status: ExportStatus
    @State private var showingNotes = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(status.count > 1 ? "Saved \(status.count) icons in “\(status.url.lastPathComponent)”" : "Saved “\(status.url.lastPathComponent)”")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(status.url.path)
                .padding(.trailing, Spacing.xs)
            if !status.notes.isEmpty {
                Button { showingNotes.toggle() } label: {
                    StatusIcon(systemImage: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("What changed during export")
                .accessibilityLabel("Export Notes")
                .popover(isPresented: $showingNotes, arrowEdge: .top) {
                    Text(status.notes.joined(separator: "\n\n"))
                        .frame(width: 260, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Spacing.l)
                }
            }
            if status.hasHTML {
                Button("Copy HTML") { model.copyFaviconHTML() }
                    .controlSize(.small)
                    .fixedSize()
                    .help("Copy the <link> tags for your page’s <head>")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([status.url]) } label: {
                StatusIcon(systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}

/// An icon-only button's glyph with a full 20 pt target.
struct StatusIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .frame(width: ResultRow.buttonSide, height: ResultRow.buttonSide)
            .contentShape(Rectangle())
    }
}

/// Format and options inside the save panel (⌘E), like Preview's Export.
struct ExportAccessory: View {
    @Bindable var model: AppModel
    let onFormatChange: (ExportFormat) -> Void

    var body: some View {
        Form {
            Picker("Format:", selection: Binding(get: { model.prefs.format }, set: { format in
                model.prefs.format = format
                onFormatChange(format)
            })) {
                ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            ExportOptionsView(model: model)
                .frame(width: 380, alignment: .leading)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
    }
}
