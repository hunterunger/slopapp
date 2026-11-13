import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Actions for editing page content, cropping, building forms, certificate signatures,
/// comparing documents and exporting to Word.
extension PaperWindowController {
    // MARK: Editing text and images

    func canvasEditContent(_ block: TextBlock, on page: PDFPage) {
        guard !model.isReadOnly else { return }
        guard page.rotation == 0 else {
            HUD.show("Rotate the page upright to edit its text", systemImage: "rotate.right")
            return
        }
        guard block.isEditable else {
            HUD.show("Paper can only edit horizontal text", systemImage: "info.circle")
            return
        }
        canvas.beginContentEditing(block, on: page)
    }

    /// The text editor closed with `text` in place of `block`.
    func commitContentEdit(_ block: TextBlock, on page: PDFPage, text: NSAttributedString) {
        guard !text.isEqual(to: block.attributedText) || text.string != block.text else { return }
        let index = model.pdf.index(for: page)
        guard index != NSNotFound, let rebuilt = ContentEditor.replaceText(block, with: text, on: page) else {
            NSSound.beep()
            return
        }
        replacePage(at: index, with: rebuilt, name: "Edit Text")
        if !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           ContentEditor.lineCount(text, in: block) > block.lines.count {
            HUD.show("The text is longer than before and runs below the old paragraph", systemImage: "exclamationmark.triangle")
        }
    }

    func replacePage(at index: Int, with page: PDFPage, name: String) {
        editor.replace([(index: index, page: page)], name: name)
        pdfView.invalidateContent()
        paperDocument?.formTracker.reset(model.pdf)
    }

    func canvasMoveImage(_ target: ImageTarget, to rect: CGRect) {
        let index = model.pdf.index(for: target.page)
        guard index != NSNotFound, let rebuilt = ContentEditor.moveImage(target.image, to: rect, on: target.page) else { return }
        let resized = abs(rect.width - target.image.rect.width) > 0.5 || abs(rect.height - target.image.rect.height) > 0.5
        replacePage(at: index, with: rebuilt, name: resized ? "Resize Image" : "Move Image")
        selectImage(near: rect, on: rebuilt)
    }

    func canvasDeleteImage(_ target: ImageTarget) {
        let index = model.pdf.index(for: target.page)
        guard index != NSNotFound, let rebuilt = ContentEditor.deleteImage(target.image, on: target.page) else { return }
        replacePage(at: index, with: rebuilt, name: "Delete Image")
        model.imageTarget = nil
        canvas.refreshOverlay()
    }

    private func selectImage(near rect: CGRect, on page: PDFPage) {
        let images = pdfView.content(of: page).images
        model.imageTarget = images.min { a, b in
            abs(a.rect.midX - rect.midX) + abs(a.rect.midY - rect.midY) < abs(b.rect.midX - rect.midX) + abs(b.rect.midY - rect.midY)
        }.map { ImageTarget(page: page, image: $0) }
        canvas.refreshOverlay()
    }

