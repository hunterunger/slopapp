import AppKit
import PDFKit
import PaperCore
import SwiftUI

/// The review walk for editing content, forms, crop, certificate signatures, compare and
/// Word export (`PAPER_SNAPSHOT`, see `Snapshots`). It drives the same controller code the
/// tools do and writes what it made (edited, built, signed files) plus a log into the
/// snapshot folder. With `PAPER_SNAPSHOT_HANDSHAKE=<folder>`, each state waits for an
/// outside screenshot instead (`<name>.ready` → `<name>.done`), since PDF pages don't draw
/// into offscreen captures.
@MainActor
enum FeatureWalk {
    static var log: [String] = []

    static func note(_ line: String) { log.append(line) }

    static func capture(_ window: NSWindow, _ name: String, _ folder: URL, wholeApp: Bool = false) async {
        guard let handshake = ProcessInfo.processInfo.environment["PAPER_SNAPSHOT_HANDSHAKE"] else {
            Snapshots.shoot(window, name, folder)
            return
        }
        let dir = URL(fileURLWithPath: handshake, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let done = dir.appendingPathComponent(name + ".done")
        try? Data((wholeApp ? "" : window.title).utf8).write(to: dir.appendingPathComponent(name + ".ready"))
        for _ in 0..<150 {
            if FileManager.default.fileExists(atPath: done.path) { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        Snapshots.shoot(window, name, folder)
    }

    static func run(base: URL, folder: URL, suffix: String) async {
        log = ["walk \(suffix)"]
        defer { try? log.joined(separator: "\n").write(to: folder.appendingPathComponent("features-\(suffix).log"), atomically: true, encoding: .utf8) }
        let frame = NSRect(x: 80, y: 80, width: 1280, height: 860)

        // Editing text and images.
        if let edit = await Snapshots.open(base.appendingPathComponent("editable.pdf")), let window = edit.window {
            window.setFrame(frame, display: true)
            edit.inspectorItem.isCollapsed = true
            // The first window of a fresh launch becomes key a moment later, which would
            // end an edit opened before then.
            await Snapshots.pause(3)
            edit.setTool(.edit)
            await Snapshots.pause()
            await capture(window, "30-edit-tool-\(suffix)", folder)
            if let page = edit.model.pdf.page(at: 0),
               let block = edit.pdfView.content(of: page).blocks.first(where: { $0.text.contains("untouched") }) {
                edit.canvas.beginContentEditing(block, on: page)
                await Snapshots.pause()
                edit.canvas.replaceEditingText("untouched", with: "unchanged")
                await Snapshots.pause(0.3)
                await capture(window, "31-editing-text-\(suffix)", folder)
                let before = edit.pdfView.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero
                edit.canvas.endContentEditing(commit: true)
                await Snapshots.pause()
                let after = edit.pdfView.documentView?.enclosingScrollView?.contentView.bounds.origin ?? .zero
                note("scroll before \(NSStringFromPoint(before)) after \(NSStringFromPoint(after))")
                let text = edit.model.pdf.page(at: 0)?.string ?? ""
                note("edit text: unchanged=\(text.contains("unchanged")) untouched=\(text.contains("untouched"))")
                await capture(window, "32-edited-text-\(suffix)", folder)
                edit.paperDocument?.undoManager?.undo()
                note("after undo: untouched=\(edit.model.pdf.page(at: 0)?.string?.contains("untouched") == true)")
                edit.paperDocument?.undoManager?.redo()
                note("after redo: unchanged=\(edit.model.pdf.page(at: 0)?.string?.contains("unchanged") == true)")
            }
            if let page = edit.model.pdf.page(at: 0), let image = edit.pdfView.content(of: page).images.first {
                let target = ImageTarget(page: page, image: image)
                edit.model.imageTarget = target
                edit.canvas.refreshOverlay()
                await Snapshots.pause()
                await capture(window, "33-image-selected-\(suffix)", folder)
                edit.canvasMoveImage(target, to: CGRect(x: image.rect.minX + 260, y: image.rect.minY - 30, width: image.rect.width * 0.75, height: image.rect.height * 0.75))
                await Snapshots.pause()
                note("image moved: images=\(edit.pdfView.content(of: edit.model.pdf.page(at: 0)!).images.map { NSStringFromRect($0.rect) })")
                await capture(window, "34-image-moved-\(suffix)", folder)
            }
            if let data = try? edit.paperDocument?.data(ofType: "com.adobe.pdf") {
                try? data.write(to: folder.appendingPathComponent("edited-\(suffix).pdf"))
            }
            if let source = edit.model.pdf.dataRepresentation(), let pdf = PDFDocument(data: source) {
                try? OfficeExport.docx(pdf, title: "editable").write(to: folder.appendingPathComponent("editable-\(suffix).docx"))
            }
            await Snapshots.close(edit)
        }

        // A font that isn't on this Mac.
        if let missing = await Snapshots.open(base.appendingPathComponent("missing-font.pdf")), let window = missing.window {
            window.setFrame(frame, display: true)
            await Snapshots.pause(1.2)
            missing.setTool(.edit)
            if let page = missing.model.pdf.page(at: 0), let block = missing.pdfView.content(of: page).blocks.first {
                missing.canvas.beginContentEditing(block, on: page)
                await Snapshots.pause()
                note("missing font notice: \(missing.model.editNotice ?? "none")")
                await capture(window, "35-missing-font-\(suffix)", folder)
                missing.canvas.endContentEditing(commit: false)
            }
            await Snapshots.close(missing)
        }

        // Building a form with a calculated total.
        if let form = await Snapshots.open(base.appendingPathComponent("text.pdf")), let window = form.window, let page = form.model.pdf.page(at: 0) {
            window.setFrame(frame, display: true)
            form.inspectorItem.isCollapsed = true
            await Snapshots.pause(1.2)
            form.model.formKind = .text
            form.setTool(.form)
            await capture(window, "36-form-tool-\(suffix)", folder)
            for (index, name) in ["qty", "price", "total"].enumerated() {
                form.canvasCreateField(on: page, rect: CGRect(x: 360, y: 340 - CGFloat(index) * 34, width: 120, height: 22))
                form.renameSelectedField(name)
            }
            form.model.formKind = .checkbox
            form.canvasCreateField(on: page, rect: CGRect(x: 72, y: 340, width: 14, height: 14))
            form.model.formKind = .radio
            form.canvasCreateField(on: page, rect: CGRect(x: 72, y: 300, width: 14, height: 14))
            form.canvasCreateField(on: page, rect: CGRect(x: 110, y: 300, width: 14, height: 14))
            form.model.formKind = .dropdown
            form.canvasCreateField(on: page, rect: CGRect(x: 72, y: 250, width: 140, height: 22))
            form.model.formKind = .signature
            form.canvasCreateField(on: page, rect: CGRect(x: 72, y: 120, width: 220, height: 56))
            let widgets = FormFields.widgets(in: form.model.pdf).map(\.annotation)
            widgets.first { $0.fieldName == "qty" }?.widgetStringValue = "3"
            widgets.first { $0.fieldName == "price" }?.widgetStringValue = "4.50"
            form.editor.setCalculation(FieldCalculation(.formula("qty * price"), decimals: 2), for: "total")
            form.canvasFormMayHaveChanged()
            note("total = \(widgets.first { $0.fieldName == "total" }?.widgetStringValue ?? "nil")")
            if let total = widgets.first(where: { $0.fieldName == "total" }) { form.pdfView.select(total) }
            form.showInspector(.selection)
            await Snapshots.pause()
            await capture(window, "37-field-inspector-\(suffix)", folder)
            form.showSidebar(.fields)
            await Snapshots.pause()
            await capture(window, "38-fields-sidebar-\(suffix)", folder)
            if let data = try? form.paperDocument?.data(ofType: "com.adobe.pdf") {
                let url = folder.appendingPathComponent("form-built-\(suffix).pdf")
                try? data.write(to: url)
                note("form scripts read back: \(FormScripts.read(from: data).calculations.keys.sorted())")
            }
            // Crop the same page.
            form.inspectorItem.isCollapsed = true
            form.showSidebar(.thumbnails)
            form.setTool(.crop)
            form.model.cropDraft = CropDraft(page: page, rect: CGRect(x: 40, y: 380, width: 532, height: 350))
            form.canvas.refreshOverlay()
            await Snapshots.pause()
            await capture(window, "40-crop-draft-\(suffix)", folder)
            form.applyCrop(.page)
            await Snapshots.pause()
            note("crop box: \(NSStringFromRect(page.bounds(for: .cropBox)))")
            await capture(window, "41-cropped-\(suffix)", folder)
            await Snapshots.close(form)
        }

        // Certificate signatures: the sheet, a signed file, a tampered copy.
        if let text = await Snapshots.open(base.appendingPathComponent("text.pdf")), let window = text.window {
            window.setFrame(frame, display: true)
            await Snapshots.pause(1.2)
            let identities = IdentityStore.identities()
            note("identities: \(identities.map(\.name))")
            let sheet = Sheet.present(on: window) { _ in
                CertificateSignView(identities: identities, signatures: [], signsField: nil) { _ in }
            }
            await Snapshots.pause()
            await capture(sheet, "42-sheet-certificate-\(suffix)", folder, wholeApp: true)
            window.endSheet(sheet)
            await Snapshots.pause(0.3)
            if let identity = identities.first, let source = try? text.paperDocument?.data(ofType: "com.adobe.pdf") {
                do {
                    let signer = try KeySigner(identity: identity.identity)
                    let request = SignatureRequest(placement: .new(page: 0, rect: CGRect(x: 320, y: 80, width: 230, height: 60)),
                                                   signerName: identity.name, reason: "Approved", location: "Test lab")
                    let signed = try PDFSigner.sign(source, request: request, signer: signer)
                    let url = folder.appendingPathComponent("signed-\(suffix).pdf")
                    try signed.write(to: url)
                    var tampered = signed
                    if let range = tampered.range(of: Data("stream\n".utf8)) { tampered[range.upperBound + 12] ^= 0xFF }
                    try tampered.write(to: folder.appendingPathComponent("tampered-\(suffix).pdf"))
                    note("signed: \(SignatureValidator.validate(signed).map(\.summary))")
                } catch {
                    note("signing failed: \(error)")
                }
            }
            await Snapshots.close(text)
        }
        for (file, shot) in [("signed-\(suffix).pdf", "43-signed-\(suffix)"), ("tampered-\(suffix).pdf", "45-tampered-\(suffix)")] {
            let url = folder.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path), let signed = await Snapshots.open(url), let window = signed.window else { continue }
            window.setFrame(frame, display: true)
            await Snapshots.pause(1.2)
            signed.showInspector(.security)
            await Snapshots.pause()
            note("\(file): \(signed.model.signatures.map(\.summary))")
            await capture(window, shot, folder)
            await Snapshots.close(signed)
        }

        // Compare.
        if let original = PDFDocument(url: base.appendingPathComponent("text.pdf")),
           let revised = PDFDocument(url: base.appendingPathComponent("text-revised.pdf")) {
            CompareWindowController.show(original: original, originalName: "text.pdf", revised: revised, revisedName: "text-revised.pdf")
            await Snapshots.pause(2)
            if let window = NSApp.windows.first(where: { $0.title.hasPrefix("Compare") }) {
                window.setFrame(frame, display: true)
                await Snapshots.pause()
                await capture(window, "46-compare-\(suffix)", folder)
                window.close()
            }
        }
    }
}
