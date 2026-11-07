import AppKit
import TallyCore

/// One sheet while it's loaded: its text (an NSTextStorage that every open editor shares),
/// its own undo history, and its latest answers.
@MainActor
final class SheetDocument {
    let id: UUID
    let storage: NSTextStorage
    let undoManager = UndoManager()
    /// Where the insertion point was, restored when the sheet is shown again.
    var selection = NSRange(location: NSNotFound, length: 0)
    private(set) var lines: [String] = []
    private(set) var outputs: [LineOutput] = []
    var displays: [ResultDisplay?] = []
    /// Lower-cased variable names, for highlighting.
    private(set) var variables: Set<String> = []
    /// Variable names as written, in sheet order, for suggestions.
    private(set) var variableNames: [String] = []
    private(set) var usesClock = false
    var dirty = false
    /// The styler generation this storage was last fully styled with.
    var styledGeneration = -1

    init(id: UUID, text: String) {
        self.id = id
        storage = NSTextStorage(string: text)
    }

    /// A native copy of the text. The storage's own string is a bridged NSString, and
    /// splitting that into lines is ~20x slower than transcoding it once.
    var text: String {
        var t = storage.string
        t.makeContiguousUTF8()
        return t
    }

    var title: String { SheetTitle.title(of: text) }

    /// Re-evaluates the whole sheet. Returns true when the set of variable names changed (so
    /// highlighting needs a full pass).
    @discardableResult
    func evaluate(engine: SheetEngine, context: SheetContext) -> Bool {
        lines = SheetEngine.lines(of: text)
        outputs = engine.evaluate(lines: lines, context: context)
        var names: [String] = []
        var seen = Set<String>()
        var clock = false
        for output in outputs {
            if let name = output.assignedName, output.result.quantity != nil, seen.insert(name.lowercased()).inserted {
                names.append(name)
            }
            if output.usesClock { clock = true }
        }
        usesClock = clock
        variableNames = names
        let changed = seen != variables
        variables = seen
        return changed
    }
}
