import Foundation

/// A link handed to Switchboard, plus what we know about how it arrived.
public struct IncomingLink: Equatable, Sendable {
    public var url: URL
    /// Bundle ID of the app the link came from, when macOS tells us.
    public var sourceBundleID: String?
    /// Modifier keys held when the link arrived.
    public var modifiers: Modifiers
    /// Forces the picker regardless of rules (e.g. `switchboard://open?pick=1`).
    public var forcePicker: Bool

    public init(url: URL, sourceBundleID: String? = nil, modifiers: Modifiers = [], forcePicker: Bool = false) {
        self.url = url
        self.sourceBundleID = sourceBundleID
        self.modifiers = modifiers
        self.forcePicker = forcePicker
    }
}

/// What to do with a URL that arrived, before any routing.
public enum LinkIntake: Equatable, Sendable {
    /// A web link (or local HTML file) to route.
    case route(URL, forcePicker: Bool)
    /// Not something Switchboard handles.
    case reject(reason: String)
}

public enum LinkParser {
    public static let ownScheme = "switchboard"

    /// Validates an incoming URL. Accepts http(s), local .html/.htm/.xhtml files, and our own
    /// `switchboard://open?url=<encoded>&pick=1` scheme (for scripts and testing).
    public static func intake(_ url: URL) -> LinkIntake {
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else {
                return .reject(reason: "The link has no web address.")
            }
            return .route(url, forcePicker: false)
        case "file":
            let ext = url.pathExtension.lowercased()
            guard ["html", "htm", "xhtml", "shtml"].contains(ext) else {
                return .reject(reason: "Switchboard only opens web pages.")
            }
            return .route(url, forcePicker: false)
        case ownScheme:
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let inner = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return .reject(reason: "Expected switchboard://open?url=<link>.")
            }
            let pick = components.queryItems?.contains { $0.name == "pick" && $0.value != "0" } ?? false
            if inner.scheme?.lowercased() != ownScheme, case .route(let innerURL, _) = intake(inner) {
                return .route(innerURL, forcePicker: pick)
            }
            return .reject(reason: "Switchboard only opens web pages.")
        default:
            return .reject(reason: "Switchboard doesn't handle \(scheme.isEmpty ? "this kind of" : scheme + ":") links.")
        }
    }

    /// Finds a web link in free text (e.g. the clipboard): the whole text if it's a link or a
    /// bare domain ("example.com/path"), else the first http(s) link inside it
    /// ("see https://example.com/a, thanks").
    public static func webLink(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace), let url = wholeLink(trimmed) {
            return url
        }
        return firstLink(inside: trimmed)
    }

    private static func wholeLink(_ text: String) -> URL? {
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host?.isEmpty == false {
            return url
        }
        // Bare domain: needs a dot in the host part and no scheme.
        guard !text.contains("://"), let url = URL(string: "https://" + text),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        return url
    }

    /// Links written out with a scheme or "www." inside longer text. Bare words with a dot
    /// ("file.txt", "e.g.") don't count here: too easy to misread.
    private static func firstLink(inside text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false, let swiftRange = Range(match.range, in: text) else { continue }
            let written = text[swiftRange].lowercased()
            if written.hasPrefix("http://") || written.hasPrefix("https://") || written.hasPrefix("www.") {
                return url
            }
        }
        return nil
    }

    /// Undoes macOS smart punctuation in typed links and patterns (curly quotes, dashes).
    public static func plainText(_ text: String) -> String {
        var result = text
        for (smart, plain) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'"),
                               ("\u{2014}", "--"), ("\u{2013}", "-"), ("\u{2026}", "...")] {
            result = result.replacingOccurrences(of: smart, with: plain)
        }
        return result
    }
}

/// How a link is shown to people: Unicode host, and short paths.
public enum LinkText {
    /// The host as people read it ("bücher.de"), without "www.". Files show their name.
    public static func host(of url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        var display = Punycode.displayHost(host.lowercased())
        if display.hasPrefix("www.") { display.removeFirst(4) }
        if let port = url.port { display += ":\(port)" }
        return display
    }

    /// Path + query, middle-truncated, or "" for a bare host.
    public static func detail(of url: URL, maxLength: Int = 48) -> String {
        if url.isFileURL { return truncateMiddle(url.deletingLastPathComponent().path, maxLength: maxLength) }
        var rest = url.path
        if let query = url.query, !query.isEmpty { rest += "?" + query }
        if rest == "/" { rest = "" }
        return truncateMiddle(rest.removingPercentEncoding ?? rest, maxLength: maxLength)
    }

    public static func truncateMiddle(_ text: String, maxLength: Int) -> String {
        guard maxLength > 1, text.count > maxLength else { return text }
        let keep = maxLength - 1
        let head = keep / 2 + keep % 2
        let tail = keep / 2
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }
}
