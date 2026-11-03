import AppKit
import SlopKit

/// Asks for the session label in a small alert with a text field.
@MainActor
enum LabelPrompt {
    /// Returns the new label (empty clears it), or nil if cancelled.
    static func ask(current: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = "What are you working on?"
        alert.informativeText = "The label shows in the menu and is saved with your sessions until you change it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = current ?? ""
        field.placeholderString = "Write the intro"
        field.setAccessibilityLabel("Session label")
        alert.accessoryView = field
        alert.addButton(withTitle: "Set Label")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        AppActivation.activate()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
