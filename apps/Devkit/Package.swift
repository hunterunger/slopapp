// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Devkit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
        // YAML parsing (wraps libyaml). MIT. Approved in docs/design-system.md §9.
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "DevkitCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Devkit",
            dependencies: ["DevkitCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "DevkitCoreTests", dependencies: ["DevkitCore"]),
    ],
    swiftLanguageModes: [.v6]
)
