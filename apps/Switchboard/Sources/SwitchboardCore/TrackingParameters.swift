import Foundation

/// Removes well-known ad and email-campaign tracking parameters from web links (off by
/// default; turned on in General). Only parameters that never change what a page shows are
/// listed, so a cleaned link always opens the same page. Offline, no network.
public enum TrackingParameters {
    /// Exact names (lowercased).
    static let names: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "twclid", "ttclid", "li_fat_id", "igshid", "mc_cid", "mc_eid", "_hsenc", "_hsmi",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "vero_conv", "rb_clickid",
        "s_cid", "_openstat", "srsltid", "epik",
    ]
    /// Name prefixes (lowercased): utm_source, utm_medium, ….
    static let prefixes = ["utm_"]

    public static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return names.contains(lower) || prefixes.contains { lower.hasPrefix($0) }
    }

    /// The link without tracking parameters, or the same URL if there were none. Everything
    /// else (other parameters, their order and encoding, the fragment) is kept as it was.
    public static func strip(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.percentEncodedQuery, !query.isEmpty else { return url }
        let pairs = query.split(separator: "&", omittingEmptySubsequences: false)
        let kept = pairs.filter { pair in
            let name = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let decoded = String(name).removingPercentEncoding ?? String(name)
            return !isTracking(decoded)
        }
        guard kept.count != pairs.count else { return url }
        components.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return components.url ?? url
    }
}
