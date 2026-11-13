import Foundation

/// What kind of thing a link is. Rules, targets and fallbacks are per kind: a web rule never
/// catches an email link, and the picker for an email link lists email apps, not browsers.
public enum LinkKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// http(s) links, and local web pages (.html files): they open in browsers.
    case web
    /// mailto: links.
    case email
    /// Other files Switchboard was asked to open (PDFs, chosen types).
    case file

    /// "Web links", for pickers and summaries.
    public var title: String {
        switch self {
        case .web: "Web links"
        case .email: "Email links"
        case .file: "Files"
        }
    }

    /// File extensions that are web pages, so they open in browsers like web links.
    public static let webPageExtensions: Set<String> = ["html", "htm", "xhtml", "shtml"]

    /// The kind of `url`, or nil for an app's own link (`zoommtg:`, `music:`…), which isn't
    /// routed at all: it goes straight to the app that handles it.
    public static func of(_ url: URL) -> LinkKind? {
        switch url.scheme?.lowercased() ?? "" {
        case "http", "https": .web
        case "mailto": .email
        case "file": webPageExtensions.contains(url.pathExtension.lowercased()) ? .web : .file
        default: nil
        }
    }
}

extension IncomingLink {
    /// nil for an app link (after a rewrite), which skips routing.
    public var kind: LinkKind? { LinkKind.of(url) }
}

/// A `mailto:` link taken apart (RFC 6068): recipients, subject, body.
public struct MailtoLink: Equatable, Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var body: String

    public init(to: [String] = [], cc: [String] = [], bcc: [String] = [], subject: String = "", body: String = "") {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    /// Parses `mailto:a@x.com,b@y.com?cc=c@z.com&subject=Hi%20there&body=…`. Header names are
    /// case-insensitive; `+` stays a plus (mailto isn't form encoding). nil if it isn't mailto.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        let raw = url.absoluteString
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let rest = raw[raw.index(after: colon)...]
        let addressPart: Substring
        let query: Substring
        if let mark = rest.firstIndex(of: "?") {
            addressPart = rest[..<mark]
            query = rest[rest.index(after: mark)...]
        } else {
            addressPart = rest
            query = ""
        }
        self.init()
        to = Self.addresses(String(addressPart))
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = (String(parts[0]).removingPercentEncoding ?? String(parts[0])).lowercased()
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let value = rawValue.removingPercentEncoding ?? rawValue
            switch name {
            case "to": to += Self.addresses(value, alreadyDecoded: true)
            case "cc": cc += Self.addresses(value, alreadyDecoded: true)
            case "bcc": bcc += Self.addresses(value, alreadyDecoded: true)
            case "subject": subject = value
            case "body": body = value
            default: break
            }
        }
    }

    private static func addresses(_ text: String, alreadyDecoded: Bool = false) -> [String] {
        let decoded = alreadyDecoded ? text : (text.removingPercentEncoding ?? text)
        return decoded.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Everyone the message goes to.
    public var recipients: [String] { to + cc + bcc }

    /// The domain of an address, lowercased ("Name@Example.COM" → "example.com").
    public static func domain(of address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: at)...].trimmingCharacters(in: CharacterSet(charactersIn: " >")).lowercased()
        return domain.isEmpty ? nil : domain
    }

    /// The link rebuilt, encoded strictly (what webmail "mailto=" parameters expect).
    public var url: URL {
        var text = "mailto:" + to.map(QueryEncoding.encode).joined(separator: ",")
        var query: [String] = []
        if !cc.isEmpty { query.append("cc=" + QueryEncoding.encode(cc.joined(separator: ","))) }
        if !bcc.isEmpty { query.append("bcc=" + QueryEncoding.encode(bcc.joined(separator: ","))) }
        if !subject.isEmpty { query.append("subject=" + QueryEncoding.encode(subject)) }
        if !body.isEmpty { query.append("body=" + QueryEncoding.encode(body)) }
        if !query.isEmpty { text += "?" + query.joined(separator: "&") }
        return URL(string: text) ?? URL(string: "mailto:")!
    }
}

/// Strict percent-encoding for query values: only unreserved characters (RFC 3986) and `@`
/// stay as they are, so `&`, `=`, `+`, `#` and `,` in a subject can't break the URL.
public enum QueryEncoding {
    static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~@")

    public static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// An email rule's "To" condition: `example.com` (and `www.`-less subdomain rules like web
/// rules: `*.example.com` covers every subdomain), or one exact address `name@example.com`.
public struct AddressPattern: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case address(String)
        case domain(HostPattern)
    }

    public let kind: Kind

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("mailto:") { text.removeFirst(7) }
        if text.hasPrefix("*@") { text.removeFirst(2) }
        if text.hasPrefix("@") { text.removeFirst() }
        guard !text.isEmpty else { return nil }
        if text.contains("@") {
            guard MailtoLink.domain(of: text) != nil, !text.hasPrefix("@") else { return nil }
            kind = .address(text)
        } else {
            guard let host = HostPattern(text), host.port == nil else { return nil }
            kind = .domain(host)
        }
    }

    public func matches(address: String) -> Bool {
        let lower = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch kind {
        case .address(let exact):
            return lower == exact
        case .domain(let pattern):
            guard let domain = MailtoLink.domain(of: lower) else { return false }
            return pattern.matches(host: domain, port: nil)
        }
    }

    /// True if every address `other` matches, this matches too (conservative).
    public func covers(_ other: AddressPattern) -> Bool {
        switch (kind, other.kind) {
        case (.address(let a), .address(let b)): a == b
        case (.domain(let mine), .domain(let theirs)): mine.covers(theirs)
        case (.domain(let mine), .address(let b)): MailtoLink.domain(of: b).map { mine.matches(host: $0, port: nil) } ?? false
        case (.address, .domain): false
        }
    }
}
