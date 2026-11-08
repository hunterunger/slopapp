import Foundation

/// A placeholder inside snippet content, written in braces:
///
/// - `{date}` `{date:short}` `{date:long}` `{date:full}` `{date:iso}`: today in the system's
///   formats (`medium` is the default); `{time}` `{time:medium}`; `{datetime}`.
/// - Offsets: `{date:+1d}` `{date:long -2w}` `{time:+30m}` (d, w, M months, y, h, m).
/// - Custom: `{date:format=EEE d MMM}` (a Unicode date pattern, to the closing brace).
/// - `{clipboard}`: the clipboard's plain text.
/// - `{cursor}`: where the caret ends up.
/// - `{{` and `}}` type a literal brace.
public enum Placeholder: Sendable, Equatable {
    case date(DateSpec)
    case clipboard
    case cursor
}

public struct DateSpec: Sendable, Equatable {
    public enum Kind: String, Sendable { case date, time, datetime }
    public enum Style: String, Sendable, CaseIterable { case short, medium, long, full, iso }

    public var kind: Kind
    public var style: Style
    public var offset: DateOffset?
    /// A Unicode date pattern; wins over `style`.
    public var format: String?

    public init(kind: Kind, style: Style? = nil, offset: DateOffset? = nil, format: String? = nil) {
        self.kind = kind
        self.style = style ?? (kind == .time ? .short : .medium)
        self.offset = offset
        self.format = format
    }
}

public struct DateOffset: Sendable, Equatable {
    public enum Unit: Character, Sendable { case day = "d", week = "w", month = "M", year = "y", hour = "h", minute = "m" }
    public var amount: Int
    public var unit: Unit

    public init(amount: Int, unit: Unit) {
        self.amount = amount
        self.unit = unit
    }

    /// `+1d`, `-2w`, `+3M`.
    public init?(_ text: Substring) {
        guard let sign = text.first, sign == "+" || sign == "-", let last = text.last,
              let unit = Unit(rawValue: last), text.count >= 3,
              let value = Int(text.dropFirst().dropLast()), value <= 100_000 else { return nil }
        self.amount = sign == "-" ? -value : value
        self.unit = unit
    }

    public var text: String { (amount < 0 ? "-" : "+") + "\(abs(amount))\(unit.rawValue)" }

    public func apply(to date: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch unit {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .hour: .hour
        case .minute: .minute
        }
        return calendar.date(byAdding: component, value: amount, to: date) ?? date
    }
}

/// Parsed snippet content.
public enum Segment: Sendable, Equatable {
    case text(String)
    case placeholder(Placeholder, raw: String)
    /// Looks like a placeholder but isn't one we know: typed as written, flagged in the editor.
    case unknown(String)
}

public enum PlaceholderParser {
    public static func parse(_ content: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var index = content.startIndex
        func flush() {
            if !literal.isEmpty { segments.append(.text(literal)); literal = "" }
        }
        while index < content.endIndex {
            let character = content[index]
            let next = content.index(after: index)
            if character == "{", next < content.endIndex, content[next] == "{" {
                literal.append("{")
                index = content.index(after: next)
                continue
            }
            if character == "}", next < content.endIndex, content[next] == "}" {
                literal.append("}")
                index = content.index(after: next)
                continue
            }
            if character == "{", let close = content[next...].firstIndex(where: { $0 == "}" || $0 == "{" || $0 == "\n" }),
               content[close] == "}" {
                let body = content[next..<close]
                let raw = String(content[index...close])
                flush()
                if let placeholder = placeholder(body) {
                    segments.append(.placeholder(placeholder, raw: raw))
                } else {
                    segments.append(.unknown(raw))
                }
                index = content.index(after: close)
                continue
            }
            literal.append(character)
            index = next
        }
        flush()
        return segments
    }

    static func placeholder(_ body: Substring) -> Placeholder? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        let name: Substring
        let argument: Substring
        if let colon = trimmed.firstIndex(of: ":") {
            name = trimmed[..<colon]
            argument = trimmed[trimmed.index(after: colon)...]
        } else {
            name = Substring(trimmed)
            argument = ""
        }
        switch name.lowercased() {
        case "clipboard": return argument.isEmpty ? .clipboard : nil
        case "cursor": return argument.isEmpty ? .cursor : nil
        case "date": return dateSpec(.date, argument).map(Placeholder.date)
        case "time": return dateSpec(.time, argument).map(Placeholder.date)
        case "datetime": return dateSpec(.datetime, argument).map(Placeholder.date)
        default: return nil
        }
    }

    static func dateSpec(_ kind: DateSpec.Kind, _ argument: Substring) -> DateSpec? {
        var spec = DateSpec(kind: kind)
        var rest = argument.drop { $0 == " " }
        while !rest.isEmpty {
            if rest.hasPrefix("format=") {
                let pattern = String(rest.dropFirst("format=".count))
                guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                spec.format = pattern
                return spec
            }
            let word = rest.prefix { $0 != " " }
            rest = rest.dropFirst(word.count).drop { $0 == " " }
            if let style = DateSpec.Style(rawValue: word.lowercased()) {
                spec.style = style
            } else if let offset = DateOffset(word) {
                guard spec.offset == nil else { return nil }
                spec.offset = offset
            } else {
                return nil
            }
        }
        return spec
    }

    /// The text that inserts `placeholder` in the editor.
    public static func token(for placeholder: Placeholder) -> String {
        switch placeholder {
        case .clipboard: return "{clipboard}"
        case .cursor: return "{cursor}"
        case .date(let spec):
            var parts: [String] = []
            let defaultStyle: DateSpec.Style = spec.kind == .time ? .short : .medium
            if spec.style != defaultStyle && spec.format == nil { parts.append(spec.style.rawValue) }
            if let offset = spec.offset { parts.append(offset.text) }
            if let format = spec.format { parts.append("format=" + format) }
            return "{" + spec.kind.rawValue + (parts.isEmpty ? "" : ":" + parts.joined(separator: " ")) + "}"
        }
    }
}

