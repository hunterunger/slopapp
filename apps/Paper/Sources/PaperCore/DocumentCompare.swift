import Foundation
import PDFKit

/// Compares the text of two documents word by word. The whole text is compared at once
/// (so a paragraph that moved to the next page isn't reported as changed everywhere), then
/// every difference is mapped back to the pages and character ranges it came from.
public enum DocumentCompare {
    public struct Token: Equatable, Sendable {
        public var text: String
        public var page: Int
        public var range: NSRange
    }

    public struct Change: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case inserted, deleted, changed }
        public var id: Int
        public var old: [Token]
        public var new: [Token]

        public var kind: Kind { old.isEmpty ? .inserted : new.isEmpty ? .deleted : .changed }
        public var oldText: String { old.map(\.text).joined(separator: " ") }
        public var newText: String { new.map(\.text).joined(separator: " ") }
        public var oldPage: Int? { old.first?.page }
        public var newPage: Int? { new.first?.page }

        public var summary: String {
            switch kind {
            case .inserted: "Added “\(Self.short(newText))”"
            case .deleted: "Removed “\(Self.short(oldText))”"
            case .changed: "“\(Self.short(oldText))” → “\(Self.short(newText))”"
            }
        }

        static func short(_ text: String) -> String { text.count > 60 ? String(text.prefix(57)) + "…" : text }
    }

    public static func tokens(_ document: PDFDocument) -> [Token] {
        var result: [Token] = []
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else { continue }
            let ns = text as NSString
            var location = 0
            while location < ns.length {
                let rest = NSRange(location: location, length: ns.length - location)
                let start = ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: rest)
                guard start.location != NSNotFound else { break }
                let after = NSRange(location: start.location, length: ns.length - start.location)
                let end = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: after)
                let length = (end.location == NSNotFound ? ns.length : end.location) - start.location
                let range = NSRange(location: start.location, length: length)
                result.append(Token(text: ns.substring(with: range), page: index, range: range))
                location = NSMaxRange(range)
            }
        }
        return result
    }

    public static func compare(_ old: PDFDocument, _ new: PDFDocument) -> [Change] {
        compare(tokens(old), tokens(new))
    }

    public static func compare(_ old: [Token], _ new: [Token]) -> [Change] {
        let difference = new.map(\.text).difference(from: old.map(\.text))
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var changes: [Change] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, !removed.contains(i), !inserted.contains(j) {
                i += 1; j += 1
                continue
            }
            var oldRun: [Token] = [], newRun: [Token] = []
            while i < old.count, removed.contains(i) { oldRun.append(old[i]); i += 1 }
            while j < new.count, inserted.contains(j) { newRun.append(new[j]); j += 1 }
            if oldRun.isEmpty, newRun.isEmpty { break }
            changes.append(Change(id: changes.count, old: oldRun, new: newRun))
        }
        return changes
    }

    /// Character ranges of `tokens`, merged where they're next to each other on one page.
    public static func ranges(_ tokens: [Token]) -> [(page: Int, range: NSRange)] {
        var result: [(page: Int, range: NSRange)] = []
        for token in tokens {
            if let last = result.last, last.page == token.page, token.range.location - NSMaxRange(last.range) <= 2 {
                result[result.count - 1].range = NSUnionRange(last.range, token.range)
            } else {
                result.append((token.page, token.range))
            }
        }
        return result
    }
}
