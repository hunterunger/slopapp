import CoreGraphics
import Foundation

// "Which fonts does this file use, and do I have them?" Open or drop a PDF, Illustrator,
// EPS, SVG, HTML, CSS or RTF file: Specimen reads the font names it uses (without rendering
// it, and without any proprietary parsing), matches them against the library, and can
// activate the matching fonts.

public enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case pdf, svg, html, css, postScript, rtf

    public init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "pdf", "ai": self = .pdf
        case "svg": self = .svg
        case "html", "htm", "xhtml": self = .html
        case "css": self = .css
        case "eps", "epsf", "ps": self = .postScript
        case "rtf": self = .rtf
        default: return nil
        }
    }

    public static let extensions = ["pdf", "ai", "svg", "html", "htm", "xhtml", "css", "eps", "epsf", "ps", "rtf"]

    public var title: String {
        switch self {
        case .pdf: "PDF"
        case .svg: "SVG"
        case .html: "HTML"
        case .css: "CSS"
        case .postScript: "PostScript"
        case .rtf: "Rich Text"
        }
    }
}

/// One font a document names.
public struct FontReference: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        /// A PostScript name ("Inter-Bold"): PDF, EPS.
        case postScript
        /// A family name ("Inter"): CSS, SVG, HTML.
        case family
        /// Could be either (RTF, CSS `local()`).
        case either
    }

    public var name: String
    public var kind: Kind
    /// PDF: the font itself is inside the file (it prints, but you need it to edit the source).
    public var isEmbedded: Bool
    /// CSS: declared by an `@font-face` rule, so the page brings its own file.
    public var isProvidedByDocument: Bool

    public init(name: String, kind: Kind, isEmbedded: Bool = false, isProvidedByDocument: Bool = false) {
        self.name = name
        self.kind = kind
        self.isEmbedded = isEmbedded
        self.isProvidedByDocument = isProvidedByDocument
    }
}

public enum DocumentFontReader {
    public enum Failure: Error, Equatable {
        case unsupported
        case unreadable
        case tooLarge
    }

    /// Text files over this size aren't read (a CSS or SVG file is rarely over a few MB).
    static let textLimit = 64 * 1024 * 1024

    /// The fonts a file names, in the order they first appear. `readLinked` reads a local
    /// stylesheet an HTML file links to (relative paths only; never the network).
    public static func references(in url: URL) throws -> [FontReference] {
        guard let kind = DocumentKind(pathExtension: url.pathExtension) else { throw Failure.unsupported }
        if kind == .pdf {
            if let document = CGPDFDocument(url as CFURL) { return references(pdf: document) }
            // An Illustrator file saved without PDF compatibility is PostScript.
            guard url.pathExtension.lowercased() == "ai" else { throw Failure.unreadable }
            return references(postScript: try text(url))
        }
        let source = try text(url)
        switch kind {
        case .svg: return references(svg: source)
        case .html: return references(html: source) { href in
            let linked = url.deletingLastPathComponent().appendingPathComponent(href).standardizedFileURL
            return try? text(linked)
        }
        case .css: return references(css: source)
        case .postScript: return references(postScript: source)
        case .rtf: return references(rtf: source)
        case .pdf: return []
        }
    }

