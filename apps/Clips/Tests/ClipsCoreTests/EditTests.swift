import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func rep(_ type: String, _ text: String) -> Representation {
    Representation(type: type, data: Data(text.utf8))
}

@Suite struct ClipEditTests {
    @Test func editedTextIsWhatPastes() throws {
        var clip = textClip("Jhon Smith", at: now, source: "com.apple.mail")
        clip.label = "Name"
        clip.boardID = Board.pinnedID
        clip.useCount = 4
        let (edited, payload) = try #require(ClipEdit.apply(text: "John Smith", rich: nil, to: clip))
        #expect(edited.id == clip.id)
        #expect(edited.text == "John Smith")
        #expect(edited.label == "Name")
        #expect(edited.boardID == Board.pinnedID)
        #expect(edited.useCount == 4)
        #expect(edited.created == clip.created && edited.lastUsed == clip.lastUsed)
        #expect(edited.sourceBundleID == "com.apple.mail")
        #expect(payload.items == [[rep(PasteboardType.string, "John Smith")]])
        #expect(edited.fingerprint == "text:" + ClipBuilder.digest(Data("John Smith".utf8)))
        #expect(edited.byteCount == payload.byteCount)
        #expect(!edited.hasRichText)
    }

    @Test func copyingTheEditedTextFindsTheEditedClip() throws {
        var history = History()
        let clip = textClip("teh draft", at: now)
        history.record(clip)
        let (edited, _) = try #require(ClipEdit.apply(text: "the draft", rich: nil, to: clip))
        let replaced = history.replace(edited)
        #expect(replaced)
        guard case .bumped(let bumped) = history.record(textClip("the draft", at: now + 10)) else {
            Issue.record("expected the edited clip to be bumped")
            return
        }
        #expect(bumped.id == clip.id)
        #expect(history.clips.count == 1)
    }

    @Test func richTextKeepsTheEditorsFormattingAndDropsStaleHTML() throws {
        let built = try ClipBuilder.build(PasteboardSnapshot(items: [[rep(PasteboardType.string, "Bold"), rep(PasteboardType.rtf, "{\\rtf1 Bold}"),
                                                                      rep(PasteboardType.html, "<b>Bold</b>")]]),
                                          sourceBundleID: nil, sourceName: nil, now: now).get()
        #expect(ClipEdit.richSource(in: built.1)?.type == PasteboardType.rtf)
        #expect(!ClipEdit.dropsFormatting(built.0, payload: built.1))
        let (edited, payload) = try #require(ClipEdit.apply(text: "Bolder", rich: rep(PasteboardType.rtf, "{\\rtf1 Bolder}"), to: built.0))
        #expect(edited.hasRichText)
        #expect(payload.items == [[rep(PasteboardType.string, "Bolder"), rep(PasteboardType.rtf, "{\\rtf1 Bolder}")]])
        #expect(payload.plainText()?.items == [[rep(PasteboardType.string, "Bolder")]])
    }

    @Test func htmlOnlyFormattingIsDroppedAndSaid() throws {
        let built = try ClipBuilder.build(PasteboardSnapshot(items: [[rep(PasteboardType.string, "Hi"), rep(PasteboardType.html, "<i>Hi</i>")]]),
                                          sourceBundleID: nil, sourceName: nil, now: now).get()
        #expect(ClipEdit.richSource(in: built.1) == nil)
        #expect(ClipEdit.dropsFormatting(built.0, payload: built.1))
        let (edited, payload) = try #require(ClipEdit.apply(text: "Hello", rich: nil, to: built.0))
        #expect(!edited.hasRichText)
        #expect(payload.items == [[rep(PasteboardType.string, "Hello")]])
        #expect(!ClipEdit.dropsFormatting(textClip("plain"), payload: nil))
    }

