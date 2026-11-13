import AppKit
import PDFKit
import PaperCore
import SlopKit
import UniformTypeIdentifiers

@MainActor
enum Exporting {
    static func baseName(_ document: PaperDocument) -> String {
        ((document.displayName ?? "Document") as NSString).deletingPathExtension
    }

    /// Export Flattened Copy…: everything baked in, in a new file. Never in place.
    static func exportFlattened(document: PaperDocument, model: DocumentModel, window: NSWindow) {
        if model.markSummary.markCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Pending redactions aren't applied by flattening."
            alert.informativeText = "The flattened copy leaves out the marks, and the text under them is still there. To remove it, choose Apply Redactions instead."
            alert.addButton(withTitle: "Export Without Marks")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    if response == .alertFirstButtonReturn { askWhere(document: document, window: window) }
                }
            }
        } else {
            askWhere(document: document, window: window)
        }
    }

    private static func askWhere(document: PaperDocument, window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(baseName(document)) (flattened).pdf"
        if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        panel.message = "Annotations, signatures and form entries become part of the page and can't be edited or removed."
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let source = document.pdf.dataRepresentation() else { return }
                Task {
                    let result = await Task.detached(priority: .userInitiated) { Result { try Flattener.flatten(source) } }.value
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url, options: .atomic)
                            HUD.show("Saved flattened copy")
                        } catch {
                            NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                        }
                    case .failure(let error):
                        NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                    }
                }
            }
        }
    }

    /// Export Text…: plain text, or rich text (fonts, sizes, paragraphs) chosen in the panel.
    static func exportText(document: PaperDocument, window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(baseName(document)).txt"
        if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        let format = FormatChooser(panel: panel)
        panel.accessoryView = format.view
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                withExtendedLifetime(format) {}
                guard response == .OK, let url = panel.url else { return }
                do {
                    if format.isRich {
                        guard let data = OfficeExport.rtf(document.pdf) else { throw PaperError.writeFailed }
                        try data.write(to: url, options: .atomic)
                        HUD.show("Saved rich text")
                    } else {
                        let text = document.pdf.string ?? ""
                        try text.write(to: url, atomically: true, encoding: .utf8)
                        HUD.show(text.isEmpty ? "Saved (the document has no text)" : "Saved text")
                    }
                } catch {
                    NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    /// The Format pop-up under the save panel.
    @MainActor
    final class FormatChooser: NSObject {
        let view: NSView
        private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        private weak var panel: NSSavePanel?

        init(panel: NSSavePanel) {
            self.panel = panel
            let label = NSTextField(labelWithString: "Format:")
            popup.addItems(withTitles: ["Plain Text", "Rich Text (RTF)"])
            popup.setAccessibilityLabel("Format")
            let stack = NSStackView(views: [label, popup])
            stack.orientation = .horizontal
            stack.spacing = Spacing.s
            stack.edgeInsets = NSEdgeInsets(top: Spacing.m, left: Spacing.l, bottom: Spacing.m, right: Spacing.l)
            view = stack
            super.init()
            popup.target = self
            popup.action = #selector(changed)
        }

        var isRich: Bool { popup.indexOfSelectedItem == 1 }

        @objc private func changed() {
            guard let panel else { return }
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.allowedContentTypes = [isRich ? .rtf : .plainText]
            panel.nameFieldStringValue = base + (isRich ? ".rtf" : ".txt")
        }
    }

    /// Save Protected Copy…: a new file with the passwords and permissions from the
    /// inspector's Security tab. The open document isn't changed.
    static func saveProtected(document: PaperDocument, protection: Protection, window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(baseName(document)) (protected).pdf"
        if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        panel.message = protection.openPassword.isEmpty ? "Anyone can open the copy; the restrictions need the permissions password to lift."
            : "The copy asks for the password when it's opened."
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                do {
                    try protection.protect(document.pdf).write(to: url, options: .atomic)
                    HUD.show("Saved protected copy", systemImage: "lock.doc")
                } catch {
                    NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }
}
