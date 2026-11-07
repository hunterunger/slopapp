import AppKit
import DevkitCore
import Observation
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

// Tools with their own layouts: URL Parser, String Inspector, Lorem Ipsum, Random String,
// QR Code, Certificate and Cron.

// MARK: - URL parser

@MainActor
@Observable
final class URLParserToolModel: ToolModel {
    let tool = Tool.urlParser
    let editor = EditorHandle()
    var input = "" { didSet { if input != oldValue { update() } } }
    private(set) var rows: [ResultRow] = []
    private(set) var queryJSON = "" {
        didSet {
            queryStyles = JSONHighlighter.spans(in: queryJSON).map { TextStyleRun(range: $0.range, style: JSONToolModel.style(for: $0.kind)) }
            queryStylesVersion += 1
        }
    }
    /// Highlighted like every other JSON output.
    private(set) var queryStyles: [TextStyleRun] = []
    private(set) var queryStylesVersion = 0
    private(set) var error: String?
    var selectedRow: String?

    var sampleInput: String? { Samples.url }
    var primaryOutput: String? {
        if let selectedRow, let row = rows.first(where: { $0.id == selectedRow }) { return row.value }
        return queryJSON.isEmpty ? nil : queryJSON
    }
    var primaryOutputName: String { selectedRow ?? "Query as JSON" }

    private func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { rows = []; queryJSON = ""; error = nil; return }
        do {
            let parsed = try URLParser.parse(trimmed)
            var rows = parsed.parts.map { ResultRow(label: $0.0, value: $0.1) }
            var seen: [String: Int] = [:]
            for (key, value) in parsed.query {
                seen[key, default: 0] += 1
                let label = "?" + key + (seen[key]! > 1 ? " (\(seen[key]!))" : "")
                rows.append(ResultRow(label: label, value: value, note: "Query parameter"))
            }
            self.rows = rows
            queryJSON = parsed.query.isEmpty ? "" : parsed.queryJSON
            error = nil
        } catch {
            rows = []
            queryJSON = ""
            self.error = "\(error)"
        }
    }
}

struct URLParserToolView: View {
    @Bindable var model: URLParserToolModel
    let app: AppModel
    @AppStorage("urlParserFraction") private var fraction = 0.6

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Each part, and every query value decoded (+ is a space). Repeated keys become arrays.")
            SplitPanes {
                Pane("URL", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Paste a URL (https://…) or a query string (a=1&b=2).",
                                accessibilityLabel: "URL", handle: model.editor) { app.clearInput() }
                }
            } second: {
                if model.rows.isEmpty {
                    Pane("Parts") {
                        EmptyResults(symbol: "link", title: "No URL", message: "The scheme, host, path, each query parameter (decoded) and the query as JSON appear here.")
                    }
                } else {
                    SplitStack(axis: .vertical, fraction: $fraction, minimum: 90, accessibilityLabel: "Parts and query divider") {
                        Pane("Parts") {
                            ResultsList(rows: model.rows, selection: $model.selectedRow) { app.copy($0.value, name: $0.label) }
                        }
                    } second: {
                        Pane("Query as JSON", accessory: {
                            CopyButton(label: "Query as JSON") { app.copy(model.queryJSON, name: "Query as JSON") }.disabled(model.queryJSON.isEmpty)
                        }) {
                            CodeTextView(text: .constant(model.queryJSON), isEditable: false,
                                         placeholder: "This URL has no query string.",
                                         accessibilityLabel: "Query as JSON", styles: model.queryStyles,
                                         stylesVersion: model.queryStylesVersion)
                        }
                    }
                }
            }
            if let error = model.error {
                StatusLine(kind: .error, text: error)
            } else {
                StatusLine(kind: .info, text: "", hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.")
            }
        }
    }
}

// MARK: - String inspector

@MainActor
@Observable
final class StringInspectorToolModel: ToolModel {
    let tool = Tool.stringInspector
    let editor = EditorHandle()
    let job = LiveJob()
    var input = "" { didSet { if input != oldValue { update() } } }
    private(set) var rows: [ResultRow] = []
    private(set) var scalars: [StringInspector.ScalarInfo] = []
    var selectedRow: String?
    var selectedScalar: StringInspector.ScalarInfo.ID?

