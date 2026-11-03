import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// Pages > Split Document…: every page, every N pages, or at each chapter, into a folder.
@MainActor
enum SplitSheet {
    enum Mode: String, CaseIterable { case everyPage, everyN, chapters }

    static func present(on window: NSWindow, pdf: PDFDocument, name: String, folder: URL?) {
        let chapters = PageOps.topLevelOutline(pdf)
        Sheet.present(on: window) { dismiss in
            SplitView(pageCount: pdf.pageCount, chapterCount: chapters.count) { choice in
                dismiss()
                guard let (mode, size) = choice else { return }
                DispatchQueue.main.async { chooseFolder(window: window, pdf: pdf, name: name, folder: folder, mode: mode, size: size, chapters: chapters) }
            }
        }
    }

    private static func chooseFolder(window: NSWindow, pdf: PDFDocument, name: String, folder: URL?, mode: Mode, size: Int,
                                     chapters: [(title: String, pageIndex: Int)]) {
        let panel = NSOpenPanel()
        if let folder { panel.directoryURL = folder }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Split Here"
        panel.message = "Choose a folder for the new files."
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let folder = panel.url else { return }
                write(pdf: pdf, name: name, mode: mode, size: size, chapters: chapters, to: folder, window: window)
            }
        }
    }

    private static func write(pdf: PDFDocument, name: String, mode: Mode, size: Int,
                              chapters: [(title: String, pageIndex: Int)], to folder: URL, window: NSWindow) {
        let base = (name as NSString).deletingPathExtension
        let ranges: [Range<Int>]
        switch mode {
        case .everyPage: ranges = PageOrder.chunks(pageCount: pdf.pageCount, every: 1)
        case .everyN: ranges = PageOrder.chunks(pageCount: pdf.pageCount, every: max(1, size))
        case .chapters: ranges = PageOrder.ranges(pageCount: pdf.pageCount, starts: chapters.map(\.pageIndex))
        }
        var written: [URL] = []
        do {
            for range in ranges {
                let part = PageOps.extract(pdf, pages: IndexSet(integersIn: range))
                var title = "\(base) \(PageOrder.label(range))"
                if mode == .chapters, let chapter = chapters.first(where: { $0.pageIndex == range.lowerBound }) {
                    title = "\(base) - \(chapter.title)"
                }
                let url = uniqueURL(folder.appendingPathComponent(sanitized(title)).appendingPathExtension("pdf"))
                guard let data = part.dataRepresentation() else { throw PaperError.writeFailed }
                try data.write(to: url, options: .atomic)
                written.append(url)
            }
        } catch {
            NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            return
        }
        HUD.show("Saved \(written.count) files")
        NSWorkspace.shared.activateFileViewerSelecting(written)
    }

    static func sanitized(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return String(cleaned.prefix(120))
    }

    static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var counter = 2
        let stem = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem) \(counter)").appendingPathExtension("pdf")
            counter += 1
        }
        return candidate
    }
}

struct SplitView: View {
    let pageCount: Int
    let chapterCount: Int
    let finish: ((SplitSheet.Mode, Int)?) -> Void
    @State private var mode: SplitSheet.Mode = .everyN
    @State private var size = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Split Document").font(.headline)
            Picker("Split", selection: $mode) {
                Text("Every page").tag(SplitSheet.Mode.everyPage)
                Text("Every \(size) pages").tag(SplitSheet.Mode.everyN)
                if chapterCount > 1 { Text("At each chapter (\(chapterCount))").tag(SplitSheet.Mode.chapters) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Stepper("Pages per file: \(size)", value: $size, in: 1...max(1, pageCount))
                .disabled(mode != .everyN)
                .monospacedDigit()
            Text(countText).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Split…") { finish((mode, size)) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 360)
    }

    private var countText: String {
        let count: Int = switch mode {
        case .everyPage: pageCount
        case .everyN: Int((Double(pageCount) / Double(max(size, 1))).rounded(.up))
        case .chapters: chapterCount
        }
        return "Makes \(count) \(count == 1 ? "file" : "files") from \(pageCount) pages. This document isn't changed."
    }
}
