import AppKit

/// TextExpander group files (`.textexpander`, an XML property list: `groupInfo` and a
/// `snippetsTE2` array of `{abbreviation, plainText, label, snippetType, …}`).
///
/// Their `%` codes become Shorthand placeholders: dates and times (`%B %e, %Y`, with date
/// math `%@+7D`), `%clipboard`, `%|` (cursor), `%snippet:…%`, fill-ins (`%filltext`,
/// `%fillarea`, `%fillpopup`, `%fillpart`…`%fillpartend%`). Key presses (`%key:tab%`) and
/// scripts can't be carried over and are reported.
public enum TextExpanderImport {
    /// `snippetType` values for scripts (AppleScript, shell, JavaScript).
    static let scriptTypes: Set<Int> = [2, 3, 4, 5, 6, 7]

    public static func entries(fromPlist dictionary: [String: Any], fallbackGroup: String) throws -> [ImportEntry] {
        let info = dictionary["groupInfo"] as? [String: Any]
        let group = (info?["groupName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackGroup
        guard let snippets = (dictionary["snippetsTE2"] ?? dictionary["snippets"]) as? [[String: Any]] else {
            throw SnippetImport.ReadError.damaged("No snippets in this TextExpander file.")
        }
        return snippets.map { entry(from: $0, group: group) }
    }

    public static func entry(from snippet: [String: Any], group: String) -> ImportEntry {
        let abbreviation = snippet["abbreviation"] as? String ?? ""
        let plain = snippet["plainText"] as? String ?? ""
        let label = snippet["label"] as? String ?? ""
        let type = (snippet["snippetType"] as? Int) ?? 0
        if scriptTypes.contains(type) || plain.hasPrefix("#!") {
            return ImportEntry(abbreviation: abbreviation, content: PlaceholderParser.escape(plain), name: label, groupName: group,
                               preview: plain, unsupported: "A script snippet: Shorthand doesn't run scripts")
        }
        // Formatted text, if the file has it (RTF or RTFD data next to the plain text).
        if let rich = richData(snippet).flatMap(RichText.fromRTF), rich.length > 0, RichText.hasFormatting(rich) {
            let conversion = TextExpanderMacros.convert(rich.string)
            let converted = RichText.applying(conversion.edits, to: rich)
            return ImportEntry(abbreviation: abbreviation, content: converted.string, richText: RichText.encode(converted), name: label,
                               groupName: group, notes: conversion.notes)
        }
        let conversion = TextExpanderMacros.convert(plain)
        var notes = conversion.notes
        if type == 1 { notes.append("Its formatting wasn't in the file, so it comes in as plain text.") }
        return ImportEntry(abbreviation: abbreviation, content: TextEdit.apply(conversion.edits, to: plain), name: label, groupName: group,
                           notes: notes)
    }

    static func richData(_ snippet: [String: Any]) -> Data? {
        for key in ["richText", "rtfText", "rtfData", "richTextData", "rtfdData"] {
            if let data = snippet[key] as? Data, !data.isEmpty { return data }
        }
        for (key, value) in snippet where key.lowercased().contains("rich") || key.lowercased().contains("rtf") {
            if let data = value as? Data, !data.isEmpty { return data }
        }
        return nil
    }
}

/// TextExpander's `%` codes → Shorthand placeholders, as edits on the text (so they work on
/// formatted text too). Literal braces are escaped.
public enum TextExpanderMacros {
    /// Date codes that may join into one `{date:format=…}`.
    static let dateCodes: Set<Character> = ["Y", "y", "B", "b", "m", "d", "e", "A", "a", "H", "I", "M", "S", "p", "Z", "j"]
    /// What may sit between two date codes in one pattern.
    static let separators: Set<Character> = [" ", ",", ".", "/", "-", ":"]

    public static func convert(_ text: String) -> (edits: [TextEdit], notes: [String]) {
        let units = Array(text.utf16)
        var edits: [TextEdit] = []
        var notes: [String] = []
        var counters: [String: Int] = [:]
        var pendingOffset: DateOffset?
        func note(_ message: String) { if !notes.contains(message) { notes.append(message) } }
        func autoName(_ kind: String) -> String {
            counters[kind, default: 0] += 1
            return "\(kind) \(counters[kind]!)"
        }
        func string(_ range: Range<Int>) -> String { String(decoding: units[range], as: UTF16.self) }
        func char(_ i: Int) -> Character? { i < units.count ? Character(Unicode.Scalar(units[i]) ?? " ") : nil }
        /// The code after `%` at `i` (`%1m` style unpadded too): (pattern, length) or nil.
        func dateCode(at i: Int) -> (String, Int)? {
            guard char(i) == "%" else { return nil }
            var j = i + 1
            var unpadded = false
            if char(j) == "1" { unpadded = true; j += 1 }
            guard let c = char(j), dateCodes.contains(c), let piece = DateFormatConversion.pattern(forCode: c, unpadded: unpadded) else { return nil }
            return (piece, j + 1 - i)
        }
        /// `%…%` starting at `i` with the given prefix: the inside and the end index.
        func delimited(at i: Int, prefix: String) -> (String, Int)? {
            let prefixUnits = Array(prefix.utf16)
            guard i + prefixUnits.count <= units.count, Array(units[i..<i + prefixUnits.count]) == prefixUnits else { return nil }
            var j = i + prefixUnits.count
            while j < units.count, units[j] != 0x25, units[j] != 0x0A { j += 1 }
            guard j < units.count, units[j] == 0x25 else { return nil }
            return (string(i + prefixUnits.count..<j), j + 1)
        }
        func clean(_ value: String) -> String {
            let cleaned = value.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            if cleaned != value { note("Braces inside a fill-in were left out.") }
            return cleaned
        }
        func parameters(_ inside: String) -> (named: [String: String], values: [String], defaultValue: String?) {
            var named: [String: String] = [:]
            var values: [String] = []
            var defaultValue: String?
            for part in inside.split(separator: ":", omittingEmptySubsequences: false).map(String.init) {
                if let equals = part.firstIndex(of: "="), ["name", "default", "width", "height"].contains(String(part[..<equals])) {
                    let key = String(part[..<equals])
                    let value = String(part[part.index(after: equals)...])
                    named[key] = value
                    if key == "default" { defaultValue = value; values.append(value) }
                } else if !part.isEmpty {
                    values.append(part)
                }
            }
            return (named, values, defaultValue)
        }

        var i = 0
        while i < units.count {
            let unit = units[i]
            if unit == 0x7B || unit == 0x7D {
                edits.append(TextEdit(i..<i + 1, unit == 0x7B ? "{{" : "}}"))
                i += 1
                continue
            }
            guard unit == 0x25 else { i += 1; continue }
            // %% is a literal percent sign.
            if char(i + 1) == "%" { edits.append(TextEdit(i..<i + 2, "%")); i += 2; continue }
            if char(i + 1) == "|" { edits.append(TextEdit(i..<i + 2, "{cursor}")); i += 2; continue }
            if let (_, end) = delimited(at: i, prefix: "%clipboard") , end == i + 11 {
                // "%clipboard%" (some versions close it)
                edits.append(TextEdit(i..<end, "{clipboard}")); i = end; continue
            }
            if string(i..<min(units.count, i + 10)) == "%clipboard" {
                edits.append(TextEdit(i..<i + 10, "{clipboard}")); i += 10; continue
            }
            if let (inside, end) = delimited(at: i, prefix: "%snippet:") {
                let abbreviation = inside.trimmingCharacters(in: .whitespaces)
                edits.append(TextEdit(i..<end, abbreviation.contains("}") ? "" : "{snippet:\(abbreviation)}"))
                i = end; continue
            }
            if let (inside, end) = delimited(at: i, prefix: "%key:") {
                edits.append(TextEdit(i..<end, ""))
                note("A key press (\(inside)) was left out: Shorthand only inserts text.")
                i = end; continue
            }
            if let (inside, end) = delimited(at: i, prefix: "%filltext:") ?? delimited(at: i, prefix: "%fillarea:") {
                let isArea = string(i..<i + 9) == "%fillarea"
                let p = parameters(inside)
                let name = clean(p.named["name"].flatMap { $0.isEmpty ? nil : $0 } ?? autoName("Field"))
                let defaultValue = clean(p.named["default"] ?? "").replacingOccurrences(of: "\n", with: " ")
                edits.append(TextEdit(i..<end, PlaceholderParser.token(for: .field(name: name, defaultValue: defaultValue))))
                if isArea { note("A multi-line fill-in became a one-line field.") }
                i = end; continue
            }
            if string(i..<min(units.count, i + 10)) == "%filltext%" || string(i..<min(units.count, i + 10)) == "%fillarea%" {
                edits.append(TextEdit(i..<i + 10, PlaceholderParser.token(for: .field(name: autoName("Field"), defaultValue: ""))))
                i += 10; continue
            }
            if let (inside, end) = delimited(at: i, prefix: "%fillpopup:") {
                let p = parameters(inside)
                var options: [String] = []
                for value in p.values.map(clean) where !value.isEmpty && !options.contains(value) {
                    options.append(value.replacingOccurrences(of: "|", with: "/"))
                }
                if let chosen = p.defaultValue.map(clean), let index = options.firstIndex(of: chosen), index > 0 {
                    options.insert(options.remove(at: index), at: 0)
                }
                if options.isEmpty {
                    edits.append(TextEdit(i..<end, ""))
                } else {
                    let name = clean(p.named["name"].flatMap { $0.isEmpty ? nil : $0 } ?? autoName("Choice"))
                    edits.append(TextEdit(i..<end, PlaceholderParser.token(for: .choice(name: name, options: options))))
                }
                i = end; continue
            }
            if string(i..<min(units.count, i + 12)) == "%fillpartend" {
                let end = char(i + 12) == "%" ? i + 13 : i + 12
                edits.append(TextEdit(i..<end, "{/optional}"))
                i = end; continue
            }
            if let (inside, end) = delimited(at: i, prefix: "%fillpart:") ?? (string(i..<min(units.count, i + 10)) == "%fillpart%" ? ("", i + 10) : nil) {
                let p = parameters(inside)
                let name = clean(p.named["name"].flatMap { $0.isEmpty ? nil : $0 } ?? autoName("Section"))
                let on = ["yes", "true", "1"].contains((p.named["default"] ?? "no").lowercased())
                edits.append(TextEdit(i..<end, PlaceholderParser.token(for: .optionalStart(name: name, defaultOn: on))))
                i = end; continue
            }
            // Date math: %@+7D applies to the date that follows.
            if char(i + 1) == "@", let sign = char(i + 2), sign == "+" || sign == "-" {
                var j = i + 3
                var digits = ""
                while let c = char(j), c.isNumber { digits.append(c); j += 1 }
                if let unitChar = char(j), let amount = Int(digits) {
                    let unitMap: [Character: DateOffset.Unit] = ["D": .day, "d": .day, "M": .month, "Y": .year, "y": .year, "h": .hour, "H": .hour, "m": .minute, "W": .week, "w": .week]
                    if let unit = unitMap[unitChar] {
                        pendingOffset = DateOffset(amount: sign == "-" ? -amount : amount, unit: unit)
                    } else {
                        note("Date math in seconds was left out.")
                    }
                    edits.append(TextEdit(i..<j + 1, ""))
                    i = j + 1; continue
                }
            }
            if let (first, length) = dateCode(at: i) {
                // Join a run like %B %e, %Y into one pattern.
                var pattern = first
                var end = i + length
                while true {
                    var j = end
                    var literal = ""
                    while let c = char(j), separators.contains(c), literal.count < 3 { literal.append(c); j += 1 }
                    guard let (next, nextLength) = dateCode(at: j) else { break }
                    pattern += DateFormatConversion.quote(literal) + next
                    end = j + nextLength
                }
                var spec = DateSpec(kind: .date, format: pattern)
                spec.offset = pendingOffset
                pendingOffset = nil
                edits.append(TextEdit(i..<end, PlaceholderParser.token(for: .date(spec))))
                i = end; continue
            }
            i += 1
        }
        return (edits, notes)
    }
}