    var sampleInput: String? { Samples.inspector }
    var primaryOutput: String? {
        if let selectedRow, let row = rows.first(where: { $0.id == selectedRow }) { return row.value }
        return rows.isEmpty ? nil : rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }
    var primaryOutputName: String { selectedRow ?? "Counts" }

    private struct Computed: Sendable {
        var stats: StringInspector.Stats?
        var scalars: [StringInspector.ScalarInfo] = []
    }

    private func update() {
        let text = input
        guard !text.isEmpty else { job.cancel(); rows = []; scalars = []; return }
        job.run(background: approximateSize(text) > LiveJob.syncLimit) { _ in
            Computed(stats: StringInspector.stats(text), scalars: StringInspector.scalars(text))
        } apply: { [weak self] computed in
            guard let self, let stats = computed.stats else { return }
            rows = [
                ResultRow(label: "Characters", value: stats.characters.formatted(), note: "What you see (grapheme clusters)"),
                ResultRow(label: "Words", value: stats.words.formatted()),
                ResultRow(label: "Lines", value: stats.lines.formatted()),
                ResultRow(label: "Sentences", value: stats.sentences.formatted()),
                ResultRow(label: "Paragraphs", value: stats.paragraphs.formatted()),
                ResultRow(label: "Letters", value: stats.letters.formatted()),
                ResultRow(label: "Digits", value: stats.digits.formatted()),
                ResultRow(label: "Spaces", value: stats.spaces.formatted(), note: "Spaces and tabs"),
                ResultRow(label: "Unicode scalars", value: stats.unicodeScalars.formatted(), note: "Code points"),
                ResultRow(label: "UTF-16 units", value: stats.utf16Units.formatted(), note: "JavaScript's .length"),
                ResultRow(label: "UTF-8 bytes", value: stats.utf8Bytes.formatted()),
                ResultRow(label: "Non-ASCII", value: stats.nonASCII.formatted(), note: "Scalars above U+007F"),
            ]
            scalars = computed.scalars
        }
    }
}

struct StringInspectorToolView: View {
    @Bindable var model: StringInspectorToolModel
    let app: AppModel
    @AppStorage("inspectorFraction") private var fraction = 0.5

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Characters are counted as you see them (grapheme clusters); bytes as UTF-8 and UTF-16.")
            SplitPanes {
                Pane("Text", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Type or paste text to count and inspect its characters.",
                                accessibilityLabel: "Text to inspect", handle: model.editor) { app.clearInput() }
                }
            } second: {
                if model.rows.isEmpty {
                    Pane("Counts") {
                        EmptyResults(symbol: "textformat.abc", title: "No Text", message: "Counts and every character's code point, name and bytes appear here.")
                    }
                } else {
                    SplitStack(axis: .vertical, fraction: $fraction, minimum: 100, accessibilityLabel: "Counts and characters divider") {
                        Pane("Counts") {
                            ResultsList(rows: model.rows, selection: $model.selectedRow, defaultSelection: "Characters") { app.copy($0.value, name: $0.label) }
                        }
                    } second: {
                        Pane(model.scalars.count >= 2000 ? "Characters (first 2,000)" : "Characters") {
                            Table(model.scalars, selection: $model.selectedScalar) {
                                // Flexible widths so all five columns fit the pane; Name gets the slack.
                                TableColumn("Char") { Text($0.character).font(.body.monospaced()) }.width(min: 32, ideal: 36, max: 56)
                                TableColumn("Code Point") { Text($0.codePoint).font(.body.monospaced()).textSelection(.enabled) }.width(min: 72, ideal: 80, max: 100)
                                TableColumn("Name") { Text($0.name).font(.callout).lineLimit(1).truncationMode(.middle).help($0.name).textSelection(.enabled) }.width(min: 80)
                                TableColumn("UTF-8") { Text($0.utf8).font(.callout.monospaced()) }.width(min: 44, ideal: 56, max: 120)
                                TableColumn("Kind") { Text($0.category).font(.callout).foregroundStyle(.secondary).lineLimit(1) }.width(min: 60, ideal: 80, max: 140)
                            }
                            .accessibilityLabel("Characters")
                        }
                    }
                }
            }
            StatusLine(kind: .info, text: "", hint: model.rows.isEmpty ? nil : "⇧⌘C copies the selected count, or all counts.")
        }
    }
}

