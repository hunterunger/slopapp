import Foundation

/// Text helpers for copying results and the first-run sheet.
public enum SheetText {
    /// The sheet a new user sees: a header, a little math, a conversion, and a note that
    /// it's all deletable. No tour.
    public static let welcome = """
    # Welcome to Tally
    // Type on any line. Answers appear on the right as you type.
    dinner = $186.40
    tip = 18%
    dinner + tip
    prev / 4
    5 km in miles
    now in Tokyo
    // Click an answer to copy it. Delete these lines whenever you like.

    """

    /// The text a result copies as: what's shown, or just the number.
    public static func copyText(_ output: LineOutput, formatter: ResultFormatter, includeUnit: Bool) -> String? {
        guard let q = output.result.quantity else { return nil }
        return includeUnit ? formatter.format(q) : formatter.plainNumber(q)
    }

    /// The whole sheet with each answer after its line: "rent / 3 = 483.33".
    public static func copyAll(lines: [String], outputs: [LineOutput], formatter: ResultFormatter) -> String {
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            guard i < outputs.count, let q = outputs[i].result.quantity else {
                out.append(line)
                continue
            }
            let shown = formatter.format(q)
            // "rent = 1450" already shows its answer; don't write "rent = 1450 = 1,450".
            if normalized(line).hasSuffix(normalized(shown)) {
                out.append(line)
            } else {
                var base = line
                while base.hasSuffix(" ") || base.hasSuffix("=") { base.removeLast() }
                out.append("\(base) = \(shown)")
            }
        }
        return out.joined(separator: "\n")
    }

    private static func normalized(_ s: String) -> String {
        String(s.filter { !$0.isWhitespace && $0 != "," && $0 != "'" && $0 != "’" })
    }

    /// The line index containing a UTF-16 offset.
    public static func lineIndex(containing offset: Int, lineStarts: [Int]) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return max(0, lo)
    }

    /// UTF-16 offsets where each line starts.
    public static func lineStarts(of text: NSString) -> [Int] {
        var starts = [0]
        let length = text.length
        guard length > 0 else { return starts }
        var buffer = [unichar](repeating: 0, count: length)
        text.getCharacters(&buffer, range: NSRange(location: 0, length: length))
        for i in 0..<length where buffer[i] == 10 { starts.append(i + 1) }
        return starts
    }
}
