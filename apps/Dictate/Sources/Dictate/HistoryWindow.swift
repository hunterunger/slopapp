import AppKit
import DictateCore
import SlopKit
import SwiftUI

/// Past dictations: search, copy, delete (with Undo), and teach a word to the vocabulary.
struct HistoryWindow: View {
    let model: AppModel
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmClear = false
    @State private var word = ""
    @Environment(\.undoManager) private var undoManager

    private var history: HistoryStore { model.history }
    private var results: [TranscriptEntry] { history.search(query) }
    private var selected: [TranscriptEntry] { results.filter { selection.contains($0.id) } }

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .searchable(text: $query, placement: .toolbar, prompt: "Search dictations")
            .toolbar {
                ToolbarItem {
                    Button("Copy", systemImage: "doc.on.doc") { copy() }
                        .disabled(selected.isEmpty)
                        .help("Copy (⌘C)")
                }
                ToolbarItem {
                    Button("Clear History…", systemImage: "trash") { confirmClear = true }
                        .disabled(history.entries.isEmpty)
                        .help("Clear history")
                }
            }
            .confirmationDialog("Clear all \(history.entries.count) dictations?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can undo this with ⌘Z while this window is open.")
            }
            .onCopyCommand { selected.isEmpty ? [] : [NSItemProvider(object: joinedText as NSString)] }
            .onDeleteCommand { delete() }
    }

    @ViewBuilder private var content: some View {
        if history.entries.isEmpty {
            ContentUnavailableView {
                Label(model.settings.saveHistory ? "No Dictations Yet" : "History Is Off", systemImage: "waveform")
            } description: {
                Text(model.settings.saveHistory
                     ? "What you dictate shows up here, so you can find and copy it again."
                     : "Turn it on to find and copy past dictations here.")
            } actions: {
                if !model.settings.saveHistory {
                    Button("Turn On History") { model.settings.saveHistory = true }
                }
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            VStack(spacing: 0) {
                List(results, selection: $selection) { entry in
                    HistoryRow(entry: entry)
                        .contextMenu {
                            Button("Copy") { copy([entry]) }
                            Button("Delete") { delete([entry.id]) }
                        }
                }
                .listStyle(.inset)
                if selected.count == 1, let entry = selected.first {
                    Hairline()
                    detail(entry)
                }
            }
        }
    }

    private func detail(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ScrollView {
                Text(entry.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            HStack(spacing: Spacing.s) {
                TextField("Add a word to the vocabulary", text: $word)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(teach)
                Button("Add Word", action: teach)
                    .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Adds it to the AI cleanup vocabulary so it's spelled this way")
            }
        }
        .padding(Spacing.l)
    }

    private var joinedText: String {
        selected.map(\.text).joined(separator: "\n\n")
    }

    private func copy(_ entries: [TranscriptEntry]? = nil) {
        let text = (entries ?? selected).map(\.text).joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        model.inserter.copy(text)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    private func delete(_ ids: Set<UUID>? = nil) {
        let ids = ids ?? Set(selected.map(\.id))
        guard !ids.isEmpty else { return }
        history.delete(ids: ids)
        selection.subtract(ids)
        registerUndo(ids.count == 1 ? "Delete Dictation" : "Delete Dictations")
    }

    private func clear() {
        history.clear()
        selection = []
        registerUndo("Clear History")
    }

    private func registerUndo(_ name: String) {
        undoManager?.registerUndo(withTarget: history) { history in
            MainActor.assumeIsolated { history.undoRemoval() }
        }
        undoManager?.setActionName(name)
    }

    private func teach() {
        let added = model.settings.teach(word)
        HUD.show(added ? "Added to vocabulary" : "Already in the vocabulary", systemImage: "text.badge.plus")
        word = ""
    }
}

struct HistoryRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(entry.text)
                .lineLimit(2)
                .truncationMode(.tail)
            HStack(spacing: Spacing.xs) {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                if let app = entry.appName, !app.isEmpty {
                    Text("·")
                    Text(app)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs / 2)
        .accessibilityElement(children: .combine)
    }
}