// MARK: - Lorem ipsum

@MainActor
@Observable
final class LoremToolModel: ToolModel {
    let tool = Tool.lorem
    let editor = EditorHandle()
    var input = ""
    var count: Int { didSet { save(); generate() } }
    var unit: LoremIpsum.Unit { didSet { save(); generate() } }
    var startWithLorem: Bool { didSet { save(); generate() } }
    private(set) var output = ""

    init() {
        let defaults = Diagnostics.defaults
        count = defaults.object(forKey: "lorem.count") as? Int ?? 3
        unit = LoremIpsum.Unit(rawValue: defaults.string(forKey: "lorem.unit") ?? "") ?? .paragraphs
        startWithLorem = defaults.object(forKey: "lorem.classic") as? Bool ?? true
        generate()
    }

    private func save() {
        Diagnostics.defaults.set(count, forKey: "lorem.count")
        Diagnostics.defaults.set(unit.rawValue, forKey: "lorem.unit")
        Diagnostics.defaults.set(startWithLorem, forKey: "lorem.classic")
    }

    func generate() {
        var random = Diagnostics.randomSource()
        output = LoremIpsum.generate(count: count, unit: unit, startWithLorem: startWithLorem, random: &random)
    }

    var primaryOutput: String? { output.isEmpty ? nil : output }
    var primaryOutputName: String { "Text" }
}

struct LoremToolView: View {
    @Bindable var model: LoremToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Stepper(value: $model.count, in: 1...500) {
                    Text("\(model.count)").monospacedDigit().frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityLabel("Count")
                .accessibilityValue("\(model.count)")
                Picker("Unit", selection: $model.unit) {
                    ForEach(LoremIpsum.Unit.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Unit")
                Toggle("Start with “Lorem ipsum”", isOn: $model.startWithLorem)
                Button("Generate") { model.generate() }
                    .help("Make new text (⌘R)")
            }
            Pane("Output", accessory: { CopyButton(label: "Text") { app.copyOutput() } }) {
                CodeTextView(text: .constant(model.output), isEditable: false, accessibilityLabel: "Placeholder text", wraps: true)
            }
            StatusLine(kind: .info, text: "\(model.output.split(whereSeparator: \.isWhitespace).count.formatted()) words, \(model.output.count.formatted()) characters",
                       hint: "⌘R makes new text. ⇧⌘C copies it.")
        }
    }
}

// MARK: - Random strings

@MainActor
@Observable
final class RandomStringToolModel: ToolModel {
    let tool = Tool.randomString
    let editor = EditorHandle()
    var input = ""
    var options: RandomStrings.Options { didSet { save(); generate() } }
    private(set) var strings: [String] = []

    init() {
        let defaults = Diagnostics.defaults
        var options = RandomStrings.Options()
        if let length = defaults.object(forKey: "random.length") as? Int { options.length = length }
        if let count = defaults.object(forKey: "random.count") as? Int { options.count = count }
        if let flags = defaults.string(forKey: "random.flags"), flags.count == 5 {
            let bits = Array(flags).map { $0 == "1" }
            (options.lowercase, options.uppercase, options.digits, options.symbols, options.avoidAmbiguous) = (bits[0], bits[1], bits[2], bits[3], bits[4])
        }
        if let group = defaults.object(forKey: "random.group") as? Int { options.groupSize = group }
        self.options = options
        generate()
    }

    private func save() {
        let defaults = Diagnostics.defaults
        defaults.set(options.length, forKey: "random.length")
        defaults.set(options.count, forKey: "random.count")
        defaults.set([options.lowercase, options.uppercase, options.digits, options.symbols, options.avoidAmbiguous].map { $0 ? "1" : "0" }.joined(), forKey: "random.flags")
        defaults.set(options.groupSize, forKey: "random.group")
    }

    func generate() {
        var random = Diagnostics.randomSource()
        strings = RandomStrings.generate(options, random: &random)
    }

    var text: String { strings.joined(separator: "\n") }
    var primaryOutput: String? { strings.isEmpty ? nil : text }
    var primaryOutputName: String { strings.count == 1 ? "String" : "Strings" }
}

