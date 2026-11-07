import Foundation

/// A line in a file diff: hunk index and line index within the hunk.
public struct LineRef: Hashable, Sendable, Comparable {
    public var hunk: Int
    public var line: Int

    public init(hunk: Int, line: Int) {
        self.hunk = hunk
        self.line = line
    }

    public static func < (a: LineRef, b: LineRef) -> Bool { (a.hunk, a.line) < (b.hunk, b.line) }
}

/// Builds the patch that applies only chosen lines of a diff, from its raw bytes.
///
/// - `.forward`: stage lines of the unstaged diff (`git apply --cached`).
/// - `.reverse`: unstage lines of the staged diff (`git apply --cached -R`) or discard
///   lines of the unstaged diff (`git apply -R`).
///
/// Unselected changes become context on the side the patch is applied to and disappear on
/// the other, so the patch applies cleanly whatever else is in the file.
public enum PatchBuilder {
    public enum Direction: Sendable { case forward, reverse }

    /// Every changed line of the file.
    public static func allChanges(in file: FileDiff) -> Set<LineRef> {
        var refs = Set<LineRef>()
        for (h, hunk) in file.hunks.enumerated() {
            for (l, line) in hunk.lines.enumerated() where line.isChange { refs.insert(LineRef(hunk: h, line: l)) }
        }
        return refs
    }

    /// Every changed line of one hunk.
    public static func changes(inHunk index: Int, of file: FileDiff) -> Set<LineRef> {
        guard file.hunks.indices.contains(index) else { return [] }
        var refs = Set<LineRef>()
        for (l, line) in file.hunks[index].lines.enumerated() where line.isChange { refs.insert(LineRef(hunk: index, line: l)) }
        return refs
    }

    /// The patch, or nil when nothing selected is a change (or the file is binary).
    public static func patch(for file: FileDiff, selecting selection: Set<LineRef>, direction: Direction) -> Data? {
        guard !file.isBinary else { return nil }
        let changed = selection.filter { ref in
            file.hunks.indices.contains(ref.hunk) && file.hunks[ref.hunk].lines.indices.contains(ref.line)
                && file.hunks[ref.hunk].lines[ref.line].isChange
        }
        guard !changed.isEmpty else { return nil }
        let isPartial = changed.count < file.changedLineCount

        var out = Data()
        out.reserveCapacity(file.raw.count)
        for line in header(of: file, partial: isPartial, direction: direction) {
            out.append(line)
            out.append(10)
        }

        var delta = 0 // (new count − old count) of the hunks written so far
        for (h, hunk) in file.hunks.enumerated() {
            guard hunk.lines.indices.contains(where: { changed.contains(LineRef(hunk: h, line: $0)) }) else { continue }
            var body = Data()
            var oldCount = 0, newCount = 0
            func emit(_ marker: UInt8, _ line: DiffLine) {
                body.append(marker)
                body.append(file.bytes(of: line))
                body.append(10)
                if line.noNewlineAtEnd { body.append(contentsOf: Array("\\ No newline at end of file\n".utf8)) }
                switch marker {
                case UInt8(ascii: "+"): newCount += 1
                case UInt8(ascii: "-"): oldCount += 1
                default: oldCount += 1; newCount += 1
                }
            }
            // Walk context lines and change blocks (runs of − and + lines). In a block, the
            // side the patch applies to keeps its order (selected lines as changes, the rest
            // as context); the selected lines of the other side are placed next to the line
            // they pair with (the i-th removal with the i-th addition), so replacing b with B
            // in "−b −c +B +c" stages as "a B c", not "a c B".
            var l = 0
            let lines = hunk.lines
            while l < lines.count {
                if lines[l].kind == .context {
                    emit(UInt8(ascii: " "), lines[l])
                    l += 1
                    continue
                }
                var removals: [(Int, DiffLine)] = [], additions: [(Int, DiffLine)] = []
                while l < lines.count, lines[l].kind != .context {
                    if lines[l].kind == .removed { removals.append((l, lines[l])) } else { additions.append((l, lines[l])) }
                    l += 1
                }
                func isSelected(_ index: Int) -> Bool { changed.contains(LineRef(hunk: h, line: index)) }
                switch direction {
                case .forward:
                    let moving = additions.enumerated().filter { isSelected($0.element.0) }
                    for (i, removal) in removals.enumerated() {
                        emit(isSelected(removal.0) ? UInt8(ascii: "-") : UInt8(ascii: " "), removal.1)
                        for (j, addition) in moving where j == i { emit(UInt8(ascii: "+"), addition.1) }
                    }
                    for (j, addition) in moving where j >= removals.count { emit(UInt8(ascii: "+"), addition.1) }
                case .reverse:
                    let moving = removals.enumerated().filter { isSelected($0.element.0) }
                    for (i, addition) in additions.enumerated() {
                        for (j, removal) in moving where j == i { emit(UInt8(ascii: "-"), removal.1) }
                        emit(isSelected(addition.0) ? UInt8(ascii: "+") : UInt8(ascii: " "), addition.1)
                    }
                    for (j, removal) in moving where j >= additions.count { emit(UInt8(ascii: "-"), removal.1) }
                }
            }
            // A side with no lines names the line before it, so an insertion's other side
            // starts one later.
            let oldStart: Int, newStart: Int
            switch direction {
            case .forward:
                oldStart = hunk.oldStart
                let base = hunk.oldStart + (oldCount == 0 ? 1 : 0) + delta
                newStart = max(0, newCount == 0 ? base - 1 : base)
            case .reverse:
                newStart = hunk.newStart
                let base = hunk.newStart + (newCount == 0 ? 1 : 0) - delta
                oldStart = max(0, oldCount == 0 ? base - 1 : base)
            }
            delta += newCount - oldCount
            let header = "@@ -\(DiffHunk.range(oldStart, oldCount)) +\(DiffHunk.range(newStart, newCount)) @@\n"
            out.append(contentsOf: Array(header.utf8))
            out.append(body)
        }
        return out
    }