    static func text(_ url: URL) throws -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= textLimit else { throw Failure.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: CSS, HTML, SVG

    /// Families in `font-family` and `font` declarations, `@font-face` names (marked as
    /// provided by the document) and `local()` sources.
    public static func references(css source: String) -> [FontReference] {
        var css = strip(source, between: "/*", and: "*/")
        var provided: [String] = []
        var local: [String] = []
        // @font-face blocks declare web fonts the page brings itself.
        while let start = css.range(of: "@font-face", options: .caseInsensitive),
              let open = css.range(of: "{", range: start.upperBound..<css.endIndex),
              let close = css.range(of: "}", range: open.upperBound..<css.endIndex) {
            let block = String(css[open.upperBound..<close.lowerBound])
            for value in declarations(of: "font-family", in: block) { provided += familyList(value) }
            local += matches(of: #"local\(\s*(?:"([^"]+)"|'([^']+)'|([^)]+))\s*\)"#, in: block)
            css.removeSubrange(start.lowerBound..<close.upperBound)
        }
        var names: [String] = []
        for value in declarations(of: "font-family", in: css) { names += familyList(value) }
        for value in declarations(of: "font", in: css) { names += familyList(shorthandFamilies(value)) }
        let providedKeys = Set(provided.map(DocumentFontMatcher.fold))
        var result = ordered(names).map { FontReference(name: $0, kind: .family, isProvidedByDocument: providedKeys.contains(DocumentFontMatcher.fold($0))) }
        let seen = Set(result.map { DocumentFontMatcher.fold($0.name) })
        result += ordered(provided).filter { !seen.contains(DocumentFontMatcher.fold($0)) }
            .map { FontReference(name: $0, kind: .family, isProvidedByDocument: true) }
        result += ordered(local.map { $0.trimmingCharacters(in: .whitespaces) }).map { FontReference(name: $0, kind: .either) }
        return result
    }

    public static func references(html source: String, readLinked: (String) -> String? = { _ in nil }) -> [FontReference] {
        var css = elements("style", in: source).joined(separator: "\n")
        for style in attributes("style", in: source) { css += "\nx{\(decodeEntities(style))}" }
        for face in attributes("face", in: source) { css += "\nx{font-family:\(decodeEntities(face))}" }
        // Linked stylesheets next to the file (never fetched from the network).
        for tag in matches(of: #"<link\b[^>]*>"#, in: source) where tag.range(of: "stylesheet", options: .caseInsensitive) != nil {
            guard let href = attributes("href", in: tag).first, !href.contains(":"), !href.hasPrefix("//") else { continue }
            if let linked = readLinked(href.components(separatedBy: "?")[0]) { css += "\n" + linked }
        }
        return references(css: css)
    }

    public static func references(svg source: String) -> [FontReference] {
        var css = elements("style", in: source).joined(separator: "\n")
        for style in attributes("style", in: source) { css += "\nx{\(decodeEntities(style))}" }
        for family in attributes("font-family", in: source) { css += "\nx{font-family:\(decodeEntities(family))}" }
        return references(css: css)
    }

    /// The entities that show up in attribute values (quotes inside `style="…"`).
    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `font-family` values in a declaration list.
    static func declarations(of property: String, in css: String) -> [String] {
        // Not part of a longer property name ("-font-family", "font-size").
        matches(of: #"(?<![-\w])"# + property + #"\s*:\s*([^;}{]+)"#, in: css)
    }

    /// The families at the end of a `font` shorthand: everything after the size (and line height).
    static func shorthandFamilies(_ value: String) -> String {
        let systemFonts: Set<String> = ["caption", "icon", "menu", "message-box", "small-caption", "status-bar"]
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if systemFonts.contains(trimmed.lowercased()) || trimmed.hasPrefix("var(") { return "" }
        let size = #"(?:^|\s)(?:[\d.]+(?:px|pt|pc|em|rem|ex|ch|%|vw|vh|vmin|vmax|cm|mm|in|q)|xx-small|x-small|small|medium|large|x-large|xx-large|xxx-large|larger|smaller)(?:\s*/\s*[^\s,]+)?\s+"#
        guard let range = trimmed.range(of: size, options: [.regularExpression, .caseInsensitive]) else { return "" }
        return String(trimmed[range.upperBound...])
    }

    static let genericFamilies: Set<String> = [
        "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-serif", "ui-sans-serif", "ui-monospace",
        "ui-rounded", "emoji", "math", "fangsong", "-apple-system", "blinkmacsystemfont", "inherit", "initial", "unset",
        "revert", "revert-layer", "default", "none",
    ]

    /// `"Brand Sans", Inter, sans-serif !important` → ["Brand Sans", "Inter"].
    public static func familyList(_ value: String) -> [String] {
        let value = value.replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
        var items: [String] = []
        var current = "", quote: Character?
        for character in value {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty && !genericFamilies.contains($0.lowercased()) && !$0.lowercased().hasPrefix("var(") }
    }

    /// The contents of every `<name>…</name>` element.
    static func elements(_ name: String, in source: String) -> [String] {
        matches(of: "<" + name + #"\b[^>]*>([\s\S]*?)</"# + name + ">", in: source)
    }

    /// The values of every `name="…"` (or `'…'`) attribute.
    static func attributes(_ name: String, in source: String) -> [String] {
        matches(of: #"(?<![-\w])"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: source)
    }

    /// The first non-empty capture group of every match (or the whole match without groups).
    static func matches(of pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let text = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            if match.numberOfRanges == 1 { return text.substring(with: match.range) }
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                return text.substring(with: match.range(at: index))
            }
            return nil
        }
    }

    static func strip(_ source: String, between open: String, and close: String) -> String {
        var result = source
        while let start = result.range(of: open) {
            let end = result.range(of: close, range: start.upperBound..<result.endIndex)?.upperBound ?? result.endIndex
            result.removeSubrange(start.lowerBound..<end)
        }
        return result
    }

    static func ordered(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(DocumentFontMatcher.fold($0)).inserted }
    }

    // MARK: PostScript (EPS, PS, older Illustrator files)

    /// DSC comments: `%%DocumentFonts:`, `%%DocumentNeededResources: font …` and their `%%+`
    /// continuations; supplied fonts are embedded.
    public static func references(postScript source: String) -> [FontReference] {
        var needed: [String] = [], supplied: [String] = []
        var section: String?
        for rawLine in source.split(whereSeparator: \.isNewline) {
            guard rawLine.hasPrefix("%%") else { section = nil; continue }
            var line = String(rawLine.dropFirst(2))
            if line.hasPrefix("+") {
                line.removeFirst()
            } else if let colon = line.firstIndex(of: ":") {
                section = String(line[..<colon])
                line = String(line[line.index(after: colon)...])
            } else {
                section = nil
                continue
            }
            guard let section else { continue }
            var words = line.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0 != "(atend)" }
            switch section {
            case "DocumentFonts", "DocumentNeededFonts", "IncludeFont":
                needed += words
            case "DocumentSuppliedFonts":
                supplied += words
            case "DocumentNeededResources", "IncludeResource", "DocumentSuppliedResources":
                // Other resources (procsets, files) are skipped.
                guard words.first == "font" else { continue }
                words.removeFirst()
                if section == "DocumentSuppliedResources" { supplied += words } else { needed += words }
            default: break
            }
        }
        let embedded = Set(supplied)
        return ordered(needed + supplied).map { FontReference(name: $0, kind: .postScript, isEmbedded: embedded.contains($0)) }
    }

    // MARK: RTF

    /// Names in the `{\fonttbl …}` group.
    public static func references(rtf source: String) -> [FontReference] {
        guard let start = source.range(of: "{\\fonttbl") else { return [] }
        // The group runs to its matching brace.
        var depth = 0
        var end = source.endIndex
        var index = start.lowerBound
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 } else if source[index] == "}" {
                depth -= 1
                if depth == 0 { end = source.index(after: index); break }
            }
            index = source.index(after: index)
        }
        var table = String(source[start.upperBound..<end])
        // Drop destination groups ({\*\panose …}, {\*\falt …}).
        table = table.replacingOccurrences(of: #"\{\\\*[^{}]*\}"#, with: " ", options: .regularExpression)
        let names = table.split(separator: ";").map { entry -> String in
            entry.replacingOccurrences(of: #"\\[a-zA-Z]+-?\d* ?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return ordered(names).map { FontReference(name: $0, kind: .either) }
    }

    // MARK: PDF

    /// `BaseFont` names in every page's font resources (and form XObjects'), subset prefixes
    /// removed ("ABCDEF+Inter-Bold" → "Inter-Bold"), with whether each is embedded.
    public static func references(pdf document: CGPDFDocument) -> [FontReference] {
        let collector = PDFFontCollector()
        for number in stride(from: 1, through: document.numberOfPages, by: 1) {
            guard let page = document.page(at: number), let dictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
                collector.collect(resources: resources, depth: 0)
            }
        }
        return collector.references
    }

    /// "ABCDEF+Inter-Bold" → "Inter-Bold".
    public static func stripSubsetPrefix(_ name: String) -> String {
        guard name.count > 7, let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6,
              name[..<plus].allSatisfy({ $0.isUppercase && $0.isASCII }) else { return name }
        return String(name[name.index(after: plus)...])
    }
}

/// Walks PDF resource dictionaries. Not thread-safe; one per document.
private final class PDFFontCollector {
    private(set) var references: [FontReference] = []
    private var seen: [String: Int] = [:]
    private var visited = Set<Int>()

