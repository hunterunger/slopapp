import AppKit
import UniformTypeIdentifiers

/// Formatted snippets: stored as RTFD (text, formatting and images in one piece of data),
/// with the plain text kept alongside in `Snippet.content`. When one expands, the resolved
/// pieces are put back together with their formatting and pasted as RTFD, RTF and HTML
/// (images inline), plus plain text for apps that don't take formatting.
///
/// Data conversion only (no windows, no pasteboard access), so it's tested headlessly.
public enum RichText {
    /// Text with no font gets the system's default document font (what TextEdit uses).
    public static var baseFont: NSFont { NSFont.userFont(ofSize: 0) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize) }

    public static var baseAttributes: [NSAttributedString.Key: Any] { [.font: baseFont] }

    // MARK: Storage

    public static func decode(_ data: Data) -> NSAttributedString? {
        NSAttributedString(rtfd: data, documentAttributes: nil)
    }

    /// RTFD for `Snippet.richText`. Colours that only mean "the normal text colour" are
    /// dropped, so the text follows the app it's pasted into (and dark mode in the editor).
    public static func encode(_ text: NSAttributedString) -> Data? {
        let clean = normalized(text)
        return clean.rtfd(from: NSRange(location: 0, length: clean.length), documentAttributes: [:])
    }

    /// The plain mirror: the same characters (images stay U+FFFC), so offsets line up.
    public static func plain(_ text: NSAttributedString) -> String { text.string }

    /// A formatted copy of plain content, in the default font.
    public static func make(fromPlain content: String) -> NSAttributedString {
        NSAttributedString(string: content, attributes: baseAttributes)
    }

    /// Removes dynamic "text colour" foreground colours (what text views add while typing).
    public static func normalized(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: copy.length)
        copy.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            guard let color = value as? NSColor, color.type == .catalog,
                  ["textColor", "labelColor", "controlTextColor"].contains(color.colorNameComponent) else { return }
            copy.removeAttribute(.foregroundColor, range: range)
        }
        return copy
    }

    /// True when the text has any formatting or images worth keeping (bold, a font, a colour,
    /// a link, an image), i.e. making it plain would lose something.
    public static func hasFormatting(_ text: NSAttributedString) -> Bool {
        var found = false
        let base = baseFont
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, stop in
            for (key, value) in attributes {
                switch key {
                case .font:
                    if let font = value as? NSFont, font != base { found = true }
                case .paragraphStyle:
                    if let style = value as? NSParagraphStyle, style != NSParagraphStyle.default { found = true }
                default:
                    found = true
                }
            }
            if found { stop.pointee = true }
        }
        return found
    }

    // MARK: Putting a resolved snippet together

    /// The resolved pieces with their formatting: literal text keeps its own, placeholder
    /// text takes the placeholder's, text from a plain snippet gets the default font.
    /// `formatted(id)`: a formatted snippet's decoded text (nil for plain ones).
    public static func assemble(_ resolved: Resolved, formatted: (UUID) -> NSAttributedString?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var cache: [UUID: NSAttributedString?] = [:]
        func source(_ id: UUID?) -> NSAttributedString? {
            guard let id else { return nil }
            if let cached = cache[id] { return cached }
            let value = formatted(id)
            cache[id] = value
            return value
        }
        for piece in resolved.pieces {
            guard let rich = source(piece.snippetID), rich.length > 0 else {
                result.append(NSAttributedString(string: piece.text.filter { $0 != attachmentCharacter }, attributes: baseAttributes))
                continue
            }
            let range = NSRange(location: min(piece.source.lowerBound, rich.length),
                                length: max(0, min(piece.source.upperBound, rich.length) - min(piece.source.lowerBound, rich.length)))
            if !piece.generated, range.length == piece.text.utf16.count {
                let sub = NSMutableAttributedString(attributedString: rich.attributedSubstring(from: range))
                if sub.string != piece.text {
                    // Same length, different letters (adapted case): replace run by run so
                    // each run keeps its formatting.
                    let units = Array(piece.text.utf16)
                    sub.enumerateAttributes(in: NSRange(location: 0, length: sub.length)) { _, run, _ in
                        let replacement = String(utf16CodeUnits: Array(units[run.location..<run.location + run.length]), count: run.length)
                        sub.replaceCharacters(in: run, with: replacement)
                    }
                }
                result.append(sub)
            } else {
                var attributes = range.location < rich.length ? rich.attributes(at: range.location, effectiveRange: nil) : baseAttributes
                attributes[.attachment] = nil
                result.append(NSAttributedString(string: piece.text.filter { $0 != attachmentCharacter }, attributes: attributes))
            }
        }
        return result
    }

    // MARK: Pasteboard

    /// What goes on the pasteboard for a formatted paste, richest first. Apps take the best
    /// type they understand: RTFD (Mail, Pages, TextEdit, Notes), HTML (browsers, Electron
    /// apps), plain text (terminals, code editors). A snippet that is only an image also
    /// goes as that image (Messages, Slack, image editors).
    public static func pasteboardTypes(_ text: NSAttributedString, plain: String) -> [(NSPasteboard.PasteboardType, Data)] {
        var types: [(NSPasteboard.PasteboardType, Data)] = []
        let whole = NSRange(location: 0, length: text.length)
        let images = attachments(in: text)
        if !images.isEmpty, let rtfd = text.rtfd(from: whole, documentAttributes: [:]) {
            types.append((.rtfd, rtfd))
            types.append((NSPasteboard.PasteboardType("com.apple.flat-rtfd"), rtfd))
        }
        if let rtf = text.rtf(from: whole, documentAttributes: [:]) { types.append((.rtf, rtf)) }
        if let html = html(text).data(using: .utf8) { types.append((.html, html)) }
        types.append((.string, Data(plain.utf8)))
        if images.count == 1, text.string.trimmingCharacters(in: .whitespacesAndNewlines) == String(attachmentCharacter),
           let image = images.first {
            if let png = image.png { types.append((.png, png)) }
            if let tiff = image.tiff { types.append((.tiff, tiff)) }
        }
        return types
    }

    public struct Image {
        public var location: Int
        public var data: Data
        public var utType: UTType
        public var size: CGSize

        /// PNG data: the original when it's PNG, else converted.
        public var png: Data? {
            if utType.conforms(to: .png) { return data }
            guard let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        public var tiff: Data? { NSImage(data: data)?.tiffRepresentation }
    }

    public static func attachments(in text: NSAttributedString) -> [Image] {
        var images: [Image] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let wrapper = attachment.fileWrapper
            guard let data = wrapper?.regularFileContents ?? attachment.contents ?? attachment.image?.tiffRepresentation else { return }
            let name = wrapper?.preferredFilename ?? wrapper?.filename ?? ""
            let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? (attachment.contents == nil && wrapper == nil ? .tiff : .data)
            var size = attachment.bounds.size
            if size == .zero, let image = NSImage(data: data) { size = image.size }
            images.append(Image(location: range.location, data: data, utType: type, size: size))
        }
        return images
    }

    /// HTML with the images inline (data URLs), so a browser or an Electron app gets them too.
    public static func html(_ text: NSAttributedString) -> String {
        let images = attachments(in: text)
        let copy = NSMutableAttributedString(attributedString: text)
        var markers: [(String, Image)] = []
        for (index, image) in images.enumerated().reversed() {
            let marker = "SHORTHANDIMAGE\(index)MARK"
            let attributes = copy.attributes(at: image.location, effectiveRange: nil).filter { $0.key != .attachment }
            copy.replaceCharacters(in: NSRange(location: image.location, length: 1), with: NSAttributedString(string: marker, attributes: attributes))
            markers.append((marker, image))
        }
        // Any attachment we couldn't read: leave it out.
        let stray = copy.string.unicodeScalars.contains("\u{FFFC}")
        if stray { copy.mutableString.replaceOccurrences(of: "\u{FFFC}", with: "", options: [], range: NSRange(location: 0, length: copy.length)) }
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let data = try? copy.data(from: NSRange(location: 0, length: copy.length), documentAttributes: attributes),
              var html = String(data: data, encoding: .utf8) else { return "" }
        for (marker, image) in markers {
            let mime: String
            let payload: Data
            if image.utType.conforms(to: .png) || image.utType.conforms(to: .jpeg) || image.utType.conforms(to: .gif) {
                mime = image.utType.preferredMIMEType ?? "image/png"
                payload = image.data
            } else if let png = image.png {
                mime = "image/png"
                payload = png
            } else {
                html = html.replacingOccurrences(of: marker, with: "")
                continue
            }
            let size = image.size == .zero ? "" : " width=\"\(Int(image.size.width.rounded()))\" height=\"\(Int(image.size.height.rounded()))\""
            html = html.replacingOccurrences(of: marker, with: "<img src=\"data:\(mime);base64,\(payload.base64EncodedString())\"\(size) alt=\"\">")
        }
        return html
    }

    /// Pasted screenshots arrive as TIFF, which is huge: turn TIFF images into PNG, in place.
    /// Returns whether anything changed (so the editor only pays for it once per image).
    @discardableResult
    public static func compactImages(in text: NSMutableAttributedString) -> Bool {
        var changed = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let wrapper = attachment.fileWrapper,
                  let name = wrapper.preferredFilename ?? wrapper.filename,
                  let type = UTType(filenameExtension: (name as NSString).pathExtension), type.conforms(to: .tiff),
                  let data = wrapper.regularFileContents, let rep = NSBitmapImageRep(data: data),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let replacement = FileWrapper(regularFileWithContents: png)
            replacement.preferredFilename = ((name as NSString).deletingPathExtension as NSString).appendingPathExtension("png")
            let newAttachment = NSTextAttachment(fileWrapper: replacement)
            newAttachment.bounds = attachment.bounds
            text.addAttribute(.attachment, value: newAttachment, range: range)
            changed = true
        }
        return changed
    }

    // MARK: Building formatted text (imports, the image button)

    /// An image file as formatted text (one attachment).
    public static func image(at url: URL) -> NSAttributedString? {
        guard let wrapper = try? FileWrapper(url: url, options: .immediate), wrapper.isRegularFile,
              let data = wrapper.regularFileContents, NSImage(data: data) != nil else { return nil }
        if wrapper.preferredFilename == nil { wrapper.preferredFilename = url.lastPathComponent }
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        return NSAttributedString(attachment: attachment)
    }

    /// Markdown's inline formatting (bold, italic, code, links) as formatted text.
    public static func fromMarkdown(_ markdown: String) -> NSAttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return nil }
        let result = NSMutableAttributedString()
        let base = baseFont
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var attributes = baseAttributes
            var traits: NSFontDescriptor.SymbolicTraits = []
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if intent.contains(.code) { traits.insert(.monoSpace) }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if traits.contains(.monoSpace) {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: traits.contains(.bold) ? .bold : .regular)
            } else if !traits.isEmpty {
                let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(traits))
                attributes[.font] = NSFont(descriptor: descriptor, size: base.pointSize) ?? base
            }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    /// HTML as formatted text (WebKit's importer: main thread only). Trailing new lines the
    /// importer adds after the last paragraph are trimmed.
    @MainActor
    public static func fromHTML(_ html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8),
              let text = try? NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                               .characterEncoding: String.Encoding.utf8.rawValue],
                                                        documentAttributes: nil) else { return nil }
        while text.length > 0, text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
        return text
    }

    /// RTF or RTFD data (an import) as formatted text.
    public static func fromRTF(_ data: Data) -> NSAttributedString? {
        NSAttributedString(rtfd: data, documentAttributes: nil) ?? NSAttributedString(rtf: data, documentAttributes: nil)
    }

    /// Applies text edits (UTF-16 ranges in `text.string`, any order) keeping the formatting
    /// around them: used to turn another app's codes into Shorthand placeholders inside
    /// formatted text.
    public static func applying(_ edits: [TextEdit], to text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            guard range.upperBound <= copy.length else { continue }
            let attributes = range.location < copy.length ? copy.attributes(at: range.location, effectiveRange: nil).filter { $0.key != .attachment } : baseAttributes
            copy.replaceCharacters(in: range, with: NSAttributedString(string: edit.replacement, attributes: attributes))
        }
        return copy
    }
}