struct RandomStringToolView: View {
    @Bindable var model: RandomStringToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                LabeledContent("Length") {
                    TextField("Length", value: $model.options.length, format: .number)
                        .frame(width: 52, height: ToolMetrics.rowControlHeight)
                        .accessibilityLabel("Length")
                    Stepper("Length", value: $model.options.length, in: 1...4096).labelsHidden()
                }
                LabeledContent("Count") {
                    TextField("Count", value: $model.options.count, format: .number)
                        .frame(width: 52, height: ToolMetrics.rowControlHeight)
                        .accessibilityLabel("Count")
                    Stepper("Count", value: $model.options.count, in: 1...1000).labelsHidden()
                }
                Picker("Groups", selection: $model.options.groupSize) {
                    Text("None").tag(0)
                    ForEach([4, 5, 6, 8], id: \.self) { Text("Every \($0)").tag($0) }
                }
                .fixedSize()
                .help("Split with dashes, like a license key")
                Button("Generate") { model.generate() }
                    .help("Make new strings (⌘R)")
            }
            OptionsBar {
                Toggle("a–z", isOn: $model.options.lowercase).accessibilityLabel("Lowercase letters")
                Toggle("A–Z", isOn: $model.options.uppercase).accessibilityLabel("Uppercase letters")
                Toggle("0–9", isOn: $model.options.digits).accessibilityLabel("Digits")
                Toggle("Symbols", isOn: $model.options.symbols).help(RandomStrings.symbolSet)
                Toggle("Avoid look-alikes", isOn: $model.options.avoidAmbiguous).help("Leaves out 0 O o 1 l I")
            }
            Pane(model.strings.count == 1 ? "Output" : "Output (\(model.strings.count))", accessory: {
                CopyButton(label: model.primaryOutputName) { app.copyOutput() }.disabled(model.strings.isEmpty)
            }) {
                if model.strings.isEmpty {
                    EmptyResults(symbol: "dice", title: "No Characters", message: "Turn on at least one set of characters.")
                } else {
                    CodeTextView(text: .constant(model.text), isEditable: false, accessibilityLabel: "Random strings")
                }
            }
            StatusLine(kind: .info, text: model.strings.isEmpty ? "" : "\(Int(RandomStrings.entropyBits(model.options).rounded())) bits of entropy each, from the system's secure random generator",
                       hint: "⌘R makes new ones.")
        }
    }
}

// MARK: - QR code

@MainActor
@Observable
final class QRToolModel: ToolModel {
    enum Mode: String, CaseIterable, Identifiable {
        case generate, read
        var id: String { rawValue }
        var title: String { self == .generate ? "Generate" : "Read" }
    }

    let tool = Tool.qrCode
    let editor = EditorHandle()
    var mode = Mode.generate
    var input = "" { didSet { if input != oldValue { render() } } }
    var correction = QRCode.Correction.medium { didSet { render() } }
    private(set) var image: CGImage?
    private(set) var modules: Int?
    private(set) var error: String?
    private(set) var readResults: [String] = []
    private(set) var readImage: CGImage?
    private(set) var readError: String?

    var sampleInput: String? { Samples.url }
    var primaryOutput: String? {
        switch mode {
        case .generate: image == nil ? nil : input
        case .read: readResults.isEmpty ? nil : readResults.joined(separator: "\n")
        }
    }
    var primaryOutputName: String { mode == .generate ? "QR Code" : "Text" }

    func receive(_ detection: Detector.Detection) { mode = .generate }

    private func render() {
        guard !input.isEmpty else { image = nil; error = nil; modules = nil; return }
        do {
            image = try QRCode.generate(input, correction: correction, scale: 10)
            modules = QRCode.modules(input, correction: correction)
            error = nil
        } catch {
            image = nil
            modules = nil
            self.error = "\(error)"
        }
    }

    var pngData: Data? { image.flatMap(QRCode.pngData) }

    func read(imageData: Data) {
        mode = .read
        do {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw QRCode.QRError(description: "That isn't an image") }
            readImage = image
            readResults = try QRCode.read(image)
            readError = readResults.isEmpty ? "No QR code found in this image" : nil
        } catch {
            readImage = nil
            readResults = []
            readError = "\(error)"
        }
    }

    func read(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            readError = "Couldn't open “\(url.lastPathComponent)”"
            return
        }
        read(imageData: data)
    }
}