    private func chooseImage(prompt: String, _ done: @escaping (CGImage) -> Void) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = prompt
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                done(cg)
            }
        }
    }

    @objc func replaceSelectedImage(_ sender: Any?) {
        guard let target = model.imageTarget else { return }
        chooseImage(prompt: "Replace") { [weak self] image in
            guard let self, let index = Optional(self.model.pdf.index(for: target.page)), index != NSNotFound,
                  let rebuilt = ContentEditor.replaceImage(target.image, with: image, on: target.page) else { return }
            self.replacePage(at: index, with: rebuilt, name: "Replace Image")
            self.selectImage(near: target.image.rect, on: rebuilt)
        }
    }

    @objc func deleteSelectedImage(_ sender: Any?) {
        if let target = model.imageTarget { canvasDeleteImage(target) }
    }

    /// Add Image…: an image becomes part of the page's content, in the middle of what's
    /// visible, then it's selected for moving and resizing.
    @objc func addImageToPage(_ sender: Any?) {
        guard !model.isReadOnly, let page = pdfView.currentPage else { return }
        chooseImage(prompt: "Add") { [weak self] image in
            guard let self else { return }
            let visible = self.pdfView.convert(self.pdfView.bounds, to: page).intersection(page.bounds(for: .cropBox))
            let area = visible.isNull ? page.bounds(for: .cropBox) : visible
            let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
            let box = CGRect(x: area.midX - area.width * 0.25, y: area.midY - area.height * 0.2, width: area.width * 0.5, height: area.height * 0.4)
            var rect = Signature.fitted(aspect: aspect, in: box)
            // Never larger than the image's own size at 72 dpi.
            if rect.width > CGFloat(image.width) { rect = Signature.fitted(aspect: aspect, in: CGRect(x: rect.midX - CGFloat(image.width) / 2, y: rect.midY - CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height))) }
            let index = self.model.pdf.index(for: page)
            guard index != NSNotFound, let rebuilt = ContentEditor.addImage(image, in: rect, on: page) else { return }
            self.setTool(.edit)
            self.replacePage(at: index, with: rebuilt, name: "Add Image")
            self.selectImage(near: rect, on: rebuilt)
        }
    }

    // MARK: Crop

    enum CropScope { case page, selected, all }

    func canvasApplyCrop() { applyCrop(.page) }

    func applyCrop(_ scope: CropScope) {
        guard let draft = model.cropDraft, let rect = PageCrop.clamped(draft.rect, to: draft.page) else { return }
        let pages: [PDFPage]
        switch scope {
        case .page: pages = [draft.page]
        case .selected: pages = pageSelection.compactMap { model.pdf.page(at: $0) }
        case .all: pages = (0..<model.pdf.pageCount).compactMap { model.pdf.page(at: $0) }
        }
        let name = pages.count == 1 ? "Crop Page" : "Crop \(pages.count) Pages"
        editor.crop(pages, to: rect, reference: draft.page, name: name)
        model.cropDraft = nil
        refit()
        canvas.refreshOverlay()
    }

    @objc func removeCrop(_ sender: Any?) {
        var pages = pageSelection.compactMap { model.pdf.page(at: $0) }.filter(PageCrop.isCropped)
        if pages.isEmpty { pages = (0..<model.pdf.pageCount).compactMap { model.pdf.page(at: $0) }.filter(PageCrop.isCropped) }
        guard !pages.isEmpty else { return }
        editor.removeCrop(pages)
        refit()
    }

    var hasCroppedPages: Bool {
        (0..<model.pdf.pageCount).contains { model.pdf.page(at: $0).map(PageCrop.isCropped) ?? false }
    }

    // MARK: Forms

    @objc func chooseFormKind(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let kind = FormFieldKind(rawValue: raw) else { return }
        model.formKind = kind
        setTool(.form)
    }

    @objc func showFieldsSidebar(_ sender: Any?) {
        showSidebar(.fields)
    }

    func canvasCreateField(on page: PDFPage, rect: CGRect) {
        guard !model.isReadOnly else { return }
        let kind = model.formKind
        let names = FormNames.all(in: model.pdf)
        let field: PDFAnnotation
        if kind == .radio {
            let group = model.lastRadioGroup.flatMap { names.contains($0) ? $0 : nil } ?? FormNames.unique(kind.baseName, existing: names)
            model.lastRadioGroup = group
            let taken = Set(FormFields.widgets(in: model.pdf).filter { $0.annotation.fieldName == group }.map(\.annotation.buttonWidgetStateString))
            var number = 1
            while taken.contains("Option \(number)") { number += 1 }
            field = FormFieldFactory.make(.radio, in: rect, name: group, exportValue: "Option \(number)")
        } else {
            field = FormFieldFactory.make(kind, in: rect, name: FormNames.unique(kind.baseName, existing: names))
        }
        editor.add(field, to: page, name: "Add \(kind.title)")
        pdfView.select(field)
    }

    /// After fields were added, removed or changed: the form tracker learns about them,
    /// facts update, calculations rerun.
    func fieldsChanged() {
        guard let document = paperDocument else { return }
        document.formTracker.reset(model.pdf)
        model.facts.formFieldCount = Set(FormFields.widgets(in: model.pdf).compactMap(\.annotation.fieldName)).count
        recalculate(recordUndo: false)
        model.annotationsRevision += 1
    }

    /// Runs the calculated fields. Their new values are picked up as form changes, so they
    /// undo together with the edit that caused them.
    @discardableResult
    func recalculate(recordUndo: Bool = true) -> Bool {
        guard !model.formScripts.isEmpty else { return false }
        let changed = model.formScripts.evaluate(FormFields.values(in: model.pdf))
        guard !changed.isEmpty else { return false }
        for item in FormFields.widgets(in: model.pdf) {
            guard let name = item.annotation.fieldName, let value = changed[name], item.annotation.widgetFieldType == .text else { continue }
            item.annotation.widgetStringValue = value
            model.touch(item.annotation.page)
        }
        pdfView.layoutDocumentView()
        if !recordUndo { paperDocument?.formTracker.reset(model.pdf) }
        return true
    }

    // MARK: Certificate signatures

    @objc func signWithCertificate(_ sender: Any?) {
        startCertificateSigning(field: nil)
    }

    func startCertificateSigning(field: String?) {
        guard let window, !model.isReadOnly else { return }
        commitEditing()
        let identities = IdentityStore.identities()
        let signatures = SignatureLibraryStore.shared.signatures
        Sheet.present(on: window) { dismiss in
            CertificateSignView(identities: identities, signatures: signatures, signsField: field) { [weak self] plan in
                dismiss()
                guard let self, let plan else { return }
                DispatchQueue.main.async {
                    if let field {
                        self.finishCertificateSigning(.field(field), plan: plan)
                    } else {
                        self.model.certificatePlan = plan
                        self.model.pendingSignature = nil
                        self.model.tool = .sign
                        self.toolbarController.refresh()
                        self.canvas.refreshOverlay()
                        self.window?.makeFirstResponder(self.pdfView)
                    }
                }
            }
        }
    }

    func canvasPlaceCertificateSignature(on page: PDFPage, rect: CGRect) {
        guard let plan = model.certificatePlan else { return }
        let index = model.pdf.index(for: page)
        guard index != NSNotFound else { return }
        finishCertificateSigning(.new(page: index, rect: rect), plan: plan)
    }

    func canvasSignatureFieldClicked(_ widget: PDFAnnotation, at point: NSPoint) {
        let menu = NSMenu(title: "Sign")
        let certificate = NSMenuItem(title: "Sign with Certificate…", action: #selector(signFieldWithCertificate(_:)), keyEquivalent: "")
        certificate.representedObject = widget.fieldName
        certificate.target = self
        menu.addItem(certificate)
        let signatures = SignatureLibraryStore.shared.signatures
        if !signatures.isEmpty { menu.addItem(.separator()) }
        for (offset, signature) in signatures.enumerated() {
            let kind = signature.kind == .initials ? "Initials" : "Signature"
            let item = NSMenuItem(title: "Place \(kind) \(offset + 1)", action: #selector(placeSignatureInField(_:)), keyEquivalent: "")
            item.representedObject = [signature.id.uuidString, widget.fieldName ?? ""]
            item.image = SignatureImage.image(signature, height: 24)
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: pdfView)
    }

    @objc func signFieldWithCertificate(_ sender: Any?) {
        startCertificateSigning(field: (sender as? NSMenuItem)?.representedObject as? String)
    }

    /// A saved (drawn) signature placed to fit an empty signature field.
    @objc func placeSignatureInField(_ sender: Any?) {
        guard let parts = (sender as? NSMenuItem)?.representedObject as? [String], parts.count == 2,
              let signature = SignatureLibraryStore.shared.signatures.first(where: { $0.id.uuidString == parts[0] }),
              let widget = FormFields.widgets(in: model.pdf).first(where: { $0.annotation.fieldName == parts[1] })?.annotation,
              let page = widget.page else { return }
        let fit = Signature.fitted(aspect: signature.aspect, in: widget.bounds.insetBy(dx: 4, dy: 4))
        guard let ink = signature.annotation(centeredAt: CGPoint(x: fit.midX, y: fit.midY), width: fit.width,
                                             color: NSColor(srgbRed: 0.05, green: 0.1, blue: 0.35, alpha: 1), factory: model.authorFactory) else { return }
        editor.add(ink, to: page, name: "Add Signature")
    }

    private func finishCertificateSigning(_ placement: SignatureRequest.Placement, plan: CertificatePlan) {
        model.certificatePlan = nil
        setTool(.select)
        guard let window, let document = paperDocument else { return }
        commitEditing()
        if document.password != nil {
            RedactionFlow.presentError(SigningError.encrypted, window: window)
            return
        }
        // Appending to the file on disk keeps earlier signatures valid; with unsaved changes
        // the document is written out first (which earlier signatures don't survive).
        let source: Data
        if !document.hasUnautosavedChanges, !document.isDocumentEdited, let url = document.fileURL, let onDisk = try? Data(contentsOf: url) {
            source = onDisk
        } else {
            guard let data = try? document.data(ofType: "com.adobe.pdf") else {
                RedactionFlow.presentError(PaperError.writeFailed, window: window)
                return
            }
            source = data
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(Exporting.baseName(document)) (signed).pdf"
        if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        panel.message = "The signed copy is a new file. Any change to it afterwards would break the signature."
        let request = SignatureRequest(placement: placement, signerName: plan.identity.name, reason: plan.reason, location: plan.location,
                                       date: Date(), ink: plan.ink?.strokes ?? [], inkAspect: plan.ink?.aspect ?? 3)
        let identity = plan.identity
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                let progress = Sheet.present(on: window) { _ in BusyView(text: "Signing and checking the signature…") }
                Task {
                    let result = await Task.detached(priority: .userInitiated) { () -> Result<(Data, SignatureStatus), Error> in
                        Result {
                            let signer = try KeySigner(identity: identity.identity)
                            let signed = try PDFSigner.sign(source, request: request, signer: signer)
                            guard let status = SignatureValidator.validate(signed).last(where: \.coversWholeFile), status.isValid else {
                                throw SigningError.signingFailed("the new signature didn't verify")
                            }
                            return (signed, status)
                        }
                    }.value
                    window.endSheet(progress)
                    switch result {
                    case .failure(let error):
                        RedactionFlow.presentError(error, window: window)
                    case .success(let (data, status)):
                        do { try data.write(to: url, options: .atomic) } catch {
                            RedactionFlow.presentError(error, window: window)
                            return
                        }
                        Sheet.present(on: window) { dismiss in SignedReportView(status: status, url: url, dismiss: dismiss) }
                    }
                }
            }
        }
    }

    // MARK: Compare

    @objc func compareDocuments(_ sender: Any?) {
        guard let window, let document = paperDocument else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.prompt = "Compare"
        panel.message = "Choose the version to compare “\(document.displayName ?? "this document")” with."
        if let folder = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { return }
                guard let other = AnnotationTags.open(url: url), !other.isLocked else {
                    RedactionFlow.presentError(PaperError.couldNotOpen(url.lastPathComponent), window: window)
                    return
                }
                CompareWindowController.show(original: self.model.pdf, originalName: document.displayName ?? "Document",
                                             revised: other, revisedName: url.lastPathComponent)
            }
        }
    }

    // MARK: Word and rich text

    @objc func exportWord(_ sender: Any?) {
        guard let window, let document = paperDocument, let source = document.pdf.dataRepresentation() else { return }
        commitEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = "\(Exporting.baseName(document)).docx"
        if let directory = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        panel.message = "Paragraphs, fonts and pictures come across; tables and columns become plain paragraphs."
        let title = document.displayName
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                let progress = Sheet.present(on: window) { _ in BusyView(text: "Exporting to Word…") }
                Task {
                    let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
                        Result {
                            guard let pdf = PDFDocument(data: source) else { throw PaperError.writeFailed }
                            return OfficeExport.docx(pdf, title: title)
                        }
                    }.value
                    window.endSheet(progress)
                    do {
                        try result.get().write(to: url, options: .atomic)
                        HUD.show("Saved Word document", systemImage: "doc.richtext")
                    } catch {
                        RedactionFlow.presentError(error, window: window)
                    }
                }
            }
        }
    }

    func validateEditingItem(_ item: NSMenuItem) -> Bool? {
        let editable = !model.isReadOnly && !model.isLocked
        switch item.action {
        case #selector(chooseFormKind(_:)):
            item.state = model.tool == .form && (item.representedObject as? String) == model.formKind.rawValue ? .on : .off
            return editable
        case #selector(addImageToPage(_:)), #selector(signWithCertificate(_:)), #selector(showFieldsSidebar(_:)):
            return editable
        case #selector(replaceSelectedImage(_:)), #selector(deleteSelectedImage(_:)):
            return editable && model.imageTarget != nil
        case #selector(removeCrop(_:)):
            return editable && hasCroppedPages
        case #selector(compareDocuments(_:)):
            return !model.isLocked && model.facts.allowsCopying
        case #selector(exportWord(_:)):
            return !model.isLocked && model.facts.allowsCopying
        default:
            return nil
        }
    }
}

