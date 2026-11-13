import Foundation
import SQLite3
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("clips-tests-\(UUID().uuidString)")
}

@Suite struct BoardsTests {
    @Test func addsWithUniqueNamesAndFreshColours() {
        var boards = Boards([Board.pinned])
        let work = boards.add(name: "  Work  ")
        #expect(work.name == "Work")
        #expect(work.color != Board.pinned.color)
        let again = boards.add(name: "work")
        #expect(again.name == "work 2")
        let unnamed = boards.add(name: "   ")
        #expect(unnamed.name == "New Board")
        #expect(boards.add().name == "New Board 2")
        #expect(Set(boards.all.map(\.color)).count == 5)
    }

    @Test func coloursCycleOnceAllAreUsed() {
        var boards = Boards()
        for _ in BoardColor.allCases { boards.add() }
        #expect(Set(boards.all.map(\.color)) == Set(BoardColor.allCases))
        let next = boards.add()
        #expect(BoardColor.allCases.contains(next.color))
    }

    @Test func renameCleansAndRefusesEmpty() {
        var boards = Boards([Board.pinned])
        let work = boards.add(name: "Work")
        #expect(boards.rename(work.id, to: "   ") == nil)
        #expect(boards.rename(work.id, to: "Pinned")?.name == "Pinned 2")
        #expect(boards.rename(work.id, to: "Client\nprojects")?.name == "Client projects")
        #expect(boards.rename(work.id, to: "Client projects") == nil) // unchanged
        let long = String(repeating: "x", count: 200)
        #expect(boards.rename(work.id, to: long)?.name.count == Board.nameLimit)
    }

    @Test func recolourMoveAndRemove() {
        var boards = Boards([Board.pinned])
        let a = boards.add(name: "A"), b = boards.add(name: "B")
        #expect(boards.setColor(.pink, of: a.id)?.color == .pink)
        #expect(boards.setColor(.pink, of: a.id) == nil)
        let moved = [boards.move(b.id, by: -1)]
        #expect(boards.all.map(\.name) == ["Pinned", "B", "A"])
        let movedFirst = boards.move(b.id, by: -5)
        #expect(boards.all.map(\.name) == ["B", "Pinned", "A"])
        let movedAgain = boards.move(b.id, by: -1) // already first
        #expect(moved == [true] && movedFirst && !movedAgain)
        boards.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(boards.all.map(\.name) == ["Pinned", "A", "B"])
        boards.move(fromOffsets: IndexSet([1, 2]), toOffset: 0)
        #expect(boards.all.map(\.name) == ["A", "B", "Pinned"])
        #expect(boards.remove(a.id)?.name == "A")
        #expect(boards.defaultBoard?.name == "B")
        #expect(boards.remove(a.id) == nil)
    }

    @Test func tabsPutBoardsBetweenAllAndTheKinds() {
        let work = Board(name: "Work", color: .blue)
        let tabs = ClipFilter.tabs(boards: [Board.pinned, work])
        #expect(tabs == [.all, .board(Board.pinnedID), .board(work.id), .text, .links, .images, .files])
        #expect(ClipFilter.board(work.id).title == nil)
        #expect(ClipFilter.all.title == "All")
    }
}

@Suite struct BoardHistoryTests {
    @Test func pinningPutsClipsOnTheDefaultBoard() {
        var clip = textClip("a", at: now)
        #expect(!clip.isPinned)
        clip.isPinned = true
        #expect(clip.boardID == Board.pinnedID)
        let work = UUID()
        clip.boardID = work
        clip.isPinned = true // already on a board: stays there
        #expect(clip.boardID == work)
        clip.isPinned = false
        #expect(clip.boardID == nil)
    }

    @Test func boardsFilterAndSurvivePruning() {
        var history = History()
        let work = UUID()
        let old = textClip("old", at: now - 400 * 86_400), kept = textClip("kept", at: now - 400 * 86_400)
        let fresh = textClip("fresh", at: now)
        [old, kept, fresh].forEach { history.record($0) }
        let changed = history.setBoard(work, ids: [kept.id, fresh.id])
        #expect(changed.map(\.text) == ["fresh", "kept"])
        #expect(history.setBoard(work, ids: [kept.id]).isEmpty) // already there
        #expect(ClipSearch.run(history.clips, query: "", filter: .board(work)).map(\.text) == ["fresh", "kept"])
        #expect(ClipSearch.run(history.clips, query: "", filter: .pinned).count == 2)
        #expect(history.count(onBoard: work) == 2)
        #expect(history.prune(retention: .week, now: now) == [old.id])
        #expect(history.clear().isEmpty)
    }

