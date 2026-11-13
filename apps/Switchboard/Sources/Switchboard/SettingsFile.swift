import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// General › Settings file: export everything to a readable JSON file, or import one (add to
/// what's here, or replace it), with a preview first.
struct SettingsFileRow: View {
    @Bindable var model: AppModel
    @State private var pending: PendingImport?
    @State private var showUndo = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.s) {
                // A menu bar app's Edit menu is never visible: keep the way back in reach.
                UndoRemovalButton(label: "Undo Import", isVisible: $showUndo)
                Button("Export…", action: export)
                Button("Import…", action: chooseImport)
            }
        } label: {
            Text("Settings file")
            Text("Your browsers, email apps, rules and rewrites as one readable JSON file, to keep or move to another Mac.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchboardOpenSheet)) { note in
            // Test hook: "import:/path" previews that file, "export:/path" writes one.
            guard let text = note.object as? String else { return }
            if text.hasPrefix("import:") { prepareImport(from: URL(fileURLWithPath: String(text.dropFirst(7)))) }
            if text.hasPrefix("export:") { export(to: URL(fileURLWithPath: String(text.dropFirst(7)))) }
        }
        .sheet(item: $pending) { item in
            ImportPreview(item: item, current: model.config) { plan, mode in
                model.applyImport(plan, mode: mode, undoManager: undoManager)
                showUndo = true
                HUD.show(mode == .replace ? "Settings replaced" : "Settings imported", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Switchboard Settings.json"
        panel.prompt = "Export"
        panel.message = "Export Switchboard's settings as a JSON file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export(to: url)
    }

    private func export(to url: URL) {
        do {
            try SettingsTransfer.export(model.config).write(to: url, options: .atomic)
            Diagnostics.record("exported settings to \(url.path)")
            HUD.show("Settings exported", systemImage: "square.and.arrow.up")
        } catch {
            HUD.show("Couldn't save the file. Choose another folder.", systemImage: "exclamationmark.triangle", duration: .seconds(3))
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose a Switchboard settings file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prepareImport(from: url)
    }

    private func prepareImport(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let incoming = try SettingsTransfer.read(data)
            pending = PendingImport(fileName: url.lastPathComponent, config: incoming)
        } catch SettingsTransfer.ReadError.newerFormat {
            HUD.show("That file is from a newer Switchboard. Update Switchboard, then import it.", systemImage: "exclamationmark.triangle", duration: .seconds(3))
        } catch {
            HUD.show("“\(url.lastPathComponent)” isn't a Switchboard settings file.", systemImage: "exclamationmark.triangle", duration: .seconds(3))
        }
    }
}

struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let config: Config
}

/// What an import will do, before it does it.
struct ImportPreview: View {
    let item: PendingImport
    let current: Config
    let onImport: (SettingsTransfer.Plan, SettingsTransfer.Mode) -> Void
    @State private var mode: SettingsTransfer.Mode = .merge
    @Environment(\.dismiss) private var dismiss

    private var plan: SettingsTransfer.Plan {
        SettingsTransfer.plan(importing: item.config, into: current, mode: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Import “\(item.fileName)”")
                .font(.headline)
            Picker("Import", selection: $mode) {
                Text("Add to my settings").tag(SettingsTransfer.Mode.merge)
                Text("Replace my settings").tag(SettingsTransfer.Mode.replace)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .replace ? "Replace" : "Import") {
                    onImport(plan, mode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .merge && plan.summary.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }

    private var description: String {
        let summary = plan.summary
        switch mode {
        case .merge:
            var text = summary.isEmpty ? "Everything in this file is already here." : "Adds \(summary.itemsText)."
            if summary.duplicateRules > 0 {
                text += summary.duplicateRules == 1 ? " 1 rule is already here." : " \(summary.duplicateRules) rules are already here."
            }
            return text + " New rules go after yours. Everything else stays as it is."
        case .replace:
            return "Your settings are replaced with the file's: \(summary.itemsText). You can undo this with ⌘Z."
        }
    }
}
