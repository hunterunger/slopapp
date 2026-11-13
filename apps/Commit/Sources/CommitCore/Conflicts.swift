import Foundation

/// A conflicted file split into the text both sides agree on and the conflicts between them,
/// parsed from the markers git writes (`<<<<<<<`, optional `|||||||` base, `=======`, `>>>>>>>`).
///
/// Lines are kept as git wrote them, line endings included, so a resolved file keeps its CRLFs
/// and non-UTF-8 bytes exactly.
public struct ConflictFile: Sendable, Equatable {
    public enum Segment: Sendable, Equatable {
        /// Lines both sides agree on.
        case common([Data])
        /// Index into `conflicts`.
        case conflict(Int)
    }

    public struct Conflict: Sendable, Equatable {
        /// "HEAD" in `<<<<<<< HEAD`.
        public var oursLabel: String
        /// "feature" in `>>>>>>> feature`.
        public var theirsLabel: String
        /// The base (`|||||||`), when the file was written with diff3 or zdiff3 style.
        public var baseLabel: String?
        public var ours: [Data]
        public var base: [Data]?
        public var theirs: [Data]
        /// The marker lines themselves, to write the conflict back unchanged.
        public var markerLines: [Data]
        /// Lines in the file before this conflict (its first line is `startLine + 1`).
        public var startLine: Int
    }

    public var segments: [Segment]
    public var conflicts: [Conflict]
    /// The file isn't valid UTF-8 (resolving by choice still works; editing as text doesn't).
    public var isUTF8: Bool

    /// nil when the data has no complete conflict.
    public static func parse(_ data: Data, markerSize: Int = 7) -> ConflictFile? {
        let lines = splitLines(data)
        var segments: [Segment] = []
        var conflicts: [Conflict] = []
        var common: [Data] = []
        var i = 0
        func flushCommon() {
            if !common.isEmpty { segments.append(.common(common)); common = [] }
        }
        while i < lines.count {
            let line = lines[i]
            guard let label = marker(line, "<", size: markerSize) else {
                common.append(line)
                i += 1
                continue
            }
            // Look for the rest of this conflict; if it isn't complete, treat the line as text.
            var j = i + 1
            var ours: [Data] = [], base: [Data]? = nil, theirs: [Data] = []
            var baseLabel: String?
            var markerLines = [line]
            var part = 0 // 0 ours, 1 base, 2 theirs
            var theirsLabel: String?
            while j < lines.count {
                let l = lines[j]
                if part == 0, let b = marker(l, "|", size: markerSize) {
                    part = 1; baseLabel = b; base = []; markerLines.append(l)
                } else if part < 2, isSeparator(l, size: markerSize) {
                    part = 2; markerLines.append(l)
                } else if part == 2, let t = marker(l, ">", size: markerSize) {
                    theirsLabel = t; markerLines.append(l)
                    break
                } else if marker(l, "<", size: markerSize) != nil {
                    break // a new conflict started before this one ended
                } else {
                    switch part {
                    case 0: ours.append(l)
                    case 1: base?.append(l)
                    default: theirs.append(l)
                    }
                }
                j += 1
            }
            guard let theirsLabel else {
                common.append(line)
                i += 1
                continue
            }
            flushCommon()
            let start = segments.reduce(0) { total, segment in
                switch segment {
                case .common(let c): total + c.count
                case .conflict(let index): total + conflicts[index].lineCountInFile
                }
            }
            conflicts.append(Conflict(oursLabel: label, theirsLabel: theirsLabel, baseLabel: baseLabel,
                                      ours: ours, base: base, theirs: theirs, markerLines: markerLines, startLine: start))
            segments.append(.conflict(conflicts.count - 1))
            i = j + 1
        }
        flushCommon()
        guard !conflicts.isEmpty else { return nil }
        return ConflictFile(segments: segments, conflicts: conflicts, isUTF8: String(data: data, encoding: .utf8) != nil)
    }