    /// The file header, adjusted when only part of a new or deleted file is applied: the
    /// result is then an ordinary modification, not a creation or deletion.
    static func header(of file: FileDiff, partial: Bool, direction: Direction) -> [Data] {
        let deletionToModify = partial && file.isDeleted && direction == .forward
        let creationToModify = partial && file.isNew && direction == .reverse
        guard deletionToModify || creationToModify else { return file.header }
        var lines: [Data] = []
        let minus = Data("--- ".utf8), plus = Data("+++ ".utf8)
        var oldSide: Data?, newSide: Data?
        for line in file.header {
            if line.starts(with: minus) { oldSide = line.dropFirst(4) }
            if line.starts(with: plus) { newSide = line.dropFirst(4) }
        }
        for line in file.header {
            if line.starts(with: Data("deleted file mode ".utf8)) || line.starts(with: Data("new file mode ".utf8))
                || line.starts(with: Data("index ".utf8)) {
                continue
            }
            if deletionToModify, line.starts(with: plus), let oldSide {
                lines.append(plus + swapSidePrefix(oldSide, from: "a/", to: "b/"))
            } else if creationToModify, line.starts(with: minus), let newSide {
                lines.append(minus + swapSidePrefix(newSide, from: "b/", to: "a/"))
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    /// "a/path" → "b/path", also inside quotes ("\"a/p q\"").
    static func swapSidePrefix(_ value: Data, from: String, to: String) -> Data {
        var bytes = [UInt8](value)
        let offset = bytes.first == UInt8(ascii: "\"") ? 1 : 0
        let fromBytes = Array(from.utf8)
        if bytes.count >= offset + fromBytes.count, Array(bytes[offset..<offset + fromBytes.count]) == fromBytes {
            bytes.replaceSubrange(offset..<offset + fromBytes.count, with: Array(to.utf8))
        }
        return Data(bytes)
    }
}