/// What a `{clipboard}` placeholder can get.
public enum ClipboardValue: Sendable, Equatable {
    case text(String)
    /// Empty, an image or files: inserts nothing.
    case none
    /// A password manager marked it concealed: inserts nothing.
    case concealed
    /// macOS would ask (or refuses) before Shorthand reads it: inserts nothing.
    case notAllowed
}

/// The resolved text of a snippet.
public struct Resolved: Sendable, Equatable {
    public var text: String
    /// Characters after the `{cursor}` marker (← presses after inserting). 0 = at the end.
    public var charactersAfterCursor: Int
    public var usedClipboard: Bool
    /// `{clipboard}` couldn't be read because of macOS's paste privacy.
    public var clipboardBlocked: Bool
    public var unknownPlaceholders: [String]
    /// The text before the caret once inserted (the next abbreviation's context).
    public var textBeforeCursor: String {
        String(text.dropLast(charactersAfterCursor))
    }
}

public struct PlaceholderResolver: Sendable {
    /// Longest clipboard text inserted.
    public static let clipboardLimit = 100_000

    public var now: Date
    public var locale: Locale
    public var calendar: Calendar
    public var timeZone: TimeZone

    public init(now: Date, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.now = now
        self.locale = locale
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    /// Whether `content` needs the clipboard (so it's only read when it does).
    public static func needsClipboard(_ content: String) -> Bool {
        PlaceholderParser.parse(content).contains { if case .placeholder(.clipboard, _) = $0 { true } else { false } }
    }

    public func resolve(_ content: String, typedCase: TypedCase = .asWritten, clipboard: () -> ClipboardValue) -> Resolved {
        var text = ""
        var afterCursor: String?
        var usedClipboard = false
        var blocked = false
        var unknown: [String] = []
        var cachedClipboard: ClipboardValue?
        func append(_ piece: String) {
            if afterCursor != nil { afterCursor! += piece } else { text += piece }
        }
        var first = true
        for segment in PlaceholderParser.parse(content) {
            switch segment {
            case .text(let literal):
                append(first ? CaseAdapter.apply(typedCase, toStartOf: literal) : CaseAdapter.apply(typedCase == .upper ? .upper : .asWritten, toStartOf: literal))
            case .unknown(let raw):
                unknown.append(raw)
                append(raw)
            case .placeholder(.cursor, _):
                if afterCursor == nil { afterCursor = "" }
            case .placeholder(.clipboard, _):
                let value = cachedClipboard ?? clipboard()
                cachedClipboard = value
                usedClipboard = true
                switch value {
                case .text(let string): append(String(string.prefix(Self.clipboardLimit)))
                case .notAllowed: blocked = true
                case .none, .concealed: break
                }
            case .placeholder(.date(let spec), _):
                append(format(spec))
            }
            first = false
        }
        let tail = afterCursor ?? ""
        return Resolved(text: text + tail, charactersAfterCursor: tail.count, usedClipboard: usedClipboard,
                        clipboardBlocked: blocked, unknownPlaceholders: unknown)
    }

    public func format(_ spec: DateSpec) -> String {
        let date = spec.offset?.apply(to: now, calendar: calendar) ?? now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        if let format = spec.format {
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        if spec.style == .iso {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = switch spec.kind {
            case .date: "yyyy-MM-dd"
            case .time: "HH:mm"
            case .datetime: "yyyy-MM-dd'T'HH:mm"
            }
            return formatter.string(from: date)
        }
        let style: DateFormatter.Style = switch spec.style {
        case .short: .short
        case .medium, .iso: .medium
        case .long: .long
        case .full: .full
        }
        formatter.dateStyle = spec.kind == .time ? .none : style
        formatter.timeStyle = spec.kind == .date ? .none : (spec.kind == .datetime ? .short : style)
        return formatter.string(from: date)
    }
}

/// "Adapt case": the expansion follows how the abbreviation was typed.
public enum CaseAdapter {
    public static func apply(_ typedCase: TypedCase, toStartOf text: String) -> String {
        switch typedCase {
        case .asWritten: return text
        case .upper: return text.uppercased()
        case .capitalized:
            guard let index = text.firstIndex(where: { $0.isLetter }) else { return text }
            return text[..<index] + text[index].uppercased() + text[text.index(after: index)...]
        }
    }
}
