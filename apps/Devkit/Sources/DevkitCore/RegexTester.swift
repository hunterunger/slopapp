import Foundation

/// Runs ICU regular expressions (`NSRegularExpression`, the engine behind Swift and
/// Objective-C) with a time limit, so a catastrophically backtracking pattern can't hang.
public enum RegexTester {
    public struct Flags: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let caseInsensitive = Flags(rawValue: 1 << 0)
        /// ^ and $ match at line breaks.
        public static let multiline = Flags(rawValue: 1 << 1)
        /// . matches line breaks.
        public static let dotAll = Flags(rawValue: 1 << 2)
        /// Whitespace and # comments in the pattern are ignored.
        public static let extended = Flags(rawValue: 1 << 3)

        var options: NSRegularExpression.Options {
            var options: NSRegularExpression.Options = []
            if contains(.caseInsensitive) { options.insert(.caseInsensitive) }
            if contains(.multiline) { options.insert(.anchorsMatchLines) }
            if contains(.dotAll) { options.insert(.dotMatchesLineSeparators) }
            if contains(.extended) { options.insert(.allowCommentsAndWhitespace) }
            return options
        }
    }

    public struct Group: Sendable, Equatable {
        public var index: Int
        public var name: String?
        /// nil when the group didn't take part in the match.
        public var range: NSRange?
        public var text: String?
    }

    public struct Match: Sendable, Equatable, Identifiable {
        public var index: Int
        public var range: NSRange
        public var text: String
        public var groups: [Group]
        public var id: Int { index }
    }

    public enum Outcome: Sendable, Equatable {
        case matches([Match], truncated: Bool)
        case invalidPattern(String)
        case timedOut(partial: [Match])
        case emptyPattern
    }

    public static let defaultTimeout: Duration = .milliseconds(500)
    public static let matchLimit = 5000

    public static func evaluate(pattern: String, flags: Flags, in text: String,
                                timeout: Duration = defaultTimeout, limit: Int = matchLimit,
                                isCancelled: () -> Bool = { false }) -> Outcome {
        guard !pattern.isEmpty else { return .emptyPattern }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: flags.options)
        } catch {
            return .invalidPattern(invalidPatternMessage(pattern))
        }
        let names = groupNames(in: pattern)
        let nsText = text as NSString
        var matches: [Match] = []
        var timedOut = false
        var truncated = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: nsText.length)) { result, _, stop in
            if clock.now > deadline || isCancelled() {
                timedOut = true
                stop.pointee = true
                return
            }
            guard let result else { return }
            if matches.count >= limit {
                truncated = true
                stop.pointee = true
                return
            }
            var groups: [Group] = []
            if result.numberOfRanges > 1 {
                for index in 1..<result.numberOfRanges {
                    let range = result.range(at: index)
                    let found = range.location != NSNotFound
                    groups.append(Group(index: index, name: names[index],
                                        range: found ? range : nil,
                                        text: found ? nsText.substring(with: range) : nil))
                }
            }
            matches.append(Match(index: matches.count + 1, range: result.range,
                                 text: nsText.substring(with: result.range), groups: groups))
        }
        if timedOut { return .timedOut(partial: matches) }
        return .matches(matches, truncated: truncated)
    }

    public enum ReplaceOutcome: Sendable, Equatable {
        case replaced(String, count: Int)
        case invalidPattern(String)
        case timedOut
        case emptyPattern
    }

    /// Replaces every match with `template` ($1, $2… and ${name} refer to groups;
    /// \$ is a literal dollar sign).
    public static func replace(pattern: String, flags: Flags, in text: String, template: String,
                               timeout: Duration = defaultTimeout, isCancelled: () -> Bool = { false }) -> ReplaceOutcome {
        guard !pattern.isEmpty else { return .emptyPattern }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: flags.options) else {
            return .invalidPattern(invalidPatternMessage(pattern))
        }
        let nsText = text as NSString
        var results: [NSTextCheckingResult] = []
        var timedOut = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: nsText.length)) { result, _, stop in
            if clock.now > deadline || isCancelled() {
                timedOut = true
                stop.pointee = true
                return
            }
            if let result { results.append(result) }
        }
        if timedOut { return .timedOut }
        let output = NSMutableString(string: text)
        var offset = 0
        for result in results {
            let replacement = regex.replacementString(for: result, in: text, offset: 0, template: expandNamedGroups(template, pattern: pattern))
            let range = NSRange(location: result.range.location + offset, length: result.range.length)
            output.replaceCharacters(in: range, with: replacement)
            offset += (replacement as NSString).length - result.range.length
        }
        return .replaced(output as String, count: results.count)
    }

    /// ICU templates only know numbered groups; turn ${name} into $n.
    static func expandNamedGroups(_ template: String, pattern: String) -> String {
        let names = groupNames(in: pattern)
        guard !names.isEmpty, template.contains("${") else { return template }
        var result = template
        for (index, name) in names {
            result = result.replacingOccurrences(of: "${\(name)}", with: "$\(index)")
        }
        return result
    }

    /// Capture group numbers → names, found by scanning the pattern for `(?<name>` and
    /// `(?P<name>`. Skips escaped parens, character classes and non-capturing groups.
    public static func groupNames(in pattern: String) -> [Int: String] {
        let characters = Array(pattern)
        var names: [Int: String] = [:]
        var groupIndex = 0
        var index = 0
        var inClass = false
        while index < characters.count {
            let character = characters[index]
            if character == "\\" { index += 2; continue }
            if inClass {
                if character == "]" { inClass = false }
                index += 1
                continue
            }
            if character == "[" { inClass = true; index += 1; continue }
            if character == "(" {
                if index + 1 < characters.count, characters[index + 1] == "?" {
                    var nameStart = index + 2
                    if nameStart < characters.count, characters[nameStart] == "P" { nameStart += 1 }
                    if nameStart < characters.count, characters[nameStart] == "<",
                       nameStart + 1 < characters.count, characters[nameStart + 1] != "=", characters[nameStart + 1] != "!" {
                        groupIndex += 1
                        var end = nameStart + 1
                        while end < characters.count, characters[end] != ">" { end += 1 }
                        names[groupIndex] = String(characters[(nameStart + 1)..<min(end, characters.count)])
                    }
                } else {
                    groupIndex += 1
                }
            }
            index += 1
        }
        return names
    }

    static func invalidPatternMessage(_ pattern: String) -> String {
        var depth = 0
        var inClass = false
        var characters = Array(pattern).makeIterator()
        while let character = characters.next() {
            if character == "\\" { _ = characters.next(); continue }
            if inClass { if character == "]" { inClass = false }; continue }
            switch character {
            case "[": inClass = true
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            if depth < 0 { return "There's a ) without a matching (. Escape it as \\) to match a parenthesis." }
        }
        if inClass { return "A [ character class isn't closed. Add a ], or escape it as \\[." }
        if depth > 0 { return "A ( group isn't closed. Add a ), or escape it as \\(." }
        if let first = pattern.first, "*+?{".contains(first) {
            return "The pattern starts with a quantifier (\(first)) that has nothing to repeat. Escape it with a backslash."
        }
        return "This pattern isn't valid. Check for a quantifier with nothing before it, or an unknown escape."
    }
}
