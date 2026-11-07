import Foundation

/// One line of a hunk. Content is a range into the file diff's raw bytes, so a 200,000-line
/// diff costs ~20 bytes a line and patches are rebuilt from the exact bytes (CRLF,
/// non-UTF-8 and missing final newlines round-trip).
public struct DiffLine: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case context, added, removed }

    public var kind: Kind
    /// Followed by "\ No newline at end of file".
    public var noNewlineAtEnd: Bool
    /// 1-based line numbers; 0 when the line doesn't exist on that side.
    public var oldNumber: Int32
    public var newNumber: Int32
    /// Byte range of the line in `FileDiff.raw`, without the leading marker and the "\n".
    public var start: Int32
    public var length: Int32

    public var isChange: Bool { kind != .context }
}

public struct DiffHunk: Sendable, Equatable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// The text after the second "@@" (often the enclosing function).
    public var heading: String
    public var lines: [DiffLine]

    public var headerText: String {
        "@@ -\(DiffHunk.range(oldStart, oldCount)) +\(DiffHunk.range(newStart, newCount)) @@" + (heading.isEmpty ? "" : " \(heading)")
    }

    static func range(_ start: Int, _ count: Int) -> String { count == 1 ? "\(start)" : "\(start),\(count)" }

    public var changedLineCount: Int { lines.lazy.filter(\.isChange).count }
}

/// One file's diff.
public struct FileDiff: Sendable, Equatable {
    /// The file's diff bytes, from "diff --git" to the end of its last hunk.
    public var raw: Data
    /// Raw header lines (without "\n"), from "diff --git" up to the first hunk.
    public var header: [Data]
    public var oldPath: String?
    public var newPath: String?
    public var isNew: Bool
    public var isDeleted: Bool
    public var isBinary: Bool
    public var oldMode: String?
    public var newMode: String?
    public var hunks: [DiffHunk]

    public init(raw: Data = Data(), header: [Data] = [], oldPath: String? = nil, newPath: String? = nil,
                isNew: Bool = false, isDeleted: Bool = false, isBinary: Bool = false,
                oldMode: String? = nil, newMode: String? = nil, hunks: [DiffHunk] = []) {
        self.raw = raw; self.header = header; self.oldPath = oldPath; self.newPath = newPath
        self.isNew = isNew; self.isDeleted = isDeleted; self.isBinary = isBinary
        self.oldMode = oldMode; self.newMode = newMode; self.hunks = hunks
    }

    public var path: String { newPath ?? oldPath ?? "" }
    public var isRename: Bool { oldPath != nil && newPath != nil && oldPath != newPath }
    public var isModeChangeOnly: Bool { hunks.isEmpty && !isBinary && oldMode != nil && newMode != nil && oldMode != newMode }
    public var lineCount: Int { hunks.reduce(0) { $0 + $1.lines.count } }
    public var changedLineCount: Int { hunks.reduce(0) { $0 + $1.changedLineCount } }
    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.lazy.filter { $0.kind == .added }.count } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.lazy.filter { $0.kind == .removed }.count } }

    /// The raw bytes of a line (no marker, no "\n"; a CRLF file keeps its "\r").
    public func bytes(of line: DiffLine) -> Data {
        let start = raw.startIndex + Int(line.start)
        return raw[start..<start + Int(line.length)]
    }

    /// The line for display: decoded leniently, trailing "\r" removed, tabs kept.
    public func text(of line: DiffLine) -> String {
        var data = bytes(of: line)
        if data.last == 13 { data = data.dropLast() }
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the line ends with "\r" (shown as a CRLF marker).
    public func hasCarriageReturn(_ line: DiffLine) -> Bool { bytes(of: line).last == 13 }
}

/// Parses `git diff` / `git show` patch output (no colour) into files and hunks.
public enum DiffParser {
    public static func parse(_ data: Data) -> [FileDiff] {
        var files: [FileDiff] = []
        let bytes = [UInt8](data)
        var lineStarts: [(Int, Int)] = [] // (start, end excluding \n)
        lineStarts.reserveCapacity(bytes.count / 30 + 1)
        var start = 0
        bytes.withUnsafeBufferPointer { buf in
            var i = 0
            let n = buf.count
            while i < n {
                if buf[i] == 10 {
                    lineStarts.append((start, i))
                    start = i + 1
                }
                i += 1
            }
        }
        if start < bytes.count { lineStarts.append((start, bytes.count)) }

        var fileStart: Int?
        for (index, (s, e)) in lineStarts.enumerated() where hasPrefix(bytes, s, e, "diff --git ") {
            if let f = fileStart { files.append(parseFile(bytes, lines: Array(lineStarts[f..<index]))) }
            fileStart = index
        }
        if let f = fileStart, f < lineStarts.count {
            files.append(parseFile(bytes, lines: Array(lineStarts[f...])))
        }
        return files
    }

