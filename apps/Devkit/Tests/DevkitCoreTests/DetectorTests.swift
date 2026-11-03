import Foundation
import Testing
@testable import DevkitCore

@Suite struct DetectorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        let tool: Tool?
        var hint: Detector.Hint = .none
        var testDescription: String { text.prefix(40) + " → " + (tool?.rawValue ?? "nothing") }
    }

    @Test(arguments: [
        // 1. JWT (with and without a Bearer prefix)
        Case(text: JWTTests.token, tool: .jwt),
        Case(text: "Bearer \(JWTTests.token)\n", tool: .jwt),
        // 2. JSON
        Case(text: "  {\"a\": [1, 2]}\n", tool: .json),
        Case(text: "[1,2,3]", tool: .json),
        // 3. UUID / ULID
        Case(text: "919108f7-52d1-4320-9bac-f847db4148a8", tool: .uuid, hint: .inspect),
        Case(text: "01ARYZ6S41TSV4RRFFQ69G5FAV", tool: .uuid, hint: .inspect),
        // 4. Unix time
        Case(text: "1730592000", tool: .timestamp),
        Case(text: "1730592000123", tool: .timestamp),
        // 5. Color
        Case(text: "#ff8800", tool: .color),
        Case(text: "#F80", tool: .color),
        Case(text: "rgb(255, 0, 0)", tool: .color),
        Case(text: "hsl(120 50% 50%)", tool: .color),
        // 6. URL-encoded
        Case(text: "name%3DAda%20Lovelace", tool: .url, hint: .decode),
        Case(text: "q=hello%20world&lang=en", tool: .url, hint: .decode),
        // 7. Base64
        Case(text: "SGVsbG8sIFdvcmxkIQ==", tool: .base64, hint: .decode),
        Case(text: "eyJ1c2VyIjoiYWRhIn0", tool: .base64, hint: .decode),
        // 8. Numbers with a base prefix
        Case(text: "0xFF", tool: .numberBase),
        Case(text: "0b1010", tool: .numberBase),
        // False positives: stay put.
        Case(text: "hello world", tool: nil),
        Case(text: "password", tool: nil),
        Case(text: "Password", tool: nil),
        Case(text: "deadbeefcafebabe", tool: nil),
        Case(text: "12345678", tool: nil),
        Case(text: "42", tool: nil),
        Case(text: "{not json}", tool: nil),
        Case(text: "100% done", tool: nil),
        Case(text: "#hashtag", tool: nil),
        Case(text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", tool: nil),
        Case(text: "", tool: nil),
        Case(text: "https://example.com/path", tool: nil),
        Case(text: "a.b.c", tool: nil),
    ])
    func detects(example: Case) {
        let detection = Detector.detect(example.text)
        #expect(detection?.tool == example.tool)
        if let detection, example.tool != nil {
            #expect(detection.hint == example.hint)
        }
    }

    @Test func skipsHugeText() {
        let big = "[" + String(repeating: "1,", count: 600_000) + "1]"
        #expect(Detector.detect(big) == nil)
    }

    @Test func passesTrimmedInput() {
        #expect(Detector.detect("\n  #abc \n")?.input == "#abc")
        #expect(Detector.detect("Bearer \(JWTTests.token)")?.input == JWTTests.token)
    }
}

final class FakeClipboard: Clipboard {
    var changeCount = 0
    var types: [String] = ["public.utf8-plain-text"]
    var text: String?
    var writes: [String] = []

    var file: URL?
    func string() -> String? { text }
    func fileURL() -> URL? { file }
    func setString(_ string: String) {
        writes.append(string)
        text = string
        changeCount += 1
    }

    func copy(_ string: String, types extra: [String] = []) {
        text = string
        types = ["public.utf8-plain-text"] + extra
        changeCount += 1
    }
}

@Suite struct ClipboardReaderTests {
    @Test func pasteAndDetect() {
        let clipboard = FakeClipboard()
        let reader = ClipboardReader()
        #expect(reader.pasteAndDetect(from: clipboard) == .noText)
        clipboard.copy("1730592000")
        #expect(reader.pasteAndDetect(from: clipboard) == .detected(.init(tool: .timestamp, input: "1730592000", hint: .none)))
        clipboard.copy("just some words")
        #expect(reader.pasteAndDetect(from: clipboard) == .unmatched("just some words"))
    }

    @Test func manualPasteReadsConcealedContent() {
        // The user asked explicitly, so a concealed item is still pasted.
        let clipboard = FakeClipboard()
        clipboard.copy("#ff0000", types: [ClipboardPolicy.concealed])
        #expect(ClipboardReader().pasteAndDetect(from: clipboard) != .noText)
    }

    @Test func automaticReadIsOptInAndOncePerChange() {
        let clipboard = FakeClipboard()
        let reader = ClipboardReader()
        clipboard.copy("#ff0000")
        #expect(reader.automaticRead(from: clipboard, enabled: false) == nil)
        #expect(reader.automaticRead(from: clipboard, enabled: true)?.tool == .color)
        // Same clipboard on the next activation: leave the user's input alone.
        #expect(reader.automaticRead(from: clipboard, enabled: true) == nil)
        clipboard.copy("0xFF")
        #expect(reader.automaticRead(from: clipboard, enabled: true)?.tool == .numberBase)
    }

    @Test func automaticReadSkipsConcealedAndTransient() {
        let clipboard = FakeClipboard()
        let reader = ClipboardReader()
        clipboard.copy("#ff0000", types: [ClipboardPolicy.concealed])
        #expect(reader.automaticRead(from: clipboard, enabled: true) == nil)
        clipboard.copy("#ff0000", types: [ClipboardPolicy.transient])
        #expect(reader.automaticRead(from: clipboard, enabled: true) == nil)
    }

    @Test func ownWritesDontBounceBack() {
        let clipboard = FakeClipboard()
        let reader = ClipboardReader()
        clipboard.setString("#00ff00")
        reader.noteOwnWrite(clipboard)
        #expect(reader.automaticRead(from: clipboard, enabled: true) == nil)
    }

    @Test func toolFilter() {
        #expect(Tool.hash.matches(filter: "sha"))
        #expect(Tool.timestamp.matches(filter: "Epoch"))
        #expect(!Tool.json.matches(filter: "sha"))
        #expect(Tool.allCases.allSatisfy { $0.matches(filter: " ") })
    }
}