struct QRToolView: View {
    @Bindable var model: QRToolModel
    let app: AppModel
    @State private var choosingImage = false

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("Mode", selection: $model.mode) {
                    ForEach(QRToolModel.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Mode")
                if model.mode == .generate {
                    Picker("Error correction", selection: $model.correction) {
                        ForEach(QRCode.Correction.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    .help("Higher correction survives damage and logos but makes a denser code.")
                } else {
                    Button("Open Image…") { choosingImage = true }
                    Button("Paste Image") { app.readQRFromClipboard() }
                        .help("Read a QR code from an image on the clipboard")
                }
            }
            if model.mode == .generate { generateBody } else { readBody }
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                let access = url.startAccessingSecurityScopedResource()
                model.read(url: url)
                if access { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private var generateBody: some View {
        VStack(spacing: 0) {
            SplitPanes {
                Pane("Content", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Type a URL or any text to encode. For Wi-Fi, use WIFI:T:WPA;S:name;P:password;;",
                                accessibilityLabel: "QR code content", handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane("QR Code", accessory: {
                    HStack(spacing: Spacing.s) {
                        Button("Save PNG…") { savePNG() }
                            .controlSize(.small)
                            .disabled(model.image == nil)
                        CopyButton(label: "QR code image") { app.copyOutput() }.disabled(model.image == nil)
                    }
                }) {
                    if let image = model.image {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            // The code's light quiet zone has to stay (scanners need it); round it
                            // into a tile so it sits well on a dark window too.
                            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                            .frame(maxWidth: 360, maxHeight: 360)
                            .padding(Spacing.l)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("QR code for \(model.input)")
                            .onDrag { NSItemProvider(item: model.pngData as NSData?, typeIdentifier: UTType.png.identifier) }
                    } else {
                        EmptyResults(symbol: "qrcode", title: "No Content", message: model.error ?? "The code appears here as you type.")
                    }
                }
            }
            StatusLine(kind: model.error == nil ? .info : .error, text: model.error ?? (model.modules.map { "\($0)×\($0) modules, \(model.input.utf8.count.formatted()) bytes" } ?? ""),
                       hint: model.image == nil ? nil : "⇧⌘C copies the image. Drag it out, or save it as PNG.")
        }
    }

    private var readBody: some View {
        VStack(spacing: 0) {
            SplitPanes {
                Pane("Image") {
                    ImageDropTarget(image: model.readImage) { data in model.read(imageData: data) } open: { choosingImage = true }
                }
            } second: {
                Pane(model.readResults.count > 1 ? "Text (\(model.readResults.count) codes)" : "Text", accessory: {
                    CopyButton(label: "Text") { app.copyOutput() }.disabled(model.readResults.isEmpty)
                }) {
                    CodeTextView(text: .constant(model.readResults.joined(separator: "\n\n")), isEditable: false, accessibilityLabel: "Decoded text")
                }
            }
            StatusLine(kind: model.readError == nil ? .info : .warning, text: model.readError ?? "",
                       hint: "Drop an image, open one, or paste one. Read on this Mac with Vision.")
        }
    }

    private func savePNG() {
        guard let data = model.pngData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "QR Code.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}

/// Shows an image and accepts dropped image files or image data.
struct ImageDropTarget: View {
    let image: CGImage?
    let onImage: (Data) -> Void
    let open: () -> Void
    @State private var isTargeted = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(Spacing.l)
                    .accessibilityLabel("Image being read")
            } else {
                EmptyResults(symbol: "qrcode.viewfinder", title: "No Image", message: "Drop a screenshot or photo with a QR code here.",
                             actionTitle: "Open Image…", action: open)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : .clear)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), let contents = try? Data(contentsOf: url) else { return }
                    Task { @MainActor in onImage(contents) }
                }
            } else {
                _ = provider.loadDataRepresentation(for: .image) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in onImage(data) }
                }
            }
            return true
        }
    }
}

// MARK: - Certificate

@MainActor
@Observable
final class CertificateToolModel: ToolModel {
    let tool = Tool.certificate
    let editor = EditorHandle()
    var input = "" { didSet { if input != oldValue { update() } } }
    private(set) var certificates: [CertificateDecoder.Decoded] = []
    private(set) var error: String?
    var index = 0
    var selectedRow: String?

