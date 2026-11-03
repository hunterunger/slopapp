import Foundation

/// The tools, in sidebar order. ⌘1…⌘9 follow this order.
public enum Tool: String, CaseIterable, Identifiable, Sendable, Codable {
    case json, jwt, base64, url, timestamp, uuid, hash, regex, diff, color, numberBase, textCase

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .json: "JSON"
        case .jwt: "JWT"
        case .base64: "Base64"
        case .url: "URL Encode"
        case .timestamp: "Unix Time"
        case .uuid: "UUID and ULID"
        case .hash: "Hash"
        case .regex: "Regex"
        case .diff: "Text Diff"
        case .color: "Color"
        case .numberBase: "Number Base"
        case .textCase: "Text Case"
        }
    }

    /// One line under the title in the window's toolbar.
    public var subtitle: String {
        switch self {
        case .json: "Format, validate and minify"
        case .jwt: "Decode tokens and check signatures"
        case .base64: "Encode and decode"
        case .url: "Percent-encode and decode"
        case .timestamp: "Timestamps to dates and back"
        case .uuid: "Generate and inspect"
        case .hash: "MD5, SHA-1 and SHA-2 for text or files"
        case .regex: "Test patterns and replacements"
        case .diff: "Compare two texts line by line"
        case .color: "Hex, RGB, HSL and code"
        case .numberBase: "Binary, octal, decimal, hex"
        case .textCase: "camelCase, snake_case and more"
        }
    }

    /// SF Symbol for the sidebar (app UI only; never in the app icon).
    public var symbol: String {
        switch self {
        case .json: "curlybraces"
        case .jwt: "key"
        case .base64: "character.textbox"
        case .url: "link"
        case .timestamp: "clock"
        case .uuid: "number"
        case .hash: "number.square"
        case .regex: "text.magnifyingglass"
        case .diff: "plus.forwardslash.minus"
        case .color: "paintpalette"
        case .numberBase: "01.square"
        case .textCase: "character.cursor.ibeam"
        }
    }

    /// Extra words the sidebar filter matches.
    public var keywords: [String] {
        switch self {
        case .json: ["format", "pretty", "minify", "validate", "beautify", "lint"]
        case .jwt: ["token", "jws", "bearer", "claims", "hmac"]
        case .base64: ["b64", "decode", "encode", "base64url"]
        case .url: ["percent", "encode", "decode", "query", "uri", "escape"]
        case .timestamp: ["epoch", "unix", "date", "time", "iso", "8601", "rfc 2822"]
        case .uuid: ["guid", "ulid", "random", "id", "generate"]
        case .hash: ["md5", "sha", "sha1", "sha256", "sha512", "checksum", "digest", "hmac"]
        case .regex: ["regular expression", "regexp", "pattern", "match", "replace"]
        case .diff: ["compare", "difference", "changes"]
        case .color: ["hex", "rgb", "hsl", "hsb", "colour", "css", "contrast"]
        case .numberBase: ["binary", "hex", "octal", "decimal", "radix", "base"]
        case .textCase: ["camel", "snake", "kebab", "pascal", "upper", "lower", "title", "case"]
        }
    }

    public func matches(filter: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
            || subtitle.lowercased().contains(query)
    }
}
