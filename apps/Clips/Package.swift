// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clips",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "ClipsCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Clips",
            dependencies: ["ClipsCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "ClipsCoreTests", dependencies: ["ClipsCore"]),
    ],
    swiftLanguageModes: [.v6]
)