    @Test func editingCanChangeTheKind() throws {
        let link = try ClipBuilder.build(PasteboardSnapshot(items: [[rep(PasteboardType.string, "https://example.com/a"),
                                                                     rep(PasteboardType.urlName, "Example")]]),
                                         sourceBundleID: nil, sourceName: nil, now: now).get().0
        #expect(link.title == "Example")
        #expect(ClipEdit.apply(text: "https://example.com/a", rich: nil, to: link)?.0.title == "Example")
        let moved = try #require(ClipEdit.apply(text: "https://example.com/b", rich: nil, to: link)?.0)
        #expect(moved.kind == .link && moved.title == nil)
        #expect(ClipEdit.apply(text: "see example.com", rich: nil, to: link)?.0.kind == .text)
        #expect(ClipEdit.apply(text: "#FF8800", rich: nil, to: textClip("orange"))?.0.kind == .color)
    }

    @Test func emptyTextAndImagesCantBeEdited() throws {
        #expect(ClipEdit.apply(text: "  \n ", rich: nil, to: textClip("x")) == nil)
        let image = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: makePNG(width: 4, height: 4))]]),
                                          sourceBundleID: nil, sourceName: nil, now: now).get().0
        #expect(!ClipEdit.canEditText(image))
        #expect(ClipEdit.apply(text: "words", rich: nil, to: image) == nil)
    }

    @Test func longTextIsEditedInFull() throws {
        let long = String(repeating: "slopapp-test ", count: 2_000)
        let (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(text: long), sourceBundleID: nil, sourceName: nil, now: now).get()
        #expect(clip.isTruncated)
        #expect(ClipEdit.plainText(in: payload, fallback: clip.text) == long)
        #expect(ClipEdit.plainText(in: nil, fallback: "short") == "short")
        let (edited, _) = try #require(ClipEdit.apply(text: long + "END", rich: nil, to: clip))
        #expect(edited.textLength == long.count + 3)
        #expect(ClipSearch.run([edited], query: "end").count == 1)
    }
}

@Suite struct StripSelectionTests {
    let ids = (0..<6).map { _ in UUID() }

    @Test func clickSelectsOne() {
        var selection = StripSelection(cursor: ids[0])
        #expect(selection.ids == [ids[0]] && !selection.isMultiple)
        selection.select(ids[3])
        #expect(selection.cursor == ids[3] && selection.ids == [ids[3]])
        selection.select(nil)
        #expect(selection.ids.isEmpty && selection.cursor == nil)
    }

    @Test func commandClickAddsAndRemoves() {
        var selection = StripSelection(cursor: ids[0])
        selection.toggle(ids[2], in: ids)
        selection.toggle(ids[4], in: ids)
        #expect(selection.ids == [ids[0], ids[2], ids[4]])
        #expect(selection.cursor == ids[4])
        selection.toggle(ids[4], in: ids)
        #expect(selection.ids == [ids[0], ids[2]])
        #expect(selection.cursor == ids[2] || selection.cursor == ids[0])
        selection.toggle(ids[0], in: ids)
        selection.toggle(ids[2], in: ids) // the last one stays
        #expect(selection.ids.count == 1)
    }

    @Test func shiftClickSelectsARangeFromTheAnchor() {
        var selection = StripSelection(cursor: ids[1])
        selection.extend(to: ids[4], in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[1...4]))
        // A new ⇧-click from the same anchor replaces the range.
        selection.extend(to: ids[2], in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[1...2]))
        selection.extend(to: ids[0], in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[0...1]))
        // ⌘-click moves the anchor there; the next ⇧-click ranges from it and keeps the rest.
        selection.toggle(ids[5], in: ids)
        selection.extend(to: ids[3], in: ids)
        #expect(selection.ordered(in: ids) == [ids[0], ids[1], ids[3], ids[4], ids[5]])
    }

    @Test func shiftArrowsGrowAndShrink() {
        var selection = StripSelection(cursor: ids[2])
        selection.extend(by: 1, in: ids)
        selection.extend(by: 1, in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[2...4]))
        selection.extend(by: -1, in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[2...3]))
        selection.extend(by: -3, in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[0...2]))
        selection.extend(toEdge: true, in: ids)
        #expect(selection.ordered(in: ids) == Array(ids[2...5]))
        selection.extend(by: 10, in: ids)
        #expect(selection.cursor == ids[5])
    }

    @Test func selectAllAndCollapse() {
        var selection = StripSelection(cursor: ids[3])
        selection.selectAll(in: ids)
        #expect(selection.count == 6 && selection.cursor == ids[3])
        selection.collapse()
        #expect(selection.ids == [ids[3]])
    }

    @Test func reconcileDropsWhatsGone() {
        var selection = StripSelection(cursor: ids[1])
        selection.extend(to: ids[3], in: ids)
        // A search that hides ids[1] and ids[2].
        let remaining = [ids[0], ids[3], ids[4]]
        selection.reconcile(with: remaining, fallback: remaining.first)
        #expect(selection.ids == [ids[3]])
        #expect(selection.cursor == ids[3])
        // Nothing selected left: the fallback.
        selection.reconcile(with: [ids[5]], fallback: ids[5])
        #expect(selection.ids == [ids[5]] && selection.cursor == ids[5])
        selection.reconcile(with: [], fallback: nil)
        #expect(selection.cursor == nil)
    }
}