    /// Parses the diff of a single file (or the first file of the output).
    public static func parseSingle(_ data: Data) -> FileDiff? { parse(data).first }

    private static func hasPrefix(_ bytes: [UInt8], _ s: Int, _ e: Int, _ prefix: StaticString) -> Bool {
        let count = prefix.utf8CodeUnitCount
        guard e - s >= count else { return false }
        return prefix.withUTF8Buffer { p in
            for k in 0..<count where bytes[s + k] != p[k] { return false }
            return true
        }
    }

    private static func string(_ bytes: [UInt8], _ s: Int, _ e: Int) -> String {
        String(decoding: bytes[s..<e], as: UTF8.self)
    }

    private static func parseFile(_ bytes: [UInt8], lines: [(Int, Int)]) -> FileDiff {
        let fileStartByte = lines.first!.0
        let fileEndByte = min(bytes.count, lines.last!.1 + 1)
        let raw = Data(bytes[fileStartByte..<fileEndByte])
        var file = FileDiff(raw: raw)
        var index = 0
        // Header.
        while index < lines.count {
            let (s, e) = lines[index]
            if hasPrefix(bytes, s, e, "@@ ") { break }
            file.header.append(Data(bytes[s..<e]))
            if hasPrefix(bytes, s, e, "diff --git ") {
                let paths = parseGitHeaderPaths(string(bytes, s + 11, e))
                file.oldPath = paths.old
                file.newPath = paths.new
            } else if hasPrefix(bytes, s, e, "--- ") {
                file.oldPath = headerPath(string(bytes, s + 4, e), prefix: "a/")
            } else if hasPrefix(bytes, s, e, "+++ ") {
                file.newPath = headerPath(string(bytes, s + 4, e), prefix: "b/")
            } else if hasPrefix(bytes, s, e, "new file mode ") {
                file.isNew = true
                file.newMode = string(bytes, s + 14, e)
            } else if hasPrefix(bytes, s, e, "deleted file mode ") {
                file.isDeleted = true
                file.oldMode = string(bytes, s + 18, e)
            } else if hasPrefix(bytes, s, e, "old mode ") {
                file.oldMode = string(bytes, s + 9, e)
            } else if hasPrefix(bytes, s, e, "new mode ") {
                file.newMode = string(bytes, s + 9, e)
            } else if hasPrefix(bytes, s, e, "rename from ") {
                file.oldPath = unquote(string(bytes, s + 12, e))
            } else if hasPrefix(bytes, s, e, "rename to ") {
                file.newPath = unquote(string(bytes, s + 10, e))
            } else if hasPrefix(bytes, s, e, "Binary files ") || hasPrefix(bytes, s, e, "GIT binary patch") {
                file.isBinary = true
            }
            index += 1
        }
        if file.isNew { file.oldPath = nil }
        if file.isDeleted { file.newPath = nil }
        // Hunks.
        var hunk: DiffHunk?
        var oldLine = 0, newLine = 0
        while index < lines.count {
            let (s, e) = lines[index]
            index += 1
            guard s < e else {
                // An empty line inside a hunk is a context line whose marker was stripped by
                // some tools; git never emits it, so treat it as the end of the hunk.
                continue
            }
            let marker = bytes[s]
            if marker == UInt8(ascii: "@"), hasPrefix(bytes, s, e, "@@ ") {
                if let h = hunk { file.hunks.append(h) }
                hunk = parseHunkHeader(string(bytes, s, e))
                oldLine = hunk?.oldStart ?? 0
                newLine = hunk?.newStart ?? 0
                continue
            }
            guard hunk != nil else { continue }
            let contentStart = Int32(s + 1 - fileStartByte)
            let length = Int32(e - s - 1)
            switch marker {
            case UInt8(ascii: " "):
                hunk!.lines.append(DiffLine(kind: .context, noNewlineAtEnd: false, oldNumber: Int32(oldLine),
                                            newNumber: Int32(newLine), start: contentStart, length: length))
                oldLine += 1; newLine += 1
            case UInt8(ascii: "+"):
                hunk!.lines.append(DiffLine(kind: .added, noNewlineAtEnd: false, oldNumber: 0,
                                            newNumber: Int32(newLine), start: contentStart, length: length))
                newLine += 1
            case UInt8(ascii: "-"):
                hunk!.lines.append(DiffLine(kind: .removed, noNewlineAtEnd: false, oldNumber: Int32(oldLine),
                                            newNumber: 0, start: contentStart, length: length))
                oldLine += 1
            case UInt8(ascii: "\\"):
                if !hunk!.lines.isEmpty { hunk!.lines[hunk!.lines.count - 1].noNewlineAtEnd = true }
            default:
                break
            }
        }
        if let h = hunk { file.hunks.append(h) }
        return file
    }

