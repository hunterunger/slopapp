import Foundation

/// A dotted version like "1.2.10", compared numerically, then by build number.
public struct AppVersion: Comparable, Sendable, Hashable, CustomStringConvertible {
    public var components: [Int]
    public var build: Int

    public init(_ string: String, build: Int = 0) {
        components = string
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        self.build = build
    }

    public init(_ string: String, build: String?) {
        self.init(string, build: build.flatMap { Int($0) } ?? 0)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return a < b }
        }
        return lhs.build < rhs.build
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
        hasher.combine(build)
    }
}

/// The running macOS meets an app's minimum ("14.0").
public func meetsMinimum(_ minimum: String?, system: OperatingSystemVersion) -> Bool {
    guard let minimum else { return true }
    let need = AppVersion(minimum)
    let have = AppVersion("\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
    return have >= need
}
