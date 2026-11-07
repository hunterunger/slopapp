import Foundation

/// Beautifies and minifies HTML and XML. Tolerant like a browser: unclosed tags are closed
/// at their parent's end, stray end tags are kept as written. XML is also checked with
/// Foundation's parser so errors carry a line number.
public enum MarkupFormatter {
    public enum Dialect: Sendable { case html, xml }

    public struct Options: Sendable, Equatable {
        public var indent: String
        public var removeComments: Bool
        public init(indent: String = "  ", removeComments: Bool = false) {
            self.indent = indent
            self.removeComments = removeComments
        }
    }

    public struct FormatError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
    }

    // MARK: Tree

    indirect enum Node {
        case element(Element)
        case text(String)
        /// Comments, doctypes, processing instructions, CDATA, stray end tags: kept verbatim.
        case raw(String, isComment: Bool)
    }

    struct Element {
        var name: String
        var openTag: String
        var closeTag: String?
        var children: [Node] = []
        var rawContent: String?
        var selfClosing: Bool
    }

    static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr", "!doctype"]
    static let rawTextElements: Set<String> = ["script", "style", "pre", "textarea"]
    static let inlineElements: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "dfn", "em", "i", "img", "kbd", "label", "mark",
        "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var", "wbr", "del", "ins",
    ]

    static func parse(_ text: String, dialect: Dialect) -> [Node] {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var stack: [Element] = [Element(name: "#root", openTag: "", selfClosing: false)]

        func append(_ node: Node) { stack[stack.count - 1].children.append(node) }
        func slice(_ start: Int, _ end: Int) -> String { String(String.UnicodeScalarView(scalars[start..<min(end, scalars.count)])) }
        func find(_ needle: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
            let target = Array(needle.unicodeScalars)
            guard target.count <= scalars.count else { return nil }
            var i = start
            while i + target.count <= scalars.count {
                var matched = true
                for (offset, scalar) in target.enumerated() {
                    let candidate = scalars[i + offset]
                    if caseInsensitive ? String(candidate).lowercased() != String(scalar).lowercased() : candidate != scalar {
                        matched = false
                        break
                    }
                }
                if matched { return i }
                i += 1
            }
            return nil
        }
        func closeElement() {
            let element = stack.removeLast()
            append(.element(element))
        }

        while index < scalars.count {
            if scalars[index] != "<" {
                let start = index
                while index < scalars.count, scalars[index] != "<" { index += 1 }
                append(.text(slice(start, index)))
                continue
            }
            let rest = { (prefix: String) in slice(index, index + prefix.unicodeScalars.count).lowercased() == prefix }
            if rest("<!--") {
                let end = (find("-->", from: index + 4) ?? scalars.count - 3) + 3
                append(.raw(slice(index, end), isComment: true))
                index = end
                continue
            }
            if rest("<![cdata[") {
                let end = (find("]]>", from: index) ?? scalars.count - 3) + 3
                append(.raw(slice(index, end), isComment: false))
                index = end
                continue
            }
            if rest("<?") || rest("<!") {
                let end = (find(">", from: index) ?? scalars.count - 1) + 1
                append(.raw(normalizeTag(slice(index, end)), isComment: false))
                index = end
                continue
            }
            // A tag: find its end, skipping quoted attribute values.
            var end = index + 1
            var quote: Unicode.Scalar?
            while end < scalars.count {
                let scalar = scalars[end]
                if let open = quote {
                    if scalar == open { quote = nil }
                } else if scalar == "\"" || scalar == "'" {
                    quote = scalar
                } else if scalar == ">" {
                    break
                }
                end += 1
            }
            guard end < scalars.count, index + 1 < scalars.count,
                  scalars[index + 1] == "/" || scalars[index + 1].properties.isAlphabetic else {
                // A lone "<" in text.
                append(.text("<"))
                index += 1
                continue
            }
            let tag = normalizeTag(slice(index, end + 1))
            index = end + 1
            if tag.hasPrefix("</") {
                let name = tagName(tag)
                let matchName = dialect == .html ? name.lowercased() : name
                if let depth = stack.lastIndex(where: { (dialect == .html ? $0.name.lowercased() : $0.name) == matchName }), depth > 0 {
                    while stack.count - 1 > depth { closeElement() }
                    stack[stack.count - 1].closeTag = tag
                    closeElement()
                } else {
                    append(.raw(tag, isComment: false))
                }
                continue
            }
            let name = tagName(tag)
            let lower = name.lowercased()
            let selfClosing = tag.hasSuffix("/>") || (dialect == .html && voidElements.contains(lower))
            if selfClosing {
                append(.element(Element(name: name, openTag: tag, selfClosing: true)))
                continue
            }
            if dialect == .html, rawTextElements.contains(lower) {
                let close = find("</\(lower)", from: index, caseInsensitive: true) ?? scalars.count
                let closeEnd = close < scalars.count ? (find(">", from: close) ?? scalars.count - 1) + 1 : close
                var element = Element(name: name, openTag: tag, selfClosing: false)
                element.rawContent = slice(index, close)
                element.closeTag = close < scalars.count ? slice(close, closeEnd) : "</\(name)>"
                append(.element(element))
                index = closeEnd
                continue
            }
            if dialect == .html {
                // Implied end tags for the common cases: <p> and <li> close their open sibling.
                let impliedBy: [String: Set<String>] = ["p": ["p", "div", "ul", "ol", "table", "h1", "h2", "h3", "h4", "h5", "h6"],
                                                        "li": ["li"], "option": ["option"], "tr": ["tr"], "td": ["td", "th", "tr"], "th": ["td", "th", "tr"]]
                if let open = stack.last?.name.lowercased(), let closers = impliedBy[open], closers.contains(lower), stack.count > 1 {
                    closeElement()
                }
            }
            stack.append(Element(name: name, openTag: tag, selfClosing: false))
        }
        while stack.count > 1 { closeElement() }
        return stack[0].children
    }

    /// Collapses whitespace inside a tag outside quoted values: newlines between attributes
    /// become single spaces.
    static func normalizeTag(_ tag: String) -> String {
        var out = ""
        var quote: Character?
        var lastWasSpace = false
        for character in tag {
            if let open = quote {
                out.append(character)
                if character == open { quote = nil }
                continue
            }
            if character == "\"" || character == "'" { quote = character }
            if character.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
                continue
            }
            if character == ">", out.hasSuffix(" ") { out.removeLast() }
            lastWasSpace = false
            out.append(character)
        }
        return out
    }

    static func tagName(_ tag: String) -> String {
        let body = tag.drop { $0 == "<" || $0 == "/" }
        return String(body.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
    }

    // MARK: Beautify

    public static func beautify(_ text: String, dialect: Dialect, options: Options = Options()) throws -> String {
        if dialect == .xml { try validateXML(text) }
        let nodes = parse(text, dialect: dialect)
        var lines: [String] = []
        renderBlock(nodes, depth: 0, dialect: dialect, options: options, into: &lines)
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    static func isInline(_ node: Node, dialect: Dialect) -> Bool {
        switch node {
        case .text: return true
        case .raw: return false
        case let .element(element):
            guard dialect == .html, inlineElements.contains(element.name.lowercased()) else { return false }
            return element.children.allSatisfy { isInline($0, dialect: dialect) }
        }
    }

    static func isBlankText(_ node: Node) -> Bool {
        if case let .text(text) = node { return text.allSatisfy(\.isWhitespace) }
        return false
    }

    private static func renderBlock(_ nodes: [Node], depth: Int, dialect: Dialect, options: Options, into lines: inout [String]) {
        let pad = String(repeating: options.indent, count: depth)
        var run: [Node] = []
        func flushRun() {
            let text = renderInline(run, dialect: dialect, options: options).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                for line in text.components(separatedBy: "\n") { lines.append(pad + line) }
            }
            run = []
        }
        for node in nodes {
            if isInline(node, dialect: dialect) {
                run.append(node)
                continue
            }
            flushRun()
            switch node {
            case .text: break
            case let .raw(text, isComment):
                if isComment && options.removeComments { continue }
                lines.append(pad + text.trimmingCharacters(in: .whitespacesAndNewlines))
            case let .element(element):
                renderElement(element, depth: depth, dialect: dialect, options: options, into: &lines)
            }
        }
        flushRun()
    }

    private static func renderElement(_ element: Element, depth: Int, dialect: Dialect, options: Options, into lines: inout [String]) {
        let pad = String(repeating: options.indent, count: depth)
        if element.selfClosing {
            lines.append(pad + element.openTag)
            return
        }
        let close = element.closeTag ?? (dialect == .html ? "</\(element.name)>" : "")
        if let raw = element.rawContent {
            let lower = element.name.lowercased()
            if lower == "pre" || lower == "textarea" {
                lines.append(pad + element.openTag + raw + close)
                return
            }
            let body = reindent(raw, pad: pad + options.indent)
            if body.isEmpty {
                lines.append(pad + element.openTag + close)
            } else {
                lines.append(pad + element.openTag)
                lines.append(contentsOf: body)
                lines.append(pad + close)
            }
            return
        }
        let children = element.children
        let meaningful = children.filter { !isBlankText($0) }
        if meaningful.isEmpty {
            lines.append(pad + element.openTag + close)
            return
        }
        if meaningful.allSatisfy({ isInline($0, dialect: dialect) }) {
            let inline = renderInline(children, dialect: dialect, options: options).trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.contains("\n"), inline.count + element.openTag.count + close.count <= 120 {
                lines.append(pad + element.openTag + inline + close)
                return
            }
        }
        lines.append(pad + element.openTag)
        renderBlock(children, depth: depth + 1, dialect: dialect, options: options, into: &lines)
        if !close.isEmpty { lines.append(pad + close) }
    }

    private static func renderInline(_ nodes: [Node], dialect: Dialect, options: Options) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case let .text(text):
                out += dialect == .html ? collapse(text) : text.trimmingCharacters(in: .whitespacesAndNewlines)
            case let .raw(text, isComment):
                if !(isComment && options.removeComments) { out += text }
            case let .element(element):
                if element.selfClosing {
                    out += element.openTag
                } else {
                    out += element.openTag + renderInline(element.children, dialect: dialect, options: options) + (element.closeTag ?? "</\(element.name)>")
                }
            }
        }
        return out
    }

    static func collapse(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(character)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Strips the common indentation of a script/style body and indents it under its tag.
    static func reindent(_ text: String, pad: String) -> [String] {
        var lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let common = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        return lines.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : pad + String($0.dropFirst(common)) }
    }

    // MARK: Minify

    public static func minify(_ text: String, dialect: Dialect, removeComments: Bool = true) throws -> String {
        if dialect == .xml { try validateXML(text) }
        let nodes = parse(text, dialect: dialect)
        return minified(nodes, dialect: dialect, removeComments: removeComments).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func minified(_ nodes: [Node], dialect: Dialect, removeComments: Bool) -> String {
        var out = ""
        for (index, node) in nodes.enumerated() {
            switch node {
            case let .text(text):
                guard dialect == .html else {
                    if !text.allSatisfy(\.isWhitespace) { out += text }
                    continue
                }
                // Whitespace next to inline content is a visible space in HTML; next to a
                // block boundary it isn't.
                let before = index > 0 && isInline(nodes[index - 1], dialect: dialect)
                let after = index + 1 < nodes.count && isInline(nodes[index + 1], dialect: dialect)
                var collapsed = collapse(text)
                if collapsed == " " {
                    if before && after { out += " " }
                    continue
                }
                if !before, collapsed.hasPrefix(" ") { collapsed.removeFirst() }
                if !after, collapsed.hasSuffix(" ") { collapsed.removeLast() }
                out += collapsed
            case let .raw(text, isComment):
                // Keep conditional comments; they're code for old IE.
                if isComment && removeComments && !text.hasPrefix("<!--[if") { continue }
                out += text
            case let .element(element):
                if element.selfClosing {
                    out += element.openTag
                } else if let raw = element.rawContent {
                    let lower = element.name.lowercased()
                    let body = lower == "pre" || lower == "textarea" ? raw : raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    out += element.openTag + body + (element.closeTag ?? "")
                } else {
                    out += element.openTag + minified(element.children, dialect: dialect, removeComments: removeComments) + (element.closeTag ?? (dialect == .html ? "</\(element.name)>" : ""))
                }
            }
        }
        return out
    }

    // MARK: XML validation

    public static func validateXML(_ text: String) throws {
        do {
            _ = try XMLDocument(xmlString: text, options: [.nodePreserveAll])
        } catch {
            let nsError = error as NSError
            var message = nsError.localizedDescription
            if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String { message = reason }
            throw FormatError(description: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Detection

    public static func looksLikeXML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return false }
        if trimmed.hasPrefix("<?xml") { return true }
        guard !looksLikeHTML(trimmed) else { return false }
        return (try? XMLDocument(xmlString: trimmed, options: [])) != nil
    }

    public static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512).lowercased()
        guard head.hasPrefix("<") else { return false }
        if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") { return true }
        let common = ["<div", "<p>", "<p ", "<span", "<a ", "<ul", "<table", "<head", "<body", "<section", "<img ", "<br", "<h1", "<h2", "<form", "<button", "<nav", "<script", "<link "]
        return text.hasSuffix(">") && common.contains { head.contains($0) }
    }
}
