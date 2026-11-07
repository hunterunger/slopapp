import AppKit
import Testing
@testable import DictateCore

/// Uses private, uniquely named pasteboards: never the system clipboard.
@Suite("Clipboard snapshot")
@MainActor
struct ClipboardTests {
    func board() -> NSPasteboard { NSPasteboard(name: .init("dictate-tests-\(UUID().uuidString)")) }

    @Test func restoresEveryItemAndType() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("plain", forType: .string)
        rich.setData(Data("{\\rtf1 rich}".utf8), forType: .rtf)
        let image = NSPasteboardItem()
        image.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([rich, image])

        let saved = ClipboardSnapshot.capture(pasteboard)
        #expect(saved.items.count == 2)
        let ours = ClipboardSnapshot.write("dictated", to: pasteboard, transient: true)
        #expect(pasteboard.string(forType: .string) == "dictated")
        #expect(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[0]) == true)
        #expect(pasteboard.changeCount == ours)

        saved.restore(to: pasteboard)
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.string(forType: .string) == "plain")
        #expect(pasteboard.data(forType: .rtf) == Data("{\\rtf1 rich}".utf8))
        #expect(pasteboard.pasteboardItems?[1].data(forType: .png) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(ClipboardSnapshot.capture(pasteboard) == saved)
    }

    @Test func emptyClipboardStaysAPlainCopy() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let saved = ClipboardSnapshot.capture(pasteboard)
        #expect(saved.isEmpty)
        ClipboardSnapshot.write("kept", to: pasteboard, transient: false)
        #expect(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[0]) == false)
        #expect(pasteboard.string(forType: .string) == "kept")
    }
}
