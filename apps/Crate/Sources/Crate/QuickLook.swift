import AppKit
@preconcurrency import Quartz

/// Drives the shared Quick Look panel for the browse list: one item (a temporary copy of the
/// selected entry), replaced as the selection moves. Arrow keys pressed while the panel is
/// in front go to the list, so the preview follows them.
@MainActor
final class QuickLookController: NSObject {
    private var url: URL?
    /// The list, which takes control of the panel and receives forwarded arrow keys.
    weak var outline: NSOutlineView?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func show(_ url: URL) {
        self.url = url
        if let outline, outline.window?.firstResponder !== outline {
            outline.window?.makeFirstResponder(outline)
        }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        if isVisible { QLPreviewPanel.shared().orderOut(nil) }
        url = nil
    }

    func take(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func release(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension QuickLookController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url.map { $0 as NSURL }
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown, let outline else { return false }
        guard [123, 124, 125, 126].contains(event.keyCode) else { return false }
        outline.keyDown(with: event)
        return true
    }
}
