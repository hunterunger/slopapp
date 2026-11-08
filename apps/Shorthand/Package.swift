// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shorthand",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "ShorthandCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Shorthand",
            dependencies: ["ShorthandCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "ShorthandCoreTests", dependencies: ["ShorthandCore"]),
    ],
    swiftLanguageModes: [.v6]
)