    var sampleInput: String? { Samples.certificate }

    var current: CertificateDecoder.Decoded? { certificates.indices.contains(index) ? certificates[index] : nil }

    var rows: [ResultRow] {
        guard let certificate = current else { return [] }
        let now = Diagnostics.now()
        var rows: [ResultRow] = []
        if let name = certificate.commonName { rows.append(ResultRow(label: "Common name", value: name)) }
        rows.append(ResultRow(label: "Subject", value: certificate.subject))
        rows.append(ResultRow(label: "Issuer", value: certificate.issuer, note: certificate.isSelfSigned ? "Self-signed" : nil))
        if !certificate.subjectAltNames.isEmpty { rows.append(ResultRow(label: "Alternative names", value: certificate.subjectAltNames.joined(separator: ", "))) }
        if let start = certificate.notBefore {
            rows.append(ResultRow(label: "Valid from", value: start.formatted(date: .abbreviated, time: .shortened), note: Timestamps.relative(start, now: now)))
        }
        if let end = certificate.notAfter {
            rows.append(ResultRow(label: "Valid until", value: end.formatted(date: .abbreviated, time: .shortened), note: end < now ? "Expired \(Timestamps.relative(end, now: now))" : Timestamps.relative(end, now: now)))
        }
        rows.append(ResultRow(label: "Public key", value: certificate.publicKey))
        rows.append(ResultRow(label: "Signature", value: certificate.signatureAlgorithm))
        rows.append(ResultRow(label: "Serial number", value: certificate.serialNumber))
        rows.append(ResultRow(label: "Version", value: "\(certificate.version)"))
        if let ca = certificate.isCA {
            rows.append(ResultRow(label: "Certificate authority", value: ca ? "Yes" + (certificate.pathLength.map { ", path length \($0)" } ?? "") : "No"))
        }
        if !certificate.keyUsage.isEmpty { rows.append(ResultRow(label: "Key usage", value: certificate.keyUsage.joined(separator: ", "))) }
        if !certificate.extendedKeyUsage.isEmpty { rows.append(ResultRow(label: "Extended key usage", value: certificate.extendedKeyUsage.joined(separator: ", "))) }
        if let id = certificate.subjectKeyID { rows.append(ResultRow(label: "Subject key ID", value: id)) }
        if let id = certificate.authorityKeyID { rows.append(ResultRow(label: "Authority key ID", value: id)) }
        rows.append(ResultRow(label: "SHA-256 fingerprint", value: certificate.sha256Fingerprint))
        rows.append(ResultRow(label: "SHA-1 fingerprint", value: certificate.sha1Fingerprint))
        return rows
    }

    var validity: (kind: StatusLine.Kind, text: String)? {
        guard let certificate = current, let start = certificate.notBefore, let end = certificate.notAfter else { return nil }
        let now = Diagnostics.now()
        if now < start { return (.warning, "Not valid yet: starts \(Timestamps.relative(start, now: now))") }
        if now > end { return (.error, "Expired \(Timestamps.relative(end, now: now))") }
        return (.success, "Valid, expires \(Timestamps.relative(end, now: now))")
    }

    var primaryOutput: String? {
        if let selectedRow, let row = rows.first(where: { $0.id == selectedRow }) { return row.value }
        return current?.sha256Fingerprint
    }
    var primaryOutputName: String { selectedRow ?? "SHA-256 fingerprint" }

    private func update() {
        index = 0
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { certificates = []; error = nil; return }
        do {
            certificates = try CertificateDecoder.decodeAll(input)
            error = nil
        } catch {
            certificates = []
            self.error = "\(error)"
        }
    }
}

