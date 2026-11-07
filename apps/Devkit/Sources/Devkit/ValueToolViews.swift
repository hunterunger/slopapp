import AppKit
import DevkitCore
import SlopKit
import SwiftUI

// Tools built around one value and a list of results: Unix Time, Color, Number Base, UUID.

/// Layout for single-value tools, built from the same parts as the two-pane tools so the
/// Input header and its Clipboard / Sample / Clear sit in the same place: an Input header, a
/// big field with one line of feedback under it, then the results. The tool's options go in
/// an `OptionsBar` above it.
struct ValueToolLayout<Field: View, Results: View>: View {
    /// Shows Clipboard / Sample / Clear in the Input header.
    var app: AppModel?
    var error: String?
    var info: String?
    var hint: String?
    @ViewBuilder var field: () -> Field
    @ViewBuilder var results: () -> Results

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Input") {
                if let app { InputActions(app: app) }
            }
            Hairline()
            VStack(alignment: .leading, spacing: Spacing.s) {
                field()
                // Always one line tall, so an error appearing doesn't move the results.
                Group {
                    if let error {
                        feedback(error, symbol: "xmark.octagon.fill", tint: .red, text: .primary)
                    } else if let info {
                        feedback(info, symbol: "info.circle", tint: .secondary, text: .secondary)
                    } else {
                        Text(" ").accessibilityHidden(true)
                    }
                }
                .font(.callout)
                .lineLimit(1)
                .textSelection(.enabled)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.s)
            Hairline()
            results()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusLine(kind: .info, text: "", hint: hint)
        }
    }

    /// A status symbol in its own colour, with the message in a readable text colour (a whole
    /// red sentence measures about 3.6:1 on a light window).
    private func feedback(_ message: String, symbol: String, tint: Color, text: HierarchicalShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(text)
                .truncationMode(.tail)
                .help(message)
        }
        .accessibilityElement(children: .combine)
    }
}



struct TimestampToolView: View {
    @Bindable var model: TimestampToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("Unit", selection: $model.unit) {
                    ForEach(Timestamps.Unit.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                .help("Automatic picks seconds, milliseconds, microseconds or nanoseconds by size.")
                Button("Now") { model.setNow() }
                    .help("Use the current time")
            }
            layout
        }
        .onAppear { model.refresh() } // "Relative" depends on the time now.
    }

    private var layout: some View {
        ValueToolLayout(app: app, error: model.error, info: model.detectedUnitDescription,
                        hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.") {
            ValueField(title: "Timestamp or date", prompt: "1730592000, or a date like 2024-11-03 10:00",
                       text: $model.input)
        } results: {
            if model.rows.isEmpty {
                EmptyResults(symbol: "clock", title: "No Time",
                             message: "Type a Unix timestamp in seconds or milliseconds, or a date to get its timestamp.",
                             actionTitle: "Use Now") { model.setNow() }
            } else {
                ResultsList(rows: model.rows, selection: $model.selectedRow) { row in
                    app.copy(row.value, name: row.label)
                }
            }
        }
    }
}

struct ColorToolView: View {
    @Bindable var model: ColorToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Hex (3, 4, 6 or 8 digits), rgb(), hsl() or hsb(), with or without alpha.")
            layout
        }
    }

    private var layout: some View {
        ValueToolLayout(app: app, error: model.error, info: nil,
                        hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.") {
            HStack(spacing: Spacing.s) {
                Swatch(color: model.color)
                ValueField(title: "Color", prompt: "#FF8800, rgb(255 136 0) or hsl(32 100% 50%)",
                           text: $model.input)
                ColorPicker("Pick a color", selection: Binding(
                    get: { model.color.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? .gray },
                    set: { model.setFromPicker(NSColor($0)) }
                ), supportsOpacity: true)
                .labelsHidden()
                .help("Pick a color, or sample one from the screen")
                .accessibilityLabel("Pick a color")
            }
        } results: {
            if model.rows.isEmpty {
                EmptyResults(symbol: "paintpalette", title: "No Color",
                             message: "Type a color in any CSS format, or pick one, to see it in every format.",
                             actionTitle: "Paste and Detect") { app.pasteAndDetect() }
            } else {
                ResultsList(rows: model.rows, selection: $model.selectedRow, defaultSelection: "Hex") { row in
                    app.copy(row.value, name: row.label)
                }
            }
        }
    }
}

/// The color over a checkerboard-free neutral backdrop, so transparency shows.
struct Swatch: View {
    let color: RGBAColor?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        shape
            .fill(.background)
            .overlay {
                if let color {
                    shape.fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                }
            }
            .hairlineBorder(shape)
            .frame(width: 44, height: 30)
            .accessibilityHidden(true)
    }
}

