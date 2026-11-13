import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite struct PasteStackTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func pastesInOrderThenFinishes() {
        var stack = PasteStack()
        #expect(stack.next == nil && !stack.isFinished)
        stack.add(a)
        stack.add(b)
        stack.add(c)
        #expect(stack.next == a && stack.remaining == 3)
        #expect(stack.advance() == b)
        #expect(stack.pastedCount == 1 && Array(stack.upcoming) == [b, c])
        #expect(stack.advance() == c)
        #expect(stack.advance() == nil)
        #expect(stack.isFinished && stack.remaining == 0)
        #expect(stack.advance() == nil) // stays finished
    }

    @Test func copiesJoinTheEndEvenWhilePasting() {
        var stack = PasteStack(items: [a])
        stack.advance()
        #expect(stack.isFinished)
        stack.add(b)
        #expect(stack.next == b && !stack.isFinished)
        stack.add(b) // the same value twice is fine
        #expect(stack.remaining == 2)
    }

    @Test func skipAndGoBack() {
        var stack = PasteStack(items: [a, b, c])
        stack.move(to: 2)
        #expect(stack.next == c)
        stack.move(to: 0)
        #expect(stack.next == a)
        stack.move(to: 7)
        #expect(stack.next == a)
    }

    @Test func deletedClipsLeave() {
        var stack = PasteStack(items: [a, b, c])
        stack.advance() // a pasted, b next
        stack.remove([a])
        #expect(stack.next == b && stack.pastedCount == 0)
        stack.remove([b])
        #expect(stack.next == c)
        stack.remove([c])
        #expect(stack.items.isEmpty && stack.next == nil && !stack.isFinished)
    }

    @Test func onlyTheFirstReadOfEachClipIsAPaste() {
        var tracker = PasteReadTracker()
        var reads: [Bool] = []
        reads.append(tracker.read(serial: 0)) // nothing out yet
        let first = tracker.arm()
        reads.append(tracker.read(serial: first))
        reads.append(tracker.read(serial: first)) // the same paste asking for another type
        let second = tracker.arm()
        reads.append(tracker.read(serial: first)) // a late read of the old one
        reads.append(tracker.read(serial: second))
        let third = tracker.arm()
        tracker.disarm() // something else replaced it
        reads.append(tracker.read(serial: third))
        #expect(reads == [false, true, false, false, true, false])
    }
}

/// A recognizer that "reads" each clip's made-up image (a word), and records what it saw.
private actor FakeRecognizer: TextRecognizer {
    private(set) var seen: [String] = []
    let images: [UUID: String]

    init(images: [UUID: String]) {
        self.images = images
    }

    func recognizeText(inClip id: UUID) async throws -> [String]? {
        guard let text = images[id] else { return nil }
        seen.append(text)
        if text == "broken" { throw CocoaError(.fileReadCorruptFile) }
        return text == "blank" ? [] : ["  " + text + "  ", "", "line two"]
    }
}

private actor Results {
    var found: [UUID: String] = [:]
    var order: [UUID] = []
    func add(_ id: UUID, _ text: String) {
        found[id] = text
        order.append(id)
    }
}

@Suite struct TextRecognitionTests {
    @Test func joinsTrimsAndCaps() {
        #expect(RecognizedText.join(["  Invoice ", "", " 4471"]) == "Invoice\n4471")
        #expect(RecognizedText.join([]) == "")
        #expect(RecognizedText.join([String(repeating: "x", count: 50)], limit: 10).count == 10)
    }

    @Test func worksThroughImagesOneAtATimeNewestFirst() async {
        let results = Results()
        let ids = (0..<4).map { _ in UUID() }
        let recognizer = FakeRecognizer(images: [ids[0]: "zero", ids[1]: "one", ids[2]: "broken", ids[3]: "blank"])
        let queue = TextRecognitionQueue(recognizer: recognizer, pause: .zero,
                                         deliver: { await results.add($0, $1) })
        await queue.enqueue([ids[1], ids[2], ids[3]])
        await queue.enqueue([ids[0]], first: true)
        await queue.enqueue([ids[1]]) // already waiting: not twice
        await queue.waitUntilIdle()
        let found = await results.found
        #expect(found[ids[0]] == "zero\nline two")
        #expect(found[ids[1]] == "one\nline two")
        #expect(found[ids[2]] == "") // unreadable: looked at, nothing found, not retried
        #expect(found[ids[3]] == "")
        let seen = await recognizer.seen
        #expect(seen.count == 4)
        #expect(Set(seen) == ["zero", "one", "broken", "blank"])
    }