struct CertificateToolView: View {
    @Bindable var model: CertificateToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Decoded on this Mac. The chain isn't checked against your trust settings.")
            SplitPanes {
                Pane("PEM", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Paste a certificate (-----BEGIN CERTIFICATE-----) or a whole chain, or drop a .pem/.crt file.",
                                accessibilityLabel: "Certificate", handle: model.editor,
                                onFileDrop: { url in
                                    if let data = try? Data(contentsOf: url) {
                                        let text = String(data: data, encoding: .utf8) ?? ("-----BEGIN CERTIFICATE-----\n" + data.base64EncodedString(options: .lineLength64Characters) + "\n-----END CERTIFICATE-----")
                                        app.setInput(text, on: model, actionName: "Open Certificate")
                                    }
                                }) { app.clearInput() }
                }
            } second: {
                Pane("Details", accessory: {
                    if model.certificates.count > 1 {
                        Picker("Certificate", selection: $model.index) {
                            ForEach(model.certificates.indices, id: \.self) { index in
                                Text("\(index + 1). \(model.certificates[index].commonName ?? "Certificate")").tag(index)
                            }
                        }
                        .fixedSize()
                        .controlSize(.small)
                    }
                }) {
                    if model.rows.isEmpty {
                        EmptyResults(symbol: "checkmark.seal", title: "No Certificate", message: "Subject, issuer, validity, key, names and fingerprints appear here.")
                    } else {
                        ResultsList(rows: model.rows, selection: $model.selectedRow) { app.copy($0.value, name: $0.label) }
                    }
                }
            }
            if let error = model.error {
                StatusLine(kind: .error, text: error)
            } else if let validity = model.validity {
                StatusLine(kind: validity.kind, text: validity.text, hint: model.rows.isEmpty ? nil : "Double-click a row to copy it.")
            } else {
                StatusLine(kind: .info, text: "")
            }
        }
    }
}

// MARK: - Cron

@MainActor
@Observable
final class CronToolModel: ToolModel {
    let tool = Tool.cron
    let editor = EditorHandle()
    var input = "" { didSet { if input != oldValue { update() } } }
    var useUTC = false { didSet { update() } }
    var runCount = 10 { didSet { update() } }
    private(set) var description = ""
    private(set) var rows: [ResultRow] = []
    private(set) var error: String?
    var selectedRow: String?

    var sampleInput: String? { "*/15 9-17 * * 1-5" }
    var primaryOutput: String? {
        if let selectedRow, let row = rows.first(where: { $0.id == selectedRow }) { return row.value }
        return description.isEmpty ? nil : description
    }
    var primaryOutputName: String { selectedRow == nil ? "Description" : "Time" }

    func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { description = ""; rows = []; error = nil; return }
        do {
            let schedule = try Cron.parse(trimmed)
            description = Cron.describe(schedule)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = useUTC ? TimeZone(identifier: "UTC")! : .current
            let now = Diagnostics.now()
            let runs = Cron.nextRuns(of: schedule, after: now, count: runCount, calendar: calendar)
            let style = Date.FormatStyle(date: .complete, time: .standard, timeZone: calendar.timeZone)
            rows = runs.enumerated().map { index, date in
                ResultRow(label: "\(index + 1)", value: date.formatted(style), note: Timestamps.relative(date, now: now))
            }
            error = runs.isEmpty ? "This schedule never runs in the next eight years" : nil
        } catch {
            description = ""
            rows = []
            self.error = "\(error)"
        }
    }
}

struct CronToolView: View {
    @Bindable var model: CronToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("Time zone", selection: $model.useUTC) {
                    Text("Local Time").tag(false)
                    Text("UTC").tag(true)
                }
                .fixedSize()
                Picker("Show", selection: $model.runCount) {
                    ForEach([5, 10, 25, 50], id: \.self) { Text("Next \($0) Runs").tag($0) }
                }
                .fixedSize()
            }
            layout
        }
        .onAppear { model.update() } // next runs depend on the time now
    }

    private var layout: some View {
        ValueToolLayout(app: app, error: model.error, info: nil,
                        hint: model.rows.isEmpty ? "minute hour day-of-month month day-of-week, optionally seconds first; or @daily, @hourly…" : "⇧⌘C copies the description, or the selected time.") {
            ValueField(title: "Cron expression", prompt: "*/15 9-17 * * 1-5", text: $model.input)
        } results: {
            if model.description.isEmpty {
                EmptyResults(symbol: "calendar.badge.clock", title: "No Schedule",
                             message: "Type a cron expression to read it in plain English and see when it runs next.",
                             actionTitle: "Try an Example") { app.loadSample() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.description)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Description: \(model.description)")
                    Hairline()
                    ResultsList(rows: model.rows, selection: $model.selectedRow) { app.copy($0.value, name: "Time") }
                }
            }
        }
    }
}
