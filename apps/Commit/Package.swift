// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Commit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "CommitCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Commit",
            dependencies: ["CommitCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "CommitCoreTests", dependencies: ["CommitCore"]),
    ],
    swiftLanguageModes: [.v6]
)
