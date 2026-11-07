import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// Recognize Text: makes scanned pages searchable and selectable by adding an invisible text
/// layer (Vision, on this Mac). Undoable; the pages look exactly the same afterwards.
@MainActor
enum OCRFlow {
    /// PAPER_FAKE_OCR=1 swaps Vision for canned lines (snapshot runs on machines where the
    /// first Vision call would take half a minute).
    static var recognizer: any TextRecognizing {
        ProcessInfo.processInfo.environment["PAPER_FAKE_OCR"] == "1" ? CannedRecognizer() : VisionTextRecognizer()
    }

    enum Scope: String, CaseIterable, Identifiable {
        case pagesWithoutText, currentPage
        var id: String { rawValue }
    }

    static func start(controller: PaperWindowController, window: NSWindow) {
        let pdf = controller.model.pdf
        let scans = (0..<pdf.pageCount).filter { pdf.page(at: $0).map(OCR.needsText) ?? false }
        let current = controller.model.currentPageIndex
        Sheet.present(on: window) { dismiss in
            OCROptionsView(scanCount: scans.count, pageCount: pdf.pageCount, currentPage: current + 1) { scope in
                dismiss()
                guard let scope else { return }
                let pages = scope == .currentPage ? [current] : scans
                run(pages: pages, controller: controller, window: window)
            }
        }
    }

    static func run(pages: [Int], controller: PaperWindowController, window: NSWindow) {
        guard !pages.isEmpty else { return }
        let progress = OCRProgress(total: pages.count)
        let sheet = Sheet.present(on: window) { _ in OCRProgressView(progress: progress) }
        let recognizer = recognizer
        Task {
            var replacements: [(index: Int, page: PDFPage)] = []
            var failure: Error?
            for (offset, index) in pages.enumerated() {
                guard !progress.stopped else { break }
                progress.done = offset
                progress.page = index + 1
                guard let page = controller.model.pdf.page(at: index), let image = OCR.displayImage(of: page) else { continue }
                let result = await Task.detached(priority: .userInitiated) { Result { try recognizer.recognize(image) } }.value
                switch result {
                case .success(let lines):
                    if !lines.isEmpty, let searchable = OCR.page(byAdding: lines, to: page) {
                        replacements.append((index, searchable))
                        progress.found += 1
                    }
                case .failure(let error):
                    failure = error
                }
                if failure != nil { break }
            }
            window.endSheet(sheet)
            if !replacements.isEmpty {
                controller.editor.replace(replacements, name: "Recognize Text")
                controller.textLayerChanged()
            }
            if let failure {
                NSAlert(error: failure).beginSheetModal(for: window, completionHandler: nil)
            } else if replacements.isEmpty {
                HUD.show("No text found", systemImage: "text.viewfinder")
            } else {
                let pagesText = replacements.count == 1 ? "1 page is" : "\(replacements.count) pages are"
                HUD.show("\(pagesText) now searchable", systemImage: "text.viewfinder")
            }
        }
    }
}

@Observable
@MainActor
final class OCRProgress {
    let total: Int
    var done = 0
    var page = 0
    var found = 0
    var stopped = false
    init(total: Int) { self.total = total }
}

struct OCROptionsView: View {
    let scanCount: Int
    let pageCount: Int
    let currentPage: Int
    let finish: (OCRFlow.Scope?) -> Void
    @State private var scope: OCRFlow.Scope = .pagesWithoutText

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Recognize Text").font(.headline)
            Text("Paper reads the text in scanned pages and adds it as an invisible layer, so you can search, select, copy and highlight it. The pages look the same. It all happens on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Picker("Pages", selection: $scope) {
                Text(scanCount == 0 ? "Pages without text (none)" : "Pages without text (\(scanCount) of \(pageCount))")
                    .tag(OCRFlow.Scope.pagesWithoutText)
                Text("Current page (\(currentPage))").tag(OCRFlow.Scope.currentPage)
            }
            .pickerStyle(.radioGroup)
            if scope == .currentPage, scanCount < pageCount {
                Text("If the page already has text, the recognized text is added on top of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Recognize Text") { finish(scope) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(scope == .pagesWithoutText && scanCount == 0)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440)
    }
}

struct OCRProgressView: View {
    let progress: OCRProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(progress.total == 1 ? "Recognizing text…" : "Recognizing text on page \(progress.page) (\(progress.done + 1) of \(progress.total))…")
                .monospacedDigit()
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .accessibilityLabel("Recognition progress")
            if progress.done == 0 {
                Text("The first page can take up to a minute while macOS prepares text recognition. Later pages are quick.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Stop") { progress.stopped = true }
                    .keyboardShortcut(.cancelAction)
                    .help("Keep the pages finished so far")
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}

/// Canned recognition for snapshot runs (PAPER_FAKE_OCR=1): one line across the top.
struct CannedRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        [RecognizedLine(text: "Scanned invoice number 55821", box: CGRect(x: 0.12, y: 0.84, width: 0.56, height: 0.04)),
         RecognizedLine(text: "Total due forty dollars", box: CGRect(x: 0.12, y: 0.78, width: 0.46, height: 0.04))]
    }
}
