import AppKit
import SwiftUI

/// Presents SwiftUI content as a document-modal sheet. The content gets a `dismiss` closure.
@MainActor
enum Sheet {
    @discardableResult
    static func present<Content: View>(on window: NSWindow, @ViewBuilder content: (@escaping () -> Void) -> Content) -> NSWindow {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let dismiss = { [weak window, weak sheet] in
            guard let sheet else { return }
            window?.endSheet(sheet)
        }
        sheet.contentViewController = NSHostingController(rootView: content(dismiss))
        window.beginSheet(sheet)
        return sheet
    }
}
