import AppKit

// Paper is a document app (design system §2e): AppKit's document architecture runs it,
// so it gets multiple windows, Open Recent, autosave, Versions, tabs and restoration for free.
// The document controller must exist before anything asks for `NSDocumentController.shared`.
_ = PaperDocumentController()
let app = NSApplication.shared
let delegate = PaperAppDelegate()
app.delegate = delegate
app.mainMenu = MainMenu.build()
app.run()
