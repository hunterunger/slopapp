import Foundation

/// Webmail services that can start a new message from a URL.
public enum WebmailProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case gmail
    case outlookWork
    case outlookPersonal
    case fastmail
    case yahoo
    case proton
    case custom

    public var title: String {
        switch self {
        case .gmail: "Gmail"
        case .outlookWork: "Outlook (work or school)"
        case .outlookPersonal: "Outlook.com"
        case .fastmail: "Fastmail"
        case .yahoo: "Yahoo Mail"
        case .proton: "Proton Mail"
        case .custom: "Other Webmail"
        }
    }

    /// Short name for picker rows and lists ("Gmail", "Outlook").
    public var shortTitle: String {
        switch self {
        case .outlookWork, .outlookPersonal: "Outlook"
        case .custom: "Webmail"
        default: title
        }
    }

    /// Whether an account can be chosen (Gmail: several signed-in accounts in one browser).
    public var supportsAccount: Bool { self == .gmail }
}

/// "Write the email in this webmail": a browser target with this set opens mailto links as
/// the service's compose page, in that browser and profile.
public struct Webmail: Codable, Hashable, Sendable {
    public var provider: WebmailProvider
    /// Gmail only: which signed-in account ("" = the first; a number like "1"; or an address).
    public var account: String
    /// Other Webmail only: a URL with {to}, {cc}, {bcc}, {subject}, {body} or {mailto}.
    public var template: String

    public init(provider: WebmailProvider, account: String = "", template: String = "") {
        self.provider = provider
        self.account = account
        self.template = template
    }

    /// Placeholders a custom template can use. Each is filled in percent-encoded.
    public static let placeholders = ["{to}", "{cc}", "{bcc}", "{subject}", "{body}", "{mailto}"]

    /// The compose page for this message, or nil if the custom template isn't a web address.
    public func composeURL(for mail: MailtoLink) -> URL? {
        let to = mail.to.joined(separator: ",")
        let cc = mail.cc.joined(separator: ",")
        let bcc = mail.bcc.joined(separator: ",")
        func query(_ pairs: [(String, String)]) -> String {
            pairs.filter { !$0.1.isEmpty }.map { "\($0.0)=\(QueryEncoding.encode($0.1))" }.joined(separator: "&")
        }
        let text: String
        switch provider {
        case .gmail:
            // https://mail.google.com/mail/?view=cm&fs=1&to=…&su=…&body=…
            let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
            var base = "https://mail.google.com/mail/"
            var pairs: [(String, String)] = []
            if !account.isEmpty {
                if account.allSatisfy(\.isNumber) { base += "u/\(account)/" } else { pairs.append(("authuser", account)) }
            }
            pairs += [("view", "cm"), ("fs", "1"), ("to", to), ("cc", cc), ("bcc", bcc), ("su", mail.subject), ("body", mail.body)]
            text = base + "?" + query(pairs)
        case .outlookWork, .outlookPersonal:
            let base = provider == .outlookWork
                ? "https://outlook.office.com/mail/deeplink/compose"
                : "https://outlook.live.com/mail/0/deeplink/compose"
            let q = query([("to", to), ("cc", cc), ("bcc", bcc), ("subject", mail.subject), ("body", mail.body)])
            text = q.isEmpty ? base : base + "?" + q
        case .fastmail:
            text = "https://app.fastmail.com/action/compose/?mailto=" + QueryEncoding.encode(mail.url.absoluteString)
        case .yahoo:
            text = "https://compose.mail.yahoo.com/?" + query([("to", to), ("cc", cc), ("bcc", bcc), ("subject", mail.subject), ("body", mail.body)])
        case .proton:
            text = "https://mail.proton.me/inbox/#mailto=" + QueryEncoding.encode(mail.url.absoluteString)
        case .custom:
            var filled = template.trimmingCharacters(in: .whitespacesAndNewlines)
            for (placeholder, value) in [("{to}", to), ("{cc}", cc), ("{bcc}", bcc), ("{subject}", mail.subject),
                                         ("{body}", mail.body), ("{mailto}", mail.url.absoluteString)] {
                filled = filled.replacingOccurrences(of: placeholder, with: QueryEncoding.encode(value))
            }
            text = filled
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Why a custom template can't be used, or nil.
    public var templateProblem: String? {
        guard provider == .custom else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter the address of the webmail's compose page." }
        guard Self.placeholders.contains(where: trimmed.contains) else {
            return "Add {to} (or {mailto}) where the address goes, so the message is filled in."
        }
        guard composeURL(for: MailtoLink(to: ["someone@example.com"], subject: "Hi")) != nil else {
            return "That isn't a web address. Start it with https://."
        }
        return nil
    }
}