struct NumberBaseToolView: View {
    @Bindable var model: NumberBaseToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("From", selection: $model.inputRadix) {
                    Text("Automatic").tag(0)
                    Divider()
                    Text("Binary").tag(2)
                    Text("Octal").tag(8)
                    Text("Decimal").tag(10)
                    Text("Hexadecimal").tag(16)
                    Divider()
                    ForEach([3, 4, 5, 6, 7, 9, 11, 12, 20, 32, 36], id: \.self) { Text("Base \($0)").tag($0) }
                }
                .fixedSize()
                .help("Automatic reads 0x as hex, 0b as binary, 0o as octal, and anything else as decimal.")
                Stepper(value: $model.customRadix, in: 2...36) {
                    // Sized for two digits, so the controls after it don't shift as it counts.
                    ZStack(alignment: .leading) {
                        Text("Extra base: 36").hidden().accessibilityHidden(true)
                        Text("Extra base: \(model.customRadix)")
                    }
                    .monospacedDigit()
                }
                .accessibilityLabel("Extra base")
                .accessibilityValue("\(model.customRadix)")
                Toggle("Uppercase letters", isOn: $model.uppercase)
            }
            layout
        }
    }

    private var layout: some View {
        ValueToolLayout(app: app, error: model.error, info: model.value.map { "Read as base \($0.detectedRadix)" },
                        hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.") {
            ValueField(title: "Number", prompt: "255, 0xFF, 0b1111_1111 or 0o377",
                       text: $model.input)
        } results: {
            if model.rows.isEmpty {
                EmptyResults(symbol: "01.square", title: "No Number",
                             message: "Type a whole number of any size. Prefixes like 0x and separators like _ work.",
                             actionTitle: "Paste and Detect") { app.pasteAndDetect() }
            } else {
                ResultsList(rows: model.rows, selection: $model.selectedRow) { row in
                    app.copy(row.value, name: row.label)
                }
            }
        }
    }
}

struct UUIDToolView: View {
    @Bindable var model: UUIDToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("Mode", selection: $model.mode) {
                    ForEach(UUIDMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Mode")
                if model.mode == .generate {
                    Picker("Type", selection: $model.kind) {
                        ForEach(IdentifierKind.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    HStack(spacing: Spacing.xs) {
                        Text("Count")
                        CodeField(text: Binding(
                            get: { String(model.count) },
                            set: { if let value = Int($0.filter(\.isNumber)) { model.count = min(max(value, 1), 1000) } }
                        ), placeholder: "1", accessibilityLabel: "Count")
                        .frame(width: 60, height: ToolMetrics.rowControlHeight)
                        Stepper("Count", value: $model.count, in: 1...1000)
                            .labelsHidden()
                            .accessibilityLabel("Count")
                    }
                    if model.kind != .ulid {
                        Toggle("Uppercase", isOn: $model.uppercase)
                        Toggle("Hyphens", isOn: $model.hyphens)
                    }
                    Button("Generate") { model.generate() }
                        .help("Generate new IDs (⌘R)")
                }
            }
            switch model.mode {
            case .generate: generateView
            case .inspect: inspectView
            }
        }
    }

    private var generateView: some View {
        VStack(spacing: 0) {
            Pane(model.generated.count == 1 ? "Generated" : "Generated (\(model.generated.count))", accessory: {
                CopyButton(label: "All") { app.copyOutput() }
            }) {
                CodeTextView(text: .constant(model.generatedText), isEditable: false, accessibilityLabel: "Generated IDs")
            }
            StatusLine(kind: .info, text: description, hint: "⇧⌘C copies, ⌘R generates again")
        }
    }

    private var description: String {
        switch model.kind {
        case .uuidV4: "122 random bits. The usual choice when order doesn't matter."
        case .uuidV7: "Starts with the time, so new IDs sort after old ones. Good for database keys."
        case .ulid: "26 characters, sortable by time, no hyphens. Case-insensitive."
        }
    }

    private var inspectView: some View {
        ValueToolLayout(app: app, error: model.error, info: nil,
                        hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.") {
            ValueField(title: "UUID or ULID", prompt: "123e4567-e89b-12d3-a456-426614174000 or 01ARZ3NDEKTSV4RRFFQ69G5FAV",
                       text: $model.input)
        } results: {
            if model.rows.isEmpty {
                EmptyResults(symbol: "number", title: "Nothing to Inspect",
                             message: "Paste a UUID or ULID to see its version, variant and the time inside it.",
                             actionTitle: "Paste and Detect") { app.pasteAndDetect() }
            } else {
                ResultsList(rows: model.rows, selection: $model.selectedRow, defaultSelection: "Canonical") { row in
                    app.copy(row.value, name: row.label)
                }
            }
        }
    }
}