    /// The file with each conflict resolved as chosen; conflicts without a choice keep their markers.
    public func resolved(_ choices: [Int: ConflictChoice]) -> Data {
        let ending: [UInt8] = conflicts.first.map { c in c.markerLines[0].suffix(2) == Data([13, 10]) ? [13, 10] : [10] } ?? [10]
        var out = Data()
        func append(_ line: Data) {
            // Joining two sides: one side's last line may lack a newline (the end of the file).
            if let last = out.last, last != 10 { out.append(contentsOf: ending) }
            out.append(line)
        }
        for segment in segments {
            switch segment {
            case .common(let lines):
                lines.forEach(append)
            case .conflict(let index):
                let lines = choices[index].map { conflicts[index].lines(for: $0) } ?? conflicts[index].original
                lines.forEach(append)
            }
        }
        return out
    }

    /// Every conflict has a choice.
    public func isFullyResolved(_ choices: [Int: ConflictChoice]) -> Bool {
        conflicts.indices.allSatisfy { choices[$0] != nil }
    }

    /// Lines split after each `\n`, endings kept. A last line without one stays as it is.
    static func splitLines(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        for i in data.indices where data[i] == 10 {
            lines.append(data[start...i])
            start = data.index(after: i)
        }
        if start < data.endIndex { lines.append(data[start..<data.endIndex]) }
        return lines.map { Data($0) }
    }

