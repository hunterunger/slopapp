import Foundation

/// Guesses which tool a piece of text belongs to. Ordered rules, first match wins.
public enum Detector {
    public enum Hint: Sendable, Equatable {
        case none
        /// Base64 / URL: switch to decoding.
        case decode
        /// UUID tool: inspect rather than generate.
        case inspect
    }

    public struct Detection: Sendable, Equatable {
        public var tool: Tool
        public var input: String
        public var hint: Hint
    }

    /// Detection never runs on more text than this.
    public static let maxBytes = 1_000_000

    public static func detect(_ text: String) -> Detection? {
        guard text.utf8.count <= maxBytes else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let singleToken = !trimmed.contains(where: \.isWhitespace)

        // 1. JWT
        var token = trimmed
        if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        if !token.contains(where: \.isWhitespace), JWT.looksLikeToken(token) {
            return Detection(tool: .jwt, input: token, hint: .none)
        }
        // 2. JSON objects and arrays
        if let first = trimmed.first, first == "{" || first == "[", JSONFormatter.isValid(trimmed) {
            return Detection(tool: .json, input: trimmed, hint: .none)
        }
        guard singleToken || trimmed.lowercased().hasPrefix("rgb") || trimmed.lowercased().hasPrefix("hsl") else {
            // Multi-word text: only URL escapes can still apply.
            return urlEncoded(trimmed)
        }
        // 3. UUID / ULID
        if Identifiers.parseUUID(trimmed) != nil || (trimmed.count == 26 && Identifiers.decodeULID(trimmed) != nil && isULIDShaped(trimmed)) {
            return Detection(tool: .uuid, input: trimmed, hint: .inspect)
        }
        // 4. Unix timestamp
        if Timestamps.isPlausibleTimestamp(trimmed) {
            return Detection(tool: .timestamp, input: trimmed, hint: .none)
        }
        // 5. Color
        if ColorConverter.looksLikeColor(trimmed) {
            return Detection(tool: .color, input: trimmed, hint: .none)
        }
        // 6. URL-encoded
        if let detection = urlEncoded(trimmed) { return detection }
        // 7. Base64
        if isLikelyBase64(trimmed) {
            return Detection(tool: .base64, input: trimmed, hint: .decode)
        }
        // 8. Numbers with a base prefix
        let lower = trimmed.lowercased()
        if ["0x", "0b", "0o"].contains(where: lower.hasPrefix), (try? NumberBase.parse(trimmed)) != nil {
            return Detection(tool: .numberBase, input: trimmed, hint: .none)
        }
        return nil
    }

    /// ULIDs are uppercase or lowercase Crockford, with at least one letter and one digit,
    /// so a 26-letter word isn't mistaken for one.
    static func isULIDShaped(_ text: String) -> Bool {
        let hasDigit = text.contains(where: \.isASCIIDigit)
        let hasLetter = text.contains(where: \.isLetter)
        let consistentCase = text == text.uppercased() || text == text.lowercased()
        return hasDigit && hasLetter && consistentCase
    }

    static func urlEncoded(_ text: String) -> Detection? {
        guard URLCoding.containsEscape(text), let decoded = try? URLCoding.decode(text, plusAsSpace: false), decoded != text else { return nil }
        return Detection(tool: .url, input: text, hint: .decode)
    }

    static func isLikelyBase64(_ text: String) -> Bool {
        guard text.count >= 8 else { return false }
        let standard = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let urlSafe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
        let isStandard = text.allSatisfy(standard.contains)
        let isURLSafe = text.allSatisfy(urlSafe.contains)
        guard isStandard || isURLSafe else { return false }
        // Standard Base64 is padded to a multiple of 4; base64url often isn't.
        if isStandard, !isURLSafe || text.count % 4 == 0 {
            guard text.count % 4 == 0 else { return false }
        }
        // Plain words and numbers are valid Base64 alphabet too; require some variety.
        let hasUpper = text.contains(where: \.isUppercase), hasLower = text.contains(where: \.isLowercase)
        guard hasUpper && hasLower || text.hasSuffix("=") else { return false }
        guard let data = try? Base64.decode(text), let decoded = UTF8Text.string(data) else { return false }
        return !decoded.isEmpty && TextHeuristics.looksLikeText(decoded, threshold: 0.95)
    }
}
