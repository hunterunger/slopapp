import Foundation

/// Undo/redo for value edits: undoing applies `old` and registers the opposite step, so
/// redo works too. One call is one step (UndoManager groups by event in the app).
/// `target` lets a caller drop a whole family of steps with `removeAllActions(withTarget:)`.
@MainActor
public enum ReversibleEdit {
    public static func register<Value>(_ manager: UndoManager, target: AnyObject, name: String, from old: Value, to new: Value,
                                       apply: @escaping @MainActor (Value) -> Void) {
        manager.registerUndo(withTarget: target) { target in
            MainActor.assumeIsolated {
                apply(old)
                register(manager, target: target, name: name, from: new, to: old, apply: apply)
            }
        }
        manager.setActionName(name)
    }
}
