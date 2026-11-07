import AppKit
import DevkitCore
import Observation
import SwiftUI

// Tools that turn input text into output text with a few options: converters, formatters,
// escapers. One model and one view, configured by a `TransformSpec` per tool.

struct TransformChoice: Hashable {
    var value: String
    var title: String
}

struct TransformOption: Identifiable {
    enum Kind {
        case picker([TransformChoice])
        case toggle
    }

    var key: String
    var title: String
    var kind: Kind
    var defaultValue: String
    /// Shown only in these modes (nil: always).
    var modes: Set<String>?
    var help: String?

    var id: String { key }

    static func picker(_ key: String, _ title: String, _ choices: [(String, String)], default value: String? = nil,
                       modes: Set<String>? = nil, help: String? = nil) -> TransformOption {
        TransformOption(key: key, title: title, kind: .picker(choices.map { TransformChoice(value: $0.0, title: $0.1) }),
                        defaultValue: value ?? choices.first?.0 ?? "", modes: modes, help: help)
    }

    static func toggle(_ key: String, _ title: String, default value: Bool, modes: Set<String>? = nil, help: String? = nil) -> TransformOption {
        TransformOption(key: key, title: title, kind: .toggle, defaultValue: value ? "1" : "0", modes: modes, help: help)
    }
}

struct TransformResult: Sendable {
    var text: String
    var summary: String?
    var isWarning = false
    /// Highlight the output as JSON.
    var isJSON = false
}

/// Option values by key. Toggles are "1"/"0".
struct TransformValues: Sendable {
    var values: [String: String]
    subscript(key: String) -> String { values[key] ?? "" }
    func flag(_ key: String) -> Bool { values[key] == "1" }
    var indent: String {
        switch values["indent"] {
        case "4": "    "
        case "tab": "\t"
        default: "  "
        }
    }
}

struct TransformSpec {
    var tool: Tool
    /// Segmented modes, e.g. Encode/Decode. The first is the default.
    var modes: [TransformChoice] = []
    /// The mode a detected clipboard item opens in (Paste and Detect's "decode" hint).
    var decodeMode: String?
    var options: [TransformOption] = []
    var inputTitle: (String) -> String = { _ in "Input" }
    var outputTitle: (String) -> String = { _ in "Output" }
    var placeholder: (String) -> String
    var sample: (String) -> String
    var hint: String?
    var run: @Sendable (_ input: String, _ mode: String, _ values: TransformValues) throws -> TransformResult
}

@MainActor
@Observable
final class TransformToolModel: ToolModel {
    let spec: TransformSpec
    let editor = EditorHandle()
    let job = LiveJob()

    var tool: Tool { spec.tool }
    var input = "" { didSet { if input != oldValue { update() } } }
    var mode: String {
        didSet {
            guard mode != oldValue else { return }
            Diagnostics.defaults.set(mode, forKey: key("mode"))
            update()
        }
    }
    private(set) var values: [String: String]

    private(set) var output = ""
    private(set) var shownOutput = ""
    private(set) var error: String?
    private(set) var summary: String?
    private(set) var isWarning = false
    private(set) var styles: [TextStyleRun] = []
    private(set) var stylesVersion = 0

    init(spec: TransformSpec) {
        self.spec = spec
        let defaults = Diagnostics.defaults
        let storedMode = defaults.string(forKey: "tool.\(spec.tool.rawValue).mode")
        mode = spec.modes.contains { $0.value == storedMode } ? storedMode! : spec.modes.first?.value ?? ""
        var values: [String: String] = [:]
        for option in spec.options {
            values[option.key] = defaults.string(forKey: "tool.\(spec.tool.rawValue).\(option.key)") ?? option.defaultValue
        }
        self.values = values
    }

    private func key(_ name: String) -> String { "tool.\(spec.tool.rawValue).\(name)" }

    func binding(for option: TransformOption) -> Binding<String> {
        Binding(get: { self.values[option.key] ?? option.defaultValue }, set: { self.set(option.key, $0) })
    }

