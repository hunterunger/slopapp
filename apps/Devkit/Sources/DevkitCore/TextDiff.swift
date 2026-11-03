import Foundation

/// Line diff (Myers, via `CollectionDifference`) with side-by-side rows, a unified diff and
/// character-level highlights inside changed lines.
public enum TextDiff {
    public struct Options: Sendable, Equatable {
        public var ignoreWhitespace: Bool
        public var ignoreCase: Bool
        public init(ignoreWhitespace: Bool = false, ignoreCase: Bool = false) {
            self.ignoreWhitespace = ignoreWhitespace
            self.ignoreCase = ignoreCase
        }
    }

    public enum Kind: Sendable, Equatable {
        case same, removed, added, changed
    }

    /// One row of a side-by-side view. Line numbers are 1-based.
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: Int
        public var kind: Kind
        public var oldLine: Int?
        public var newLine: Int?
        public var oldText: String?
        public var newText: String?
        /// UTF-16 ranges inside the texts that differ (changed rows only).
        public var oldHighlights: [NSRange] = []
        public var newHighlights: [NSRange] = []
    }

    public struct Result: Sendable, Equatable {
        public var rows: [Row]
        public var added: Int
        public var removed: Int
        public var isIdentical: Bool { added == 0 && removed == 0 }
    }

    public static func lines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    static func key(_ line: String, _ options: Options) -> String {
        var key = line
        if options.ignoreWhitespace { key = key.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        if options.ignoreCase { key = key.lowercased() }
        return key
    }

    public static func compare(_ old: String, _ new: String, options: Options = Options()) -> Result {
        let oldLines = lines(old), newLines = lines(new)
        let oldKeys = oldLines.map { key($0, options) }, newKeys = newLines.map { key($0, options) }
        let difference = newKeys.difference(from: oldKeys)
        var removedOffsets = Set<Int>(), insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removedOffsets.insert(offset)
            case let .insert(offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var rows: [Row] = []
        var oldIndex = 0, newIndex = 0
        var pendingRemoved: [Int] = [], pendingAdded: [Int] = []

        func flush() {
            // Pair removals with additions as changed lines, then the leftovers.
            let paired = min(pendingRemoved.count, pendingAdded.count)
            for index in 0..<paired {
                let o = pendingRemoved[index], n = pendingAdded[index]
                var row = Row(id: rows.count, kind: .changed, oldLine: o + 1, newLine: n + 1, oldText: oldLines[o], newText: newLines[n])
                (row.oldHighlights, row.newHighlights) = characterHighlights(oldLines[o], newLines[n])
                rows.append(row)
            }
            for o in pendingRemoved.dropFirst(paired) {
                rows.append(Row(id: rows.count, kind: .removed, oldLine: o + 1, oldText: oldLines[o]))
            }
            for n in pendingAdded.dropFirst(paired) {
                rows.append(Row(id: rows.count, kind: .added, newLine: n + 1, newText: newLines[n]))
            }
            pendingRemoved.removeAll()
            pendingAdded.removeAll()
        }

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removedOffsets.contains(oldIndex) {
                pendingRemoved.append(oldIndex)
                oldIndex += 1
            } else if newIndex < newLines.count, insertedOffsets.contains(newIndex) {
                pendingAdded.append(newIndex)
                newIndex += 1
            } else {
                flush()
                guard oldIndex < oldLines.count, newIndex < newLines.count else { break }
                rows.append(Row(id: rows.count, kind: .same, oldLine: oldIndex + 1, newLine: newIndex + 1,
                                oldText: oldLines[oldIndex], newText: newLines[newIndex]))
                oldIndex += 1
                newIndex += 1
            }
        }
        flush()
        return Result(rows: rows, added: insertedOffsets.count, removed: removedOffsets.count)
    }

    /// Ranges of characters that differ between two similar lines (skipped for long lines).
    static func characterHighlights(_ old: String, _ new: String) -> ([NSRange], [NSRange]) {
        let a = Array(old), b = Array(new)
        guard a.count <= 2000, b.count <= 2000 else { return ([], []) }
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        return (ranges(of: removed, in: a), ranges(of: inserted, in: b))
    }

    static func ranges(of offsets: Set<Int>, in characters: [Character]) -> [NSRange] {
        var ranges: [NSRange] = []
        var utf16Offset = 0
        var current: NSRange?
        for (index, character) in characters.enumerated() {
            let length = character.utf16.count
            if offsets.contains(index) {
                if let range = current, range.location + range.length == utf16Offset {
                    current = NSRange(location: range.location, length: range.length + length)
                } else {
                    if let range = current { ranges.append(range) }
                    current = NSRange(location: utf16Offset, length: length)
                }
            }
            utf16Offset += length
        }
        if let range = current { ranges.append(range) }
        return ranges
    }

    /// A unified diff (`diff -u` style) with `context` lines around each change.
    public static func unified(_ result: Result, oldName: String = "Original", newName: String = "Changed", context: Int = 3) -> String {
        guard !result.isIdentical else { return "" }
        // Expand changed rows into a removal and an addition.
        struct Line { var prefix: Character; var text: String }
        var lines: [Line] = []
        for row in result.rows {
            switch row.kind {
            case .same: lines.append(Line(prefix: " ", text: row.oldText ?? ""))
            case .removed: lines.append(Line(prefix: "-", text: row.oldText ?? ""))
            case .added: lines.append(Line(prefix: "+", text: row.newText ?? ""))
            case .changed:
                lines.append(Line(prefix: "-", text: row.oldText ?? ""))
                lines.append(Line(prefix: "+", text: row.newText ?? ""))
            }
        }
        var output = ["--- \(oldName)", "+++ \(newName)"]
        // Hunks: each change plus `context` lines around it, merged when they touch.
        var hunks: [ClosedRange<Int>] = []
        for (index, line) in lines.enumerated() where line.prefix != " " {
            let range = max(0, index - context)...min(lines.count - 1, index + context)
            if let last = hunks.last, range.lowerBound <= last.upperBound + 1 {
                hunks[hunks.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                hunks.append(range)
            }
        }
        for hunk in hunks {
            let before = lines[..<hunk.lowerBound]
            let oldBefore = before.filter { $0.prefix != "+" }.count
            let newBefore = before.filter { $0.prefix != "-" }.count
            let body = lines[hunk]
            let oldCount = body.filter { $0.prefix != "+" }.count
            let newCount = body.filter { $0.prefix != "-" }.count
            let oldStart = oldCount == 0 ? oldBefore : oldBefore + 1
            let newStart = newCount == 0 ? newBefore : newBefore + 1
            output.append("@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@")
            for line in body { output.append("\(line.prefix)\(line.text)") }
        }
        return output.joined(separator: "\n")
    }
}
