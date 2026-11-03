// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "__NAME__",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "__NAME__Core"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "__NAME__",
            dependencies: ["__NAME__Core", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "__NAME__CoreTests", dependencies: ["__NAME__Core"]),
    ],
    swiftLanguageModes: [.v6]
)
