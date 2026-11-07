import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// Diagnostics for design reviews when the screen can't be captured (a locked screen, CI):
/// `PAPER_SNAPSHOT=<folder>` opens the generated fixtures in `PAPER_SNAPSHOT_FIXTURES`, walks
/// the document window through its main states and sheets in light and dark, writes a PNG of
/// Paper's own windows for each (never the screen), then quits. Use with
/// `PAPER_DEFAULTS_SUITE`, `PAPER_DATA_DIR` and `PAPER_FAKE_OCR=1`. Not used in normal runs.
@MainActor
enum Snapshots {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["PAPER_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var isActive: Bool { folder != nil }

    static func runIfAsked() {
        guard let folder, let fixtures = ProcessInfo.processInfo.environment["PAPER_SNAPSHOT_FIXTURES"] else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Never the Mac account's real name in review images.
        Prefs.defaults.set("Sample Reviewer", forKey: Prefs.authorName)
        // Work on a copy: the walk edits documents (highlights, OCR), and autosave would
        // otherwise write those edits into the fixtures.
        let source = URL(fileURLWithPath: fixtures, isDirectory: true)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("paper-snapshot-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.copyItem(at: source, to: base) } catch { return }
        Task {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                await walk(base: base, folder: folder, suffix: name)
            }
            NSApp.terminate(nil)
        }
    }

    private static func open(_ url: URL) async -> PaperWindowController? {
        await withCheckedContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                continuation.resume(returning: (document as? PaperDocument)?.windowController)
            }
        }
    }

    private static func pause(_ seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func walk(base: URL, folder: URL, suffix: String) async {
        guard let text = await open(base.appendingPathComponent("text.pdf")), let window = text.window else { return }
        window.setFrame(NSRect(x: 80, y: 80, width: 1240, height: 860), display: true)
        text.inspectorItem.isCollapsed = true
        text.setTool(.select)
        await pause(1.5)
        shoot(window, "01-document-\(suffix)", folder)

        text.showInspector(.document)
        await pause()
        shoot(window, "02-inspector-document-\(suffix)", folder)
        text.showInspector(.security)
        await pause()
        shoot(window, "03-inspector-security-\(suffix)", folder)

        text.inspectorItem.isCollapsed = true
        text.model.markupStyle = .highlight
        text.setTool(.highlight)
        await pause()
        shoot(window, "04-tool-highlight-\(suffix)", folder)
        text.model.shapeKind = .arrow
        text.setTool(.shape)
        await pause()
        shoot(window, "05-tool-shape-\(suffix)", folder)
        text.setTool(.select)

        // Find and Highlight: search, highlight every result, select one, inspect it.
        text.search("public sentence")
        await pause(1.2)
        text.highlightSearchResults(nil)
        await pause()
        shoot(window, "06-find-and-highlight-\(suffix)", folder)
        if let annotation = text.model.pdf.page(at: 0)?.annotations.first(where: { $0.type == "Highlight" }) {
            text.pdfView.select(annotation)
        }
        text.showInspector(.selection)
        await pause()
        shoot(window, "07-inspector-selection-\(suffix)", folder)
        text.inspectorItem.isCollapsed = true

        // Sheets.
        await sheet(on: window, "08-sheet-export-images-\(suffix)", folder) { _ in
            ExportImagesView(pageCount: 3, selectedCount: 1) { _ in }
        }
        await sheet(on: window, "09-sheet-signature-draw-\(suffix)", folder) { _ in SignaturePad { _ in } }
        await sheet(on: window, "09b-sheet-signature-type-\(suffix)", folder) { _ in
            SignaturePad(source: .type, typedName: "Sample Reviewer") { _ in }
        }
        let imported = ImportedSignature()
        imported.load(SnapshotArt.signaturePhoto(), name: "signature.jpg")
        await sheet(on: window, "10-sheet-signature-image-\(suffix)", folder) { _ in
            ImportedSignaturePreview(imported: imported)
        }
        await sheet(on: window, "15-sheet-headers-footers-\(suffix)", folder) { _ in
            HeadersFootersView(stamp: .pageNumbers, pageCount: 3, selectedCount: 1) { _ in }
        }
        await sheet(on: window, "16-sheet-apply-redactions-\(suffix)", folder) { _ in
            ApplyRedactionsView(summary: MarkSummary(markCount: 3, pageCount: 2), canReplace: true) { _ in }
        }
        let report = RedactionReport(areaCount: 3, pageCount: 2, rasterizedPages: [1], removedAnnotations: 0, metadataCleared: true)
        await sheet(on: window, "17-sheet-redaction-report-\(suffix)", folder) { dismiss in
            RedactionReportView(report: report, url: base.appendingPathComponent("text (redacted).pdf"), replaced: false, dismiss: dismiss)
        }
        await sheet(on: window, "18-sheet-split-\(suffix)", folder) { _ in SplitView(pageCount: 3, chapterCount: 0) { _ in } }
        let export = ExportProgress(total: 3)
        await sheet(on: window, "19-sheet-export-progress-\(suffix)", folder) { _ in ExportProgressView(progress: export) }
        await sheet(on: window, "20-sheet-busy-\(suffix)", folder) { _ in BusyView(text: "Removing marked content and checking the result…") }
        let progress = OCRProgress(total: 12)
        progress.page = 1
        await sheet(on: window, "11-sheet-ocr-progress-\(suffix)", folder) { _ in OCRProgressView(progress: progress) }
        await close(text)

        // Combine Files, empty and with files (one long name, one unreadable).
        for (label, urls) in [("empty", [URL]()), ("files", ["text.pdf", "long-100.pdf", "landscape-a4.pdf", "not-a-pdf.pdf"].map { base.appendingPathComponent($0) })] {
            let model = CombineModel()
            model.add(urls)
            let combine = NSWindow(contentViewController: NSHostingController(rootView: CombineView(model: model, close: {}, combine: {})))
            combine.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            combine.title = "Combine Files"
            combine.setContentSize(NSSize(width: 480, height: 420))
            combine.orderFront(nil)
            await pause()
            shoot(combine, "21-combine-\(label)-\(suffix)", folder)
            combine.close()
        }

        // Settings, General tab.
        let settings = NSWindow(contentViewController: NSHostingController(rootView:
            SlopSettings(info: AppInfo.current(fallbackName: "Paper"), isMenuBarApp: false) { PaperGeneralSettings() }))
        settings.styleMask = [.titled, .closable]
        settings.title = "Paper Settings"
        settings.orderFront(nil)
        await pause()
        shoot(settings, "22-settings-general-\(suffix)", folder)
        settings.close()

        // A scan: the notice, then Recognize Text (canned lines) makes it searchable.
        guard let scan = await open(base.appendingPathComponent("scan.pdf")), let scanWindow = scan.window else { return }
        scanWindow.setFrame(NSRect(x: 80, y: 80, width: 1240, height: 860), display: true)
        await pause(1.5)
        shoot(scanWindow, "12-scan-notice-\(suffix)", folder)
        await sheet(on: scanWindow, "13-sheet-ocr-options-\(suffix)", folder) { _ in
            OCROptionsView(scanCount: 1, pageCount: 1, currentPage: 1) { _ in }
        }
        OCRFlow.run(pages: [0], controller: scan, window: scanWindow)
        await pause(2)
        scan.search("invoice")
        await pause(1.2)
        shoot(scanWindow, "14-scan-after-ocr-search-\(suffix)", folder)
        await close(scan)
    }

    /// Closes without saving: the fixtures stay as generated.
    private static func close(_ controller: PaperWindowController) async {
        guard let document = controller.paperDocument else { return }
        document.undoManager?.removeAllActions()
        document.updateChangeCount(.changeCleared)
        document.close()
        await pause(0.5)
    }

    private static func sheet<Content: View>(on window: NSWindow, _ name: String, _ folder: URL,
                                             @ViewBuilder content: (@escaping () -> Void) -> Content) async {
        let sheet = Sheet.present(on: window, content: content)
        await pause()
        shoot(sheet, name, folder)
        window.endSheet(sheet)
        await pause(0.3)
    }

    /// Draws a window (frame, toolbar and content) into a PNG.
    static func shoot(_ window: NSWindow, _ name: String, _ folder: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
    }
}

