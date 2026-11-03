import Foundation

/// Which URLs the launcher will fetch from. Production: HTTPS only. A developer override
/// (`SLOPAPP_FEED_URL`) also allows file:// and http://localhost so tests run offline.
public struct URLPolicy: Sendable, Equatable {
    public var allowsLocal: Bool

    public init(allowsLocal: Bool) {
        self.allowsLocal = allowsLocal
    }

    public func allows(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host?.isEmpty == false
        case "http":
            return allowsLocal && Self.isLoopback(url.host)
        case "file":
            return allowsLocal
        default:
            return false
        }
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}

/// What the code signature of a downloaded (or installed) app says.
public struct SignatureInfo: Sendable, Equatable {
    /// The signature is intact and covers every file (codesign --verify --strict --deep).
    public var isValid: Bool
    /// The signing identifier (the bundle id for apps signed by our pipeline).
    public var identifier: String?
    /// The Apple Developer team, nil for ad-hoc signatures.
    public var teamID: String?
    /// Signed without a certificate (`codesign --sign -`).
    public var isAdHoc: Bool
    /// The certificate chains to Apple (`anchor apple generic`), so `teamID` is real and
    /// not just a name in a self-made certificate.
    public var isAppleIssued: Bool
    /// Why validation failed, for logs.
    public var failure: String?

    public init(isValid: Bool, identifier: String?, teamID: String?, isAdHoc: Bool, isAppleIssued: Bool = false, failure: String? = nil) {
        self.isValid = isValid
        self.identifier = identifier
        self.teamID = teamID
        self.isAdHoc = isAdHoc
        self.isAppleIssued = isAppleIssued
        self.failure = failure
    }

    public static func invalid(_ reason: String) -> SignatureInfo {
        SignatureInfo(isValid: false, identifier: nil, teamID: nil, isAdHoc: false, failure: reason)
    }

    /// A team ID we can believe: Apple-issued certificate, not ad-hoc.
    public var verifiedTeamID: String? {
        isAppleIssued && !isAdHoc ? teamID : nil
    }
}

public enum SignatureVerdict: Sendable, Equatable {
    /// Signed by the required (or any) Developer ID team.
    case trusted(teamID: String)
    /// Valid ad-hoc signature, accepted because no team ID is configured. Shown as an
    /// "unsigned development build".
    case developmentBuild
    case rejected(SignatureRejection)

    public var isAccepted: Bool {
        if case .rejected = self { return false }
        return true
    }
}

public enum SignatureRejection: Sendable, Equatable {
    case invalid
    case wrongIdentifier
    case wrongTeam(found: String?)
    case unsignedNotAllowed
    case teamChanged(from: String, to: String?)
}

/// The trust rules. See apps/Slopapp/README.md, "Trust model".
public struct SignaturePolicy: Sendable, Equatable {
    /// When set (brand.json `teamId`), every app must be signed by this team.
    public var requiredTeamID: String?

    public init(requiredTeamID: String?) {
        let trimmed = requiredTeamID?.trimmingCharacters(in: .whitespaces)
        self.requiredTeamID = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// - Parameters:
    ///   - signature: the new copy's signature.
    ///   - bundleID: the bundle id the feed promised.
    ///   - installedTeamID: the team of the copy being replaced, if it was team-signed. An
    ///     update may never switch to a different team or drop back to ad-hoc.
    public func evaluate(_ signature: SignatureInfo, bundleID: String, installedTeamID: String? = nil) -> SignatureVerdict {
        guard signature.isValid else { return .rejected(.invalid) }
        guard signature.identifier == bundleID else { return .rejected(.wrongIdentifier) }
        let team = signature.verifiedTeamID
        if let installedTeamID, team != installedTeamID {
            return .rejected(.teamChanged(from: installedTeamID, to: team))
        }
        if let requiredTeamID {
            guard team == requiredTeamID else {
                return team == nil ? .rejected(.unsignedNotAllowed) : .rejected(.wrongTeam(found: team))
            }
            return .trusted(teamID: requiredTeamID)
        }
        if let team { return .trusted(teamID: team) }
        return .developmentBuild
    }

    /// The label the UI shows next to an installed copy, if any.
    public func label(for signature: SignatureInfo?) -> String? {
        guard let signature else { return nil }
        if !signature.isValid { return "Damaged or modified" }
        if signature.verifiedTeamID == nil { return "Unsigned development build" }
        return nil
    }
}
