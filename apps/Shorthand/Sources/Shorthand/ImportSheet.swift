import AppKit
import ShorthandCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Import snippets: this Mac's Text Replacements, or a file from another expander
/// (TextExpander, espanso, a Text Replacements export, CSV) or Shorthand's own export. A
/// preview with checkboxes says what couldn't be carried over. macOS's own list is never changed.
struct ImportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ImportCandidate]?
    @State private var format: SnippetImport.Format?
    @State private var fileNotes: [String] = []
    @State private var error: String?

    /// A file to read as soon as the sheet opens (test hooks), taken once.
    @MainActor static var pendingFile: URL?

    init(model: AppModel, rows: [ImportCandidate]? = nil, format: SnippetImport.Format? = nil) {
        self.model = model
        _rows = State(initialValue: rows)
        _format = State(initialValue: format)
    }

    static let fileTypes: [UTType] = [.propertyList, .json, .yaml, .commaSeparatedText, .tabSeparatedText, .plainText,
                                      UTType(filenameExtension: "textexpander") ?? .data, UTType(filenameExtension: "yml") ?? .data]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(format.map { "Import from \($0.displayName)" } ?? "Import Snippets")
                .font(.title2.bold())
            if let rows {
                preview(rows)
            } else {
                chooser
            }
        }
        .padding(Spacing.xl)
        .frame(width: 600)
        .frame(minHeight: 320)
        .onAppear {
            if let file = Self.pendingFile, rows == nil {
                Self.pendingFile = nil
                read(file)
            }
        }
    }

    // MARK: Choose a source

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Bring in the Text Replacements you set up in System Settings › Keyboard. Nothing changes in macOS's own list.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Import Text Replacements from This Mac") { readFromThisMac() }
                    .buttonStyle(.borderedProminent)
            }
            DropZone("Or drop a file from TextExpander, espanso, Text Replacements or Shorthand, or a CSV",
                     systemImage: "doc.badge.plus", types: Self.fileTypes, allowsMultiple: false) { urls in
                if let url = urls.first { read(url) }
            }
            .frame(height: 150)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.textOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func readFromThisMac() {
        if let fixture = Diagnostics.fakeReplacements {
            read(fixture)
            return
        }
        if Diagnostics.isTestMode {
            // Test mode never reads the person's own list.
            error = "Test mode: set SHORTHAND_FAKE_REPLACEMENTS to a fixture file."
            return
        }
        let dictionary = NSSpellChecker.shared.userReplacementsDictionary
        guard !dictionary.isEmpty else {
            error = "This Mac has no text replacements, or macOS didn't share them. Try dragging them out of System Settings › Keyboard › Text Replacements and dropping the file here."
            return
        }
        show(TextReplacementsImport.importEntries(TextReplacementsImport.entries(fromDictionary: dictionary)), format: .textReplacements, notes: [])
    }

    private func read(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't open that file. Check that it's still there."
            return
        }
        do {
            let result = try SnippetImport.read(data, fileURL: url)
            show(result.entries, format: result.format, notes: result.fileNotes)
        } catch SnippetImport.ReadError.damaged(let why) {
            error = "That file couldn't be read: \(why)"
        } catch {
            self.error = "Shorthand doesn't recognise that file. It reads TextExpander group files (.textexpander), espanso match files (.yml), the file you get by dragging rows out of System Settings › Keyboard › Text Replacements, CSV files and Shorthand exports."
        }
    }

    private func show(_ entries: [ImportEntry], format: SnippetImport.Format, notes: [String]) {
        error = nil
        self.format = format
        fileNotes = notes
        rows = SnippetImport.candidates(entries, library: model.library)
        Diagnostics.record("import preview format=\(format.rawValue) rows=\(entries.count)")
    }

    // MARK: Preview

    private func preview(_ rows: [ImportCandidate]) -> some View {
        let selected = rows.filter { $0.isSelected && $0.canSelect }.count
        let partial = rows.filter { !$0.notes.isEmpty && $0.canSelect }.count
        let skipped = rows.filter { !$0.canSelect }.count
        return VStack(alignment: .leading, spacing: Spacing.m) {
            if rows.isEmpty {
                ContentUnavailableView("Nothing to Import", systemImage: "text.badge.xmark",
                                       description: Text("The file has no snippets."))
            } else {
                if partial > 0 || skipped > 0 || !fileNotes.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if partial > 0 {
                            Text(partial == 1 ? "1 snippet has parts Shorthand can't do; they're described under it."
                                 : "\(partial) snippets have parts Shorthand can't do; they're described under each.")
                        }
                        if skipped > 0 {
                            Text(skipped == 1 ? "1 can't be imported (the reason is under it)." : "\(skipped) can't be imported (the reason is under each).")
                        }
                        ForEach(fileNotes, id: \.self) { Text($0) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Table(of: Binding<ImportCandidate>.self) {
                    TableColumn("") { $row in
                        Toggle("Import \(row.shortcut)", isOn: $row.isSelected)
                            .labelsHidden()
                            .disabled(!row.canSelect)
                    }
                    .width(24)
                    TableColumn("Abbreviation") { $row in
                        Text(row.shortcut).font(.body.monospaced()).lineLimit(1)
                    }
                    .width(min: 80, ideal: 110, max: 160)
                    TableColumn("Text") { $row in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: Spacing.xs) {
                                if row.entry.richText != nil {
                                    Image(systemName: "textformat")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Formatted")
                                }
                                Text(row.phrase.isEmpty && row.entry.richText != nil ? "Image" : row.phrase.replacingOccurrences(of: "\n", with: " "))
                                    .lineLimit(2)
                            }
                            if let reason = row.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(row.notes, id: \.self) { note in
                                Text(note).font(.caption).foregroundStyle(.textOrange).lineLimit(2)
                            }
                        }
                    }
                } rows: {
                    ForEach(Binding(get: { self.rows ?? [] }, set: { self.rows = $0 })) { $row in
                        TableRow($row)
                    }
                }
                .frame(minHeight: 240)
                .hairlineBorder(Rectangle())
            }
            if format == .textReplacements {
                Text("macOS keeps applying its own copies in apps that support them. To avoid doubles, you can remove them in Keyboard settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if format == .textReplacements {
                    Button("Open Keyboard Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                } else {
                    Button("Choose Another File") {
                        self.rows = nil
                        self.format = nil
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selected == 1 ? "Import 1 Snippet" : "Import \(selected) Snippets") { importRows(rows) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == 0)
            }
        }
    }

    private func importRows(_ rows: [ImportCandidate]) {
        var added = 0
        model.edit { added = SnippetImport.apply(rows, to: &$0) }
        Diagnostics.record("imported \(added)")
        dismiss()
        HUD.show(added == 1 ? "Imported 1 snippet" : "Imported \(added) snippets", systemImage: "square.and.arrow.down")
    }
}