    @Test func deletingABoardLeavesItsClipsInTheHistory() {
        var history = History()
        let work = UUID(), other = UUID()
        let a = textClip("a", at: now), b = textClip("b", at: now + 1), c = textClip("c", at: now + 2)
        [a, b, c].forEach { history.record($0) }
        history.setBoard(work, ids: [a.id, b.id])
        history.setBoard(other, ids: [c.id])
        let released = history.releaseBoard(work)
        #expect(Set(released.map(\.id)) == [a.id, b.id])
        #expect(released.allSatisfy { !$0.isPinned })
        #expect(history.clips.count == 3)
        #expect(history.clip(id: c.id)?.boardID == other)
    }

    @Test func recopyingKeepsBoardAndLabel() {
        var history = History()
        let first = textClip("address", at: now)
        history.record(first)
        history.setBoard(Board.pinnedID, ids: [first.id])
        history.setLabel("Home", id: first.id)
        guard case .bumped(let bumped) = history.record(textClip("address", at: now + 5)) else {
            Issue.record("expected a bump")
            return
        }
        #expect(bumped.label == "Home")
        #expect(bumped.boardID == Board.pinnedID)
    }

    @Test func labelsAreSearchedAndTitleTheClip() {
        var history = History()
        let clip = textClip("221B Baker Street, London", at: now)
        history.record(clip)
        #expect(history.setLabel(ClipText.cleanLabel("  Home   address "), id: clip.id)?.label == "Home address")
        #expect(history.setLabel("Home address", id: clip.id) == nil) // unchanged
        let labelled = history.clip(id: clip.id)!
        #expect(ClipSearch.run(history.clips, query: "home").count == 1)
        #expect(ClipSearch.run(history.clips, query: "baker").count == 1)
        #expect(ClipText.title(of: labelled) == "Home address")
        #expect(ClipText.contentTitle(of: labelled) == "221B Baker Street, London")
        #expect(ClipText.headerTitle(of: labelled) == "Home address")
        #expect(ClipText.headerTitle(of: clip) == "Text")
        #expect(ClipText.cleanLabel(" \n ") == nil)
        history.setLabel(nil, id: clip.id)
        #expect(ClipSearch.run(history.clips, query: "home").isEmpty)
    }
}

