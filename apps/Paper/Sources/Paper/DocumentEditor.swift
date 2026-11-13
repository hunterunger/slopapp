import AppKit
import PDFKit
import PaperCore

/// Every change to a document goes through here, so each one is undoable and the
/// views refresh. Undo names follow the menu titles ("Undo Rotate Pages").
@MainActor
final class DocumentEditor {
    let model: DocumentModel
    weak var document: PaperDocument?
    /// Called after changes so the canvas can redraw what PDFKit doesn't.
    var onChange: (PDFPage?) -> Void = { _ in }
    var onPagesChange: () -> Void = {}

    init(model: DocumentModel, document: PaperDocument) {
        self.model = model
        self.document = document
    }

    var undoManager: UndoManager? { document?.undoManager }
    var pdf: PDFDocument { model.pdf }

    private func register(_ name: String, _ undo: @escaping @MainActor (DocumentEditor) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { undo(editor) }
        }
        if !undoManager.isUndoing, !undoManager.isRedoing { undoManager.setActionName(name) }
    }

    // MARK: Annotations

    func add(_ annotation: PDFAnnotation, to page: PDFPage, name: String) {
        page.addAnnotation(annotation)
        register(name) { $0.remove(annotation, from: page, name: name) }
        changed(page)
        if annotation.type == "Widget" { onFieldsChange() }
    }

    func remove(_ annotation: PDFAnnotation, from page: PDFPage, name: String = "Delete") {
        page.removeAnnotation(annotation)
        if model.selectedAnnotation === annotation { model.selectedAnnotation = nil }
        register(name) { $0.add(annotation, to: page, name: name) }
        changed(page)
        if annotation.type == "Widget" { onFieldsChange() }
    }

    func setBounds(_ annotation: PDFAnnotation, _ bounds: CGRect, name: String) {
        let old = annotation.bounds
        guard old != bounds else { return }
        if old.size == bounds.size {
            AnnotationGeometry.move(annotation, by: CGVector(dx: bounds.minX - old.minX, dy: bounds.minY - old.minY))
        } else {
            AnnotationGeometry.resize(annotation, to: bounds)
        }
        register(name) { $0.setBounds(annotation, old, name: name) }
        changed(annotation.page)
    }

    func setColor(_ annotation: PDFAnnotation, _ color: NSColor) {
        AnnotationGeometry.invalidateAppearance(annotation)
        if annotation.type == "FreeText" {
            let old = annotation.fontColor ?? .black
            annotation.fontColor = color
            register("Change Color") { $0.setColor(annotation, old) }
        } else {
            let old = annotation.color
            annotation.color = color
            if let fill = annotation.interiorColor, fill.alphaComponent > 0 {
                annotation.interiorColor = color.withAlphaComponent(fill.alphaComponent)
            }
            register("Change Color") { $0.setColor(annotation, old) }
        }
        changed(annotation.page)
    }

    func setFill(_ annotation: PDFAnnotation, _ fill: NSColor?) {
        AnnotationGeometry.invalidateAppearance(annotation)
        let old = annotation.interiorColor
        annotation.interiorColor = fill
        register("Change Fill") { $0.setFill(annotation, old) }
        changed(annotation.page)
    }

    func setLineWidth(_ annotation: PDFAnnotation, _ width: CGFloat) {
        AnnotationGeometry.invalidateAppearance(annotation)
        let old = annotation.border?.lineWidth ?? 1
        let border = annotation.border ?? PDFBorder()
        border.lineWidth = width
        annotation.border = border
        if annotation.type == "Ink", let paths = annotation.paths {
            for path in paths { path.lineWidth = width }
        }
        register("Change Line Width") { $0.setLineWidth(annotation, old) }
        changed(annotation.page)
    }

    func setFontSize(_ annotation: PDFAnnotation, _ size: CGFloat) {
        AnnotationGeometry.invalidateAppearance(annotation)
        let old = annotation.font?.pointSize ?? 12
        annotation.font = NSFont.systemFont(ofSize: size)
        let fitted = TextBoxLayout.size(for: annotation.contents ?? "", font: annotation.font!)
        let top = annotation.bounds.maxY
        annotation.bounds = CGRect(x: annotation.bounds.minX, y: top - fitted.height, width: fitted.width, height: fitted.height)
        register("Change Font Size") { $0.setFontSize(annotation, old) }
        changed(annotation.page)
    }

    func setContents(_ annotation: PDFAnnotation, _ text: String, name: String = "Edit Text") {
        let old = annotation.contents ?? ""
        guard old != text else { return }
        let oldBounds = annotation.bounds
        AnnotationGeometry.invalidateAppearance(annotation)
        annotation.contents = text
        if annotation.type == "FreeText", let font = annotation.font {
            let size = TextBoxLayout.size(for: text, font: font)
            annotation.bounds = CGRect(x: oldBounds.minX, y: oldBounds.maxY - size.height, width: max(size.width, oldBounds.width), height: size.height)
        }
        register(name) { editor in
            editor.setContents(annotation, old, name: name)
            annotation.bounds = oldBounds
        }
        changed(annotation.page)
    }

    func setAuthor(_ annotation: PDFAnnotation, _ name: String) {
        let old = annotation.userName ?? ""
        let new = name.trimmingCharacters(in: .whitespaces)
        guard old != new else { return }
        annotation.userName = new.isEmpty ? nil : new
        register("Change Author") { $0.setAuthor(annotation, old) }
        changed(annotation.page)
    }

    func setFormValue(_ annotation: PDFAnnotation, old: FormTracker.Value) {
        let new = FormTracker.value(of: annotation)
        register("Fill Form") { editor in
            FormTracker.apply(old, to: annotation)
            editor.document?.formTracker.record(annotation)
            editor.setFormValue(annotation, old: new)
            editor.changed(annotation.page)
        }
        changed(annotation.page)
    }

    /// Several changes as one undo step ("Mark 12 Results").
    func group(_ name: String, _ body: () -> Void) {
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.setActionName(name)
        undoManager?.endUndoGrouping()
    }

    private func changed(_ page: PDFPage?) {
        model.touch(page)
        model.refreshMarks()
        onChange(page)
    }

    // MARK: Pages

    func reorder(_ order: [Int], name: String) {
        guard order != PageOrder.identity(order.count) else { return }
        let selected = model.selectedIndexes
        PageOps.reorder(pdf, to: order)
        model.refreshPages()
        model.selectPages(PageOrder.newIndexes(of: selected, in: order))
        register(name) { $0.reorder(PageOrder.inverse(order), name: name) }
        onPagesChange()
    }

    func rotate(_ indexes: IndexSet, by degrees: Int) {
        PageOps.rotate(pdf, pages: indexes, by: degrees)
        for index in indexes { model.touch(pdf.page(at: index)) }
        register(degrees > 0 ? "Rotate Right" : "Rotate Left") { $0.rotate(indexes, by: -degrees) }
        onPagesChange()
    }

    func delete(_ indexes: IndexSet) {
        guard indexes.count < pdf.pageCount else { return }
        let removed = PageOps.remove(pdf, pages: indexes)
        model.refreshPages()
        register(indexes.count == 1 ? "Delete Page" : "Delete Pages") { editor in
            editor.insert(removed, name: indexes.count == 1 ? "Delete Page" : "Delete Pages")
        }
        onPagesChange()
    }

    func insert(_ pages: [(index: Int, page: PDFPage)], name: String) {
        PageOps.insert(pdf, pages: pages)
        model.refreshPages()
        model.selectPages(IndexSet(pages.map(\.index)))
        let indexes = IndexSet(pages.map(\.index))
        register(name) { $0.removeInserted(indexes, name: name) }
        onPagesChange()
    }

    private func removeInserted(_ indexes: IndexSet, name: String) {
        let removed = PageOps.remove(pdf, pages: indexes)
        model.refreshPages()
        register(name) { $0.insert(removed, name: name) }
        onPagesChange()
    }

    /// Inserts copies of `source` pages at `index` (another document, an image, a blank page).
    func insert(pages newPages: [PDFPage], at index: Int, name: String) {
        let items = newPages.enumerated().map { (index: index + $0.offset, page: $0.element) }
        insert(items, name: name)
    }

    /// Swaps pages for rebuilt ones (OCR text layer, stamped headers). Annotations move to the
    /// new page; undo swaps the originals back with their annotations.
    /// Remembers what's in view before pages are swapped and returns how to get back there
    /// (a swapped page is a new object, and PDFView would otherwise jump).
    var positionKeeper: () -> () -> Void = { {} }

    func replace(_ replacements: [(index: Int, page: PDFPage)], name: String) {
        let restorePosition = positionKeeper()
        defer { restorePosition() }
        var originals: [(index: Int, page: PDFPage)] = []
        for item in replacements.sorted(by: { $0.index < $1.index }) {
            guard let old = pdf.page(at: item.index) else { continue }
            PageRewriter.moveAnnotations(from: old, to: item.page)
            pdf.removePage(at: item.index)
            pdf.insert(item.page, at: item.index)
            originals.append((item.index, old))
        }
        guard !originals.isEmpty else { return }
        model.refreshPages()
        register(name) { $0.replace(originals, name: name) }
        onPagesChange()
    }

    // MARK: Crop

    func crop(_ pages: [PDFPage], to rect: CGRect, reference: PDFPage, name: String) {
        let old = PageCrop.apply(rect, from: reference, to: pages)
        register(name) { $0.restoreCrop(old, name: name) }
        for page in pages { model.touch(page) }
        onPagesChange()
    }

    func removeCrop(_ pages: [PDFPage]) {
        let old = PageCrop.remove(from: pages)
        register("Remove Crop") { $0.restoreCrop(old, name: "Remove Crop") }
        for page in pages { model.touch(page) }
        onPagesChange()
    }

    private func restoreCrop(_ boxes: [(PDFPage, CGRect)], name: String) {
        let current = boxes.map { ($0.0, $0.0.bounds(for: .cropBox)) }
        for (page, box) in boxes { page.setBounds(box, for: .cropBox) }
        register(name) { $0.restoreCrop(current, name: name) }
        for (page, _) in boxes { model.touch(page) }
        onPagesChange()
    }

    // MARK: Form fields

    /// Called after field edits so the form tracker and calculations catch up.
    var onFieldsChange: () -> Void = {}

    /// One undoable change to a field: `set` applies a value, `get` reads the current one.
    func change<Value>(_ fields: [PDFAnnotation], _ name: String, get: @escaping (PDFAnnotation) -> Value,
                       set: @escaping (PDFAnnotation, Value) -> Void, to value: Value) {
        let old = fields.map(get)
        for field in fields { set(field, value) }
        register(name) { editor in
            editor.restore(fields, name, values: old, get: get, set: set)
        }
        for field in fields { changed(field.page) }
        onFieldsChange()
    }

    private func restore<Value>(_ fields: [PDFAnnotation], _ name: String, values: [Value], get: @escaping (PDFAnnotation) -> Value,
                                set: @escaping (PDFAnnotation, Value) -> Void) {
        let current = fields.map(get)
        for (field, value) in zip(fields, values) { set(field, value) }
        register(name) { $0.restore(fields, name, values: current, get: get, set: set) }
        for field in fields { changed(field.page) }
        onFieldsChange()
    }

    /// Renames a field (every widget of a radio group) and the calculations that read it.
    func renameField(_ fields: [PDFAnnotation], from old: String, to new: String) {
        guard old != new, !new.isEmpty else { return }
        let scripts = model.formScripts
        for field in fields {
            field.fieldName = new
            // A tooltip that was just the name follows it.
            if FormFieldFactory.tooltip(of: field) == old { FormFieldFactory.setTooltip(new, on: field) }
        }
        var renamed = scripts
        renamed.rename(old, to: new)
        setScriptsQuietly(renamed)
        register("Rename Field") { editor in
            editor.renameField(fields, from: new, to: old)
        }
        for field in fields { changed(field.page) }
        onFieldsChange()
    }

    func setCalculation(_ calculation: FieldCalculation?, for name: String) {
        var scripts = model.formScripts
        scripts.set(calculation, for: name)
        setScripts(scripts, name: calculation == nil ? "Remove Calculation" : "Change Calculation")
    }

    func setScripts(_ scripts: FormScripts, name: String) {
        let old = model.formScripts
        guard old != scripts else { return }
        setScriptsQuietly(scripts)
        register(name) { $0.setScripts(old, name: name) }
        onFieldsChange()
    }

    private func setScriptsQuietly(_ scripts: FormScripts) {
        model.formScripts = scripts
        document?.formScripts = scripts
        // Saving writes the scripts; mark the document edited even if no field changed.
        document?.updateChangeCount(.changeDone)
        model.annotationsRevision += 1
    }

    /// Reorders a page's fields (tab order).
    func reorderFields(on page: PDFPage, to order: [PDFAnnotation]) {
        let old = page.annotations.filter { $0.type == "Widget" }
        guard old.map(ObjectIdentifier.init) != order.map(ObjectIdentifier.init) else { return }
        FormFields.reorder(page, widgets: order)
        register("Change Tab Order") { $0.reorderFields(on: page, to: old) }
        changed(page)
        onFieldsChange()
    }

    // MARK: Document

    func setInfo(_ info: DocumentInfo) {
        let old = DocumentInfo(pdf)
        guard old != info else { return }
        info.apply(to: pdf)
        model.infoRevision += 1
        register("Change Document Info") { $0.setInfo(old) }
    }
}
