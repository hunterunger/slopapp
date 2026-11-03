// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "AwakeCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Awake",
            dependencies: ["AwakeCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "AwakeCoreTests", dependencies: ["AwakeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
