import Foundation
import Testing
@testable import IconsmithCore

/// Mirrors the app's editor: every size or nudge step is its own undo step.
@MainActor @Suite struct UndoTests {
    @MainActor final class Editor {
        let undo = UndoManager()
        let target = NSObject()
        var style = IconStyle()

        init() { undo.groupsByEvent = false }

        func edit(_ name: String, _ change: (inout IconStyle) -> Void) {
            let old = style
            change(&style)
            style = style.clamped()
            undo.beginUndoGrouping()
            ReversibleEdit.register(undo, target: target, name: name, from: old, to: style) { [unowned self] in self.style = $0 }
            undo.endUndoGrouping()
        }
    }

    @Test func sizeAndNudgeStepsUndoOneAtATimeAndRedo() {
        let editor = Editor()
        let original = editor.style
        editor.edit("Change Size") { $0.scale *= 1.1 }
        editor.edit("Change Size") { $0.scale *= 1.1 }
        editor.edit("Move Picture") { $0.offset.x -= 1.0 / 256 }
        editor.edit("Move Picture") { $0.offset.x -= 1.0 / 256 }
        let edited = editor.style
        #expect(editor.undo.undoActionName == "Move Picture")

        editor.undo.undo()
        #expect(abs(editor.style.offset.x - -1.0 / 256) < 1e-12)
        #expect(editor.undo.canUndo)
        editor.undo.undo()
        #expect(editor.style.offset == .zero)
        #expect(editor.undo.undoActionName == "Change Size")
        editor.undo.undo()
        editor.undo.undo()
        #expect(editor.style == original)
        #expect(!editor.undo.canUndo)

        for _ in 0..<4 { editor.undo.redo() }
        #expect(editor.style == edited)
        #expect(!editor.undo.canRedo)
    }

    @Test func droppingAFamilyLeavesOtherSteps() {
        let editor = Editor()
        let other = NSObject()
        var applied = 0
        editor.undo.beginUndoGrouping()
        ReversibleEdit.register(editor.undo, target: other, name: "Apply Icon", from: 0, to: 1) { applied = $0 }
        editor.undo.endUndoGrouping()
        editor.edit("Change Size") { $0.scale = 1.5 }
        editor.undo.removeAllActions(withTarget: editor.target)
        #expect(editor.undo.undoActionName == "Apply Icon")
        editor.undo.undo()
        #expect(applied == 0)
    }
}