    func toggleBinding(for option: TransformOption) -> Binding<Bool> {
        Binding(get: { self.values[option.key] == "1" }, set: { self.set(option.key, $0 ? "1" : "0") })
    }

    func set(_ key: String, _ value: String) {
        guard values[key] != value else { return }
        values[key] = value
        Diagnostics.defaults.set(value, forKey: self.key(key))
        update()
    }

    var visibleOptions: [TransformOption] { spec.options.filter { $0.modes?.contains(mode) ?? true } }

    var primaryOutput: String? { output.isEmpty ? nil : output }
    var sampleInput: String? { spec.sample(mode) }

    func receive(_ detection: Detector.Detection) {
        if detection.hint == .decode, let decodeMode = spec.decodeMode { mode = decodeMode }
    }

    /// Use Output as Input on a two-way tool runs it the other way.
    func flipMode() {
        guard spec.modes.count == 2 else { return }
        mode = mode == spec.modes[0].value ? spec.modes[1].value : spec.modes[0].value
    }

    private struct Computed: Sendable {
        var result: TransformResult?
        var error: String?
        var spans: [JSONHighlighter.Span] = []
    }

    private func update() {
        let text = input, mode = mode, values = TransformValues(values: values), run = spec.run
        guard !isBlank(text) else {
            job.cancel()
            apply(Computed())
            return
        }
        job.run(background: approximateSize(text) > LiveJob.syncLimit / 4) { _ in
            do {
                let result = try run(text, mode, values)
                let spans = result.isJSON && result.text.utf8.count <= JSONHighlighter.limit ? JSONHighlighter.spans(in: result.text) : []
                return Computed(result: result, spans: spans)
            } catch {
                return Computed(error: "\(error)")
            }
        } apply: { [weak self] computed in
            self?.apply(computed)
        }
    }

    private func apply(_ computed: Computed) {
        output = computed.result?.text ?? ""
        let clipped = DisplayLimit.clip(output)
        shownOutput = clipped.shown
        error = computed.error
        summary = computed.result?.summary ?? (clipped.clipped ? "Showing the first \(formatBytes(DisplayLimit.bytes)); Copy Output copies all of it." : nil)
        isWarning = computed.result?.isWarning ?? false
        styles = clipped.clipped ? [] : computed.spans.map { TextStyleRun(range: $0.range, style: JSONToolModel.style(for: $0.kind)) }
        stylesVersion += 1
    }
}

