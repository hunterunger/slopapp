import Foundation
import Testing
@testable import SlopappCore

@Suite struct URLPolicyTests {
    @Test func productionIsHTTPSOnly() {
        let policy = URLPolicy(allowsLocal: false)
        #expect(policy.allows(URL(string: "https://github.com/a.zip")!))
        #expect(!policy.allows(URL(string: "http://github.com/a.zip")!))
        #expect(!policy.allows(URL(string: "http://localhost:8000/a.zip")!))
        #expect(!policy.allows(URL(fileURLWithPath: "/tmp/a.zip")))
        #expect(!policy.allows(URL(string: "ftp://x/a.zip")!))
    }

    @Test func developerOverrideAllowsLoopbackAndFiles() {
        let policy = URLPolicy(allowsLocal: true)
        #expect(policy.allows(URL(string: "http://localhost:8000/a.zip")!))
        #expect(policy.allows(URL(string: "http://127.0.0.1:8000/a.zip")!))
        #expect(policy.allows(URL(fileURLWithPath: "/tmp/a.zip")))
        #expect(!policy.allows(URL(string: "http://example.com/a.zip")!))
    }
}

@Suite struct SignaturePolicyTests {
    let id = "app.slopapp.tiny"

    @Test func withoutTeamIDAdHocIsADevelopmentBuild() {
        let policy = SignaturePolicy(requiredTeamID: nil)
        #expect(policy.evaluate(adHoc, bundleID: id) == .developmentBuild)
        #expect(policy.label(for: adHoc) == "Unsigned development build")
        #expect(policy.evaluate(developerID("ABCDE12345"), bundleID: id) == .trusted(teamID: "ABCDE12345"))
        #expect(policy.label(for: developerID("ABCDE12345")) == nil)
    }

    @Test func withTeamIDOnlyThatTeamPasses() {
        let policy = SignaturePolicy(requiredTeamID: "ABCDE12345")
        #expect(policy.evaluate(developerID("ABCDE12345"), bundleID: id) == .trusted(teamID: "ABCDE12345"))
        #expect(policy.evaluate(adHoc, bundleID: id) == .rejected(.unsignedNotAllowed))
        #expect(policy.evaluate(developerID("ZZZZZ99999"), bundleID: id) == .rejected(.wrongTeam(found: "ZZZZZ99999")))
        // A self-made certificate claiming our team doesn't count.
        #expect(policy.evaluate(developerID("ABCDE12345", apple: false), bundleID: id) == .rejected(.unsignedNotAllowed))
    }

    @Test func blankTeamIDMeansNone() {
        #expect(SignaturePolicy(requiredTeamID: "  ").requiredTeamID == nil)
    }

    @Test func rejectsBrokenOrForeignSignatures() {
        let policy = SignaturePolicy(requiredTeamID: nil)
        #expect(policy.evaluate(.invalid("modified"), bundleID: id) == .rejected(.invalid))
        #expect(policy.evaluate(developerID("ABCDE12345", id: "com.evil"), bundleID: id) == .rejected(.wrongIdentifier))
        #expect(policy.label(for: .invalid("x")) == "Damaged or modified")
    }

    @Test func updatesKeepTheInstalledTeam() {
        let policy = SignaturePolicy(requiredTeamID: nil)
        #expect(policy.evaluate(developerID("OTHER00000"), bundleID: id, installedTeamID: "ABCDE12345")
            == .rejected(.teamChanged(from: "ABCDE12345", to: "OTHER00000")))
        #expect(policy.evaluate(adHoc, bundleID: id, installedTeamID: "ABCDE12345")
            == .rejected(.teamChanged(from: "ABCDE12345", to: nil)))
        #expect(policy.evaluate(developerID("ABCDE12345"), bundleID: id, installedTeamID: "ABCDE12345") == .trusted(teamID: "ABCDE12345"))
    }
}