    func collect(resources: CGPDFDictionaryRef, depth: Int) {
        guard depth < 8, visited.insert(unsafeBitCast(resources, to: Int.self)).inserted else { return }
        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
            CGPDFDictionaryApplyBlock(fonts, { _, object, _ in
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(object, .dictionary, &font), let font { self.add(font: font) }
                return true
            }, nil)
        }
        // Form XObjects carry their own resources (placed artwork, PDF-in-PDF).
        var xObjects: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects {
            CGPDFDictionaryApplyBlock(xObjects, { _, object, _ in
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
                var inner: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &inner), let inner { self.collect(resources: inner, depth: depth + 1) }
                return true
            }, nil)
        }
    }

    private func add(font: CGPDFDictionaryRef) {
        guard let raw = Self.name(font, "BaseFont") else { return }
        let name = DocumentFontReader.stripSubsetPrefix(raw)
        var descriptor: CGPDFDictionaryRef?
        if !CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor) {
            // Composite (Type 0) fonts keep it on their descendant.
            var descendants: CGPDFArrayRef?
            var first: CGPDFDictionaryRef?
            if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
               CGPDFArrayGetDictionary(descendants, 0, &first), let first {
                CGPDFDictionaryGetDictionary(first, "FontDescriptor", &descriptor)
            }
        }
        var embedded = false
        if let descriptor {
            var stream: CGPDFStreamRef?
            for key in ["FontFile", "FontFile2", "FontFile3"] where !embedded {
                embedded = key.withCString { CGPDFDictionaryGetStream(descriptor, $0, &stream) }
            }
        }
        if let index = seen[name] {
            references[index].isEmbedded = references[index].isEmbedded || embedded
        } else {
            seen[name] = references.count
            references.append(FontReference(name: name, kind: .postScript, isEmbedded: embedded))
        }
    }

    static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(validatingCString: value) ?? String(cString: value)
    }
}

