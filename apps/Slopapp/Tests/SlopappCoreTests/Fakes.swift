import Foundation
@testable import SlopappCore

final class FakeLocator: AppLocating, SignatureChecking, @unchecked Sendable {
    var infos: [String: BundleInfo] = [:]       // path -> info
    var registered: [String: [URL]] = [:]        // bundle id -> urls
    var signatures: [String: SignatureInfo] = [:]

    func bundleInfo(at url: URL) -> BundleInfo? { infos[url.path] }
    func registeredCopies(bundleID: String) -> [URL] { registered[bundleID] ?? [] }
    func signature(at url: URL) -> SignatureInfo {
        signatures[url.path] ?? SignatureInfo(isValid: true, identifier: infos[url.path]?.bundleID, teamID: nil, isAdHoc: true)
    }
}

struct FakeFetcher: FeedFetching {
    var result: Result<Data, NetworkError>
    func data(from url: URL) async throws -> Data { try result.get() }
}

/// Fails every download with the given error.
struct FailingDownloader: Downloading {
    var error: NetworkError
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw error
    }
}

/// Never finishes until cancelled, like a slow download.
struct HangingDownloader: Downloading {
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.1)
        try await Task.sleep(for: .seconds(60))
    }
}

extension BundleInfo {
    static func app(_ id: String, _ version: String, _ build: String = "1") -> BundleInfo {
        BundleInfo(bundleID: id, version: version, build: build)
    }
}

let adHoc = SignatureInfo(isValid: true, identifier: "app.slopapp.tiny", teamID: nil, isAdHoc: true)
func developerID(_ team: String, id: String = "app.slopapp.tiny", apple: Bool = true) -> SignatureInfo {
    SignatureInfo(isValid: true, identifier: id, teamID: team, isAdHoc: false, isAppleIssued: apple)
}
