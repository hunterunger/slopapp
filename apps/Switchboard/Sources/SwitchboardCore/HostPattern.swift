import Foundation

/// A host pattern from a rule: `example.com`, `*.example.com`, `localhost:3000`, `*`.
///
/// - `example.com` matches example.com and www.example.com.
/// - `*.example.com` matches example.com and every subdomain.
/// - `*` anywhere matches any run of characters (`docs.*.com`); a lone `*` matches any host.
/// - A `:port` suffix must match the link's port; without one, any port matches.
/// - Case-insensitive. Unicode hosts are compared in their punycode form.
public struct HostPattern: Equatable, Sendable {
    public let host: String
    public let port: Int?

    /// Parses what the user typed. Tolerates a scheme and a trailing path ("https://x.com/a"),
    /// which the rule editor splits off into the path field. Returns nil for empty input.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        guard !text.isEmpty else { return nil }

        var port: Int?
        let colons = text.filter { $0 == ":" }.count
        // "host:port" or "[v6]:port". A bare IPv6 address ("::1") has no port.
        if let colon = text.lastIndex(of: ":"), colons == 1 || text.hasPrefix("[") {
            let portText = text[text.index(after: colon)...]
            if let value = Int(portText), (0...65535).contains(value), !text[..<colon].hasSuffix(":") {
                port = value
                text = String(text[..<colon])
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !text.isEmpty else { return nil }
        self.host = Self.asciiHost(text)
        self.port = port
    }

    public func matches(_ url: URL) -> Bool {
        guard let rawHost = url.host?.lowercased(), !rawHost.isEmpty else { return false }
        if let port, url.port != port { return false }
        let target = Self.asciiHost(rawHost)
        if host == "*" { return true }
        if host.hasPrefix("*."), !host.dropFirst(2).contains("*") {
            let base = String(host.dropFirst(2))
            return target == base || target.hasSuffix("." + base)
        }
        if host.contains("*") {
            return Self.glob(host, target)
        }
        return target == host || target == "www." + host
    }

    /// True if every host this pattern's `other` matches is also matched by this pattern.
    /// Approximate for exotic globs (answers false when unsure).
    public func covers(_ other: HostPattern) -> Bool {
        if let port, other.port != port { return false }
        if host == "*" { return true }
        let theirs = other.host
        if theirs == "*" { return false }
        if host.hasPrefix("*."), !host.dropFirst(2).contains("*") {
            let base = String(host.dropFirst(2))
            let theirBase = theirs.hasPrefix("*.") ? String(theirs.dropFirst(2)) : theirs
            guard !theirBase.contains("*") else { return false }
            return theirBase == base || theirBase.hasSuffix("." + base)
        }
        if host.contains("*") {
            if theirs.contains("*") { return theirs == host }
            return Self.glob(host, theirs) && Self.glob(host, "www." + theirs)
        }
        if theirs.contains("*") { return false }
        return theirs == host || theirs == "www." + host
    }

    /// Unicode labels to punycode, via Foundation's URL parser (which applies IDNA).
    static func asciiHost(_ host: String) -> String {
        guard host.unicodeScalars.contains(where: { !$0.isASCII }) else { return host }
        // Wildcards aren't valid in hosts; encode label by label.
        return host.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            guard label.unicodeScalars.contains(where: { !$0.isASCII }),
                  let encoded = URL(string: "https://\(label)")?.host
            else { return String(label) }
            return encoded.lowercased()
        }.joined(separator: ".")
    }

    /// `*` matches any run of characters (including dots).
    static func glob(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// A path prefix from a rule: `/j/` matches `/j/123`. A trailing `*` is allowed and ignored.
public struct PathPrefix: Equatable, Sendable {
    public let prefix: String

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<cut]) }
        while text.hasSuffix("*") { text.removeLast() }
        guard !text.isEmpty, text != "/" else { return nil }
        if !text.hasPrefix("/") { text = "/" + text }
        self.prefix = text
    }

    public func matches(_ url: URL) -> Bool {
        // Compare decoded with decoded, so "/café" and "/caf%C3%A9" are the same prefix.
        let decodedPrefix = prefix.removingPercentEncoding ?? prefix
        let path = url.path.isEmpty ? "/" : url.path
        let encodedPath = url.path(percentEncoded: true)
        return path.hasPrefix(decodedPrefix) || encodedPath.hasPrefix(prefix)
    }
}