    /// "@@ -12,5 +12,6 @@ func name()" → a hunk with no lines yet.
    static func parseHunkHeader(_ line: String) -> DiffHunk? {
        let scanner = line.dropFirst(3) // "@@ "
        guard let end = scanner.range(of: " @@") else { return nil }
        let ranges = scanner[..<end.lowerBound].split(separator: " ")
        guard ranges.count >= 2 else { return nil }
        func parse(_ s: Substring) -> (Int, Int) {
            let body = s.dropFirst()
            let parts = body.split(separator: ",", omittingEmptySubsequences: false)
            let start = Int(parts[0]) ?? 0
            let count = parts.count > 1 ? Int(parts[1]) ?? 0 : 1
            return (start, count)
        }
        let (os, oc) = parse(ranges[0])
        let (ns, nc) = parse(ranges[ranges.count - 1])
        let heading = scanner[end.upperBound...].trimmingCharacters(in: .whitespaces)
        return DiffHunk(oldStart: os, oldCount: oc, newStart: ns, newCount: nc, heading: heading, lines: [])
    }

    /// "a/foo b/foo" → both paths (only when unambiguous: same length halves or quoted).
    static func parseGitHeaderPaths(_ rest: String) -> (old: String?, new: String?) {
        if rest.hasPrefix("\"") {
            // Quoted: "a/x y" "b/x y"
            let parts = splitQuoted(rest)
            if parts.count == 2 {
                return (stripPrefix(parts[0], "a/"), stripPrefix(parts[1], "b/"))
            }
            return (nil, nil)
        }
        // Unquoted: same path twice ("a/P b/P") is the common case.
        let chars = Array(rest)
        if chars.count % 2 == 1 {
            let half = chars.count / 2
            let left = String(chars[..<half]), right = String(chars[(half + 1)...])
            if left.hasPrefix("a/"), right.hasPrefix("b/"), left.dropFirst(2) == right.dropFirst(2) {
                return (String(left.dropFirst(2)), String(right.dropFirst(2)))
            }
        }
        return (nil, nil)
    }

    static func headerPath(_ value: String, prefix: String) -> String? {
        let trimmed = value.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? value
        if trimmed == "/dev/null" { return nil }
        return stripPrefix(unquote(trimmed), prefix)
    }

    static func stripPrefix(_ s: String, _ prefix: String) -> String {
        s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s
    }

    static func splitQuoted(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for c in s {
            if escaped { current.append("\\"); current.append(c); escaped = false; continue }
            if c == "\\" && inQuotes { escaped = true; continue }
            if c == "\"" { inQuotes.toggle(); current.append(c); continue }
            if c == " " && !inQuotes {
                if !current.isEmpty { parts.append(unquote(current)); current = "" }
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { parts.append(unquote(current)) }
        return parts
    }

    /// Undoes git's C-style quoting ("a\tb", octal escapes for bytes).
    public static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        let inner = Array(s.utf8.dropFirst().dropLast())
        var out: [UInt8] = []
        var i = 0
        while i < inner.count {
            let c = inner[i]
            if c == UInt8(ascii: "\\"), i + 1 < inner.count {
                let n = inner[i + 1]
                switch n {
                case UInt8(ascii: "n"): out.append(10); i += 2
                case UInt8(ascii: "t"): out.append(9); i += 2
                case UInt8(ascii: "r"): out.append(13); i += 2
                case UInt8(ascii: "\""): out.append(34); i += 2
                case UInt8(ascii: "\\"): out.append(92); i += 2
                case UInt8(ascii: "a"): out.append(7); i += 2
                case UInt8(ascii: "b"): out.append(8); i += 2
                case UInt8(ascii: "f"): out.append(12); i += 2
                case UInt8(ascii: "v"): out.append(11); i += 2
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var value = 0, k = i + 1
                    while k < inner.count, k < i + 4, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(inner[k]) {
                        value = value * 8 + Int(inner[k] - 48); k += 1
                    }
                    out.append(UInt8(truncatingIfNeeded: value)); i = k
                default: out.append(n); i += 2
                }
            } else {
                out.append(c); i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
