import AppKit
import SwiftUI

/// "Report a Problem…" and "Suggest an Improvement…": the project's GitHub issue forms
/// (`.github/ISSUE_TEMPLATE/bug.yml` and `feature.yml`), opened in the browser with the
/// boring facts already filled in: the app's name, its version and build, and the macOS
/// version and kind of Mac.
///
/// Nothing is sent from the app. Those facts travel only in the query of a URL that's opened
/// when the person picks the menu item; they read the form on github.com, write the rest and
/// submit it themselves, or close the tab. No clipboard, files, settings or logs are attached.
///
///     Button("Report a Problem…") { IssueReport.open(.problem, info: info) }
///
/// `MenuFooter`, `AboutView` and `HelpCommands` already include it.
public enum IssueReport {
    /// Which form to open.
    public enum Kind: Sendable, CaseIterable {
        /// "Report a problem" (`bug.yml`): app, version and macOS are filled in.
        case problem
        /// "Suggest an improvement" (`feature.yml`): the app is filled in.
        case improvement

        /// The issue form's file name in `.github/ISSUE_TEMPLATE`.
        public var template: String {
            switch self {
            case .problem: "bug.yml"
            case .improvement: "feature.yml"
            }
        }

        /// The menu item title, with the ellipsis (the browser opens a form to finish).
        public var title: String {
            switch self {
            case .problem: "Report a Problem…"
            case .improvement: "Suggest an Improvement…"
            }
        }
    }

    /// The Mac the app runs on, as the form's macOS field shows it.
    public struct System: Sendable, Equatable {
        public var majorVersion: Int
        public var minorVersion: Int
        public var patchVersion: Int
        public var isAppleSilicon: Bool

        public init(majorVersion: Int, minorVersion: Int, patchVersion: Int = 0, isAppleSilicon: Bool) {
            self.majorVersion = majorVersion
            self.minorVersion = minorVersion
            self.patchVersion = patchVersion
            self.isAppleSilicon = isAppleSilicon
        }

        /// This Mac, read when called.
        public static var current: System {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return System(majorVersion: version.majorVersion, minorVersion: version.minorVersion,
                          patchVersion: version.patchVersion, isAppleSilicon: hasAppleSilicon)
        }

        /// "macOS 27.2 on Apple silicon", "macOS 15.2.1 on Intel".
        public var description: String {
            var version = "\(majorVersion).\(minorVersion)"
            if patchVersion > 0 { version += ".\(patchVersion)" }
            return "macOS \(version) on \(isAppleSilicon ? "Apple silicon" : "Intel")"
        }

        /// Asks the kernel rather than checking the build architecture, so an Intel slice
        /// running under Rosetta still reports the Apple silicon Mac it's on.
        private static var hasAppleSilicon: Bool {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 { return value == 1 }
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }
    }

    /// The form's version field: "0.1.0 (12)".
    public static func versionText(version: String, build: String) -> String {
        build.isEmpty ? version : "\(version) (\(build))"
    }

    /// The pre-filled form for `app` (its `name` in app.json, which is what the form's App
    /// menu lists; the launcher is "Slopapp"). `version` is left blank when nil or empty, as
    /// for an app that isn't installed. The improvement form has no version or macOS fields,
    /// so only the app is filled in.
    public static func url(_ kind: Kind, app: String, version: String?, system: System = .current) -> URL {
        var fields: [(String, String)] = [("template", kind.template), ("app", app)]
        if kind == .problem {
            if let version, !version.isEmpty { fields.append(("version", version)) }
            fields.append(("macos", system.description))
        }
        // The same "[App]: " start as the form's own title, with the app named.
        fields.append(("title", "[\(app)]: "))

        var components = URLComponents(url: newIssueURL, resolvingAgainstBaseURL: false)!
        // Encoded here rather than by `queryItems`, which leaves "+" alone (GitHub reads it
        // as a space) along with other reserved characters such as "/", "?" and "(".
        components.percentEncodedQueryItems = fields.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: unreserved))
        }
        return components.url!
    }

    /// The pre-filled form for the running app.
    public static func url(_ kind: Kind, info: AppInfo, system: System = .current) -> URL {
        url(kind, app: info.name, version: versionText(version: info.version, build: info.build), system: system)
    }

    /// Opens the pre-filled form in the browser. Call only from the person's own click.
    @MainActor
    public static func open(_ kind: Kind, info: AppInfo) {
        NSWorkspace.shared.open(url(kind, info: info))
    }

    /// Opens the pre-filled form for another app (the launcher's app pages).
    @MainActor
    public static func open(_ kind: Kind, app: String, version: String?) {
        NSWorkspace.shared.open(url(kind, app: app, version: version))
    }

    /// Where new issues start: `Brand.repoURL` + /issues/new.
    static var newIssueURL: URL { Brand.repoURL.appending(path: "issues/new") }

    /// RFC 3986 unreserved characters; everything else in a value is percent-encoded.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

/// The standard Help menu: the app's own help items (if any), then Report a Problem… and
/// Suggest an Improvement…. Replaces SwiftUI's default Help item, which only says help
/// isn't available.
///
///     .commands {
///         HelpCommands(info: info)
///         // or, with the app's own items first:
///         HelpCommands(info: info) {
///             Button("Squish Help") { NSWorkspace.shared.open(helpURL) }
///         }
///     }
public struct HelpCommands<AppItems: View>: Commands {
    let info: AppInfo
    let appItems: AppItems

    public init(info: AppInfo, @ViewBuilder appItems: () -> AppItems) {
        self.info = info
        self.appItems = appItems()
    }

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            appItems
            if AppItems.self != EmptyView.self { Divider() }
            IssueReportButtons(info: info)
        }
    }
}

extension HelpCommands where AppItems == EmptyView {
    public init(info: AppInfo) {
        self.init(info: info) { EmptyView() }
    }
}

/// Report a Problem… and Suggest an Improvement…, as menu items. For a Help menu that
/// isn't built with `HelpCommands`.
public struct IssueReportButtons: View {
    let info: AppInfo

    public init(info: AppInfo) {
        self.info = info
    }

    public var body: some View {
        ForEach(IssueReport.Kind.allCases, id: \.self) { kind in
            Button(kind.title) { IssueReport.open(kind, info: info) }
        }
    }
}
