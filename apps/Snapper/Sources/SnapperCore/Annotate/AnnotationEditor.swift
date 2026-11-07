import SlopKit
import CoreGraphics
import Foundation

/// Everything that makes up an edited capture, as one value so undo can snapshot it.
public struct AnnotationDocument: Equatable, Sendable {
    /// The capture's size in image points.
    public var imageSize: CGSize
    public var annotations: [Annotation] = []
    /// The kept part of the image (image points), or nil for all of it.
    public var crop: CGRect?
    /// A backdrop around the image (padding, gradient, shadow), or nil.
    public var background: CaptureBackground?

    public init(imageSize: CGSize, annotations: [Annotation] = [], crop: CGRect? = nil, background: CaptureBackground? = nil) {
        self.imageSize = imageSize
        self.annotations = annotations
        self.crop = crop
        self.background = background
    }

    public var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    /// The part of the image that will be exported.
    public var visibleRect: CGRect { crop ?? imageBounds }

    /// The whole exported area: the visible part plus the background's padding.
    public var outputRect: CGRect {
        guard let background else { return visibleRect }
        return visibleRect.insetBy(dx: -background.padding, dy: -background.padding)
    }

    public var isEdited: Bool { !annotations.isEmpty || crop != nil || background != nil }
}

/// Editing state and operations, with undo and redo. Pure value logic: the canvas view
/// calls these and redraws.
///
/// Live drags change `document` directly between `beginChange()` and `commitChange()`, so a
/// whole drag is one undo step.
public struct AnnotationEditor: Sendable {
    public private(set) var document: AnnotationDocument
    public var selection: UUID?
    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    private var pending: AnnotationDocument?
    public static let undoLimit = 100

    public init(document: AnnotationDocument) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var selected: Annotation? {
        selection.flatMap { id in document.annotations.first { $0.id == id } }
    }

    // MARK: Undo

    /// Starts a change that may span many updates (a drag).
    public mutating func beginChange() {
        if pending == nil { pending = document }
    }

    /// Ends the change; records one undo step if anything changed.
    public mutating func commitChange() {
        guard let before = pending else { return }
        pending = nil
        if before != document { pushUndo(before) }
    }

    /// Abandons a change in progress (Esc during a drag).
    public mutating func cancelChange() {
        if let before = pending { document = before }
        pending = nil
    }

    public mutating func undo() {
        commitChange()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        dropStaleSelection()
    }

    public mutating func redo() {
        commitChange()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        dropStaleSelection()
    }

    private mutating func pushUndo(_ snapshot: AnnotationDocument) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Applies `change` as one undoable step (or as part of an open change).
    private mutating func perform(_ change: (inout AnnotationDocument) -> Void) {
        let before = document
        change(&document)
        renumberCounters()
        if pending == nil, before != document { pushUndo(before) }
    }

    private mutating func dropStaleSelection() {
        if let selection, !document.annotations.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    // MARK: Annotations

    /// Adds an annotation and selects it. Counters get the next number.
    public mutating func add(_ annotation: Annotation) {
        perform { $0.annotations.append(annotation) }
        selection = annotation.id
    }

    /// Replaces the annotation with the same id.
    public mutating func update(_ annotation: Annotation) {
        perform { document in
            guard let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
            document.annotations[index] = annotation
        }
    }

    public mutating func remove(id: UUID) {
        perform { $0.annotations.removeAll { $0.id == id } }
        if selection == id { selection = nil }
    }

    public mutating func deleteSelection() {
        guard let selection else { return }
        remove(id: selection)
    }

    public mutating func moveSelection(by delta: CGVector) {
        guard let selected else { return }
        update(selected.moved(by: delta))
    }

    /// Recolors the selection (if any). Redactions have no color.
    public mutating func setColor(_ color: RGBA) {
        guard var selected, selected.kind.usesColor, selected.color != color else { return }
        selected.color = color
        update(selected)
    }

    public mutating func setWidth(_ width: CGFloat) {
        guard var selected, selected.width != width else { return }
        selected.width = width
        update(selected)
    }

    /// Adds a copy of the selection, nudged so it's visible, and selects it (⌘D).
    public mutating func duplicateSelection(offset: CGFloat = 12) {
        guard let selected else { return }
        paste(selected, offset: offset)
    }

    /// Adds a copy of `annotation` (e.g. from the editor's own clipboard) with a new id.
    public mutating func paste(_ annotation: Annotation, offset: CGFloat = 12) {
        var copy = annotation.moved(by: CGVector(dx: offset, dy: offset))
        copy.id = UUID()
        add(copy)
    }

    /// Sets or removes the background (one undo step).
    public mutating func setBackground(_ background: CaptureBackground?) {
        let value = background?.clamped
        guard document.background != value else { return }
        perform { $0.background = value }
    }

    /// Changes the background while a slider is dragged: call between `beginChange()` and
    /// `commitChange()` so the whole drag is one undo step.
    public mutating func adjustBackground(_ change: (inout CaptureBackground) -> Void) {
        guard var background = document.background else { return }
        change(&background)
        setBackground(background)
    }

    /// The front-most annotation `point` grabs.
    public func hit(_ point: CGPoint, tolerance: CGFloat, loose: Bool, textSize: (Annotation) -> CGSize = TextMetrics.size) -> Annotation? {
        // Same order as drawing: marks sit above blur and pixelate.
        let hits = document.annotations.filter { $0.hitTest(point, tolerance: tolerance, loose: loose, textSize: textSize) }
        return hits.last { !$0.kind.isRedaction } ?? hits.last
    }

    /// The number the next counter will get.
    public var nextCounterNumber: Int {
        document.annotations.filter { $0.kind == .counter }.count + 1
    }

    /// Counters are numbered 1, 2, 3… in the order they were added, with no gaps.
    private mutating func renumberCounters() {
        var n = 0
        for index in document.annotations.indices where document.annotations[index].kind == .counter {
            n += 1
            if document.annotations[index].number != n { document.annotations[index].number = n }
        }
    }

    // MARK: Crop

    /// Sets the crop (image points), clamped to the image. A crop covering the whole image,
    /// or too small to keep, clears it.
    public mutating func setCrop(_ rect: CGRect?) {
        var value = rect.map { $0.standardized.intersection(document.imageBounds) }
        if let crop = value {
            let snapped = SelectionGeometry.snapped(crop)
            if snapped.isNull || snapped.width < 4 || snapped.height < 4 || snapped == document.imageBounds {
                value = nil
            } else {
                value = snapped
            }
        }
        perform { $0.crop = value }
    }
}
