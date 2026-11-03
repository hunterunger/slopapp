import CoreServices
import Foundation
import Security

/// Reads app bundles from disk, LaunchServices and the Security framework.
public struct LocalAppLocator: AppLocating, SignatureChecking {
    public init() {}

    public func bundleInfo(at url: URL) -> BundleInfo? {
        Self.readInfo(at: url)
    }

    /// Info.plist read directly (Bundle caches, and we re-read after updates).
    @Sendable public static func readInfo(at url: URL) -> BundleInfo? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String
        else { return nil }
        return BundleInfo(
            bundleID: id,
            version: dict["CFBundleShortVersionString"] as? String ?? "0",
            build: dict["CFBundleVersion"] as? String ?? "0"
        )
    }

    public func registeredCopies(bundleID: String) -> [URL] {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] else {
            return []
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func signature(at url: URL) -> SignatureInfo {
        CodeSignature.check(url)
    }
}

/// Code signature checks with the Security framework (what `codesign --verify --strict --deep` does).
public enum CodeSignature {
    public static func check(_ url: URL) -> SignatureInfo {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return .invalid("not a code bundle")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &error)

        var infoRef: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef)
        let info = infoRef as? [String: Any] ?? [:]
        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = codeFlags & 0x0002 != 0 // kSecCodeSignatureAdhoc

        guard status == errSecSuccess else {
            let reason = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "status \(status)"
            return SignatureInfo(isValid: false, identifier: identifier, teamID: teamID, isAdHoc: isAdHoc, failure: reason)
        }

        // Does the certificate chain to Apple? Only then is the team ID more than a label.
        var appleIssued = false
        if !isAdHoc, teamID != nil {
            var requirement: SecRequirement?
            if SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
               let requirement {
                appleIssued = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
            }
        }
        return SignatureInfo(isValid: true, identifier: identifier, teamID: teamID, isAdHoc: isAdHoc, isAppleIssued: appleIssued)
    }
}
