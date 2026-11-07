import AppKit
import Observation
import PDFKit
import PaperCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

struct CombineFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var pageCount: Int?
    var problem: String?
}

@Observable
@MainActor
final class CombineModel {
    var files: [CombineFile] = []
    var selection: Set<UUID> = []
    var interleave = false

    func add(_ urls: [URL]) {
        for url in urls where !files.contains(where: { $0.url == url }) {
            if PaperDocumentController.isImage(url) {
                files.append(CombineFile(url: url, pageCount: NSImage(contentsOf: url) == nil ? nil : 1,
                                         problem: NSImage(contentsOf: url) == nil ? "Can't read this image" : nil))
            } else if let document = PDFDocument(url: url) {
                files.append(CombineFile(url: url, pageCount: document.isLocked ? nil : document.pageCount,
                                         problem: document.isLocked ? "Password-protected: open and unlock it first" : nil))
            } else {
                files.append(CombineFile(url: url, pageCount: nil, problem: "Not a PDF or image Paper can read"))
            }
        }
        if files.count != 2 { interleave = false }
    }

    var usable: [CombineFile] { files.filter { $0.problem == nil } }
    var totalPages: Int { usable.compactMap(\.pageCount).reduce(0, +) }
}

/// File > Combine Files…: an ordered list of PDFs and images that becomes one new document.
@MainActor
enum CombineWindow {
    private static var window: NSWindow?

    static func show(with urls: [URL] = []) {
        if window == nil {
            let model = CombineModel()
            let view = CombineView(model: model, close: { window?.close() }, combine: { combine(model) })
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = "Combine Files"
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 480, height: 420))
            newWindow.center()
            if !Prefs.isTestSuite { newWindow.setFrameAutosaveName("CombineFiles") }
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func combine(_ model: CombineModel) {
        var documents: [PDFDocument] = []
        for file in model.usable {
            if PaperDocumentController.isImage(file.url) {
                guard let image = NSImage(contentsOf: file.url), let page = ImagePages.page(for: image) else { continue }
                let document = PDFDocument()
                document.insert(page, at: 0)
                documents.append(document)
            } else if let open = NSDocumentController.shared.document(for: file.url) as? PaperDocument, !open.pdf.isLocked {
                // Open in Paper: use what's on screen, including unsaved edits.
                documents.append(open.pdf)
            } else if let document = AnnotationTags.open(url: file.url), !document.isLocked {
                documents.append(document)
            }
        }
        guard !documents.isEmpty else { return }
        let finish = {
            let combined = PageOps.combine(documents, interleave: model.interleave && documents.count == 2)
            (NSDocumentController.shared as? PaperDocumentController)?.openUntitled(combined, name: "Combined")
            window?.close()
            model.files = []
        }
        let collisions = PageOps.collidingFieldNames(documents)
        guard !collisions.isEmpty, let window else { finish(); return }
        let alert = NSAlert()
        alert.messageText = "Some form fields have the same name in more than one file."
        alert.informativeText = "In the combined document, filling one of them fills the others too (\(collisions.prefix(3).joined(separator: ", "))\(collisions.count > 3 ? "…" : "")). Fill each form first, then use Export Flattened Copy, to keep them separate."
        alert.addButton(withTitle: "Combine Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { if response == .alertFirstButtonReturn { finish() } }
        }
    }
}

struct CombineView: View {
    @Bindable var model: CombineModel
    let close: () -> Void
    let combine: () -> Void
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.files.isEmpty {
                DropZone("Drop PDFs or images here", types: [.pdf, .image]) { urls in model.add(urls) }
                    .padding(Spacing.windowMargin)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.files) { file in
                        HStack(spacing: Spacing.s) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                .resizable().frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                if let problem = file.problem {
                                    Text(problem).font(.caption).foregroundStyle(.textRed)
                                } else if let count = file.pageCount {
                                    Text(count == 1 ? "1 page" : "\(count) pages").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                        .tag(file.id)
                        .accessibilityElement(children: .combine)
                    }
                    .onMove { model.files.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { model.files.remove(atOffsets: $0) }
                }
                .onDeleteCommand {
                    model.files.removeAll { model.selection.contains($0.id) }
                    model.selection = []
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.add(urls)
                    return true
                }
                .accessibilityLabel("Files to combine")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Toggle("Interleave pages (front and back scans)", isOn: $model.interleave)
                        .disabled(model.usable.count != 2)
                    Text("Takes page 1 of the first file, then the last page of the second, and so on.")
                        .font(.caption).foregroundStyle(.secondary)
                    // The status line lives here, not between the buttons, so the button row
                    // never truncates or wraps.
                    Text("Drag to reorder. \(model.totalPages == 1 ? "1 page" : "\(model.totalPages) pages") in all.")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .padding(.top, Spacing.xs)
                }
                .padding(.horizontal, Spacing.windowMargin)
                .padding(.vertical, Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack {
                Button("Add Files…", action: addFiles)
                Button("Add Open Documents") { model.add(Self.openDocumentURLs()) }
                    .disabled(Self.openDocumentURLs().allSatisfy { url in model.files.contains { $0.url == url } })
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Combine", action: combine)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.usable.isEmpty)
            }
            // Same leading edge as the interleave option above it.
            .padding(.horizontal, Spacing.windowMargin)
            .padding(.vertical, Spacing.m)
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    /// PDFs open in Paper that have been saved somewhere, front window first.
    static func openDocumentURLs() -> [URL] {
        NSApp.orderedDocuments.compactMap { $0.fileURL }.filter { !PaperDocumentController.isImage($0) }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf] + PaperDocumentController.imageTypes
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        model.add(panel.urls)
    }
}