    /// The label after a marker line of `size` copies of `character` ("<<<<<<< HEAD" → "HEAD").
    static func marker(_ line: Data, _ character: Character, size: Int) -> String? {
        let byte = character.asciiValue!
        guard line.count >= size, line.prefix(size).allSatisfy({ $0 == byte }) else { return nil }
        let rest = line.dropFirst(size)
        if let next = rest.first, next == byte { return nil } // a longer run is a different marker size
        if let next = rest.first, next != 32, next != 10, next != 13 { return nil }
        return String(decoding: rest, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSeparator(_ line: Data, size: Int) -> Bool {
        let trimmed = line.filter { $0 != 10 && $0 != 13 }
        return trimmed.count == size && trimmed.allSatisfy { $0 == UInt8(ascii: "=") }
    }

}

/// How one conflict is resolved.
public enum ConflictChoice: Sendable, Equatable, Hashable {
    case ours, theirs
    /// Ours, then theirs.
    case both
    /// Theirs, then ours.
    case bothTheirsFirst
    /// The common ancestor (only for files written with a base).
    case base
    /// Neither side.
    case neither
}

public extension ConflictFile.Conflict {
    /// The conflict as git wrote it, markers included.
    var original: [Data] {
        var lines = [markerLines[0]] + ours
        var next = 1
        if let base {
            lines.append(markerLines[next]); next += 1
            lines += base
        }
        lines.append(markerLines[next]); next += 1
        lines += theirs
        lines.append(markerLines[next])
        return lines
    }

    var lineCountInFile: Int { original.count }

    func lines(for choice: ConflictChoice) -> [Data] {
        switch choice {
        case .ours: ours
        case .theirs: theirs
        case .both: ours + theirs
        case .bothTheirsFirst: theirs + ours
        case .base: base ?? []
        case .neither: []
        }
    }
}

/// What kind of conflict a file has, from the two letters of `git status` ("UU", "UD"…).
public enum ConflictKind: Sendable, Equatable {
    case bothModified, bothAdded, bothDeleted
    case deletedByUs, deletedByThem
    case addedByUs, addedByThem

    public init(code: String) {
        switch code {
        case "AA": self = .bothAdded
        case "DD": self = .bothDeleted
        case "DU": self = .deletedByUs
        case "UD": self = .deletedByThem
        case "AU": self = .addedByUs
        case "UA": self = .addedByThem
        default: self = .bothModified
        }
    }

    /// Our side has no file.
    public var oursMissing: Bool { self == .deletedByUs || self == .bothDeleted || self == .addedByThem }
    /// Their side has no file.
    public var theirsMissing: Bool { self == .deletedByThem || self == .bothDeleted || self == .addedByUs }

    /// One sentence for the resolver's header.
    public var explanation: String {
        switch self {
        case .bothModified: "Both sides changed this file."
        case .bothAdded: "Both sides added a file with this name."
        case .bothDeleted: "Both sides deleted this file."
        case .deletedByUs: "Your side deleted this file; the other side changed it."
        case .deletedByThem: "The other side deleted this file; your side changed it."
        case .addedByUs: "Only your side has this file."
        case .addedByThem: "Only the other side has this file."
        }
    }
}

public extension StatusEntry {
    var conflictKind: ConflictKind? {
        if case .unmerged(let code) = kind { return ConflictKind(code: code) }
        return nil
    }
}

/// Saved before resolving a conflicted file: its bytes and its index stages, so ⌘Z can put the
/// conflict back exactly (markers in the file, stages 1–3 in the index).
public struct ConflictSnapshot: Sendable, Equatable {
    public var path: String
    /// nil when the file didn't exist in the working tree.
    public var contents: Data?
    /// `git ls-files -s` lines for the path ("mode hash stage\tpath").
    public var stages: [String]
}

/// Which `git mergetool` the user configured, and whether it can run without a terminal.
public struct MergeToolSetting: Sendable, Equatable {
    public var name: String?

    public init(name: String?) { self.name = name }

    /// Tools that need a terminal (vimdiff, emerge…) can't run from a Mac app.
    public var needsTerminal: Bool {
        guard let name else { return false }
        let terminal = ["vimdiff", "vimdiff1", "vimdiff2", "vimdiff3", "nvimdiff", "nvimdiff1", "nvimdiff2", "nvimdiff3", "emerge", "vim", "nvim"]
        return terminal.contains(name)
    }

    public var isUsable: Bool { name != nil && !needsTerminal }
}

public extension Repository {
    /// The file's conflict markers, parsed (nil: no markers, e.g. a delete/modify conflict or binary file).
    func conflictFile(_ path: String) async -> ConflictFile? {
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path) else { return nil }
        if data.prefix(8000).contains(0) { return nil } // binary
        return ConflictFile.parse(data, markerSize: await conflictMarkerSize(path))
    }

    /// `conflict-marker-size` from .gitattributes, else 7.
    func conflictMarkerSize(_ path: String) async -> Int {
        // "path: conflict-marker-size: 10"
        guard let output = try? await read(["check-attr", "conflict-marker-size", "--", path]).stdoutString,
              let value = output.split(separator: ":").last.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              let size = Int(value), size > 0 else { return 7 }
        return size
    }

    /// The file and its stages, before resolving it.
    func snapshotConflict(_ path: String) async throws -> ConflictSnapshot {
        let contents = FileManager.default.contents(atPath: root.appendingPathComponent(path).path)
        let result = try await read(["ls-files", "-s", "-z", "--", path])
        let lines = result.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return ConflictSnapshot(path: path, contents: contents, stages: lines)
    }

    /// Writes the resolved file and stages it (marks it resolved).
    func resolveConflict(_ path: String, with data: Data) async throws {
        try await exclusive {
            try data.write(to: self.root.appendingPathComponent(path))
            try await self.write(["add", "--", path])
        }
    }

    /// Resolves with one side's whole file (`checkout --ours/--theirs`), or removes the file
    /// when that side deleted it.
    func resolveConflict(_ entry: StatusEntry, takingOurs: Bool) async throws {
        let kind = entry.conflictKind ?? .bothModified
        let missing = takingOurs ? kind.oursMissing : kind.theirsMissing
        try await exclusive {
            if missing {
                try await self.write(["rm", "-q", "--ignore-unmatch", "--", entry.path])
            } else {
                try await self.write(["checkout", takingOurs ? "--ours" : "--theirs", "--", entry.path], environment: Self.english)
                try await self.write(["add", "--", entry.path])
            }
        }
    }

    /// Puts a conflict back as it was before it was resolved (Undo Mark Resolved).
    func restoreConflict(_ snapshot: ConflictSnapshot) async throws {
        try await exclusive {
            let url = self.root.appendingPathComponent(snapshot.path)
            if let contents = snapshot.contents {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            // A mode-0 entry removes the path; then the stage lines put the conflict back.
            let remove = "0 \(String(repeating: "0", count: 40)) 0\t\(snapshot.path)"
            let lines = [remove] + snapshot.stages
            try await self.write(["update-index", "-z", "--index-info"],
                                 stdin: Data(lines.joined(separator: "\0").utf8 + [0]))
        }
    }

    /// The user's `merge.tool`.
    func mergeTool() async -> MergeToolSetting {
        let name = try? await read(["config", "--get", "merge.tool"]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return MergeToolSetting(name: (name?.isEmpty ?? true) ? nil : name)
    }

    /// Runs the user's merge tool on one file and waits for it to close. git stages the file
    /// if the tool reports success.
    func runMergeTool(_ path: String) async throws {
        try await write(["mergetool", "--no-prompt", "--", path], environment: Self.english)
    }
}