// MARK: Sheets

/// Choose the certificate, reason and look of a certificate signature.
struct CertificateSignView: View {
    let identities: [SigningIdentity]
    let signatures: [Signature]
    let signsField: String?
    let finish: (CertificatePlan?) -> Void
    @State private var selection: Data?
    @State private var reason = ""
    @State private var location = ""
    @State private var ink: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Sign with a Certificate").font(.headline)
                    Text("A certificate signature proves who signed and that the document hasn't changed since. Paper saves the signed version as a new file.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if identities.isEmpty {
                Text("No signing certificates were found in your keychain. Your organization or a certificate authority can issue one; Keychain Access can also create a self-signed certificate for testing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Form {
                    Picker("Certificate", selection: $selection) {
                        ForEach(identities) { identity in
                            Text(label(identity)).tag(Optional(identity.id))
                        }
                    }
                    TextField("Reason", text: $reason, prompt: Text("Optional"))
                    TextField("Location", text: $location, prompt: Text("Optional"))
                    Picker("Shows", selection: $ink) {
                        Text("Name and date").tag(UUID?.none)
                        ForEach(Array(signatures.enumerated()), id: \.element.id) { offset, signature in
                            Text("My signature \(offset + 1), name and date").tag(Optional(signature.id))
                        }
                    }
                }
                .formStyle(.columns)
                if let identity = chosen, identity.isExpired {
                    Text("This certificate has expired. Viewers will show the signature as not valid.")
                        .font(.callout).foregroundStyle(.textRed)
                }
            }
            if signsField == nil, !identities.isEmpty {
                Text("Next, drag a box on the page where the signature should appear.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button(signsField == nil ? "Choose Where…" : "Sign…") {
                    guard let identity = chosen else { return }
                    finish(CertificatePlan(identity: identity, reason: reason, location: location,
                                           ink: signatures.first { $0.id == ink }))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480)
        .onAppear { selection = identities.first { !$0.isExpired }?.id ?? identities.first?.id }
    }

    private var chosen: SigningIdentity? { identities.first { $0.id == selection } }

    private func label(_ identity: SigningIdentity) -> String {
        var text = identity.name
        if let issuer = identity.issuer, issuer != identity.name { text += " — \(issuer)" }
        if let expires = identity.expires { text += identity.isExpired ? " (expired)" : " (until \(expires.formatted(date: .abbreviated, time: .omitted)))" }
        return text
    }
}

struct SignedReportView: View {
    let status: SignatureStatus
    let url: URL
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.textGreen)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Signed “\(url.lastPathComponent)”").font(.headline)
                    Text("Checked: the signature is valid and covers the whole file.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !status.trusted {
                        Text("Others will see that it's signed by \(status.signerName), but their viewer may warn that the certificate isn't from an authority it trusts.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Open") {
                    dismiss()
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }
}
