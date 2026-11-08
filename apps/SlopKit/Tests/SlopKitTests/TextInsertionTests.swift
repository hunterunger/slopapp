import AppKit
import Carbon.HIToolbox
import Testing
@testable import SlopKit

/// Uses private, uniquely named pasteboards: never the system clipboard. Nothing is posted.
@Suite("Clipboard snapshot")
@MainActor
struct ClipboardSnapshotTests {
    func board() -> NSPasteboard { NSPasteboard(name: .init("slopkit-tests-\(UUID().uuidString)")) }

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
        #expect(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[1]) == true)
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

@Suite("Clipboard paster")
@MainActor
struct ClipboardPasterTests {
    func board() -> NSPasteboard { NSPasteboard(name: .init("slopkit-tests-\(UUID().uuidString)")) }

    func fill(_ pasteboard: NSPasteboard, _ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @Test func pastesThenRestores() async {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        fill(pasteboard, "theirs")
        var seenAtPaste: String?
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(1), restoreDelay: .milliseconds(5)) {
            seenAtPaste = pasteboard.string(forType: .string)
        }
        let outcome = await paster.paste("slopapp-test snippet").value
        #expect(seenAtPaste == "slopapp-test snippet")
        #expect(outcome == .restored)
        #expect(pasteboard.string(forType: .string) == "theirs")
    }

    @Test func keepsANewerCopy() async {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        fill(pasteboard, "theirs")
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(1), restoreDelay: .milliseconds(30)) {
            // The person copies something right after the paste.
            pasteboard.clearContents()
            pasteboard.setString("newer", forType: .string)
        }
        let outcome = await paster.paste("slopapp-test snippet").value
        #expect(outcome == .keptNewerCopy)
        #expect(pasteboard.string(forType: .string) == "newer")
    }

    @Test func emptyClipboardLeavesTheTextCopied() async {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(1), restoreDelay: .milliseconds(1)) {}
        let outcome = await paster.paste("slopapp-test snippet").value
        #expect(outcome == .leftCopied)
        #expect(pasteboard.string(forType: .string) == "slopapp-test snippet")
        #expect(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[0]) == false)
    }

    @Test func withoutRestoreNothingIsReadAndTheTextStays() async {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        fill(pasteboard, "theirs")
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(1), restoreDelay: .milliseconds(1)) {}
        let outcome = await paster.paste("slopapp-test snippet", restore: false).value
        #expect(outcome == .leftCopied)
        #expect(pasteboard.string(forType: .string) == "slopapp-test snippet")
        // A normal copy, not a transient one: the person may paste it again.
        #expect(pasteboard.types?.contains(ClipboardSnapshot.transientTypes[0]) == false)
    }
}

@Suite("Synthetic keyboard")
struct SyntheticKeyboardTests {
    @Test func shortTextIsOneStroke() {
        #expect(SyntheticKeyboard.strokes(typing: "hello") == [.text(Array("hello".utf16))])
        #expect(SyntheticKeyboard.strokes(typing: "").isEmpty)
    }

    @Test func longTextIsChunkedAtTwentyUnits() {
        let text = String(repeating: "a", count: 45)
        let strokes = SyntheticKeyboard.strokes(typing: text)
        #expect(strokes.count == 3)
        #expect(strokes.map { if case .text(let u) = $0 { u.count } else { -1 } } == [20, 20, 5])
    }

    @Test func surrogatePairsAreNeverSplit() {
        // 19 letters then an emoji (2 units) straddling the 20-unit boundary.
        let text = String(repeating: "a", count: 19) + "😀" + "b"
        let strokes = SyntheticKeyboard.strokes(typing: text)
        guard case .text(let first) = strokes[0], case .text(let second) = strokes[1] else {
            Issue.record("expected text strokes")
            return
        }
        #expect(first.count == 19)
        #expect(String(decoding: second, as: UTF16.self) == "😀b")
    }

    @Test func newLinesBecomeReturn() {
        let strokes = SyntheticKeyboard.strokes(typing: "a\n\nb")
        #expect(strokes == [.text([97]), .key(CGKeyCode(kVK_Return), flags: nil), .key(CGKeyCode(kVK_Return), flags: nil), .text([98])])
    }

    @Test func tabsStayInsideText() {
        #expect(SyntheticKeyboard.strokes(typing: "a\tb") == [.text(Array("a\tb".utf16))])
    }

    @Test func currentLayoutHasACommandKey() {
        // Whatever the layout, ⌘V resolves to some key (or the ANSI fallback).
        let key = KeyboardLayout.commandKey("v", fallback: kVK_ANSI_V)
        #expect(key < 128)
    }
}

@Suite("Pasteboard privacy")
@MainActor
struct PasteboardPrivacyTests {
    @Test func opensThePasteFromOtherAppsPane() {
        #expect(PasteboardPrivacy.settingsURL.absoluteString.hasSuffix("Privacy_Pasteboard"))
    }
}

@Suite("Clipboard paster on quit")
@MainActor
struct ClipboardPasterQuitTests {
    @Test func restoresPendingRightAway() async {
        let pasteboard = NSPasteboard(name: .init("slopkit-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("theirs", forType: .string)
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(1), restoreDelay: .seconds(5)) {}
        let task = paster.paste("slopapp-test snippet")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(pasteboard.string(forType: .string) == "slopapp-test snippet")
        ClipboardPaster.restorePendingNow(on: pasteboard)
        #expect(pasteboard.string(forType: .string) == "theirs")
        task.cancel()
        #expect(await task.value == .restored)
    }
}
