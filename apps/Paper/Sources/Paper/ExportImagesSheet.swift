import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// File > Export as Images…: format, resolution and which pages, then a folder.
@MainActor
enum ExportImagesSheet {
    enum Pages: String, CaseIterable, Identifiable {
        case all, selected
        var id: String { rawValue }
    }

    static func present(on window: NSWindow, document: PaperDocument, model: DocumentModel) {
        let selected = model.selectedIndexes
        Sheet.present(on: window) { dismiss in
            ExportImagesView(pageCount: model.pdf.pageCount, selectedCount: selected.count) { choice in
                dismiss()
                guard let choice else { return }
                let pages = choice.pages == .all ? IndexSet(integersIn: 0..<model.pdf.pageCount) : selected
                askForFolder(window: window, document: document, pages: pages, format: choice.format, dpi: choice.dpi)
            }
        }
    }

    struct Choice {
        var format: ImageExport.Format
        var dpi: Int
        var pages: Pages
    }

    private static func askForFolder(window: NSWindow, document: PaperDocument, pages: IndexSet, format: ImageExport.Format, dpi: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = pages.count == 1 ? "Choose a folder for the image." : "Choose a folder for the \(pages.count) images."
        if let folder = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let folder = panel.url, let data = document.pdf.dataRepresentation() else { return }
                run(data: data, pages: pages, format: format, dpi: dpi, folder: folder, base: Exporting.baseName(document), window: window)
            }
        }
    }

    /// Renders from a private copy of the document, off the main thread.
    static func run(data: Data, pages: IndexSet, format: ImageExport.Format, dpi: Int, folder: URL, base: String, window: NSWindow) {
        let progress = ExportProgress(total: pages.count)
        let sheet = Sheet.present(on: window) { _ in ExportProgressView(progress: progress) }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                Result {
                    guard let copy = PDFDocument(data: data) else { throw ImageExport.ExportError.renderFailed(page: 0) }
                    return try ImageExport.export(copy, pages: pages, format: format, dpi: dpi, to: folder, baseName: base) { done, _ in
                        Task { @MainActor in progress.done = done }
                        return !progress.isStopped
                    }
                }
            }.value
            window.endSheet(sheet)
            switch result {
            case .success(let urls):
                HUD.show(urls.count == 1 ? "Exported 1 image" : "Exported \(urls.count) images", systemImage: "photo.on.rectangle")
                if let first = urls.first { NSWorkspace.shared.activateFileViewerSelecting(urls.count == 1 ? [first] : urls) }
            case .failure(let error):
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }
}

@Observable
final class ExportProgress: @unchecked Sendable {
    let total: Int
    @MainActor var done = 0
    private let lock = NSLock()
    private var stopped = false
    init(total: Int) { self.total = total }

    var isStopped: Bool { lock.withLock { stopped } }
    func stop() { lock.withLock { stopped = true } }
}

struct ExportProgressView: View {
    let progress: ExportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Exporting \(progress.total == 1 ? "1 page" : "\(progress.total) pages")…")
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .accessibilityLabel("Export progress")
            HStack {
                Spacer()
                Button("Stop") { progress.stop() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 380)
    }
}

struct ExportImagesView: View {
    let pageCount: Int
    let selectedCount: Int
    let finish: (ExportImagesSheet.Choice?) -> Void
    @AppStorage(Prefs.imageFormat, store: Prefs.defaults) private var format = ImageExport.Format.png.rawValue
    @AppStorage(Prefs.imageDPI, store: Prefs.defaults) private var dpi = 150
    @State private var pages: ExportImagesSheet.Pages = .all

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Export as Images").font(.headline)
            Form {
                Picker("Format", selection: $format) {
                    ForEach(ImageExport.Format.available, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Resolution", selection: $dpi) {
                    ForEach(ImageExport.resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                }
                Picker("Pages", selection: $pages) {
                    Text("All \(pageCount) pages").tag(ExportImagesSheet.Pages.all)
                    Text(selectedCount == 1 ? "Selected page" : "Selected \(selectedCount) pages").tag(ExportImagesSheet.Pages.selected)
                }
                .pickerStyle(.radioGroup)
            }
            Text("One image per page, as it looks on screen, including annotations.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Export…") {
                    finish(.init(format: ImageExport.Format(rawValue: format) ?? .png, dpi: dpi, pages: pages))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 400)
    }
}