/// The Image tab of the signature sheet with a picture already loaded.
struct ImportedSignaturePreview: View {
    let imported: ImportedSignature
    var body: some View {
        SignaturePad(source: .image, imported: imported) { _ in }
    }
}

/// A generated "photo" of a signature for snapshot runs (no real signatures anywhere).
enum SnapshotArt {
    static func signaturePhoto() -> CGImage {
        let width = 900, height = 320
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.93, green: 0.92, blue: 0.88, alpha: 1)) // lint:allow generated test photo (paper tone), not UI
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(red: 0.08, green: 0.1, blue: 0.3, alpha: 1)) // lint:allow generated test photo (ink), not UI
        context.setLineWidth(7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 120, y: 120))
        context.addCurve(to: CGPoint(x: 260, y: 230), control1: CGPoint(x: 150, y: 300), control2: CGPoint(x: 230, y: 260))
        context.addCurve(to: CGPoint(x: 330, y: 110), control1: CGPoint(x: 280, y: 180), control2: CGPoint(x: 250, y: 90))
        context.addCurve(to: CGPoint(x: 520, y: 170), control1: CGPoint(x: 400, y: 140), control2: CGPoint(x: 450, y: 220))
        context.addCurve(to: CGPoint(x: 780, y: 140), control1: CGPoint(x: 600, y: 110), control2: CGPoint(x: 700, y: 200))
        context.strokePath()
        context.move(to: CGPoint(x: 140, y: 80))
        context.addLine(to: CGPoint(x: 760, y: 95))
        context.strokePath()
        return context.makeImage()!
    }
}
