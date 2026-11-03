import Foundation
import SQLite3

/// Stores the history in one SQLite file (`history.sqlite`), readable only by the user.
/// Metadata loads at launch; payloads (rich text, image bytes) load only when pasted.
/// All access goes through this actor, off the main thread.
public actor ClipDatabase {
    public enum Failure: Error, Equatable {
        case open(String)
        case sql(String)
    }

    // Only touched inside the actor, and in deinit once nothing else can.
    private nonisolated(unsafe) var db: OpaquePointer?
    public nonisolated let fileURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        fileURL = directory.appendingPathComponent("history.sqlite")
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw Failure.open(message)
        }
        db = handle
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        try Self.exec(handle, """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS clips(
                id TEXT PRIMARY KEY, kind INTEGER NOT NULL, text TEXT NOT NULL, text_length INTEGER NOT NULL,
                width INTEGER NOT NULL, height INTEGER NOT NULL, bytes INTEGER NOT NULL, rich INTEGER NOT NULL,
                source_id TEXT, source_name TEXT, created REAL NOT NULL, last_used REAL NOT NULL,
                use_count INTEGER NOT NULL, pinned INTEGER NOT NULL, fingerprint TEXT NOT NULL,
                thumbnail BLOB);
            CREATE TABLE IF NOT EXISTS reps(
                clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
                item INTEGER NOT NULL, idx INTEGER NOT NULL, type TEXT NOT NULL, data BLOB NOT NULL);
            CREATE INDEX IF NOT EXISTS reps_clip ON reps(clip_id);
            """)
        try Self.migrate(handle)
    }

    /// Schema changes since the first release. `user_version` says which have run.
    private static func migrate(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        var version: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW {
            version = sqlite3_column_int(statement, 0)
        }
        sqlite3_finalize(statement)
        if version < 2 {
            // v2: the text search sees for long clips (up to Clip.searchLimit characters),
            // backfilled from the stored plain text.
            let hasColumn = (try? exec(db, "SELECT full_text FROM clips LIMIT 0")) != nil
            if !hasColumn { try exec(db, "ALTER TABLE clips ADD COLUMN full_text TEXT") }
            try exec(db, """
                UPDATE clips SET full_text = substr(CAST((SELECT data FROM reps WHERE reps.clip_id = clips.id
                    AND reps.type = '\(PasteboardType.string)' LIMIT 1) AS TEXT), 1, \(Clip.searchLimit))
                WHERE text_length > \(Clip.textLimit) AND full_text IS NULL;
                PRAGMA user_version = 2;
                """)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Reading

    /// Every clip's metadata, most recently used first.
    public func loadAll() throws -> [Clip] {
        let statement = try prepare("""
            SELECT id, kind, text, text_length, width, height, bytes, rich, source_id, source_name,
                   created, last_used, use_count, pinned, fingerprint, full_text FROM clips ORDER BY last_used DESC
            """)
        defer { sqlite3_finalize(statement) }
        var clips: [Clip] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: column(statement, 0) ?? "") else { continue }
            clips.append(Clip(
                id: id,
                kind: ClipKind(rawValue: Int(sqlite3_column_int(statement, 1))) ?? .text,
                text: column(statement, 2) ?? "",
                textLength: Int(sqlite3_column_int64(statement, 3)),
                longText: column(statement, 15),
                imageWidth: Int(sqlite3_column_int(statement, 4)),
                imageHeight: Int(sqlite3_column_int(statement, 5)),
                byteCount: Int(sqlite3_column_int64(statement, 6)),
                hasRichText: sqlite3_column_int(statement, 7) != 0,
                sourceBundleID: column(statement, 8),
                sourceName: column(statement, 9),
                created: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 10)),
                lastUsed: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 11)),
                useCount: Int(sqlite3_column_int(statement, 12)),
                isPinned: sqlite3_column_int(statement, 13) != 0,
                fingerprint: column(statement, 14) ?? ""
            ))
        }
        return clips
    }

    /// The full content of a clip, for putting it back on the pasteboard.
    public func payload(for id: UUID) throws -> ClipPayload? {
        let statement = try prepare("SELECT item, type, data FROM reps WHERE clip_id = ? ORDER BY item, idx")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        var items: [Int: [Representation]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let item = Int(sqlite3_column_int(statement, 0))
            let type = column(statement, 1) ?? ""
            items[item, default: []].append(Representation(type: type, data: blob(statement, 2)))
        }
        guard !items.isEmpty else { return nil }
        return ClipPayload(items: items.keys.sorted().compactMap { items[$0] })
    }

    /// A small PNG preview of an image clip.
    public func thumbnail(for id: UUID) throws -> Data? {
        let statement = try prepare("SELECT thumbnail FROM clips WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return blob(statement, 0)
    }

    public func count() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM clips")
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    // MARK: - Writing

    /// Inserts a clip with its payload, or replaces the stored one with the same id.
    public func save(_ clip: Clip, payload: ClipPayload?, thumbnail: Data? = nil) throws {
        try transaction {
            try upsert(clip, thumbnail: thumbnail, replaceThumbnail: payload != nil)
            if let payload {
                try run("DELETE FROM reps WHERE clip_id = ?", [clip.id.uuidString])
                let statement = try prepare("INSERT INTO reps(clip_id, item, idx, type, data) VALUES (?, ?, ?, ?, ?)")
                defer { sqlite3_finalize(statement) }
                for (itemIndex, item) in payload.items.enumerated() {
                    for (repIndex, rep) in item.enumerated() {
                        sqlite3_reset(statement)
                        bind(statement, 1, clip.id.uuidString)
                        sqlite3_bind_int(statement, 2, Int32(itemIndex))
                        sqlite3_bind_int(statement, 3, Int32(repIndex))
                        bind(statement, 4, rep.type)
                        bindBlob(statement, 5, rep.data)
                        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
                    }
                }
            }
        }
    }

    /// Saves many clips in one transaction (synthetic data, undo of a big delete).
    public func saveAll(_ entries: [(Clip, ClipPayload?)]) throws {
        try transaction {
            for (clip, payload) in entries {
                try upsert(clip, thumbnail: nil, replaceThumbnail: false)
                if let payload {
                    let statement = try prepare("INSERT INTO reps(clip_id, item, idx, type, data) VALUES (?, ?, ?, ?, ?)")
                    defer { sqlite3_finalize(statement) }
                    for (itemIndex, item) in payload.items.enumerated() {
                        for (repIndex, rep) in item.enumerated() {
                            sqlite3_reset(statement)
                            bind(statement, 1, clip.id.uuidString)
                            sqlite3_bind_int(statement, 2, Int32(itemIndex))
                            sqlite3_bind_int(statement, 3, Int32(repIndex))
                            bind(statement, 4, rep.type)
                            bindBlob(statement, 5, rep.data)
                            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
                        }
                    }
                }
            }
        }
    }

    /// Updates metadata only (pinned, last used, use count).
    public func update(_ clip: Clip) throws {
        try run("UPDATE clips SET last_used = ?, use_count = ?, pinned = ?, source_id = ?, source_name = ?, rich = ?, bytes = ? WHERE id = ?",
                [clip.lastUsed.timeIntervalSinceReferenceDate, clip.useCount, clip.isPinned ? 1 : 0,
                 clip.sourceBundleID, clip.sourceName, clip.hasRichText ? 1 : 0, clip.byteCount, clip.id.uuidString])
    }

    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            for id in ids {
                try run("DELETE FROM clips WHERE id = ?", [id.uuidString])
            }
        }
    }

    /// Payloads for several clips, so a delete can be undone.
    public func payloads(for ids: [UUID]) throws -> [UUID: ClipPayload] {
        var result: [UUID: ClipPayload] = [:]
        for id in ids {
            if let payload = try payload(for: id) { result[id] = payload }
        }
        return result
    }

    /// Reclaims space after big deletions.
    public func compact() throws {
        try Self.exec(db, "PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }

    // MARK: - SQLite plumbing

    private func upsert(_ clip: Clip, thumbnail: Data?, replaceThumbnail: Bool) throws {
        let sql = """
            INSERT INTO clips(id, kind, text, text_length, width, height, bytes, rich, source_id, source_name,
                              created, last_used, use_count, pinned, fingerprint, thumbnail, full_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, text = excluded.text,
                text_length = excluded.text_length, width = excluded.width, height = excluded.height,
                bytes = excluded.bytes, rich = excluded.rich, source_id = excluded.source_id,
                source_name = excluded.source_name, last_used = excluded.last_used,
                use_count = excluded.use_count, pinned = excluded.pinned, fingerprint = excluded.fingerprint,
                full_text = excluded.full_text
                \(replaceThumbnail ? ", thumbnail = excluded.thumbnail" : "")
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, clip.id.uuidString)
        sqlite3_bind_int(statement, 2, Int32(clip.kind.rawValue))
        bind(statement, 3, clip.text)
        sqlite3_bind_int64(statement, 4, Int64(clip.textLength))
        sqlite3_bind_int(statement, 5, Int32(clip.imageWidth))
        sqlite3_bind_int(statement, 6, Int32(clip.imageHeight))
        sqlite3_bind_int64(statement, 7, Int64(clip.byteCount))
        sqlite3_bind_int(statement, 8, clip.hasRichText ? 1 : 0)
        bind(statement, 9, clip.sourceBundleID)
        bind(statement, 10, clip.sourceName)
        sqlite3_bind_double(statement, 11, clip.created.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 12, clip.lastUsed.timeIntervalSinceReferenceDate)
        sqlite3_bind_int(statement, 13, Int32(clip.useCount))
        sqlite3_bind_int(statement, 14, clip.isPinned ? 1 : 0)
        bind(statement, 15, clip.fingerprint)
        if let thumbnail { bindBlob(statement, 16, thumbnail) } else { sqlite3_bind_null(statement, 16) }
        bind(statement, 17, clip.longText)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try Self.exec(db, "BEGIN IMMEDIATE")
        do {
            try body()
            try Self.exec(db, "COMMIT")
        } catch {
            try? Self.exec(db, "ROLLBACK")
            throw error
        }
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let string as String: bind(statement, index, string)
            case let int as Int: sqlite3_bind_int64(statement, index, Int64(int))
            case let double as Double: sqlite3_bind_double(statement, index, double)
            default: sqlite3_bind_null(statement, index)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        return statement
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw Failure.sql(message)
        }
    }

    private func lastError() -> Failure {
        .sql(String(cString: sqlite3_errmsg(db)))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bindBlob(_ statement: OpaquePointer?, _ index: Int32, _ data: Data) {
        data.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func blob(_ statement: OpaquePointer?, _ index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
