import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// Apply Redactions: choose options, write a new file (or replace after confirming),
/// verify it, then report. Nothing is written unless verification passes.
@MainActor
enum RedactionFlow {
    enum Destination: String, CaseIterable { case newFile, replace }

    static func start(document: PaperDocument, model: DocumentModel, window: NSWindow) {
        let summary = model.markSummary
        guard summary.markCount > 0 else { return }
        Sheet.present(on: window) { dismiss in
            ApplyRedactionsView(summary: summary, canReplace: document.fileURL != nil) { choice in
                dismiss()
                guard let choice else { return }
                DispatchQueue.main.async { choose(choice, document: document, window: window) }
            }
        }
    }

    struct Choice {
        var removeMetadata: Bool
        var destination: Destination
    }

    private static func choose(_ choice: Choice, document: PaperDocument, window: NSWindow) {
        switch choice.destination {
        case .newFile:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            let base = (document.displayName as NSString? ?? "Document").deletingPathExtension
            panel.nameFieldStringValue = "\(base) (redacted).pdf"
            if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
            panel.message = "The redacted copy is saved as a new file. Your original isn't changed."
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    guard response == .OK, let url = panel.url else { return }
                    run(choice, document: document, window: window, to: url, replacing: false)
                }
            }
        case .replace:
            guard let url = document.fileURL else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Replace “\(url.lastPathComponent)” with the redacted version?"
            alert.informativeText = "The marked content is removed for good. This can't be undone, though earlier versions stay in File > Revert To."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    guard response == .alertFirstButtonReturn else { return }
                    run(choice, document: document, window: window, to: url, replacing: true)
                }
            }
        }
    }

    private static func run(_ choice: Choice, document: PaperDocument, window: NSWindow, to url: URL, replacing: Bool) {
        guard let source = document.pdf.dataRepresentation() else {
            presentError(RedactionError.unreadable, window: window)
            return
        }
        let progress = Sheet.present(on: window) { _ in BusyView(text: "Removing marked content and checking the result…") }
        let options = RedactionOptions(removeMetadata: choice.removeMetadata)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(Data, RedactionReport), Error> in
                Result { try Redactor(options: options).apply(to: source) }
            }.value
            window.endSheet(progress)
            switch result {
            case .failure(let error):
                presentError(error, window: window)
            case .success(let (data, report)):
                do {
                    if replacing { try document.preserveVersion() }
                    try data.write(to: url, options: .atomic)
                } catch {
                    presentError(error, window: window)
                    return
                }
                if replacing {
                    try? document.revert(toContentsOf: url, ofType: "com.adobe.pdf")
                }
                showReport(report, url: url, replaced: replacing, window: window)
            }
        }
    }

    private static func showReport(_ report: RedactionReport, url: URL, replaced: Bool, window: NSWindow) {
        Sheet.present(on: window) { dismiss in
            RedactionReportView(report: report, url: url, replaced: replaced, dismiss: dismiss)
        }
    }

    static func presentError(_ error: Error, window: NSWindow) {
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}

extension PaperDocument {
    /// Keeps the current file as a version before it's replaced, so Revert To can reach it.
    func preserveVersion() throws {
        guard let url = fileURL else { return }
        _ = try? NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
    }
}

struct ApplyRedactionsView: View {
    let summary: MarkSummary
    let canReplace: Bool
    let finish: (RedactionFlow.Choice?) -> Void
    @State private var removeMetadata = true
    @State private var destination: RedactionFlow.Destination = .newFile

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "rectangle.fill.badge.xmark")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Apply \(summary.markCount == 1 ? "1 Redaction" : "\(summary.markCount) Redactions")").font(.headline)
                    Text("Marked text and images are permanently removed and replaced with black boxes. Notes and form fields are flattened into the page, and the result is checked before it's saved.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Remove document information (title, author, keywords)", isOn: $removeMetadata)
            Picker("Save to", selection: $destination) {
                Text("A new file (recommended)").tag(RedactionFlow.Destination.newFile)
                Text("The original file").tag(RedactionFlow.Destination.replace)
                    .disabled(!canReplace)
            }
            .pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button(destination == .newFile ? "Apply and Save…" : "Apply…") {
                    finish(.init(removeMetadata: removeMetadata, destination: destination))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }
}

struct RedactionReportView: View {
    let report: RedactionReport
    let url: URL
    let replaced: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.textGreen)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(replaced ? "Redacted “\(url.lastPathComponent)”" : "Saved “\(url.lastPathComponent)”").font(.headline)
                    Text("\(report.summary) \(report.verificationLine)")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach([report.rasterizedLine, report.outlineLine, report.metadataCleared ? "Document information was removed." : nil].compactMap { $0 }, id: \.self) { line in
                        Text(line).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
                Spacer()
                if replaced {
                    Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                    Button("Open") {
                        dismiss()
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }
}

struct BusyView: View {
    let text: String
    var body: some View {
        HStack(spacing: Spacing.m) {
            ProgressView().controlSize(.small)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(width: 420, alignment: .leading)
    }
}