// MARK: Matching

/// A document's font, and the library's faces for it.
public struct DocumentFontMatch: Hashable, Sendable, Identifiable {
    public enum Status: Sendable, Hashable {
        /// Every matching face is on.
        case active
        /// Some are on.
        case partlyActive
        /// In the library, but off: Specimen can activate it.
        case inactive
        /// Not in the library.
        case missing
    }

    public var reference: FontReference
    /// The best copy of each matching face (see `DocumentFontMatcher`).
    public var faces: [FontFace]
    public var status: Status

    public var id: String { "\(reference.kind.rawValue):\(reference.name)" }
    public var inactiveFaces: [FontFace] { faces.filter { !$0.isEnabled } }
}

public enum DocumentFontMatcher {
    /// Case-, accent- and width-insensitive.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Letters and digits only, folded: "Source Sans Pro" and "SourceSansPro" match.
    public static func squash(_ text: String) -> String {
        String(fold(text).unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Matches each reference to library faces. Where several files hold the same face, the
    /// active copy wins, else the one nearest the document (a project's own Fonts folder).
    public static func match(_ references: [FontReference], in faces: [FontFace], documentPath: String?) -> [DocumentFontMatch] {
        match(references, in: Index(faces), documentPath: documentPath)
    }

    /// The same, against an index built once for several documents.
    public static func match(_ references: [FontReference], in index: Index, documentPath: String?) -> [DocumentFontMatch] {
        references.map { reference in
            let candidates: [FontFace]
            switch reference.kind {
            case .postScript: candidates = index.postScript(reference.name)
            case .family: candidates = index.family(reference.name)
            case .either:
                let byName = index.postScript(reference.name)
                candidates = byName.isEmpty ? index.family(reference.name) : byName
            }
            let chosen = bestCopies(candidates, near: documentPath)
            let enabled = chosen.filter(\.isEnabled).count
            let status: DocumentFontMatch.Status = chosen.isEmpty ? .missing
                : enabled == chosen.count ? .active : enabled == 0 ? .inactive : .partlyActive
            return DocumentFontMatch(reference: reference, faces: chosen, status: status)
        }
    }

    /// One face per PostScript name: an active copy, else the copy sharing the longest folder
    /// path with the document, else the first by path.
    static func bestCopies(_ faces: [FontFace], near documentPath: String?) -> [FontFace] {
        let folder = documentPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        func closeness(_ face: FontFace) -> Int {
            guard let path = face.path else { return 0 }
            return zip(folder.split(separator: "/"), path.split(separator: "/")).prefix { $0 == $1 }.count
        }
        let grouped = Dictionary(grouping: faces, by: \.postScriptName)
        return grouped.keys.sorted().compactMap { name in
            grouped[name]?.min { a, b in
                if a.isEnabled != b.isEnabled { return a.isEnabled }
                let ca = closeness(a), cb = closeness(b)
                if ca != cb { return ca > cb }
                return (a.path ?? "") < (b.path ?? "")
            }
        }.sorted(by: FontFamily.styleOrder)
    }

    public struct Index: Sendable {
        var byPostScript: [String: [FontFace]] = [:]
        var bySquashedName: [String: [FontFace]] = [:]
        var byFamily: [String: [FontFace]] = [:]
        var bySquashedFamily: [String: [FontFace]] = [:]

        public init(_ faces: [FontFace]) {
            for face in faces {
                byPostScript[face.postScriptName.lowercased(), default: []].append(face)
                for name in Set([squash(face.postScriptName), squash(face.fullName), squash(face.familyName + face.styleName)]) {
                    bySquashedName[name, default: []].append(face)
                }
                for family in Set([fold(face.familyName), fold(face.displayFamilyName)]) { byFamily[family, default: []].append(face) }
                for family in Set([squash(face.familyName), squash(face.displayFamilyName)]) { bySquashedFamily[family, default: []].append(face) }
            }
        }

        func postScript(_ name: String) -> [FontFace] {
            if let exact = byPostScript[name.lowercased()] { return exact }
            if let loose = bySquashedName[squash(name)] { return loose }
            // "Arial,Bold" (PDF) and "Family-Style" with a PostScript name the font doesn't use.
            for separator in [",", "-"] {
                guard let cut = name.range(of: separator, options: .backwards) else { continue }
                let family = squash(String(name[..<cut.lowerBound])), style = squash(String(name[cut.upperBound...]))
                guard !family.isEmpty, let members = bySquashedFamily[family] else { continue }
                let styled = members.filter { squash($0.styleName) == style }
                if !styled.isEmpty { return styled }
            }
            return []
        }

        func family(_ name: String) -> [FontFace] {
            byFamily[fold(name)] ?? bySquashedFamily[squash(name)] ?? []
        }
    }
}

// MARK: Opened documents

/// A document in the sidebar's Documents section.
public struct OpenedDocument: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public var opened: Date

    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, opened: Date = Date()) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.opened = opened
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var kind: DocumentKind? { DocumentKind(pathExtension: (path as NSString).pathExtension) }
}

/// The Documents list, newest first, in documents.json.
public struct DocumentsStore: Sendable {
    public let url: URL
    public static let limit = 20

    public init(directory: URL) {
        url = directory.appendingPathComponent("documents.json")
    }

    public func load() -> [OpenedDocument] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([OpenedDocument].self, from: data)) ?? []
    }

    public func save(_ documents: [OpenedDocument]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(Array(documents.prefix(Self.limit))).write(to: url, options: .atomic)
    }

    /// Opening a document again moves it to the top instead of adding it twice.
    public static func adding(_ path: String, to documents: [OpenedDocument], bookmark: Data? = nil) -> (documents: [OpenedDocument], id: UUID) {
        var list = documents
        let existing = list.firstIndex { $0.path == path }
        let id = existing.map { list[$0].id } ?? UUID()
        if let existing { list.remove(at: existing) }
        list.insert(OpenedDocument(id: id, path: path, bookmark: bookmark), at: 0)
        return (Array(list.prefix(limit)), id)
    }
}
