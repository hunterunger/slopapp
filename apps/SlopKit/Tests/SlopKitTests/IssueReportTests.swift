import Foundation
import Testing
@testable import SlopKit

@Suite struct IssueReportTests {
    private let appleSilicon = IssueReport.System(majorVersion: 27, minorVersion: 2, isAppleSilicon: true)
    private let info = AppInfo(name: "Clips", version: "0.1.0", build: "12", tagline: "")

    /// The query as name → decoded value.
    private func fields(_ url: URL) throws -> [String: String] {
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func problemFillsAppVersionAndMacOS() throws {
        let url = IssueReport.url(.problem, info: info, system: appleSilicon)
        #expect(url.absoluteString == "https://github.com/hunterunger/slopapp/issues/new?template=bug.yml"
            + "&app=Clips&version=0.1.0%20%2812%29&macos=macOS%2027.2%20on%20Apple%20silicon&title=%5BClips%5D%3A%20")
        #expect(try fields(url) == [
            "template": "bug.yml", "app": "Clips", "version": "0.1.0 (12)",
            "macos": "macOS 27.2 on Apple silicon", "title": "[Clips]: ",
        ])
    }

    @Test func improvementFillsOnlyTheApp() throws {
        let url = IssueReport.url(.improvement, info: info, system: appleSilicon)
        #expect(try fields(url) == ["template": "feature.yml", "app": "Clips", "title": "[Clips]: "])
    }

    @Test func startsAtTheRepositorysNewIssuePage() {
        let url = IssueReport.url(.problem, info: info, system: appleSilicon)
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        #expect(url.path() == Brand.repoURL.path() + "/issues/new")
    }

    @Test func missingVersionIsLeftBlank() throws {
        for version in [nil, ""] as [String?] {
            let fields = try fields(IssueReport.url(.problem, app: "Squish", version: version, system: appleSilicon))
            #expect(fields["version"] == nil)
            #expect(fields["app"] == "Squish")
            #expect(fields["macos"] == "macOS 27.2 on Apple silicon")
        }
    }

    @Test func reservedCharactersAreEncoded() throws {
        // "+" would read as a space on GitHub; "&", "=" and "#" would end the value early.
        let url = IssueReport.url(.problem, app: "A&B=C#D", version: "1.0+beta", system: appleSilicon)
        #expect(!url.absoluteString.contains("+"))
        #expect(url.absoluteString.contains("app=A%26B%3DC%23D&"))
        #expect(try fields(url)["version"] == "1.0+beta")
        #expect(try fields(url)["title"] == "[A&B=C#D]: ")
    }

    @Test func macOSDescription() {
        #expect(appleSilicon.description == "macOS 27.2 on Apple silicon")
        #expect(IssueReport.System(majorVersion: 15, minorVersion: 2, patchVersion: 1, isAppleSilicon: false).description
            == "macOS 15.2.1 on Intel")
        #expect(IssueReport.System(majorVersion: 14, minorVersion: 0, isAppleSilicon: false).description == "macOS 14.0 on Intel")
    }

    @Test func currentSystemMatchesThisMac() {
        let system = IssueReport.System.current
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(system.majorVersion == version.majorVersion)
        #expect(system.minorVersion == version.minorVersion)
        #if arch(arm64)
        #expect(system.isAppleSilicon)
        #endif
    }

    @Test func versionText() {
        #expect(IssueReport.versionText(version: "0.1.0", build: "12") == "0.1.0 (12)")
        #expect(IssueReport.versionText(version: "1.2", build: "") == "1.2")
    }

    @Test func menuTitles() {
        #expect(IssueReport.Kind.problem.title == "Report a Problem…")
        #expect(IssueReport.Kind.improvement.title == "Suggest an Improvement…")
    }
}

/// The fields filled in must exist in the forms (`.github/ISSUE_TEMPLATE`), and the
/// repository must be the one in brand/brand.json.
@Suite struct IssueFormTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func form(_ template: String) throws -> String {
        try String(contentsOf: root.appending(path: ".github/ISSUE_TEMPLATE/\(template)"), encoding: .utf8)
    }

    @Test func formsHaveTheFieldsWeFill() throws {
        let bug = try Self.form(IssueReport.Kind.problem.template)
        for id in ["app", "version", "macos"] {
            #expect(bug.contains("id: \(id)\n"), "bug.yml has a field with id \(id)")
        }
        #expect(try Self.form(IssueReport.Kind.improvement.template).contains("id: app\n"))
    }

    @Test func repositoryMatchesBrandJSON() throws {
        let data = try Data(contentsOf: Self.root.appending(path: "brand/brand.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["repoUrl"] as? String == Brand.repoURL.absoluteString)
    }
}
