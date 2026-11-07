import DevkitCore
import SlopKit
import SwiftUI

// Tools built around a text input and a text output: JSON, Base64, URL, Hash, Text Case.

private let pastePrompt = "or press ⇧⌘V to paste and detect what's on the clipboard."

struct JSONToolView: View {
    @Bindable var model: JSONToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar(isBusy: model.job.isBusy) {
                Picker("Style", selection: $model.style) {
                    ForEach(JSONFormatter.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Style")
                Picker("Indent", selection: $model.indent) {
                    ForEach(JSONFormatter.Indent.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                .disabled(model.style == .minified)
                Toggle("Sort keys", isOn: $model.sortKeys)
            }
            SplitPanes {
                Pane("Input", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Paste JSON, \(pastePrompt)",
                                accessibilityLabel: "JSON input", handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane("Output", accessory: {
                    CopyButton(label: "Output") { app.copyOutput() }.disabled(model.output.isEmpty)
                }) {
                    CodeTextView(text: .constant(model.shownOutput), isEditable: false,
                                 accessibilityLabel: "Formatted JSON", styles: model.styles,
                                 stylesVersion: model.stylesVersion)
                }
            }
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let error = model.error {
            StatusLine(kind: .error, text: error.description,
                       action: ("Show in Input", { model.editor.revealUTF8Offset(error.offset) }))
        } else if !model.output.isEmpty {
            let base = "Valid JSON, \(model.lineCount.formatted()) \(model.lineCount == 1 ? "line" : "lines"), \(formatBytes(model.output.utf8.count))"
            if let warning = model.warnings.first {
                StatusLine(kind: .warning, text: base + ". " + warning + (model.warnings.count > 1 ? " (+\(model.warnings.count - 1) more)" : ""))
            } else if model.isClipped {
                StatusLine(kind: .success, text: base + ". Showing the first \(formatBytes(DisplayLimit.bytes)); Copy Output copies all of it.")
            } else {
                StatusLine(kind: .success, text: base, hint: "⇧⌘C copies the output")
            }
        } else {
            StatusLine(kind: .info, text: "", hint: "Strict JSON (RFC 8259). Key order and numbers are kept exactly.")
        }
    }
}

struct Base64ToolView: View {
    @Bindable var model: Base64ToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar(isBusy: model.job.isBusy) {
                Picker("Mode", selection: $model.mode) {
                    ForEach(CodingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Mode")
                if model.mode == .encode {
                    Toggle("URL-safe (base64url)", isOn: $model.urlSafe)
                    Toggle("Padding", isOn: $model.padding)
                } else {
                    ToolNote("Accepts standard and URL-safe Base64, with or without padding.")
                }
            }
            SplitPanes {
                Pane(model.mode == .encode ? "Text" : "Base64", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input,
                                placeholder: model.mode == .encode ? "Type or paste text to encode, \(pastePrompt)" : "Paste Base64 to decode, \(pastePrompt)",
                                accessibilityLabel: model.mode == .encode ? "Text to encode" : "Base64 to decode", handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane(model.mode == .encode ? "Base64" : (model.isHexDump ? "Bytes (hex)" : "Text"), accessory: {
                    CopyButton(label: "Output") { app.copyOutput() }.disabled(model.output.isEmpty)
                }) {
                    CodeTextView(text: .constant(model.shownOutput), isEditable: false,
                                 accessibilityLabel: model.mode == .encode ? "Base64 output" : "Decoded output")
                }
            }
            if let error = model.error {
                StatusLine(kind: .error, text: error)
            } else {
                StatusLine(kind: model.isHexDump ? .warning : .info, text: model.summary, hint: model.output.isEmpty ? nil : "⌘↩ uses the output as input")
            }
        }
    }
}

struct URLToolView: View {
    @Bindable var model: URLToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar {
                Picker("Mode", selection: $model.mode) {
                    ForEach(CodingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Mode")
                if model.mode == .encode {
                    Picker("Encode", selection: $model.scope) {
                        ForEach(URLCoding.Scope.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    .help("Component encodes everything but letters, digits and - . _ ~. Whole URL keeps : / ? # & = and other URL punctuation.")
                    Toggle("Spaces as +", isOn: $model.spaceAsPlus)
                } else {
                    Toggle("Treat + as a space", isOn: $model.plusAsSpace)
                        .help("Form data and query strings encode spaces as +.")
                }
            }
            SplitPanes {
                Pane(model.mode == .encode ? "Text" : "Encoded", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input,
                                placeholder: model.mode == .encode ? "Type or paste text to percent-encode, \(pastePrompt)" : "Paste percent-encoded text, \(pastePrompt)",
                                accessibilityLabel: model.mode == .encode ? "Text to encode" : "Text to decode", handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane(model.mode == .encode ? "Encoded" : "Decoded", accessory: {
                    CopyButton(label: "Output") { app.copyOutput() }.disabled(model.output.isEmpty)
                }) {
                    CodeTextView(text: .constant(model.output), isEditable: false, accessibilityLabel: "Output")
                }
            }
            if let error = model.error {
                StatusLine(kind: .error, text: error)
            } else {
                StatusLine(kind: .info, text: "", hint: model.output.isEmpty ? nil : "⌘↩ uses the output as input")
            }
        }
    }
}

struct HashToolView: View {
    @Bindable var model: HashToolModel
    let app: AppModel
    @State private var choosingFile = false

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar(isBusy: model.job.isBusy) {
                Picker("Format", selection: $model.encoding) {
                    ForEach(DigestEncoding.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Output format")
                Toggle("HMAC", isOn: $model.useHMAC)
                    .help("Hash with a secret key (HMAC) instead of a plain digest.")
                if model.useHMAC {
                    CodeField(text: $model.hmacKey, placeholder: "Key", accessibilityLabel: "HMAC key")
                        // A fixed width: the options row sizes controls to their ideal width.
                        .frame(width: 180, height: ToolMetrics.rowControlHeight)
                }
                Button("Hash a File…") { choosingFile = true }
            }
            SplitPanes {
                Pane(model.file == nil ? "Text" : "File", accessory: { InputActions(app: app) }) {
                    if let file = model.file {
                        FileCard(file: file) { model.cancelFile() }
                    } else {
                        InputEditor(text: $model.input,
                                    placeholder: "Type or paste text to hash (its UTF-8 bytes are hashed). To hash a file, drop it here, choose Hash a File…, or copy it in Finder and press ⇧⌘V.",
                                    accessibilityLabel: "Text to hash", handle: model.editor,
                                    onFileDrop: { model.hashFile($0) }) { app.clearInput() }
                    }
                }
            } second: {
                Pane(model.useHMAC ? "HMAC" : "Digests") {
                    VStack(spacing: 0) {
                        if model.rows.isEmpty {
                            EmptyResults(symbol: "number.square", title: "No Input",
                                         message: "Digests appear here as you type, or after you choose a file.",
                                         actionTitle: "Hash a File…") { choosingFile = true }
                        } else {
                            ResultsList(rows: model.rows, selection: $model.selectedRow,
                                        defaultSelection: HashAlgorithm.sha256.title,
                                        highlighted: model.matched?.title) { row in
                                app.copy(row.value, name: row.label)
                            }
                        }
                        Hairline()
                        HStack(spacing: Spacing.s) {
                            CodeField(text: $model.expected, placeholder: "Paste a checksum to compare",
                                      accessibilityLabel: "Checksum to compare")
                            if !model.expected.isEmpty, !model.rows.isEmpty {
                                if let matched = model.matched {
                                    Label("Matches \(matched.title)", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.textGreen)
                                } else {
                                    Label("No match", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.textOrange)
                                }
                            }
                        }
                        .font(.callout)
                        .padding(Spacing.s)
                    }
                }
            }
            StatusLine(kind: .info, text: model.useHMAC && model.hmacKey.isEmpty ? "Type a key to compute HMACs." : "",
                       hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.")
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result {
                let access = url.startAccessingSecurityScopedResource()
                model.hashFile(url)
                if access { url.stopAccessingSecurityScopedResource() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .devkitOpenFile)) { _ in
            choosingFile = true
        }
    }
}

struct FileCard: View {
    let file: HashToolModel.HashedFile
    let clear: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(file.url.lastPathComponent)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatBytes(Int(file.size)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if file.isHashing {
                ProgressView(value: file.progress)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Hashing progress")
            }
            if let error = file.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.textRed)
                    .multilineTextAlignment(.center)
            }
            if file.isHashing {
                Button("Cancel", action: clear)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Clear File", action: clear)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CaseToolView: View {
    @Bindable var model: CaseToolModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Each line is converted on its own. Words split at spaces, punctuation and case changes; acronyms stay together.")
            SplitPanes {
                Pane("Text", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input,
                                placeholder: "Type or paste words or identifiers. Each line is converted on its own.",
                                accessibilityLabel: "Text to convert", handle: model.editor) { app.clearInput() }
                }
            } second: {
                Pane("Cases") {
                    if model.rows.isEmpty {
                        EmptyResults(symbol: "textformat", title: "No Text", message: "Every case appears here as you type.")
                    } else {
                        ResultsList(rows: model.rows, selection: $model.selectedRow,
                                    defaultSelection: CaseConverter.Style.camel.title) { row in
                            app.copy(row.value, name: row.label)
                        }
                    }
                }
            }
            StatusLine(kind: .info, text: "", hint: model.rows.isEmpty ? nil : "⇧⌘C copies \(model.primaryOutputName). Double-click a row to copy it.")
        }
    }
}

extension Notification.Name {
    /// File ▸ Open… while the Hash tool is showing.
    static let devkitOpenFile = Notification.Name("devkitOpenFile")
}
