import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

/// Shape, picture placement, background and export, top to bottom in the order people
/// decide them.
struct Inspector: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Shape") {
                    ShapePicker(model: model)
                }
                Section("Picture") {
                    PictureControls(model: model)
                }
                Section("Background") {
                    BackgroundControls(model: model)
                }
            }
            .formStyle(.grouped)
            Divider()
            ExportBar(model: model)
        }
    }
}

struct ShapePicker: View {
    let model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(Array(IconShape.allCases.enumerated()), id: \.element) { index, shape in
                let selected = model.style.shape == shape
                Button { model.setShape(shape) } label: {
                    VStack(spacing: Spacing.xs) {
                        Group {
                            if let image = model.thumbnails[shape] {
                                Image(decorative: image, scale: 2).resizable().interpolation(.high)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 40, height: 40)
                        .shapeGuide(shape, model: model, outlineAlways: true)
                        Text(shape.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.accentColor : .primary)
                    }
                    .padding(.vertical, Spacing.xs + 2)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(shape.title) (⌘\(index + 1))")
                .accessibilityLabel(shape.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct PictureControls: View {
    @Bindable var model: AppModel

    private var scale: Binding<Double> {
        Binding(get: { model.style.scale }, set: { model.style.scale = $0 })
    }

    var body: some View {
        LabeledContent("Size") {
            HStack(spacing: Spacing.s) {
                Slider(value: scale, in: IconStyle.scaleRange) { editing in
                    editing ? model.beginContinuousEdit() : model.endContinuousEdit("Change Size")
                }
                .labelsHidden()
                .accessibilityLabel("Size")
                .accessibilityValue("\(Int((model.style.scale * 100).rounded())) percent")
                Text("\(Int((model.style.scale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        Picker("Framing", selection: Binding(get: { model.style.fill }, set: { model.setFill($0) })) {
            Text("Fit").tag(false)
            Text("Fill").tag(true)
        }
        .pickerStyle(.segmented)
        .help("Fit shows the whole picture. Fill covers the shape and crops what doesn’t fit.")
        HStack {
            Button("Re-center") { model.resetPosition() }
                .disabled(model.style.isCentered)
                .help("Put the picture back in the middle (⌘0). You can also double-click the preview.")
            Spacer()
            Button("Reset Size") { model.resetSize() }
        }
    }
}

struct BackgroundControls: View {
    @Bindable var model: AppModel

    private var mode: Binding<BackgroundMode> {
        Binding(get: { model.style.background }, set: { mode in model.edit("Change Background") { $0.background = mode } })
    }

    private var color: Binding<Color> {
        Binding(get: {
            let c = model.style.color
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { newColor in
            if let rgba = RGBA(NSColor(newColor).cgColor) { model.style.color = rgba }
        })
    }

    var body: some View {
        let usesBackground = model.style.shape.usesBackground
        Picker("Background", selection: mode) {
            ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
        }
        .disabled(!usesBackground)
        if model.style.background == .color && usesBackground {
            ColorPicker("Color", selection: color, supportsOpacity: false)
        }
        if !usesBackground {
            Text("\(model.style.shape.title) icons have no background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.style.background == .none {
            Text("Transparent. The dashed outline in the preview shows where the shape clips the picture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.style.background == .automatic {
            Text(automaticDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var automaticDescription: String {
        guard let source = model.source else { return "" }
        if source.edges.color != nil { return "Matches the color at the picture’s edges." }
        return "White, because the picture’s edges are transparent."
    }
}

/// Pinned under the options so the main action never scrolls away.
struct ExportBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Picker("Format", selection: $model.prefs.format) {
                    ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help(model.prefs.format.detail)
                Spacer(minLength: 0)
                if model.isExporting { ProgressView().controlSize(.small) }
                Button("Export…") { model.export() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting)
                    .help("Export \(model.prefs.format.title) (⌘E)")
            }
            if let status = model.exportStatus {
                ExportStatusLine(model: model, status: status)
            }
        }
        .padding(Spacing.l)
    }
}

/// One line under Export: what was saved, plus small buttons for the rest.
struct ExportStatusLine: View {
    let model: AppModel
    let status: ExportStatus
    @State private var showingNotes = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Saved “\(status.url.lastPathComponent)”")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(status.url.path)
            Spacer(minLength: 0)
            if !status.notes.isEmpty {
                Button { showingNotes.toggle() } label: {
                    Image(systemName: "info.circle")
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
                    .help("Copy the <link> tags for your page’s <head>")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([status.url]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Format and options inside the export save panel, like Preview's Export.
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
            switch model.prefs.format {
            case .xcode:
                LabeledContent("Platforms:") {
                    HStack(spacing: Spacing.l) {
                        ForEach(XcodePlatform.allCases) { platform in
                            Toggle(platform.title, isOn: Binding(
                                get: { model.prefs.options.xcodePlatforms.contains(platform) },
                                set: { on in
                                    if on { model.prefs.options.xcodePlatforms.insert(platform) } else { model.prefs.options.xcodePlatforms.remove(platform) }
                                }))
                        }
                    }
                }
            case .png:
                Picker("Size:", selection: $model.prefs.options.pngSize) {
                    ForEach(ExportOptions.pngSizes, id: \.self) { Text("\($0) × \($0) pixels").tag($0) }
                }
                .fixedSize()
            default:
                EmptyView()
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
    }

    private var note: String {
        let format = model.prefs.format
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