@Suite struct BoardDatabaseTests {
    /// A history file exactly as the last build before boards (schema v3) left it.
    private func makeVersion3(at dir: URL, pinned: UUID, unpinned: UUID) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var db: OpaquePointer?
        #expect(sqlite3_open(dir.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE clips(
                id TEXT PRIMARY KEY, kind INTEGER NOT NULL, text TEXT NOT NULL, text_length INTEGER NOT NULL,
                width INTEGER NOT NULL, height INTEGER NOT NULL, bytes INTEGER NOT NULL, rich INTEGER NOT NULL,
                source_id TEXT, source_name TEXT, created REAL NOT NULL, last_used REAL NOT NULL,
                use_count INTEGER NOT NULL, pinned INTEGER NOT NULL, fingerprint TEXT NOT NULL,
                thumbnail BLOB, full_text TEXT, title TEXT);
            CREATE TABLE reps(
                clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
                item INTEGER NOT NULL, idx INTEGER NOT NULL, type TEXT NOT NULL, data BLOB NOT NULL);
            CREATE INDEX reps_clip ON reps(clip_id);
            INSERT INTO clips VALUES ('\(pinned.uuidString)', 0, 'slopapp-test pinned', 19, 0, 0, 19, 0, NULL, NULL,
                \(now.timeIntervalSinceReferenceDate - 900 * 86_400), \(now.timeIntervalSinceReferenceDate - 900 * 86_400),
                3, 1, 'text:pinned', NULL, NULL, NULL);
            INSERT INTO clips VALUES ('\(unpinned.uuidString)', 0, 'slopapp-test loose', 18, 0, 0, 18, 0, NULL, NULL,
                \(now.timeIntervalSinceReferenceDate), \(now.timeIntervalSinceReferenceDate), 1, 0, 'text:loose', NULL, NULL, NULL);
            INSERT INTO reps VALUES ('\(pinned.uuidString)', 0, 0, 'public.utf8-plain-text', CAST('slopapp-test pinned' AS BLOB));
            PRAGMA user_version = 3;
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func execute(_ sql: String, in dir: URL) {
        var db: OpaquePointer?
        guard sqlite3_open(dir.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test func pinnedClipsMoveOntoThePinnedBoard() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pinned = UUID(), unpinned = UUID()
        try makeVersion3(at: dir, pinned: pinned, unpinned: unpinned)

        let db = try ClipDatabase(directory: dir)
        #expect(try await db.loadBoards() == [Board.pinned])
        let clips = try await db.loadAll()
        #expect(clips.count == 2)
        let old = try #require(clips.first { $0.id == pinned })
        #expect(old.boardID == Board.pinnedID)
        #expect(old.isPinned)
        #expect(old.useCount == 3)
        #expect(clips.first { $0.id == unpinned }?.boardID == nil)
        // Still pinned after a prune that would remove a 900-day-old clip, and its content is intact.
        var history = History(clips: clips)
        #expect(history.prune(retention: .month, now: now).isEmpty)
        #expect(try await db.payload(for: pinned)?.plainText()?.items.first?.first?.data == Data("slopapp-test pinned".utf8))

        // Opening again doesn't add another board.
        let reopened = try ClipDatabase(directory: dir)
        #expect(try await reopened.loadBoards().count == 1)
    }

    @Test func aFreshHistoryStartsWithPinned() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        #expect(try await db.loadBoards() == [Board.pinned])
    }

    @Test func boardsAndLabelsRoundTrip() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        var boards = Boards(try await db.loadBoards())
        let work = boards.add(name: "Work")
        boards.move(work.id, by: -1)
        try await db.saveBoards(boards.all)
        #expect(try await db.loadBoards().map(\.name) == ["Work", "Pinned"])

        var (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(text: "slopapp-test board"), sourceBundleID: nil,
                                                    sourceName: nil, now: now).get()
        try await db.save(clip, payload: payload)
        clip.boardID = work.id
        clip.label = "Standup notes"
        try await db.update(clip)
        let loaded = try #require(try await ClipDatabase(directory: dir).loadAll().first)
        #expect(loaded.boardID == work.id)
        #expect(loaded.label == "Standup notes")
        #expect(loaded == clip)

        // Deleting the board takes its clips off it (they stay in the history).
        boards.remove(work.id)
        try await db.saveBoards(boards.all)
        let after = try #require(try await db.loadAll().first)
        #expect(after.boardID == nil)
        #expect(!after.isPinned)
    }

    @Test func pinsMadeByAnOlderBuildAreKept() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = textClip("slopapp-test a", at: now), b = textClip("slopapp-test b", at: now + 1)
        do {
            let db = try ClipDatabase(directory: dir)
            var pinnedB = b
            pinnedB.boardID = Board.pinnedID
            try await db.saveAll([(a, nil), (pinnedB, nil)])
        }
        // An older copy of Clips pins a and unpins b: it only knows the pinned column.
        execute("UPDATE clips SET pinned = 1 WHERE id = '\(a.id.uuidString)'; UPDATE clips SET pinned = 0 WHERE id = '\(b.id.uuidString)';", in: dir)
        let clips = try await ClipDatabase(directory: dir).loadAll()
        #expect(clips.first { $0.id == a.id }?.boardID == Board.pinnedID)
        #expect(clips.first { $0.id == b.id }?.boardID == nil)
    }

    @Test func anOlderPinWithEveryBoardDeletedBringsPinnedBack() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = textClip("slopapp-test a", at: now)
        do {
            let db = try ClipDatabase(directory: dir)
            try await db.saveAll([(a, nil)])
            try await db.saveBoards([])
        }
        execute("UPDATE clips SET pinned = 1", in: dir)
        let db = try ClipDatabase(directory: dir)
        #expect(try await db.loadBoards() == [Board.pinned])
        #expect(try await db.loadAll().first?.boardID == Board.pinnedID)
    }

    @Test func recognizedTextIsStoredAndSearched() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        let png = makePNG(width: 8, height: 8)
        let (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]]),
                                                    sourceBundleID: nil, sourceName: nil, now: now).get()
        try await db.save(clip, payload: payload)
        #expect(try await db.loadAll().first?.recognizedText == nil)
        try await db.setRecognizedText("Invoice 4471\nTotal due", for: clip.id)
        let loaded = try #require(try await db.loadAll().first)
        #expect(loaded.recognizedText == "Invoice 4471\nTotal due")
        #expect(ClipSearch.run([loaded], query: "4471").count == 1)
        #expect(ClipSearch.run([loaded], query: "image").count == 1)
        #expect(ClipSearch.run([clip], query: "4471").isEmpty)
        // The helper reads the image straight from the file, read-only.
        #expect(ClipDatabase.imageData(inFile: db.fileURL, clipID: clip.id) == png)
        #expect(ClipDatabase.imageData(inFile: db.fileURL, clipID: UUID()) == nil)
        // A later metadata save doesn't lose it.
        try await db.update(loaded)
        #expect(try await db.loadAll().first?.recognizedText == "Invoice 4471\nTotal due")
    }
}