    @Test func deletedImagesAreSkipped() async {
        let results = Results()
        let keep = UUID(), gone = UUID(), missing = UUID()
        let recognizer = FakeRecognizer(images: [keep: "img", gone: "img"])
        let queue = TextRecognitionQueue(recognizer: recognizer, pause: .milliseconds(20),
                                         deliver: { await results.add($0, $1) })
        await queue.enqueue([keep, gone, missing])
        await queue.cancel([gone])
        await queue.waitUntilIdle()
        #expect(await results.order == [keep])
        #expect(await queue.pendingCount == 0)
    }

    @Test func imageTextShowsUpInSearchAndSnippets() throws {
        let png = makePNG(width: 4, height: 4)
        var clip = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]]),
                                         sourceBundleID: nil, sourceName: nil, now: now).get().0
        #expect(ClipText.imageTextSnippet(of: clip, query: "4471") == nil)
        clip.recognizedText = "Quarterly report\nInvoice number 4471 for March, due on the first of April"
        #expect(clip.imageText != nil)
        #expect(ClipSearch.run([clip], query: "invoice 4471").count == 1)
        let snippet = try #require(ClipText.imageTextSnippet(of: clip, query: "4471"))
        #expect(snippet.contains("4471"))
        #expect(!snippet.contains("\n"))
        #expect(snippet.count <= 46)
        #expect(ClipText.imageTextSnippet(of: clip, query: "absent") == nil)
        #expect(ClipText.imageTextSnippet(of: clip, query: "") == nil)
        clip.recognizedText = ""
        #expect(clip.imageText == nil)
        #expect(ClipSearch.run([clip], query: "4471").isEmpty)
    }

    @Test func historyListsImagesStillToRead() throws {
        var history = History()
        let png = makePNG(width: 4, height: 4)
        let image = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]]),
                                          sourceBundleID: nil, sourceName: nil, now: now).get().0
        history.record(textClip("words", at: now - 1))
        history.record(image)
        #expect(history.imagesAwaitingText == [image.id])
        #expect(history.setRecognizedText("", id: image.id) != nil)
        #expect(history.imagesAwaitingText.isEmpty)
        #expect(history.setRecognizedText("x", id: UUID()) == nil)
    }
}

@Suite struct NewPanelKeysTests {
    func command(_ code: UInt16, _ chars: String? = nil, _ mods: PanelKeys.Modifiers = []) -> PanelCommand? {
        PanelKeys.command(keyCode: code, characters: chars, modifiers: mods, context: .init())
    }

    @Test func shiftExtendsTheSelection() {
        #expect(command(123, nil, .shift) == .extend(-1))
        #expect(command(124, nil, .shift) == .extend(1))
        #expect(command(125, nil, .shift) == .extend(1))
        #expect(command(126, nil, .shift) == .extend(-1))
        #expect(command(115, nil, .shift) == .extendToFirst)
        #expect(command(119, nil, .shift) == .extendToLast)
        #expect(command(126, nil, [.command, .shift]) == .extendToFirst)
        #expect(command(125, nil, [.command, .shift]) == .extendToLast)
        #expect(command(0, "a", .command) == .selectAll)
        // ⌘← ⌘→ still switch tabs.
        #expect(command(123, nil, [.command, .shift]) == .previousTab)
    }

    @Test func boardsEditingAndStacks() {
        #expect(command(18, "1", [.command, .option]) == .pinToBoard(index: 0))
        #expect(command(20, "3", [.command, .option]) == .pinToBoard(index: 2))
        #expect(command(18, "1", .command) == .quickPaste(index: 0, plain: false))
        #expect(command(45, "n", [.command, .shift]) == .newBoard)
        #expect(command(45, "n", .command) == nil)
        #expect(command(14, "e", .command) == .edit)
        #expect(command(15, "r", .command) == .rename)
        #expect(command(8, "c", [.command, .shift]) == .pasteStack)
        #expect(command(8, "c", .command) == .copy)
    }
}