struct TransformToolView: View {
    @Bindable var model: TransformToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.spec.modes.isEmpty || !model.visibleOptions.isEmpty {
                OptionsBar(isBusy: model.job.isBusy) {
                    if !model.spec.modes.isEmpty {
                        Picker("Mode", selection: $model.mode) {
                            ForEach(model.spec.modes, id: \.value) { Text($0.title).tag($0.value) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityLabel("Mode")
                    }
                    ForEach(model.visibleOptions) { option in
                        switch option.kind {
                        case let .picker(choices):
                            Picker(option.title, selection: model.binding(for: option)) {
                                ForEach(choices, id: \.value) { Text($0.title).tag($0.value) }
                            }
                            .fixedSize()
                            .help(option.help ?? "")
                        case .toggle:
                            Toggle(option.title, isOn: model.toggleBinding(for: option))
                                .help(option.help ?? "")
                        }
                    }
                }
            }
            SplitPanes {
                Pane(model.spec.inputTitle(model.mode), accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: model.spec.placeholder(model.mode),
                                accessibilityLabel: model.spec.inputTitle(model.mode), handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane(model.spec.outputTitle(model.mode), accessory: {
                    CopyButton(label: "Output") { app.copyOutput() }.disabled(model.output.isEmpty)
                }) {
                    CodeTextView(text: .constant(model.shownOutput), isEditable: false,
                                 accessibilityLabel: model.spec.outputTitle(model.mode), styles: model.styles,
                                 stylesVersion: model.stylesVersion)
                }
            }
            if let error = model.error {
                StatusLine(kind: .error, text: error)
            } else if let summary = model.summary {
                StatusLine(kind: model.isWarning ? .warning : .success, text: summary, hint: "⇧⌘C copies the output")
            } else {
                StatusLine(kind: .info, text: "", hint: model.output.isEmpty ? model.spec.hint : "⇧⌘C copies the output")
            }
        }
    }
}

// MARK: - The specs

private func count(_ value: Int, _ noun: String) -> String {
    "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
}

private let indentOption = TransformOption.picker("indent", "Indent", [("2", "2 Spaces"), ("4", "4 Spaces"), ("tab", "Tab")])

extension TransformSpec {
    static func make(_ tool: Tool) -> TransformSpec? {
        switch tool {
        case .yamlToJSON:
            return TransformSpec(
                tool: tool, options: [indentOption],
                inputTitle: { _ in "YAML" }, outputTitle: { _ in "JSON" },
                placeholder: { _ in "Paste YAML. Several documents (---) become an array." },
                sample: { _ in Samples.yaml },
                hint: "YAML 1.2: yes/no/on stay strings; anchors and merge keys are resolved.",
                run: { input, _, values in
                    let json = try YAMLConverter.toJSON(input, indent: values.indent)
                    return TransformResult(text: json, isJSON: true)
                })
        case .jsonToYAML:
            return TransformSpec(
                tool: tool, options: [.picker("indent", "Indent", [("2", "2 Spaces"), ("4", "4 Spaces")])],
                inputTitle: { _ in "JSON" }, outputTitle: { _ in "YAML" },
                placeholder: { _ in "Paste JSON. Key order and numbers are kept exactly." },
                sample: { _ in Samples.json },
                run: { input, _, values in
                    TransformResult(text: try YAMLConverter.fromJSON(input, indent: values["indent"] == "4" ? 4 : 2))
                })
        case .csvToJSON:
            return TransformSpec(
                tool: tool,
                options: [
                    .picker("delimiter", "Delimiter", CSVConverter.Delimiter.allCases.map { ($0.rawValue, $0.title) }),
                    .toggle("header", "First row is the header", default: true),
                    .toggle("infer", "Detect numbers and booleans", default: true, help: "Leading zeros (like ZIP codes) always stay text."),
                ],
                inputTitle: { _ in "CSV" }, outputTitle: { _ in "JSON" },
                placeholder: { _ in "Paste CSV or TSV. Quoted fields, commas and line breaks inside quotes are handled." },
                sample: { _ in Samples.csv },
                run: { input, _, values in
                    let options = CSVConverter.ToJSONOptions(headerRow: values.flag("header"), inferTypes: values.flag("infer"),
                                                             delimiter: CSVConverter.Delimiter(rawValue: values["delimiter"]) ?? .auto)
                    let value = try CSVConverter.toJSONValue(input, options: options)
                    let rows = if case let .array(items) = value { items.count } else { 0 }
                    return TransformResult(text: JSONTree.serialize(value), summary: count(rows, "row"), isJSON: true)
                })
        case .jsonToCSV:
            return TransformSpec(
                tool: tool,
                options: [
                    .picker("delimiter", "Delimiter", [CSVConverter.Delimiter.comma, .semicolon, .tab, .pipe].map { ($0.rawValue, $0.title) }),
                    .toggle("flatten", "Flatten nested objects", default: true, help: "Nested objects become parent.child columns."),
                    .toggle("header", "Header row", default: true),
                ],
                inputTitle: { _ in "JSON" }, outputTitle: { _ in "CSV" },
                placeholder: { _ in "Paste a JSON array of objects (or of arrays)." },
                sample: { _ in Samples.jsonArray },
                run: { input, _, values in
                    let options = CSVConverter.ToCSVOptions(delimiter: CSVConverter.Delimiter(rawValue: values["delimiter"]) ?? .comma,
                                                            flatten: values.flag("flatten"), header: values.flag("header"))
                    let csv = try CSVConverter.fromJSON(input, options: options)
                    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).count - 1
                    return TransformResult(text: csv, summary: count(lines, "line"))
                })
        case .htmlEntities:
            return TransformSpec(
                tool: tool, modes: [.init(value: "encode", title: "Encode"), .init(value: "decode", title: "Decode")], decodeMode: "decode",
                options: [.picker("scope", "Encode", HTMLEntities.EncodeScope.allCases.map { ($0.rawValue, $0.title) }, modes: ["encode"])],
                inputTitle: { $0 == "encode" ? "Text" : "HTML" }, outputTitle: { $0 == "encode" ? "HTML" : "Text" },
                placeholder: { $0 == "encode" ? "Type or paste text to escape for HTML." : "Paste HTML with entities like &amp; &#233; or &#xE9;." },
                sample: { $0 == "encode" ? Samples.htmlText : HTMLEntities.encode(Samples.htmlText, scope: .named) },
                hint: "Decodes all 2,125 named references from the HTML standard, plus numeric ones.",
                run: { input, mode, values in
                    if mode == "encode" {
                        return TransformResult(text: HTMLEntities.encode(input, scope: HTMLEntities.EncodeScope(rawValue: values["scope"]) ?? .unsafeOnly))
                    }
                    return TransformResult(text: HTMLEntities.decode(input))
                })
        case .backslash:
            return TransformSpec(
                tool: tool, modes: [.init(value: "escape", title: "Escape"), .init(value: "unescape", title: "Unescape")], decodeMode: "unescape",
                options: [.toggle("unicode", "Escape non-ASCII as \\u", default: false, modes: ["escape"])],
                inputTitle: { $0 == "escape" ? "Text" : "Escaped" }, outputTitle: { $0 == "escape" ? "Escaped" : "Text" },
                placeholder: { $0 == "escape" ? "Type or paste text to escape for a string literal." : "Paste text with \\n, \\t, \\\", \\u00e9, \\x41 or \\u{1F600} escapes." },
                sample: { $0 == "escape" ? Samples.escapeText : BackslashEscapes.escape(Samples.escapeText) },
                hint: "C-family escapes: JavaScript, Swift, Java, Go, Python and JSON strings.",
                run: { input, mode, values in
                    if mode == "escape" { return TransformResult(text: BackslashEscapes.escape(input, escapeUnicode: values.flag("unicode"))) }
                    return TransformResult(text: try BackslashEscapes.unescape(input))
                })
        case .htmlFormat, .xmlFormat:
            let dialect: MarkupFormatter.Dialect = tool == .htmlFormat ? .html : .xml
            return TransformSpec(
                tool: tool, modes: [.init(value: "beautify", title: "Beautify"), .init(value: "minify", title: "Minify")],
                options: [indentOption.restricted(to: ["beautify"]),
                          .toggle("comments", "Remove comments", default: false, modes: ["beautify"])],
                inputTitle: { _ in tool == .htmlFormat ? "HTML" : "XML" },
                outputTitle: { $0 == "beautify" ? "Beautified" : "Minified" },
                placeholder: { _ in tool == .htmlFormat ? "Paste HTML." : "Paste XML (also plist and SVG). It's validated as you type." },
                sample: { _ in tool == .htmlFormat ? Samples.html : Samples.xml },
                hint: tool == .htmlFormat ? "Inline elements stay on one line; <pre> and <textarea> are left exactly as written." : nil,
                run: { input, mode, values in
                    let text = mode == "minify"
                        ? try MarkupFormatter.minify(input, dialect: dialect)
                        : try MarkupFormatter.beautify(input, dialect: dialect, options: .init(indent: values.indent, removeComments: values.flag("comments")))
                    return TransformResult(text: text, summary: sizeSummary(input, text, valid: dialect == .xml ? "Valid XML" : nil))
                })
        case .cssFormat:
            return TransformSpec(
                tool: tool, modes: [.init(value: "beautify", title: "Beautify"), .init(value: "minify", title: "Minify")],
                options: [indentOption.restricted(to: ["beautify"])],
                inputTitle: { _ in "CSS" }, outputTitle: { $0 == "beautify" ? "Beautified" : "Minified" },
                placeholder: { _ in "Paste CSS, SCSS or LESS." },
                sample: { _ in Samples.css },
                hint: "Minify keeps /*! license */ comments.",
                run: { input, mode, values in
                    let text = mode == "minify" ? CSSFormatter.minify(input) : CSSFormatter.beautify(input, indent: values.indent)
                    return TransformResult(text: text, summary: sizeSummary(input, text, valid: nil))
                })
        case .sqlFormat:
            return TransformSpec(
                tool: tool, modes: [.init(value: "format", title: "Format"), .init(value: "minify", title: "Minify")],
                options: [indentOption.restricted(to: ["format"]),
                          .picker("case", "Keywords", SQLFormatter.KeywordCase.allCases.map { ($0.rawValue, $0.title) }, modes: ["format"])],
                inputTitle: { _ in "SQL" }, outputTitle: { $0 == "format" ? "Formatted" : "Minified" },
                placeholder: { _ in "Paste SQL: one statement or several, separated by semicolons." },
                sample: { _ in Samples.sql },
                hint: "Works with standard SQL, PostgreSQL, MySQL and SQLite syntax.",
                run: { input, mode, values in
                    let text = mode == "minify" ? SQLFormatter.minify(input)
                        : SQLFormatter.format(input, indent: values.indent, keywordCase: SQLFormatter.KeywordCase(rawValue: values["case"]) ?? .upper)
                    return TransformResult(text: text)
                })
        case .svgToCSS:
            return TransformSpec(
                tool: tool,
                options: [.picker("encoding", "Encoding", SVGToCSS.Encoding.allCases.map { ($0.rawValue, $0.title) },
                                  help: "URL encoding is usually smaller than Base64 and stays readable.")],
                inputTitle: { _ in "SVG" }, outputTitle: { _ in "CSS" },
                placeholder: { _ in "Paste SVG markup (<svg …>…</svg>)." },
                sample: { _ in Samples.svg },
                run: { input, _, values in
                    let css = try SVGToCSS.convert(input, encoding: SVGToCSS.Encoding(rawValue: values["encoding"]) ?? .url)
                    return TransformResult(text: css, summary: "\(formatBytes(css.utf8.count)) of CSS")
                })
        case .hexText:
            return TransformSpec(
                tool: tool, modes: [.init(value: "encode", title: "Text to Hex"), .init(value: "decode", title: "Hex to Text")], decodeMode: "decode",
                options: [.picker("separator", "Format", HexText.Separator.allCases.map { ($0.rawValue, $0.title) }, modes: ["encode"]),
                          .toggle("upper", "Uppercase", default: false, modes: ["encode"])],
                inputTitle: { $0 == "encode" ? "Text" : "Hex" }, outputTitle: { $0 == "encode" ? "Hex (UTF-8)" : "Text" },
                placeholder: { $0 == "encode" ? "Type or paste text. Its UTF-8 bytes are shown in hex." : "Paste hex bytes. Spaces, colons, 0x and \\x are ignored." },
                sample: { $0 == "encode" ? "Hello, Devkit ✓" : HexText.encode("Hello, Devkit ✓") },
                run: { input, mode, values in
                    if mode == "encode" {
                        let hex = HexText.encode(input, separator: HexText.Separator(rawValue: values["separator"]) ?? .space, uppercase: values.flag("upper"))
                        return TransformResult(text: hex, summary: count(input.utf8.count, "byte"))
                    }
                    let decoded = try HexText.decode(input)
                    if decoded.text == nil {
                        return TransformResult(text: decoded.display, summary: "\(count(decoded.data.count, "byte")). They aren't UTF-8 text, so they're shown as a hex dump.", isWarning: true)
                    }
                    return TransformResult(text: decoded.display, summary: count(decoded.data.count, "byte"))
                })
        case .lineSort:
            return TransformSpec(
                tool: tool,
                options: [.picker("sort", "Order", LineTools.Sort.allCases.map { ($0.rawValue, $0.title) }, default: LineTools.Sort.ascending.rawValue),
                          .toggle("dedupe", "Remove duplicates", default: true),
                          .toggle("case", "Case-sensitive", default: true),
                          .toggle("trim", "Trim spaces", default: false),
                          .toggle("empty", "Remove empty lines", default: true)],
                inputTitle: { _ in "Lines" }, outputTitle: { _ in "Result" },
                placeholder: { _ in "Paste lines to sort, dedupe or tidy." },
                sample: { _ in Samples.lines },
                run: { input, _, values in
                    var random = SystemRandomNumberGenerator()
                    let options = LineTools.Options(sort: LineTools.Sort(rawValue: values["sort"]) ?? .ascending, removeDuplicates: values.flag("dedupe"),
                                                    caseSensitive: values.flag("case"), trimWhitespace: values.flag("trim"), removeEmpty: values.flag("empty"))
                    let result = LineTools.process(input, options: options, random: &random)
                    var summary = "\(count(result.inputLines, "line")) → \(result.outputLines.formatted())"
                    if result.duplicatesRemoved > 0 { summary += ", \(count(result.duplicatesRemoved, "duplicate")) removed" }
                    return TransformResult(text: result.text, summary: summary)
                })
        case .gzip:
            return TransformSpec(
                tool: tool, modes: [.init(value: "compress", title: "Compress"), .init(value: "decompress", title: "Decompress")], decodeMode: "decompress",
                options: [.picker("format", "Format", GZip.Format.allCases.map { ($0.rawValue, $0.title) }, modes: ["compress"]),
                          .picker("output", "Output", [("base64", "Base64"), ("hex", "Hex")], modes: ["compress"])],
                inputTitle: { $0 == "compress" ? "Text" : "Compressed (Base64 or hex)" },
                outputTitle: { $0 == "compress" ? "Compressed" : "Text" },
                placeholder: { $0 == "compress" ? "Type or paste text to compress." : "Paste Base64 or hex of gzip, zlib or raw deflate data. The format is detected." },
                sample: { mode in
                    mode == "compress" ? Samples.lines : Base64.encode((try? GZip.compress(Data(Samples.lines.utf8))) ?? Data())
                },
                run: { input, mode, values in
                    if mode == "compress" {
                        let data = try GZip.compress(Data(input.utf8), format: GZip.Format(rawValue: values["format"]) ?? .gzip)
                        let shown = values["output"] == "hex" ? data.map { String(format: "%02x", $0) }.joined(separator: " ") : Base64.encode(data)
                        let ratio = input.utf8.isEmpty ? 0 : Double(data.count) / Double(input.utf8.count)
                        return TransformResult(text: shown, summary: "\(formatBytes(input.utf8.count)) → \(formatBytes(data.count)) (\(ratio.formatted(.percent.precision(.fractionLength(0)))))")
                    }
                    let trimmed = input.filter { !$0.isWhitespace }
                    let bytes: Data
                    // Hex that starts like gzip (1F) or zlib (78); otherwise Base64.
                    let looksHex: Bool = !trimmed.isEmpty && trimmed.count.isMultiple(of: 2) && trimmed.allSatisfy(\.isHexDigit)
                    let hexBytes: Data? = looksHex ? (try? HexText.bytes(from: trimmed)) : nil
                    let first: UInt8? = hexBytes?.first
                    if let hexBytes, first == 0x1F || first == 0x78 {
                        bytes = hexBytes
                    } else {
                        do { bytes = try Base64.decode(trimmed) } catch { throw GZip.GZipError(description: "That isn't Base64 or hex") }
                    }
                    let (data, format) = try GZip.decompress(bytes)
                    let decoded = DecodedBytes(data: data)
                    return TransformResult(text: decoded.display,
                                           summary: "\(format.title): \(formatBytes(bytes.count)) → \(formatBytes(data.count))" + (decoded.text == nil ? ". Not text, so shown as hex." : ""),
                                           isWarning: decoded.text == nil)
                })
        default:
            return nil
        }
    }
}

private func sizeSummary(_ input: String, _ output: String, valid: String?) -> String {
    let base = "\(formatBytes(input.utf8.count)) → \(formatBytes(output.utf8.count))"
    return valid.map { "\($0). \(base)" } ?? base
}

extension TransformOption {
    func restricted(to modes: Set<String>) -> TransformOption {
        var copy = self
        copy.modes = modes
        return copy
    }
}