@Suite struct ClipJoinTests {
    @Test func textJoinsOldestFirstOnePerLine() throws {
        let a = textClip("first", at: now), b = textClip("second", at: now + 1), c = textClip("third", at: now + 2)
        let payload = try #require(ClipJoin.payload(for: [c, a, b], payloads: [:]))
        #expect(payload.items == [[rep(PasteboardType.string, "first\nsecond\nthird")]])
        #expect(ClipJoin.describe([a, b, c]) == "3 clips")
    }

    @Test func longClipsJoinInFull() throws {
        let long = String(repeating: "slopapp-test ", count: 1_000) + "END"
        let (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(text: long), sourceBundleID: nil, sourceName: nil, now: now).get()
        let short = textClip("after", at: now + 1)
        let text = try #require(ClipJoin.text(of: [short, clip], payloads: [clip.id: payload]))
        #expect(text == long + "\nafter")
    }

    @Test func imagesAreLeftOutOfMixedText() throws {
        let png = makePNG(width: 4, height: 4)
        let (image, imagePayload) = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]]),
                                                          sourceBundleID: nil, sourceName: nil, now: now).get()
        let text = textClip("caption", at: now + 1)
        let payload = try #require(ClipJoin.payload(for: [text, image], payloads: [image.id: imagePayload]))
        #expect(payload.items == [[rep(PasteboardType.string, "caption")]])
        // Only images: every one of them, as separate items.
        let (other, otherPayload) = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: makePNG(width: 5, height: 5))]]),
                                                          sourceBundleID: nil, sourceName: nil, now: now + 2).get()
        let images = try #require(ClipJoin.payload(for: [other, image], payloads: [image.id: imagePayload, other.id: otherPayload]))
        #expect(images.items.count == 2)
        #expect(images.items[0] == imagePayload.items[0])
        #expect(ClipJoin.describe([image, other]) == "2 images")
        #expect(ClipJoin.payload(for: [image], payloads: [:]) == nil)
    }

    @Test func filesPasteAsFiles() throws {
        func files(_ paths: [String], at date: Date) throws -> (Clip, ClipPayload) {
            let items = paths.map { [rep(PasteboardType.fileURL, URL(fileURLWithPath: $0).absoluteString)] }
            return try ClipBuilder.build(PasteboardSnapshot(items: items), sourceBundleID: nil, sourceName: nil, now: date).get()
        }
        let one = try files(["/tmp/clips-test/a.txt", "/tmp/clips-test/b.txt"], at: now)
        let two = try files(["/tmp/clips-test/b.txt", "/tmp/clips-test/c.txt"], at: now + 1)
        let payload = try #require(ClipJoin.payload(for: [two.0, one.0], payloads: [one.0.id: one.1, two.0.id: two.1]))
        #expect(payload.items.count == 3) // b.txt once
        #expect(ClipJoin.describe([one.0, two.0]) == "4 files")
        // Mixed with text: the paths, as text.
        let mixed = try #require(ClipJoin.text(of: [one.0, textClip("note", at: now + 2)]))
        #expect(mixed == "/tmp/clips-test/a.txt\n/tmp/clips-test/b.txt\nnote")
    }
}
