import AppKit
import ShorthandCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Import macOS Text Replacements: from this Mac, or from the file System Settings writes
/// when rows are dragged out of Keyboard › Text Replacements. A preview with checkboxes;
/// macOS's own list is never changed.
struct ImportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ImportCandidate]?
    @State private var error: String?

    init(model: AppModel, rows: [ImportCandidate]? = nil) {
        self.model = model
        _rows = State(initialValue: rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Import Text Replacements")
                .font(.title2.bold())
            if let rows {
                preview(rows)
            } else {
                chooser
            }
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .frame(minHeight: 300)
    }

    // MARK: Choose a source

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Bring in the replacements you set up in System Settings › Keyboard. Nothing changes in macOS's own list.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Import from This Mac") { readFromThisMac() }
                .buttonStyle(.borderedProminent)
            DropZone("Or drop the file you dragged out of Text Replacements", systemImage: "doc.badge.plus",
                     types: [.propertyList], allowsMultiple: false) { urls in
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
        show(TextReplacementsImport.entries(fromDictionary: dictionary))
    }

    private func read(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't open that file. Check that it's still there."
            return
        }
        do {
            show(try TextReplacementsImport.entries(fromPlist: data))
        } catch {
            self.error = "That file isn't a Text Replacements export. In System Settings › Keyboard › Text Replacements, select the rows and drag them to the desktop to make one."
        }
    }

    private func show(_ entries: [(shortcut: String, phrase: String)]) {
        error = nil
        rows = TextReplacementsImport.candidates(entries, library: model.library)
        Diagnostics.record("import preview rows=\(entries.count)")
    }

    // MARK: Preview

    private func preview(_ rows: [ImportCandidate]) -> some View {
        let selected = rows.filter { $0.isSelected && $0.canSelect }.count
        return VStack(alignment: .leading, spacing: Spacing.m) {
            if rows.isEmpty {
                ContentUnavailableView("Nothing to Import", systemImage: "text.badge.xmark",
                                       description: Text("The list is empty."))
            } else {
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
                    .width(min: 80, ideal: 110)
                    TableColumn("Text") { $row in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.phrase.replacingOccurrences(of: "\n", with: " ")).lineLimit(1)
                            if let reason = row.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } rows: {
                    ForEach(Binding(get: { self.rows ?? [] }, set: { self.rows = $0 })) { $row in
                        TableRow($row)
                    }
                }
                .frame(minHeight: 220)
                .hairlineBorder(Rectangle())
            }
            Text("macOS keeps applying its own copies in apps that support them. To avoid doubles, you can remove them in Keyboard settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Keyboard Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
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
        model.edit { added = TextReplacementsImport.apply(rows, to: &$0) }
        Diagnostics.record("imported \(added)")
        dismiss()
        HUD.show(added == 1 ? "Imported 1 snippet" : "Imported \(added) snippets", systemImage: "square.and.arrow.down")
    }
}
